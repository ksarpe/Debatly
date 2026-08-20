-- ============================================================================
-- The GLOBAL daily is back — as a curated calendar with a personal fallback.
-- ----------------------------------------------------------------------------
-- 2026-08-20.
--
-- WHY (and why it is safe where 20260713120000 was not)
--   The personal daily fixed a real bug — feed votes on future CALENDAR days
--   killed streaks, because back then the streak only advanced on a
--   current-daily vote and the legacy calendar covered the whole catalog. But
--   it also dissolved the community moment: everyone debates a different
--   question, so "the world argues about X today" stopped existing.
--
--   Both hazards of the old design are gone:
--     * The streak has advanced on ANY vote (once per UTC day) since that same
--       migration — an already-voted daily can no longer kill it.
--     * The new calendar is not "the whole catalog on a schedule": it is a
--       SEPARATE owner-curated table (daily_picks), seeded only with questions
--       nobody has really voted on, and any collision falls back to the
--       personal draw below — the caller just gets a different question, the
--       rest of the world keeps the shared one.
--
-- WHAT
--   1) daily_picks — the curated calendar: one question pinned per date. Only
--      the owner writes it (SQL editor / service_role); no client access. A
--      date with no row simply means "personal daily for everyone that day" —
--      the app never breaks on a gap.
--   2) get_daily_question — the draw order becomes:
--        a. the caller's STORED assignment for the date (stability within the
--           day and across devices — unchanged);
--        b. the GLOBAL pick for the date, unless the caller already voted it
--           (a PRO browser may have met it in the feed weeks ago);
--        c. the personal draw (unchanged);
--        d. the legacy daily_questions calendar (unchanged last resort).
--      The winning question is still written to user_daily_questions, so
--      can_read_question_text, the peek/reveal exclusion windows, the history
--      union and the vote guard all keep working untouched.
--   3) peek_next_question — the day wall's teaser now shows TOMORROW'S PICK
--      (first 4 words) when one exists and the caller hasn't voted it, so the
--      wall advertises the actual next shared debate; otherwise the old random
--      unvoted pick. Still a single SELECT that writes nothing.
--
-- NOT CHANGED
--   cast_daily_vote (first-write-wins, 20260820120000), can_read_question_text,
--   reveal_* (live for old versions), get_daily_history, the streak, the
--   legacy daily_questions table (still the voted-everything fallback).
--
-- The seed of the calendar itself is a DATA migration
-- (20260820151000_seed_daily_picks): ~300 active questions with zero real
-- votes, categories interleaved, one per day from 2026-08-21.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) The curated calendar. publish_date PK = one pick per date; question_id
--    UNIQUE = a question is somebody's daily at most once (repeats would make
--    "already voted the pick" the common case instead of the edge case).
--    RLS on, no policies, no client grants: only the SECURITY DEFINER RPCs
--    read it, only the owner writes it.
-- ----------------------------------------------------------------------------
create table if not exists public.daily_picks (
  publish_date date primary key,
  question_id  uuid not null unique references public.questions(id) on delete cascade,
  created_at   timestamptz not null default now()
);

alter table public.daily_picks enable row level security;

revoke all on table public.daily_picks from anon, authenticated;

comment on table public.daily_picks is
  'Owner-curated global daily calendar: the question the whole world debates '
  'on publish_date. A missing date falls back to the personal draw in '
  'get_daily_question. Written only via the SQL editor / service_role.';

-- ----------------------------------------------------------------------------
-- 2) get_daily_question — global pick first, personal draw as the fallback.
--    Signature, return shape, clamp, seen-memory and assignment write are all
--    exactly 20260713120000; only the draw order changes.
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
  -- The daily needs an identity; the app always signs in (anonymous included)
  -- before fetching. An unauthenticated call gets no row.
  if v_uid is null then
    return;
  end if;

  -- Honour the device's local "today" but clamp to UTC ±1 (the widest a real
  -- timezone can be off), so a client can't harvest assignments for arbitrary
  -- dates. Out-of-window claims just get the server's today.
  if v_date is null or v_date < v_today - 1 or v_date > v_today + 1 then
    v_date := v_today;
  end if;

  -- Today's assignment, if it exists and its question is still active. Stored
  -- wins even over the global pick: a user who resolved their daily this
  -- morning must not watch it swap mid-day because the calendar changed.
  select ud.question_id into v_qid
  from public.user_daily_questions ud
  join public.questions q on q.id = ud.question_id and q.is_active
  where ud.user_id = v_uid and ud.assigned_on = v_date;

  if v_qid is null then
    -- Clear a stale assignment whose question was deactivated mid-day, so the
    -- redraw below can replace it instead of serving nothing.
    delete from public.user_daily_questions
     where user_id = v_uid and assigned_on = v_date;

    -- THE GLOBAL PICK: the curated question pinned to this date — the shared
    -- debate. Skipped only when the caller has already voted it (a PRO feed
    -- browser may have; re-serving it would show dead result bars as the whole
    -- day's content and cost a smaczek gate that can never open).
    select dp.question_id into v_qid
    from public.daily_picks dp
    join public.questions q on q.id = dp.question_id and q.is_active
    where dp.publish_date = v_date
      and not exists (
        select 1 from public.question_votes v
        where v.user_id = v_uid and v.question_id = dp.question_id
      );

    -- Personal fallback: any active question the user has NOT voted on,
    -- never-seen ones first (fresh over "shown but skipped"), random within
    -- each group. This is the whole daily for a gap date, and the collision
    -- escape for a caller who already voted the pick.
    if v_qid is null then
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
    end if;

    -- Voted on the whole catalog: fall back to the legacy calendar question
    -- for the date (deterministic, always exists while the calendar lasts) so
    -- the screen never comes up empty.
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
  -- gate and the vote guard read this.
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

comment on function public.get_daily_question(text, date) is
  'Serves (and on first call of the day assigns) the caller''s daily: the '
  'global daily_picks question for the date, falling back to a personal '
  'unvoted draw when the pick is missing, inactive, or already voted by the '
  'caller. See 20260820150000.';

-- ----------------------------------------------------------------------------
-- 3) peek_next_question — tease TOMORROW'S PICK when the caller can still meet
--    it as their daily; otherwise the old random unvoted pick. Teaser stays
--    the first 4 words (20260817160000); still a pure read, no writes.
--    The claimed date is clamped to UTC ±1 like everywhere else before the +1,
--    so a client cannot walk the future calendar by lying about its date.
-- ----------------------------------------------------------------------------
create or replace function public.peek_next_question(
  p_locale      text  default 'pl',
  p_date        date  default (now() at time zone 'utc')::date,
  p_exclude_ids uuid[] default '{}'
)
returns table (id uuid, teaser text)
language sql security definer set search_path to 'public'
as $$
  with bounds as (
    select least(greatest(coalesce(p_date, (now() at time zone 'utc')::date),
                          (now() at time zone 'utc')::date - 1),
                 (now() at time zone 'utc')::date + 1) + 1 as peek_date
  )
  select x.id, x.teaser
  from (
    -- Tomorrow's global pick: what the wall's countdown actually unlocks.
    (
      select 0 as pri, q.id,
             array_to_string(
               (regexp_split_to_array(
                  btrim(coalesce(tr.question_text, en.question_text)), '\s+'))[1:4],
               ' '
             ) as teaser
      from bounds b
      join public.daily_picks dp on dp.publish_date = b.peek_date
      join public.questions q on q.id = dp.question_id and q.is_active
      left join public.question_translations tr
             on tr.question_id = q.id and tr.locale = p_locale
      left join public.question_translations en
             on en.question_id = q.id and en.locale = 'en'
      where not (q.id = any (p_exclude_ids))
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
    )
    union all
    -- Fallback: random unvoted question outside the caller's own assignment
    -- window — exactly the pre-calendar behaviour, for gap dates and callers
    -- who already voted tomorrow's pick (their tomorrow IS a personal draw).
    (
      select 1 as pri, q.id,
             array_to_string(
               (regexp_split_to_array(
                  btrim(coalesce(tr.question_text, en.question_text)), '\s+'))[1:4],
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
      limit 1
    )
  ) x
  order by x.pri
  limit 1;
$$;

revoke all on function public.peek_next_question(text, date, uuid[]) from public;
grant execute on function public.peek_next_question(text, date, uuid[]) to authenticated;
