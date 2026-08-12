-- ============================================================================
-- First-party product analytics (2026-07-12): the `app_events` table.
--
-- Purpose: measure the onboarding funnel (the app's conversion bottleneck) and
-- activation (first daily vote) WITHOUT adding a third-party analytics SDK.
-- The Flutter side writes through the `Analytics` facade
-- (lib/services/analytics.dart); reads happen only server-side (SQL editor /
-- service_role) via the `onboarding_funnel` view below.
--
-- Design notes:
--   * `install_id` is a client-minted, pseudonymous UUID persisted in
--     SharedPreferences. It exists because onboarding runs BEFORE any Supabase
--     session (even the anonymous one), so `auth.uid()` is null for exactly
--     the events we care most about. It identifies an install, not a person.
--   * Client roles are APPEND-ONLY: insert-only RLS policy, no select/update/
--     delete policies and no such grants — a leaked anon key can add noise but
--     never read anyone's trail. (Remember 2026-07-05: grants matter alongside
--     RLS — hence the explicit revoke/grant pair.)
--   * `user_id` references auth.users ON DELETE SET NULL so account deletion
--     (the `delete-account` edge function) automatically de-links the trail.
--   * CHECKs keep rows lean and the event namespace tidy; a hostile client can
--     at worst insert well-formed noise, throttled by PostgREST as usual.
-- ============================================================================

create table public.app_events (
  id          bigint generated always as identity primary key,
  install_id  uuid        not null,
  user_id     uuid        references auth.users (id) on delete set null,
  event       text        not null check (event ~ '^[a-z0-9_]{1,64}$'),
  properties  jsonb       not null default '{}'::jsonb
                          check (pg_column_size(properties) <= 2048),
  app_locale  text        check (app_locale is null or length(app_locale) <= 8),
  created_at  timestamptz not null default now()
);

comment on table public.app_events is
  'Append-only product-analytics events from the app (first-party, no external vendor). Client roles may only INSERT; read via SQL/service_role.';

alter table public.app_events enable row level security;

-- Append-only surface for the API roles: INSERT and nothing else. A signed-in
-- client may only stamp its own user id (or none); pre-auth onboarding events
-- carry only the install id.
revoke all on table public.app_events from anon, authenticated;
grant insert on table public.app_events to anon, authenticated;

create policy "clients append their own events"
  on public.app_events
  for insert
  to anon, authenticated
  with check (user_id is null or user_id = auth.uid());

-- Funnel/aggregation reads (SQL editor, dashboards).
create index app_events_event_created_at_idx
  on public.app_events (event, created_at);
-- Stitching one install's trail + fast ON DELETE SET NULL for account deletion.
create index app_events_install_id_idx on public.app_events (install_id);
create index app_events_user_id_idx
  on public.app_events (user_id)
  where user_id is not null;

-- ----------------------------------------------------------------------------
-- The onboarding funnel, one row per step in order: how many installs reached
-- each step (distinct install_id, so retries/dupes don't inflate). Not exposed
-- to API roles — it's for the SQL editor / service_role.
-- ----------------------------------------------------------------------------
create view public.onboarding_funnel
with (security_invoker = true) as
select
  step.ord                                            as step,
  step.event,
  count(distinct e.install_id)                        as installs,
  count(e.id)                                         as events
from unnest(array[
  'onboarding_started',
  'onboarding_taste_shown',
  'onboarding_taste_voted',
  'onboarding_notify_shown',
  'onboarding_choice_shown',
  'onboarding_finished',
  'daily_vote_cast'
]) with ordinality as step(event, ord)
left join public.app_events e on e.event = step.event
group by step.ord, step.event
order by step.ord;

revoke all on public.onboarding_funnel from anon, authenticated;
