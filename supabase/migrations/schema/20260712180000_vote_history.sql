-- ============================================================================
-- History = EVERY question you voted on (was: past dailies only).
--
-- WHY
--   With the votable-feed pivot (20260712160000) every unlocked question is
--   votable and shows the community split, so "history" framed as a table of
--   past DAILIES no longer matches how the app works: a user who votes ten
--   times a day through the feed would still see only their daily votes.
--   The new history is simply the user's voting record — every question they
--   ever voted on, with the live community split — ordered by when they voted,
--   newest first.
--
-- WHAT CHANGES
--   * New RPC `get_vote_history(p_locale)`: rows come from the caller's own
--     `question_votes`, not from `daily_questions`. No date clamp is needed —
--     you can only have voted on a question you were actually shown (the
--     cast_daily_vote guard), so nothing future/unseen can leak through here.
--   * `voted_at` (timestamptz) replaces `publish_date`: the row's date is when
--     YOU voted, which exists for every vote — feed votes have no publish date.
--     Returned as a timestamp so the client can render it in local time.
--   * Today's daily appears as soon as you vote on it (no "past only" wall):
--     you cast the vote and saw the split, so hiding it for a day bought
--     nothing and made the screen look broken ("I just voted, where is it?").
--
-- UNCHANGED
--   * PREMIUM ONLY, same shape as get_daily_history: no session / no premium
--     → zero rows, and the client renders the PRO upsell.
--   * Tallies aggregated server-side over ALL of question_votes (daily + feed
--     votes are indistinguishable by design). 1 = TAK, 2 = NIE.
--   * `get_daily_history` is left in place untouched — clients already in the
--     stores still call it. Drop it once those versions are retired.
-- ============================================================================

create function public.get_vote_history(
  p_locale text default 'pl'
)
returns table(
  question_id uuid,
  category text,
  question_text text,
  voted_at timestamptz,
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
      mv.voted_at,
      coalesce(vc.yes_count, 0),
      coalesce(vc.no_count, 0),
      mv.choice::int
    from public.question_votes mv
    join public.questions q on q.id = mv.question_id and q.is_active
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
    where mv.user_id = v_uid
    order by mv.voted_at desc
    limit 1000;
end;
$function$;

revoke all on function public.get_vote_history(text) from public, anon;
grant execute on function public.get_vote_history(text) to authenticated, service_role;
