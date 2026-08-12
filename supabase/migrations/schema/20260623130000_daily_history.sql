-- Daily history (premium-only): a read-back of every PAST daily question with
-- the community TAK/NIE split and the caller's own vote.
--
-- Why: once a day rolls over, that question stops being "the daily" and melts
-- back into the general pool, so a user who wasn't around can no longer see how
-- the vote went. PRO users get a bottom-sheet history to catch up on missed days.
--
-- Gating decisions:
--   * PREMIUM ONLY. A guest / free user gets ZERO rows (the client shows a PRO
--     upsell instead). Premium can already read every active question's text via
--     get_questions, so returning the text here leaks nothing new.
--   * PAST DAYS ONLY. The daily calendar is pre-filled with FUTURE dates too, so
--     we must never return them — that would reveal tomorrow's question early.
--     The natural bound is `publish_date < p_date` (p_date = the caller's local
--     today, so today's still-votable daily on the home screen is excluded). We
--     ALSO clamp to the server UTC clock (`<= utc_today`) so a spoofed p_date far
--     in the future can't surface the upcoming schedule.
--   * Vote tallies are aggregated server-side (a user never reads other users'
--     vote rows), mirroring get_daily_vote_state. 1 = TAK, 2 = NIE.

-- Drop the earlier "archive" name (renamed to "history" 2026-06-23) so the
-- function has a single canonical name; idempotent for fresh environments.
drop function if exists public.get_daily_archive(text, date);

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
    left join public.question_votes mv
           on mv.question_id = q.id and mv.user_id = v_uid
    where d.publish_date < p_date
      and d.publish_date <= (now() at time zone 'utc')::date
    order by d.publish_date desc
    limit 366;
end;
$function$;

grant execute on function public.get_daily_history(text, date) to authenticated;
