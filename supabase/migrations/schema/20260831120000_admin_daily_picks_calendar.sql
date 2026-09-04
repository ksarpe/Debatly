-- ============================================================================
-- Admin panel: the daily calendar becomes editable — from the day after
-- tomorrow onwards.
-- ----------------------------------------------------------------------------
-- 2026-08-31.
--
-- WHY
--   daily_picks (20260820150000) is owner-curated but SQL-editor-only: 396
--   future picks in one column, no way to see what lands on a given day and no
--   way to move a strong question onto a day with a big ad push. That is the
--   day the pick matters most — the traffic is new users, and for a free user
--   the daily IS the whole deck.
--
-- WHY TODAY AND TOMORROW ARE LOCKED (in the DB, not in the UI)
--   Today's pick is on screens and already written into user_daily_questions.
--   Tomorrow's is published too: get_daily_question clamps the caller's date
--   to UTC ±1, so a device at UTC+13 can already hold tomorrow's assignment;
--   the day wall teases tomorrow's pick through peek_next_question; and the
--   reminder loop bakes get_upcoming_daily_teasers text into notifications
--   that are already scheduled on the device. UTC today+2 is the first date no
--   device can have been assigned — so that is the floor.
--   (Changing a pick 2-5 days out can still contradict a teaser baked into a
--   notification on a device that has not opened the app since; the loop
--   re-arms on every launch/resume/vote, so it self-heals for anyone active.)
--
-- WHAT
--   admin_list_daily_picks        — a window over the calendar (gaps included)
--                                   with the facts needed to judge a pick.
--   admin_search_daily_candidates — catalog search for the swap picker: says
--                                   whether a question is already scheduled
--                                   and how many REAL votes it carries.
--   admin_set_daily_pick          — the single mutation. approver only.
--   admin_compact_daily_picks     — owner-triggered compact_daily_picks().
--
-- WHY THE MUTATION NEVER LEAVES A HOLE
--   compact_daily_picks() (20260820190000) re-dates every future pick onto
--   consecutive days from tomorrow, so ONE hole anywhere pulls EVERY later
--   pick a day earlier at 02:47 UTC — silently un-pinning the date somebody
--   just pinned for an ad day. Therefore: swapping two dates exchanges them in
--   place, and replacing a date parks the displaced question at the END of the
--   calendar instead of dropping it. Neither changes the number of future
--   picks, so compaction stays a no-op.
--   Same reason the list reports inactive future picks: those DO shift the
--   calendar on the next nightly run, and the owner should settle that shift
--   (button "Uporządkuj teraz") BEFORE pinning a date.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) The calendar window.
--    A date with no pick comes back as an empty row on purpose — a gap means
--    "personal draw for everyone that day", which is worth seeing.
--    Calendar-wide facts (cal_*) ride on every row, same trick as
--    admin_list_questions.total_count.
-- ----------------------------------------------------------------------------
create or replace function public.admin_list_daily_picks(
  p_from date default null,
  p_days int  default 45
) returns table (
  publish_date        date,
  question_id         uuid,
  pl                  text,
  en                  text,
  category            text,
  is_active           boolean,
  is_premium          boolean,
  smaczki_count       int,
  smaczki_untagged    int,
  votes               int,
  is_favorite         boolean,
  is_verified         boolean,
  locked              boolean,
  day_label           text,
  cal_future          int,
  cal_last_date       date,
  cal_inactive_future int,
  cal_first_editable  date
) language plpgsql stable security definer set search_path = public as $$
declare
  v_today date := (now() at time zone 'utc')::date;
  v_from  date := coalesce(p_from, (now() at time zone 'utc')::date);
  v_days  int  := greatest(1, least(coalesce(p_days, 45), 180));
begin
  perform public.admin_require();
  return query
  with days as (
    select d::date as day
    from generate_series(v_from, v_from + (v_days - 1), interval '1 day') d
  )
  select
    days.day,
    q.id,
    tp.question_text,
    te.question_text,
    q.category,
    q.is_active,
    q.is_premium,
    (select count(*)::int from public.question_smaczki s
      where s.question_id = q.id and s.is_active),
    (select count(*)::int from public.question_smaczki s
      where s.question_id = q.id and s.is_active and s.side is null),
    -- REAL votes only (question_votes), not the seeded split: this is the
    -- "how many people would land on result bars instead of the buttons".
    (select count(*)::int from public.question_votes v where v.question_id = q.id),
    exists (select 1 from public.admin_question_favorites f
             where f.question_id = q.id and f.user_id = auth.uid()),
    (q.verified_at is not null),
    (days.day < v_today + 2),
    case when days.day <  v_today     then 'past'
         when days.day =  v_today     then 'today'
         when days.day =  v_today + 1 then 'tomorrow'
         else '' end,
    (select count(*)::int from public.daily_picks x where x.publish_date > v_today),
    (select max(x.publish_date) from public.daily_picks x),
    (select count(*)::int
       from public.daily_picks x join public.questions xq on xq.id = x.question_id
      where x.publish_date > v_today and not xq.is_active),
    v_today + 2
  from days
  left join public.daily_picks dp on dp.publish_date = days.day
  left join public.questions q on q.id = dp.question_id
  left join public.question_translations tp on tp.question_id = q.id and tp.locale = 'pl'
  left join public.question_translations te on te.question_id = q.id and te.locale = 'en'
  order by days.day;
end;
$$;

revoke all on function public.admin_list_daily_picks(date, int) from public, anon;
grant execute on function public.admin_list_daily_picks(date, int) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2) The swap picker's search. Active questions only — an inactive pick is
--    deleted by the nightly compaction, so offering one would be a trap.
--    scheduled_on tells the panel whether choosing this question means a SWAP
--    (it already owns a date) or a REPLACE.
-- ----------------------------------------------------------------------------
create or replace function public.admin_search_daily_candidates(
  p_search           text    default null,
  p_only_favorites   boolean default false,
  p_only_unscheduled boolean default false,
  p_limit            int     default 30
) returns table (
  id                uuid,
  pl                text,
  en                text,
  category          text,
  is_premium        boolean,
  smaczki_count     int,
  smaczki_untagged  int,
  votes             int,
  is_favorite       boolean,
  is_verified       boolean,
  scheduled_on      date,
  total_count       int
) language plpgsql stable security definer set search_path = public as $$
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

revoke all on function public.admin_search_daily_candidates(text, boolean, boolean, int) from public, anon;
grant execute on function public.admin_search_daily_candidates(text, boolean, boolean, int) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 3) The mutation. approver only — this publishes to every device in the
--    world, which is the same weight as approving a draft.
--
--    p_expected_question_id = what the panel had on screen for that date. NULL
--    skips the check (SQL-editor use); a mismatch is refused instead of
--    overwriting a change made since the page loaded.
-- ----------------------------------------------------------------------------
create or replace function public.admin_set_daily_pick(
  p_date                 date,
  p_question_id          uuid,
  p_expected_question_id uuid default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_floor     date := (now() at time zone 'utc')::date + 2;
  v_cur       uuid;                 -- who sits on p_date now
  v_other     date;                 -- where p_question_id sits now, if anywhere
  v_end       date;                 -- last date in the whole calendar
  v_displaced date;
  v_action    text;
  v_active    boolean;
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

  select q.is_active into v_active from public.questions q where q.id = p_question_id;
  if not found then
    raise exception 'NOT_FOUND: no such question' using errcode = '22023';
  end if;
  if not v_active then
    raise exception 'QUESTION_INACTIVE: an inactive question is deleted from the calendar by the nightly compaction'
      using errcode = '22023';
  end if;

  select dp.question_id into v_cur from public.daily_picks dp where dp.publish_date = p_date;

  if p_expected_question_id is not null and v_cur is distinct from p_expected_question_id then
    raise exception 'CALENDAR_CHANGED: % now holds a different question', p_date
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

revoke all on function public.admin_set_daily_pick(date, uuid, uuid) from public, anon;
grant execute on function public.admin_set_daily_pick(date, uuid, uuid) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 4) Run the nightly compaction on demand. The panel offers it when the
--    calendar holds inactive future picks, so the owner can settle the
--    resulting date shift BEFORE pinning a question to an ad day instead of
--    discovering it at 02:47 UTC.
-- ----------------------------------------------------------------------------
create or replace function public.admin_compact_daily_picks()
returns text language plpgsql security definer set search_path = public as $$
begin
  perform public.admin_require(true);
  return public.compact_daily_picks();
end;
$$;

revoke all on function public.admin_compact_daily_picks() from public, anon;
grant execute on function public.admin_compact_daily_picks() to authenticated, service_role;

-- The table comment from 20260820150000 said "written only via the SQL editor /
-- service_role". That stops being true here.
comment on table public.daily_picks is
  'Owner-curated global daily calendar: the question the whole world debates '
  'on publish_date. A missing date falls back to the personal draw in '
  'get_daily_question. Written from the admin panel (admin_set_daily_pick, '
  'approver only, never earlier than UTC today+2) or via the SQL editor / '
  'service_role.';

comment on function public.admin_set_daily_pick(date, uuid, uuid) is
  'Admin panel: put a question on a daily_picks date (approver only). Refuses '
  'anything before UTC today+2 — today and tomorrow are already on devices. '
  'Swaps in place / parks the displaced question at the end of the calendar so '
  'the future pick COUNT never changes and compact_daily_picks() stays a no-op. '
  'See 20260831120000.';
