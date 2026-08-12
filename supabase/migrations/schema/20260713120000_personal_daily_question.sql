-- ============================================================================
-- PERSONAL daily question + streak on ANY vote.
--
-- Retires the "same calendar question for everyone" daily. Every user now gets
-- their own free question of the day, drawn from the questions THEY have not
-- voted on yet.
--
-- WHY
--   The votable-feed pivot (20260712160000-190000) made every unlocked question
--   votable. But the pre-filled calendar (daily_questions) covers the ENTIRE
--   catalog — all 1000 active questions are somebody's future daily — so every
--   feed vote is a vote on a future global daily. When that date arrives, the
--   user opens the app to a question they already voted: the client shows the
--   result bars (no buttons), cast_daily_vote never fires, and — because the
--   streak only moved on a CURRENT-daily vote — their streak is dead for the
--   day through no fault of their own. A heavy voter eventually votes every
--   future daily and can NEVER advance a streak again. Confirmed on prod:
--   votes already sit on future calendar dailies.
--
--   Nothing user-visible depends on "everyone gets the same question" anymore:
--   the pivot stripped the daily framing from the UX, and the split shown is
--   the all-time tally (not "today's result"), so the calendar bought no
--   community moment — only the collision bug.
--
-- WHAT CHANGES
--   1) user_daily_questions — one row per (user, local date): the personal
--      assignment. Assigned lazily by get_daily_question on first call of the
--      day; stable for the rest of that date (and across devices).
--   2) get_daily_question — serves (and on first call draws) the caller's
--      personal daily: active + NOT YET VOTED, preferring never-seen questions,
--      random within each group. Falls back to the calendar question only when
--      the user has voted on literally everything. Same signature and return
--      shape, so every shipped client keeps working; publish_date echoes the
--      (clamped) request date.
--   3) can_read_question_text — the free branch now grants the caller's OWN
--      assignment for the claimed date (still clamped to UTC ±1), instead of
--      the calendar row. Premium unchanged.
--   4) cast_daily_vote — the streak advances on EVERY successful vote, at most
--      once per UTC day, from the decayed baseline. "Vote (on anything) every
--      day" is the streak rule that matches a feed where every question is
--      votable; it also survives the daily being already-voted. The
--      read/seen guard on WHICH questions are votable is unchanged.
--   5) peek_next_question / reveal_ad_question / reveal_free_question — the
--      pool now excludes the caller's own current assignments (±1 day around
--      the claimed date) instead of the calendar daily, so a paid reveal never
--      duplicates the question already free at position 0.
--   6) get_daily_history (legacy, shipped clients) — the "past dailies you
--      voted on" now unions the personal assignments with the old calendar
--      days, so history keeps filling up after this change.
--
-- KEPT
--   * daily_questions (calendar) stays: legacy history rows + the voted-
--     everything fallback. No writes to it anymore.
--   * The vote-eligibility guard, budgets, credits, decay, ranks: unchanged.
--   * question_seen 'daily' rows still written for the (personal) daily — the
--     smaczki gate and the vote guard read them.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) The per-user daily assignment. PK (user_id, assigned_on) = one per day;
--    only the SECURITY DEFINER RPCs write it. Read-own for completeness.
-- ----------------------------------------------------------------------------
create table if not exists public.user_daily_questions (
  user_id     uuid not null references auth.users(id) on delete cascade,
  assigned_on date not null,
  question_id uuid not null references public.questions(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (user_id, assigned_on)
);

alter table public.user_daily_questions enable row level security;

drop policy if exists "read own personal daily" on public.user_daily_questions;
create policy "read own personal daily" on public.user_daily_questions
  for select to authenticated
  using (user_id = (select auth.uid()));

grant select on public.user_daily_questions to authenticated;

-- ----------------------------------------------------------------------------
-- 2) get_daily_question — personal draw. plpgsql + VOLATILE (it writes the
--    assignment + the seen row). Same signature/return shape as before.
-- ----------------------------------------------------------------------------
create or replace function public.get_daily_question(
  p_locale text default 'pl',
  p_date   date default (now() at time zone 'utc')::date
)
returns table (
  id            uuid,
  category      text,
  is_premium    boolean,
  question_text text,
  publish_date  date
)
language plpgsql volatile security definer set search_path = public as $$
declare
  v_uid   uuid := auth.uid();
  v_today date := (now() at time zone 'utc')::date;
  v_date  date := p_date;
  v_qid   uuid;
begin
  -- The personal daily needs an identity; the app always signs in (anonymous
  -- included) before fetching. An unauthenticated call gets no row.
  if v_uid is null then
    return;
  end if;

  -- Honour the device's local "today" but clamp to UTC ±1 (the widest a real
  -- timezone can be off), so a client can't harvest assignments for arbitrary
  -- dates. Out-of-window claims just get the server's today.
  if v_date is null or v_date < v_today - 1 or v_date > v_today + 1 then
    v_date := v_today;
  end if;

  -- Today's assignment, if it exists and its question is still active.
  select ud.question_id into v_qid
  from public.user_daily_questions ud
  join public.questions q on q.id = ud.question_id and q.is_active
  where ud.user_id = v_uid and ud.assigned_on = v_date;

  if v_qid is null then
    -- Clear a stale assignment whose question was deactivated mid-day, so the
    -- redraw below can replace it instead of serving nothing.
    delete from public.user_daily_questions
     where user_id = v_uid and assigned_on = v_date;

    -- The draw: any active question the user has NOT voted on, never-seen ones
    -- first (fresh over "shown but skipped"), random within each group.
    select q.id into v_qid
    from public.questions q
    where q.is_active
      and not exists (
        select 1 from public.question_votes v
        where v.user_id = v_uid and v.question_id = q.id
      )
    order by
      exists (
        select 1 from public.question_seen s
        where s.user_id = v_uid and s.question_id = q.id
      ) asc,
      random()
    limit 1;

    -- Voted on the whole catalog: fall back to the calendar question for the
    -- date (deterministic, always exists while the calendar lasts) so the
    -- screen never comes up empty.
    if v_qid is null then
      select d.question_id into v_qid
      from public.daily_questions d
      join public.questions q on q.id = d.question_id and q.is_active
      where d.publish_date = v_date;
    end if;

    if v_qid is null then
      return;
    end if;

    insert into public.user_daily_questions (user_id, assigned_on, question_id)
    values (v_uid, v_date, v_qid)
    on conflict (user_id, assigned_on) do nothing;

    -- A concurrent call (second device) may have won the insert; serve the
    -- STORED assignment either way so both devices show the same question.
    select ud.question_id into v_qid
    from public.user_daily_questions ud
    where ud.user_id = v_uid and ud.assigned_on = v_date;
  end if;

  -- Seen-memory: the daily was shown to this user (idempotent). The smaczki
  -- gate and the vote guard read this; the reveal pool does not (it excludes
  -- by VOTE + the assignment window below).
  insert into public.question_seen (user_id, question_id, source)
  values (v_uid, v_qid, 'daily')
  on conflict (user_id, question_id) do nothing;

  -- The caller's own assignment within the clamp is readable by construction
  -- (see can_read_question_text), so the text is returned un-gated.
  return query
    select q.id, q.category, q.is_premium,
           coalesce(tr.question_text, en.question_text),
           v_date
    from public.questions q
    left join public.question_translations tr
           on tr.question_id = q.id and tr.locale = p_locale
    left join public.question_translations en
           on en.question_id = q.id and en.locale = 'en'
    where q.id = v_qid;
end;
$$;

grant execute on function public.get_daily_question(text, date) to anon, authenticated;

-- ----------------------------------------------------------------------------
-- 3) can_read_question_text — free = your OWN assignment for the claimed date
--    (clamped), premium = everything. Same signature.
-- ----------------------------------------------------------------------------
create or replace function public.can_read_question_text(
  p_question_id uuid,
  p_date        date
)
returns boolean
language sql stable security definer set search_path = public as $$
  select
    public.is_premium(auth.uid())
    or exists (
      select 1 from public.user_daily_questions ud
      where ud.user_id = auth.uid()
        and ud.question_id = p_question_id
        and ud.assigned_on = p_date
        and p_date between (now() at time zone 'utc')::date - 1
                       and (now() at time zone 'utc')::date + 1
    );
$$;
revoke all on function public.can_read_question_text(uuid, date) from public;

-- ----------------------------------------------------------------------------
-- 4) cast_daily_vote — streak on ANY successful vote (once per UTC day, from
--    the decayed baseline). The eligibility guard is unchanged from
--    20260712160000: readable now, or genuinely shown via reveal/daily.
-- ----------------------------------------------------------------------------
create or replace function public.cast_daily_vote(
  p_question_id uuid,
  p_choice      int,
  p_date        date default (now() at time zone 'utc')::date,
  p_locale      text default 'pl'
)
returns table (
  yes_count int,
  no_count  int,
  my_choice int
)
language plpgsql security definer set search_path = public as $$
declare
  v_uid       uuid := auth.uid();
  v_today     date := (now() at time zone 'utc')::date;
  v_last_vote date;
  v_streak    int;
  v_longest   int;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if p_choice not in (1, 2) then
    raise exception 'invalid choice %', p_choice;
  end if;
  -- Votable = readable now (premium / own daily) OR actually shown via a paid
  -- reveal or a daily. 'view' stays excluded: it is an unpaid browse marker and
  -- would let a free user fabricate eligibility (see 20260712160000).
  if not (
    public.can_read_question_text(p_question_id, p_date)
    or exists (
      select 1 from public.question_seen s
      where s.user_id = v_uid
        and s.question_id = p_question_id
        and s.source in ('ad', 'free_credit', 'daily')
    )
  ) then
    raise exception 'question not readable';
  end if;

  -- Record / update the vote (changing your mind is allowed).
  insert into public.question_votes (user_id, question_id, choice)
  values (v_uid, p_question_id, p_choice::smallint)
  on conflict (user_id, question_id)
  do update set choice = excluded.choice, voted_at = now();

  -- The streak: EVERY vote counts, at most once per UTC day. There is no
  -- daily-only branch anymore — "vote on anything today" is the streak rule in
  -- a feed where every question is votable, and it cannot be blocked by having
  -- already voted the served daily. Still keyed on the SERVER clock.
  select p.last_vote_date, p.current_streak, p.longest_streak
    into v_last_vote, v_streak, v_longest
  from public.profiles p
  where p.id = v_uid
  for update;

  if found and v_last_vote is distinct from v_today then
    v_streak := public.decayed_streak(v_streak, v_last_vote, v_today) + 1;
    update public.profiles
       set current_streak = v_streak,
           longest_streak = greatest(coalesce(v_longest, 0), v_streak),
           last_vote_date = v_today
     where id = v_uid;
  end if;

  return query
    select
      count(*) filter (where v.choice = 1)::int,
      count(*) filter (where v.choice = 2)::int,
      p_choice
    from public.question_votes v
    where v.question_id = p_question_id;
end;
$$;

revoke all on function public.cast_daily_vote(uuid, int, date, text) from public;
grant execute on function public.cast_daily_vote(uuid, int, date, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 5) The reveal pool — swap the calendar-daily exclusion for the caller's own
--    assignment window (±1 day around the claimed date), so a paid reveal
--    never duplicates the question already free at position 0. Pool otherwise
--    unchanged: active + NOT YET VOTED (20260712170000).
-- ----------------------------------------------------------------------------
create or replace function public.peek_next_question(
  p_locale      text  default 'pl',
  p_date        date  default (now() at time zone 'utc')::date,
  p_exclude_ids uuid[] default '{}'
)
returns table (id uuid, teaser text)
language sql security definer set search_path to 'public'
as $$
  select
    q.id,
    array_to_string(
      (regexp_split_to_array(
         btrim(coalesce(tr.question_text, en.question_text)), '\s+'))[1:2],
      ' '
    ) as teaser
  from public.questions q
  left join public.question_translations tr
         on tr.question_id = q.id and tr.locale = p_locale
  left join public.question_translations en
         on en.question_id = q.id and en.locale = 'en'
  where q.is_active
    and not (q.id = any (p_exclude_ids))
    and not exists (
      select 1 from public.user_daily_questions ud
      where ud.user_id = auth.uid()
        and ud.question_id = q.id
        and ud.assigned_on between p_date - 1 and p_date + 1
    )
    and not exists (
      select 1 from public.question_votes v
      where v.user_id = auth.uid() and v.question_id = q.id
    )
  order by random()
  limit 1;
$$;

revoke all on function public.peek_next_question(text, date, uuid[]) from public;
grant execute on function public.peek_next_question(text, date, uuid[]) to authenticated;

create or replace function public.reveal_ad_question(
  p_locale      text  default 'pl',
  p_date        date  default (now() at time zone 'utc')::date,
  p_question_id uuid  default null,
  p_exclude_ids uuid[] default '{}'
)
returns table (id uuid, category text, is_premium boolean, question_text text)
language plpgsql security definer set search_path to 'public'
as $$
declare
  c_grace    constant int := 2;
  v_uid      uuid := auth.uid();
  v_qid      uuid;
  v_used     int;
  v_verified int;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  -- Budget gate: the reveal must be backed by a verified ad reward (+ grace).
  select p.ad_reveals_used into v_used
  from public.profiles p
  where p.id = v_uid
  for update;

  select count(*) into v_verified
  from public.ad_reward_events e
  where e.user_id = v_uid and e.verified;

  if coalesce(v_used, 0) >= coalesce(v_verified, 0) + c_grace then
    raise exception 'ad reward not verified';
  end if;

  -- Prefer the peeked (teased) question, but only if still eligible: not the
  -- caller's current daily assignment and NOT YET VOTED.
  if p_question_id is not null then
    select q.id into v_qid
    from public.questions q
    where q.id = p_question_id
      and q.is_active
      and not exists (
        select 1 from public.user_daily_questions ud
        where ud.user_id = v_uid
          and ud.question_id = q.id
          and ud.assigned_on between p_date - 1 and p_date + 1
      )
      and not exists (
        select 1 from public.question_votes v
        where v.user_id = v_uid and v.question_id = q.id
      );
  end if;

  -- No (valid) peek: random UNVOTED pick, skipping this session's shown ids so
  -- a watched ad never re-serves a question already on screen this session.
  if v_qid is null then
    select q.id into v_qid
    from public.questions q
    where q.is_active
      and not (q.id = any (p_exclude_ids))
      and not exists (
        select 1 from public.user_daily_questions ud
        where ud.user_id = v_uid
          and ud.question_id = q.id
          and ud.assigned_on between p_date - 1 and p_date + 1
      )
      and not exists (
        select 1 from public.question_votes v
        where v.user_id = v_uid and v.question_id = q.id
      )
    order by random()
    limit 1;
  end if;

  -- Nothing votable left: return no row and DON'T spend budget on an empty reveal.
  if v_qid is null then
    return;
  end if;

  -- Record that the user was SHOWN this text (the smaczki + vote gates read this).
  insert into public.question_seen (user_id, question_id, source)
  values (v_uid, v_qid, 'ad')
  on conflict (user_id, question_id) do nothing;

  -- Spend one unit of the ad-reveal budget (only on a real reveal).
  update public.profiles
     set ad_reveals_used = coalesce(v_used, 0) + 1
   where profiles.id = v_uid;

  return query
    select q.id, q.category, q.is_premium,
           coalesce(tr.question_text, en.question_text)
    from public.questions q
    left join public.question_translations tr
           on tr.question_id = q.id and tr.locale = p_locale
    left join public.question_translations en
           on en.question_id = q.id and en.locale = 'en'
    where q.id = v_qid;
end;
$$;

revoke all on function public.reveal_ad_question(text, date, uuid, uuid[]) from public;
grant execute on function public.reveal_ad_question(text, date, uuid, uuid[]) to authenticated;

create or replace function public.reveal_free_question(
  p_locale      text  default 'pl',
  p_date        date  default (now() at time zone 'utc')::date,
  p_exclude_ids uuid[] default '{}'
)
returns table (id uuid, category text, is_premium boolean, question_text text)
language plpgsql security definer set search_path to 'public'
as $$
declare
  v_uid     uuid := auth.uid();
  v_credits int;
  v_qid     uuid;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if public.is_premium(v_uid) then
    raise exception 'premium users do not use unlock credits';
  end if;
  if not public.is_real_account(v_uid) then
    raise exception 'free credit is for real accounts only';
  end if;

  select p.free_unlock_credits into v_credits
  from public.profiles p
  where p.id = v_uid
  for update;

  if coalesce(v_credits, 0) < 1 then
    raise exception 'no free unlock credits';
  end if;

  select q.id into v_qid
  from public.questions q
  where q.is_active
    and not (q.id = any (p_exclude_ids))
    and not exists (
      select 1 from public.user_daily_questions ud
      where ud.user_id = v_uid
        and ud.question_id = q.id
        and ud.assigned_on between p_date - 1 and p_date + 1
    )
    and not exists (
      select 1 from public.question_votes v
      where v.user_id = v_uid and v.question_id = q.id
    )
  order by random()
  limit 1;

  -- Nothing votable left: don't charge the credit.
  if v_qid is null then
    return;
  end if;

  insert into public.question_seen (user_id, question_id, source)
  values (v_uid, v_qid, 'free_credit')
  on conflict (user_id, question_id) do nothing;

  update public.profiles set free_unlock_credits = v_credits - 1
   where profiles.id = v_uid;

  return query
    select q.id, q.category, q.is_premium,
           coalesce(tr.question_text, en.question_text)
    from public.questions q
    left join public.question_translations tr
           on tr.question_id = q.id and tr.locale = p_locale
    left join public.question_translations en
           on en.question_id = q.id and en.locale = 'en'
    where q.id = v_qid;
end;
$$;

revoke all on function public.reveal_free_question(text, date, uuid[]) from public;
grant execute on function public.reveal_free_question(text, date, uuid[]) to authenticated;

-- ----------------------------------------------------------------------------
-- 6) get_daily_history (legacy shipped clients; the new client uses
--    get_vote_history) — union the personal assignments with the old calendar
--    days so the "past dailies you voted on" keeps growing after the switch.
--    A question can appear in both sources; keep its most recent day.
--    Still premium-only, past-only, voted-only.
-- ----------------------------------------------------------------------------
create or replace function public.get_daily_history(
  p_locale text default 'pl',
  p_date date default ((now() at time zone 'utc')::date)
)
returns table(
  question_id uuid,
  category text,
  question_text text,
  publish_date date,
  yes_count int,
  no_count int,
  my_choice int
)
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_uid   uuid := auth.uid();
  v_today date := (now() at time zone 'utc')::date;
begin
  -- History is a PRO feature: no session or no premium → nothing to show.
  if v_uid is null or not public.is_premium(v_uid) then
    return;
  end if;

  return query
    with days as (
      -- Legacy: the global calendar (votes cast while the daily was shared).
      select d.question_id as qid, d.publish_date as day
      from public.daily_questions d
      where d.publish_date < p_date and d.publish_date <= v_today
      union
      -- Personal assignments since the switch.
      select ud.question_id, ud.assigned_on
      from public.user_daily_questions ud
      where ud.user_id = v_uid
        and ud.assigned_on < p_date and ud.assigned_on <= v_today
    ),
    dedup as (
      select distinct on (days.qid) days.qid, days.day
      from days
      order by days.qid, days.day desc
    )
    select
      q.id,
      q.category,
      coalesce(tr.question_text, en.question_text),
      dedup.day,
      coalesce(vc.yes_count, 0),
      coalesce(vc.no_count, 0),
      mv.choice::int
    from dedup
    join public.questions q on q.id = dedup.qid and q.is_active
    -- Voted-only: the community split stays a reward for voting.
    join public.question_votes mv
           on mv.question_id = q.id and mv.user_id = v_uid
    left join public.question_translations tr
           on tr.question_id = q.id and tr.locale = p_locale
    left join public.question_translations en
           on en.question_id = q.id and en.locale = 'en'
    left join lateral (
      select
        count(*) filter (where v.choice = 1)::int as yes_count,
        count(*) filter (where v.choice = 2)::int as no_count
      from public.question_votes v
      where v.question_id = q.id
    ) vc on true
    order by dedup.day desc
    limit 366;
end;
$function$;

revoke all on function public.get_daily_history(text, date) from public, anon;
grant execute on function public.get_daily_history(text, date) to authenticated, service_role;
