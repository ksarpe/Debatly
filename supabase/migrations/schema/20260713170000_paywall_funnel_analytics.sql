-- ============================================================================
-- Paywall funnel analytics view (2026-07-13).
--
-- The client now logs the paywall funnel into the existing `app_events` table
-- (no schema change needed — this migration only adds a read-side view).
-- Events, all carrying properties->>'source' (which paywall entry point:
-- general | readingLimit | smaczki | favorites | history):
--
--   paywall_shown              sheet opened
--   paywall_plan_selected      user tapped a different plan card (+ plan)
--   paywall_purchase_started   CTA tapped, store flow launched (+ plan)
--   paywall_purchased          entitlement bought (+ plan, price, currency)
--   paywall_purchase_abandoned store flow cancelled/failed (+ plan)
--   paywall_restored           previous purchase restored from the sheet
--   paywall_dismissed          closed without ending up entitled
--   paywall_offer_unavailable  offering fetch failed/empty (+ reason)
--
-- The view mirrors `onboarding_funnel`: one row per (step, source), distinct
-- install counts so retries don't inflate. Read server-side only (SQL editor /
-- service_role) — not exposed to API roles.
--
-- Example: conversion per entry point =
--   purchased installs / shown installs, per source.
-- ============================================================================

create or replace view public.paywall_funnel
with (security_invoker = true) as
select
  step.ord                                     as step,
  step.event,
  coalesce(e.properties->>'source', '(none)')  as source,
  count(distinct e.install_id)                 as installs,
  count(e.id)                                  as events
from unnest(array[
  'paywall_shown',
  'paywall_plan_selected',
  'paywall_purchase_started',
  'paywall_purchased',
  'paywall_purchase_abandoned',
  'paywall_restored',
  'paywall_dismissed',
  'paywall_offer_unavailable'
]) with ordinality as step(event, ord)
left join public.app_events e on e.event = step.event
group by step.ord, step.event, source
order by step.ord, source;

revoke all on public.paywall_funnel from anon, authenticated;
