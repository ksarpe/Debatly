-- ============================================================================
-- Perf: get_vote_history was O(votes cast), not O(rows shown).
--
-- THE PROBLEM (20260712180000)
--   The query put a correlated `left join lateral` community tally on EVERY row,
--   and the `limit 1000` was applied only AFTER the join + sort. So for a user
--   who voted N times through the feed, it ran N separate tally aggregations
--   (each a scan of question_votes for that question) plus 2N translation joins
--   before throwing away everything past 1000. With the votable feed a single
--   active user racks up hundreds of votes fast, so history got slow to load.
--
-- THE FIX (same signature + return shape + premium gate)
--   1) `mine` CTE takes the user's latest 1000 votes FIRST (bounded work).
--   2) `splits` computes every tally in ONE grouped pass over just those
--      questions (question_votes(question_id) index), instead of N laterals.
--   3) New index question_votes(user_id, voted_at desc) so step 1 is an ordered
--      index scan with no sort of the user's whole vote history.
--
-- Reads only, so applying this cannot corrupt anything; it just replaces the
-- function body and adds an index. Still PRO-only; still 1 = TAK, 2 = NIE.
--
-- NOTE (future): every live tally — here AND get_daily_vote_state on each vote
-- panel — is a count over question_votes. If vote volume grows large, denormalise
-- a per-question counts table maintained by a trigger and read that instead.
-- ============================================================================

create index if not exists question_votes_user_voted_at_idx
  on public.question_votes (user_id, voted_at desc);

create or replace function public.get_vote_history(
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
  with mine as (
    -- The caller's most recent 1000 votes — bound the work BEFORE tallying.
    select mv.question_id, mv.choice, mv.voted_at
    from public.question_votes mv
    where mv.user_id = v_uid
    order by mv.voted_at desc
    limit 1000
  ),
  splits as (
    -- One grouped pass for the community split of just those questions.
    select v.question_id,
           count(*) filter (where v.choice = 1)::int as yes_count,
           count(*) filter (where v.choice = 2)::int as no_count
    from public.question_votes v
    where v.question_id in (select m.question_id from mine m)
    group by v.question_id
  )
  select
    q.id,
    q.category,
    coalesce(tr.question_text, en.question_text),
    mine.voted_at,
    coalesce(s.yes_count, 0),
    coalesce(s.no_count, 0),
    mine.choice::int
  from mine
  join public.questions q on q.id = mine.question_id and q.is_active
  left join public.question_translations tr
         on tr.question_id = q.id and tr.locale = p_locale
  left join public.question_translations en
         on en.question_id = q.id and en.locale = 'en'
  left join splits s on s.question_id = mine.question_id
  order by mine.voted_at desc;
end;
$function$;

revoke all on function public.get_vote_history(text) from public, anon;
grant execute on function public.get_vote_history(text) to authenticated, service_role;
