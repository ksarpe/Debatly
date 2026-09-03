-- ============================================================================
-- admin_set_daily_pick: the optimistic lock also covers EMPTY days.
-- ----------------------------------------------------------------------------
-- 2026-08-31.
--
-- WHY
--   20260831120000 gave the mutation p_expected_question_id: what the panel had
--   on screen for the date, refused on mismatch (CALENDAR_CHANGED). But NULL
--   means "skip the check" (SQL-editor convenience) — and NULL is also exactly
--   what the panel sends for a GAP day, because a gap has no question id. So
--   two approvers filling the same empty day never conflict: the second one's
--   "Wstaw" (confirmed against "this day has no pick") silently becomes a
--   replace, shoving the first approver's fresh pick to the END of the
--   calendar. That is the very overwrite the lock exists to refuse, and the
--   admin README promises it is refused.
--
-- WHAT
--   p_expect_empty boolean default false — the panel passes true when the row
--   it rendered was a gap; the mutation then refuses if the day has since
--   gained a pick. Defaults keep both old callers intact: the SQL editor
--   (nothing passed → both checks skipped) and any stale panel build (3-arg
--   call → PostgREST fills the default).
--
--   The 3-arg signature is dropped rather than kept alongside: two overloads
--   would make every PostgREST rpc call ambiguous.
-- ============================================================================

drop function if exists public.admin_set_daily_pick(date, uuid, uuid);

create or replace function public.admin_set_daily_pick(
  p_date                 date,
  p_question_id          uuid,
  p_expected_question_id uuid    default null,
  p_expect_empty         boolean default false
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

revoke all on function public.admin_set_daily_pick(date, uuid, uuid, boolean) from public, anon;
grant execute on function public.admin_set_daily_pick(date, uuid, uuid, boolean) to authenticated, service_role;

comment on function public.admin_set_daily_pick(date, uuid, uuid, boolean) is
  'Admin panel: put a question on a daily_picks date (approver only). Refuses '
  'anything before UTC today+2 — today and tomorrow are already on devices. '
  'Swaps in place / parks the displaced question at the end of the calendar so '
  'the future pick COUNT never changes and compact_daily_picks() stays a no-op. '
  'Optimistic lock: p_expected_question_id for an occupied day, p_expect_empty '
  'for a gap — either mismatch is CALENDAR_CHANGED. See 20260831150000.';
