-- ============================================================================
-- VOTE-FARMING MONITORING: tighten `instant_first_vote` from 60s to 5s
--
-- WHY
--   The 60-second threshold was calibrated for a hard-paywall app where the
--   anonymous session was minted long before the first question was readable.
--   Under freemium the app lands straight on the feed, so a normal human votes
--   within ~20 seconds of the session being created — the owner does it in
--   under 20 himself. Result: the flag fired on ordinary users and the
--   "Podejrzane konta" tile was permanently non-zero (24 accounts at the time
--   of writing, ALL of them tripping this one signal and nothing else), which
--   trains the reviewer to ignore the panel — the opposite of what a warning
--   tile is for.
--
--   5 seconds is below the floor of a real session: read the question, decide,
--   tap. Anything faster is a script or an app that never rendered a question.
--   The other two signals (no_app_events, over_free_budget) are unchanged.
--
-- This only narrows a heuristic view — no data, no app behaviour, no grants.
-- Idempotent: create-or-replace. Grants from 20260713150000 survive.
-- ============================================================================

create or replace view public.admin_vote_farming_suspects as
with votes_per_day as (
  select
    v.user_id,
    (v.voted_at at time zone 'utc')::date as vote_day,
    count(*) as votes_that_day
  from public.question_votes v
  group by 1, 2
),
per_user as (
  select
    d.user_id,
    sum(d.votes_that_day)::int as vote_count,
    count(*)::int              as active_days,
    max(d.votes_that_day)::int as max_votes_in_one_day
  from votes_per_day d
  group by 1
),
vote_span as (
  select
    v.user_id,
    min(v.voted_at) as first_vote_at,
    max(v.voted_at) as last_vote_at
  from public.question_votes v
  group by 1
)
select
  u.id                                   as user_id,
  u.created_at                           as account_created_at,
  coalesce(u.is_anonymous, false)        as is_anonymous,
  public.is_premium(u.id)                as is_premium,
  p.vote_count,
  p.active_days,
  p.max_votes_in_one_day,
  s.first_vote_at,
  s.last_vote_at,
  extract(epoch from (s.first_vote_at - u.created_at))::int
                                         as secs_to_first_vote,
  not exists (
    select 1 from public.app_events e where e.user_id = u.id
  )                                      as no_app_events,
  (s.first_vote_at - u.created_at) < interval '5 seconds'
                                         as instant_first_vote,
  (not public.is_premium(u.id) and p.max_votes_in_one_day > 12)
                                         as over_free_budget
from per_user p
join vote_span s using (user_id)
join auth.users u on u.id = p.user_id
where
  not exists (select 1 from public.app_events e where e.user_id = u.id)
  or (s.first_vote_at - u.created_at) < interval '5 seconds'
  or (not public.is_premium(u.id) and p.max_votes_in_one_day > 12);

comment on view public.admin_vote_farming_suspects is
  'Admin-only bot heuristics: accounts with votes that trip >=1 farming signal (no app_events / first vote <5s after signup / over free unlock budget). Read via SQL editor or service_role; never granted to client roles.';
