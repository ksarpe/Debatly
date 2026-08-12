-- ============================================================================
-- VOTE-FARMING MONITORING (admin-only views, no app change)
--
-- WHY
--   Votes are already hard to farm at the write path: one vote per
--   (user_id, question_id), and cast_daily_vote only accepts questions the
--   caller can read — which for a free account means server-side RANDOM draws
--   (personal daily + reveal pool), so a bot cannot target a specific
--   question. The remaining cheap vector is mass-created anonymous accounts
--   adding noise. These views make that visible BEFORE it needs any
--   enforcement.
--
-- SIGNALS (heuristics, not verdicts — a human reads these)
--   * no_app_events      — the app emits first-party analytics into
--                          app_events; an account with votes but ZERO events
--                          almost certainly never ran the real app (script
--                          hitting the API directly). A sophisticated bot
--                          could fake events (insert is open to clients), so
--                          treat this as a strong hint, not proof.
--   * instant_first_vote — first vote < 60s after account creation. Weak on
--                          its own (an eager human can vote fast after the
--                          anonymous session is created), included as a
--                          corroborating column.
--   * over_free_budget   — a non-premium account voting on >12 questions in
--                          one UTC day exceeds what the unlock budget
--                          (daily + credit + capped ad reveals) plausibly
--                          allows.
--
-- ACCESS
--   Admin-only: revoked from public/anon/authenticated, readable via the
--   dashboard SQL editor / service_role only. The views are owner-rights
--   (postgres) on purpose — they must read auth.users and app_events, which
--   client roles cannot. Because client roles hold no grant, PostgREST never
--   exposes them; the security-definer-view advisor warning (if it appears)
--   is acceptable here.
--
-- Idempotent: create-or-replace + guarded revokes/grants.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Per-account suspect list: every account with >=1 vote that trips at
--    least one signal. Raw numbers are exposed alongside the boolean flags so
--    a reviewer can judge borderline rows.
-- ----------------------------------------------------------------------------
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
  (s.first_vote_at - u.created_at) < interval '60 seconds'
                                         as instant_first_vote,
  (not public.is_premium(u.id) and p.max_votes_in_one_day > 12)
                                         as over_free_budget
from per_user p
join vote_span s using (user_id)
join auth.users u on u.id = p.user_id
where
  not exists (select 1 from public.app_events e where e.user_id = u.id)
  or (s.first_vote_at - u.created_at) < interval '60 seconds'
  or (not public.is_premium(u.id) and p.max_votes_in_one_day > 12);

comment on view public.admin_vote_farming_suspects is
  'Admin-only bot heuristics: accounts with votes that trip >=1 farming signal (no app_events / instant first vote / over free unlock budget). Read via SQL editor or service_role; never granted to client roles.';

-- ----------------------------------------------------------------------------
-- 2) Per-question daily vote velocity, with the share coming from suspect
--    accounts. NOTE: voted_at is updated when a user changes their choice, so
--    a re-vote counts on its LATEST day — fine for spotting spikes.
-- ----------------------------------------------------------------------------
create or replace view public.admin_question_vote_velocity as
select
  v.question_id,
  qt.question_text                                          as question_text_pl,
  (v.voted_at at time zone 'utc')::date                     as vote_day,
  count(*)::int                                             as votes,
  (count(*) filter (where v.choice = 1))::int               as yes_votes,
  (count(*) filter (where v.choice = 2))::int               as no_votes,
  (count(*) filter (where sus.user_id is not null))::int    as suspect_votes,
  round(
    100.0 * count(*) filter (where sus.user_id is not null) / count(*), 1
  )                                                         as suspect_pct
from public.question_votes v
left join public.admin_vote_farming_suspects sus
  on sus.user_id = v.user_id
left join public.question_translations qt
  on qt.question_id = v.question_id and qt.locale = 'pl'
group by v.question_id, qt.question_text,
         ((v.voted_at at time zone 'utc')::date);

comment on view public.admin_question_vote_velocity is
  'Admin-only: votes per question per UTC day with yes/no split and the share cast by admin_vote_farming_suspects accounts. A question whose split moves on high suspect_pct is being farmed.';

-- ----------------------------------------------------------------------------
-- Lock both views down to admin surfaces only.
-- ----------------------------------------------------------------------------
revoke all on public.admin_vote_farming_suspects   from public, anon, authenticated;
revoke all on public.admin_question_vote_velocity  from public, anon, authenticated;
grant select on public.admin_vote_farming_suspects  to service_role;
grant select on public.admin_question_vote_velocity to service_role;
