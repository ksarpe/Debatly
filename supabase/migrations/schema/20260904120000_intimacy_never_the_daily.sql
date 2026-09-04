-- ============================================================================
-- "Seks i intymność" is never the daily (2026-09-04)
-- ----------------------------------------------------------------------------
-- WHY
--   The Intimacy category (QuestionMode.intimacy, 2026-09-02) is a PRO-only
--   topic mode. The daily question is free for everyone and shows up on the
--   day wall, in the reminder notifications and on the onboarding bridge —
--   the one place a free user reads the catalog. An intimacy question there
--   would (a) hand the PRO mode's content to the free tier one day at a time
--   and (b) put mature-discussion text into the notification tray and the
--   first screen, which the 3+/14+ store ratings were not written for.
--
--   Category is text with no constraint, so nothing stopped the admin panel
--   or the draws from picking one. This is the server-side fence the client
--   brief promised "with the first INSERT batch" — applied BEFORE the batch,
--   so the first Intimacy row is already safe.
--
-- WHAT
--   * is_daily_eligible_category(text) — the single predicate every draw
--     reads. One place to extend if another topic is ever fenced the same way.
--   * daily_picks trigger — the calendar itself refuses an ineligible
--     question, whatever wrote it (admin RPC, SQL editor, a script).
--   * admin_set_daily_pick raises QUESTION_EXCLUDED (the panel maps it) and
--     admin_search_daily_candidates never lists one.
--   * get_daily_question's personal fallback, peek_next_question's gap
--     fallback, and the LEGACY reveal_free_question / reveal_ad_question draws
--     (still live for pre-freemium app versions, whose free users drew from
--     the whole catalog) all skip the category.
--   * get_questions is untouched: PRO sees the whole catalog by design and
--     the client filters by mode; free rows come back locked with no text.
--
-- Hygiene, same migration: billing_event_telegram_notify() kept the default
-- PUBLIC execute — a trigger function needs none, and the advisor flags it.
--
-- Idempotent: every object is create-or-replace / drop-if-exists.
-- ============================================================================

create or replace function public.is_daily_eligible_category(p_category text)
returns boolean
language sql
immutable
parallel safe
as $$
  select p_category is distinct from 'Intimacy';
$$;

comment on function public.is_daily_eligible_category(text) is
  'Whether a question of this category may be the daily (calendar, personal '
  'fallback, wall teaser, legacy reveals). Intimacy is a PRO-only mode and '
  'never is.';

-- ----------------------------------------------------------------------------
-- The calendar refuses an ineligible question at the row level.
-- ----------------------------------------------------------------------------
create or replace function public.daily_picks_reject_ineligible()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cat text;
begin
  select q.category into v_cat from public.questions q where q.id = new.question_id;
  if not public.is_daily_eligible_category(v_cat) then
    raise exception 'QUESTION_EXCLUDED: category % is never the daily', v_cat
      using errcode = '22023';
  end if;
  return new;
end;
$$;

revoke all on function public.daily_picks_reject_ineligible() from public, anon, authenticated;

drop trigger if exists daily_picks_reject_ineligible on public.daily_picks;
create trigger daily_picks_reject_ineligible
  before insert or update of question_id on public.daily_picks
  for each row execute function public.daily_picks_reject_ineligible();

-- ----------------------------------------------------------------------------
-- Admin panel: a friendly code before the trigger's, and no such candidate.
-- ----------------------------------------------------------------------------
create or replace function public.admin_set_daily_pick(
  p_date date,
  p_question_id uuid,
  p_expected_question_id uuid default null,
  p_expect_empty boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_floor     date := (now() at time zone 'utc')::date + 2;
  v_cur       uuid;                 -- who sits on p_date now
  v_other     date;                 -- where p_question_id sits now, if anywhere
  v_end       date;                 -- last date in the whole calendar
  v_displaced date;
  v_action    text;
  v_active    boolean;
  v_cat       text;
  v_new_pl    text;
  v_cur_pl    text;
begin
  perform public.admin_require(true);

  if p_date is null or p_question_id is null then
    raise exception 'BAD_ARGS: date and question are required' using errcode = '22023';
  end if;

  -- The floor. Enforced here so no UI, script or stale tab can go under it.
  if p_date < v_floor then
    raise exception 'DAY_LOCKED: % is today or tomorrow (first editable: %)', p_date, v_floor
      using errcode = '22023';
  end if;

  select q.is_active, q.category into v_active, v_cat
    from public.questions q where q.id = p_question_id;
  if not found then
    raise exception 'NOT_FOUND: no such question' using errcode = '22023';
  end if;
  if not v_active then
    raise exception 'QUESTION_INACTIVE: an inactive question is deleted from the calendar by the nightly compaction'
      using errcode = '22023';
  end if;
  if not public.is_daily_eligible_category(v_cat) then
    raise exception 'QUESTION_EXCLUDED: category % is never the daily', v_cat
      using errcode = '22023';
  end if;

  select dp.question_id into v_cur from public.daily_picks dp where dp.publish_date = p_date;

  -- The optimistic lock, both directions: the panel saw a question (expected id
  -- must still sit there) or the panel saw a gap (the day must still be empty).
  if p_expected_question_id is not null and v_cur is distinct from p_expected_question_id then
    raise exception 'CALENDAR_CHANGED: % now holds a different question', p_date
      using errcode = '22023';
  end if;
  if p_expect_empty and v_cur is not null then
    raise exception 'CALENDAR_CHANGED: % is no longer empty', p_date
      using errcode = '22023';
  end if;

  if v_cur = p_question_id then
    return jsonb_build_object('action', 'noop', 'date', p_date, 'question_id', p_question_id);
  end if;

  select dp.publish_date into v_other
    from public.daily_picks dp where dp.question_id = p_question_id;

  -- A question is the daily at most once (daily_picks.question_id is UNIQUE),
  -- so one sitting on a past/today/tomorrow date cannot be moved here.
  if v_other is not null and v_other < v_floor then
    raise exception 'QUESTION_USED: this question is already the daily on % and that date is locked', v_other
      using errcode = '22023';
  end if;

  select t.question_text into v_new_pl from public.question_translations t
   where t.question_id = p_question_id and t.locale = 'pl';
  if v_cur is not null then
    select t.question_text into v_cur_pl from public.question_translations t
     where t.question_id = v_cur and t.locale = 'pl';
  end if;

  select max(dp.publish_date) into v_end from public.daily_picks dp;

  if v_other is not null and v_cur is not null then
    -- Straight exchange. Delete+insert because question_id is UNIQUE and a
    -- two-step UPDATE would collide on it mid-flight.
    v_action := 'swap';
    delete from public.daily_picks where publish_date in (p_date, v_other);
    insert into public.daily_picks (publish_date, question_id)
    values (p_date, p_question_id), (v_other, v_cur);

  elsif v_other is not null then
    -- The target date is a gap: move the pick here. That opens a hole at its
    -- old date, which the nightly compaction closes by pulling everything
    -- after it one day earlier — reported back so the panel can say so.
    v_action := 'moved';
    update public.daily_picks set publish_date = p_date where publish_date = v_other;

  elsif v_cur is not null then
    -- Replace. The displaced question goes to the END of the calendar rather
    -- than out of it: the number of future picks is unchanged, so compaction
    -- stays a no-op and no other date moves.
    v_action := 'replace';
    v_displaced := v_end + 1;
    delete from public.daily_picks where publish_date = p_date;
    insert into public.daily_picks (publish_date, question_id)
    values (p_date, p_question_id), (v_displaced, v_cur);

  else
    v_action := 'insert';
    insert into public.daily_picks (publish_date, question_id) values (p_date, p_question_id);
  end if;

  -- Audit: one row per question touched, so a calendar move also shows up in
  -- that question's own history screen.
  insert into public.admin_audit_log (question_id, action, actor, before, after)
  values (p_question_id, 'daily_pick_set', auth.uid(),
          jsonb_build_object('publish_date', v_other),
          jsonb_build_object('publish_date', p_date, 'op', v_action));
  if v_cur is not null then
    insert into public.admin_audit_log (question_id, action, actor, before, after)
    values (v_cur, 'daily_pick_moved', auth.uid(),
            jsonb_build_object('publish_date', p_date),
            jsonb_build_object('publish_date', coalesce(v_other, v_displaced), 'op', v_action));
  end if;

  return jsonb_build_object(
    'action', v_action,
    'date', p_date,
    'question_id', p_question_id,
    'question_pl', v_new_pl,
    'previous_question_id', v_cur,
    'previous_pl', v_cur_pl,
    'swapped_from', v_other,
    'displaced_to', coalesce(v_other, v_displaced),
    'gap_left_at', case when v_action = 'moved' then v_other end
  );
end;
$$;

create or replace function public.admin_search_daily_candidates(
  p_search text default null,
  p_only_favorites boolean default false,
  p_only_unscheduled boolean default false,
  p_limit integer default 30
)
returns table(
  id uuid, pl text, en text, category text, is_premium boolean,
  smaczki_count integer, smaczki_untagged integer, votes integer,
  is_favorite boolean, is_verified boolean, scheduled_on date, total_count integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.admin_require();
  return query
  with base as (
    select q.id, q.category, q.is_premium,
           tp.question_text as pl, te.question_text as en,
           (q.verified_at is not null) as is_verified,
           exists (select 1 from public.admin_question_favorites f
                    where f.question_id = q.id and f.user_id = auth.uid()) as is_favorite,
           (select x.publish_date from public.daily_picks x
             where x.question_id = q.id) as scheduled_on
    from public.questions q
    left join public.question_translations tp on tp.question_id = q.id and tp.locale = 'pl'
    left join public.question_translations te on te.question_id = q.id and te.locale = 'en'
    where q.is_active
      and public.is_daily_eligible_category(q.category)
      and (not p_only_favorites or exists
             (select 1 from public.admin_question_favorites f
               where f.question_id = q.id and f.user_id = auth.uid()))
      and (not p_only_unscheduled
           or not exists (select 1 from public.daily_picks x where x.question_id = q.id))
      and (p_search is null or btrim(p_search) = ''
           or tp.question_text ilike '%' || p_search || '%'
           or te.question_text ilike '%' || p_search || '%')
  )
  select b.id, b.pl, b.en, b.category, b.is_premium,
         (select count(*)::int from public.question_smaczki s
           where s.question_id = b.id and s.is_active),
         (select count(*)::int from public.question_smaczki s
           where s.question_id = b.id and s.is_active and s.side is null),
         (select count(*)::int from public.question_votes v where v.question_id = b.id),
         b.is_favorite, b.is_verified, b.scheduled_on,
         (select count(*)::int from base)
  from base b
  order by b.pl
  limit greatest(1, least(coalesce(p_limit, 30), 100));
end;
$$;

-- ----------------------------------------------------------------------------
-- The daily itself: the pick join and the personal fallback both skip it.
-- ----------------------------------------------------------------------------
create or replace function public.get_daily_question(
  p_locale text default 'pl',
  p_date date default (now() at time zone 'utc')::date
)
returns table(id uuid, category text, is_premium boolean, question_text text, publish_date date)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_today date := (now() at time zone 'utc')::date;
  v_date  date := p_date;
  v_qid   uuid;
begin
  if v_uid is null then
    return;
  end if;

  if v_date is null or v_date < v_today - 1 or v_date > v_today + 1 then
    v_date := v_today;
  end if;

  select ud.question_id into v_qid
  from public.user_daily_questions ud
  join public.questions q on q.id = ud.question_id and q.is_active
  where ud.user_id = v_uid and ud.assigned_on = v_date;

  if v_qid is null then
    delete from public.user_daily_questions
     where user_id = v_uid and assigned_on = v_date;

    -- THE GLOBAL PICK — outranks the caller's vote history: premium always
    -- lands here (voted = result bars), free lands here when unvoted or when
    -- the old vote melts (_daily_pick_revote_ok).
    select dp.question_id into v_qid
    from public.daily_picks dp
    join public.questions q on q.id = dp.question_id and q.is_active
    where dp.publish_date = v_date
      and public.is_daily_eligible_category(q.category)
      and (
        public.is_premium(v_uid)
        or not exists (
          select 1 from public.question_votes v
          where v.user_id = v_uid and v.question_id = dp.question_id
        )
        or public._daily_pick_revote_ok(v_uid, dp.question_id)
      );

    -- Personal fallback: unvoted, never-seen first, random — FUTURE picks are
    -- off limits (the fallback used to burn the shared calendar), and so is
    -- a category that is never the daily.
    if v_qid is null then
      select q.id into v_qid
      from public.questions q
      where q.is_active
        and public.is_daily_eligible_category(q.category)
        and not exists (
          select 1 from public.question_votes v
          where v.user_id = v_uid and v.question_id = q.id
        )
        and not exists (
          select 1 from public.daily_picks dp
          where dp.question_id = q.id and dp.publish_date > v_date
        )
      order by
        exists (
          select 1 from public.question_seen s
          where s.user_id = v_uid and s.question_id = q.id
        ) asc,
        random()
      limit 1;
    end if;

    if v_qid is null then
      select d.question_id into v_qid
      from public.daily_questions d
      join public.questions q on q.id = d.question_id and q.is_active
      where d.publish_date = v_date
        and public.is_daily_eligible_category(q.category);
    end if;

    if v_qid is null then
      return;
    end if;

    insert into public.user_daily_questions (user_id, assigned_on, question_id)
    values (v_uid, v_date, v_qid)
    on conflict (user_id, assigned_on) do nothing;

    select ud.question_id into v_qid
    from public.user_daily_questions ud
    where ud.user_id = v_uid and ud.assigned_on = v_date;
  end if;

  insert into public.question_seen (user_id, question_id, source)
  values (v_uid, v_qid, 'daily')
  on conflict (user_id, question_id) do nothing;

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

-- ----------------------------------------------------------------------------
-- The day wall's teaser: tomorrow's pick (fenced by the trigger, but the
-- join says so too) and the gap-date fallback.
-- ----------------------------------------------------------------------------
create or replace function public.peek_next_question(
  p_locale text default 'pl',
  p_date date default (now() at time zone 'utc')::date,
  p_exclude_ids uuid[] default '{}'
)
returns table(id uuid, teaser text)
language sql
security definer
set search_path = public
as $$
  with bounds as (
    select least(greatest(coalesce(p_date, (now() at time zone 'utc')::date),
                          (now() at time zone 'utc')::date - 1),
                 (now() at time zone 'utc')::date + 1) + 1 as peek_date
  )
  select x.id, x.teaser
  from (
    (
      -- Tomorrow's pick, for everyone: no vote / assignment lookups, so the
      -- wall's promise and tomorrow's reminder name the same question.
      select 0 as pri, q.id,
             rtrim(
               array_to_string(
                 (regexp_split_to_array(
                    btrim(coalesce(tr.question_text, en.question_text)), '\s+'))[1:4],
                 ' '
               ),
               ' ,;:-' || U&'\2013' || U&'\2014'
             ) as teaser
      from bounds b
      join public.daily_picks dp on dp.publish_date = b.peek_date
      join public.questions q on q.id = dp.question_id and q.is_active
      left join public.question_translations tr
             on tr.question_id = q.id and tr.locale = p_locale
      left join public.question_translations en
             on en.question_id = q.id and en.locale = 'en'
      where not (q.id = any (p_exclude_ids))
        and public.is_daily_eligible_category(q.category)
        and btrim(coalesce(tr.question_text, en.question_text, '')) <> ''
    )
    union all
    (
      -- Gap date (no pick tomorrow, or an inactive one): a random question
      -- the caller has not met, as before.
      select 1 as pri, q.id,
             rtrim(
               array_to_string(
                 (regexp_split_to_array(
                    btrim(coalesce(tr.question_text, en.question_text)), '\s+'))[1:4],
                 ' '
               ),
               ' ,;:-' || U&'\2013' || U&'\2014'
             ) as teaser
      from public.questions q
      left join public.question_translations tr
             on tr.question_id = q.id and tr.locale = p_locale
      left join public.question_translations en
             on en.question_id = q.id and en.locale = 'en'
      where q.is_active
        and public.is_daily_eligible_category(q.category)
        and not (q.id = any (p_exclude_ids))
        and btrim(coalesce(tr.question_text, en.question_text, '')) <> ''
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

-- ----------------------------------------------------------------------------
-- Legacy reveals — live for pre-freemium app versions whose FREE users drew
-- from the whole catalog. Same fence, both the peeked id and the random draw.
-- ----------------------------------------------------------------------------
create or replace function public.reveal_free_question(
  p_locale text default 'pl',
  p_date date default (now() at time zone 'utc')::date,
  p_exclude_ids uuid[] default '{}'
)
returns table(id uuid, category text, is_premium boolean, question_text text)
language plpgsql
security definer
set search_path = public
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
    and public.is_daily_eligible_category(q.category)
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

create or replace function public.reveal_ad_question(
  p_locale text default 'pl',
  p_date date default (now() at time zone 'utc')::date,
  p_question_id uuid default null,
  p_exclude_ids uuid[] default '{}'
)
returns table(id uuid, category text, is_premium boolean, question_text text)
language plpgsql
security definer
set search_path = public
as $$
declare
  c_grace     constant int := 2;
  v_uid       uuid := auth.uid();
  v_today     date := (now() at time zone 'utc')::date; -- server clock, not p_date
  v_qid       uuid;
  v_used      int;
  v_verified  int;
  v_ads_today int;
  v_last_ad   date;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  -- Lock the profile row so two concurrent taps can't both pass the gates.
  select p.ad_reveals_used, p.ad_reveals_today, p.last_ad_reveal_date
    into v_used, v_ads_today, v_last_ad
  from public.profiles p
  where p.id = v_uid
  for update;

  -- Daily cap gate: lazy reset when the last ad reveal was on an earlier day.
  if v_last_ad is distinct from v_today then
    v_ads_today := 0;
  end if;
  if coalesce(v_ads_today, 0) >= public.ad_reveal_daily_cap() then
    raise exception 'daily ad reveal limit reached';
  end if;

  -- Budget gate: the reveal must be backed by a verified ad reward (+ grace).
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
      and public.is_daily_eligible_category(q.category)
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

  -- No (valid) peek: random UNVOTED pick, skipping this session's shown ids.
  if v_qid is null then
    select q.id into v_qid
    from public.questions q
    where q.is_active
      and public.is_daily_eligible_category(q.category)
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

  -- Spend one unit of the ad-reveal budget and one slot of today's cap.
  update public.profiles
     set ad_reveals_used     = coalesce(v_used, 0) + 1,
         ad_reveals_today    = coalesce(v_ads_today, 0) + 1,
         last_ad_reveal_date = v_today
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

-- ----------------------------------------------------------------------------
-- Hygiene: a trigger function needs no EXECUTE for API roles.
-- ----------------------------------------------------------------------------
revoke all on function public.billing_event_telegram_notify() from public, anon, authenticated;
