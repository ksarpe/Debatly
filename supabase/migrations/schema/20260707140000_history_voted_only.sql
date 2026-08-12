-- Daily history: restrict to past dailies the caller ACTUALLY VOTED ON.
--
-- Why: the history used to return every past daily with its community TAK/NIE
-- split regardless of whether the user had voted. That let a user open the
-- history and read the results of days they skipped — removing the reason to log
-- in and vote each day. Now the community split is a *reward for voting*: you can
-- only see how a past daily went if you voted on it while it was live. Miss a day
-- and that result stays hidden, so daily engagement is the only way in.
--
-- Everything else is unchanged from 20260623130000_daily_history.sql:
--   * PREMIUM ONLY (guest / free → zero rows; client shows a PRO upsell).
--   * PAST DAYS ONLY, clamped to the server UTC clock (never leak future dailies).
--   * Tallies aggregated server-side. 1 = TAK, 2 = NIE.
--
-- The only added constraint is `mv.choice is not null` in the WHERE clause: the
-- caller must have a vote row for that daily. Because votes are only ever cast
-- via cast_daily_vote (gated on can_read_question_text, and the vote panel only
-- shows on the live daily), a vote row means the user voted while it was the
-- daily. As a side effect `my_choice` is now always non-null, so every history
-- row shows the caller's own side.

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
  v_uid uuid := auth.uid();
begin
  -- History is a PRO feature: no session or no premium → nothing to show.
  if v_uid is null or not public.is_premium(v_uid) then
    return;
  end if;

  return query
    select
      q.id,
      q.category,
      coalesce(tr.question_text, en.question_text),
      d.publish_date,
      coalesce(vc.yes_count, 0),
      coalesce(vc.no_count, 0),
      mv.choice::int
    from public.daily_questions d
    join public.questions q on q.id = d.question_id and q.is_active
    -- Only surface a past daily the caller voted on. INNER join on the caller's
    -- own vote row is what walls off the "peek at days I skipped" loophole.
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
    where d.publish_date < p_date
      and d.publish_date <= (now() at time zone 'utc')::date
    order by d.publish_date desc
    limit 366;
end;
$function$;

-- Grants are unchanged; restated for a fresh environment applying migrations in
-- order (execute is revoked from public/anon in 20260702120000).
revoke all on function public.get_daily_history(text, date) from public, anon;
grant execute on function public.get_daily_history(text, date) to authenticated, service_role;
