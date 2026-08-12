-- ============================================================================
-- Install-attribution funnel view (2026-07-29).
--
-- The client now reads the Play Install Referrer on first launch and logs it
-- as ONE `install_attributed` event per install into the existing `app_events`
-- table (no schema change needed — this migration only adds a read-side view).
-- Properties on that event:
--
--   status              ok | unavailable (no Play services / sideload)
--   error               why it was unavailable (only when status=unavailable)
--   referrer            the raw referrer string (truncated)
--   utm_source/_medium/_campaign/_term/_content   parsed from the referrer
--   referrer_click_ts   epoch seconds of the store-link click
--   install_begin_ts    epoch seconds of the actual install (NOT this event's
--                       created_at — existing installs updating to the build
--                       that added attribution log their row late)
--   install_version     app version first installed
--   google_play_instant present+true only for instant-experience installs
--
-- The view answers what Play Console can't: per acquisition source (and
-- campaign), how many installs finished onboarding, cast a vote, saw the
-- paywall, and bought premium. Joined on `install_id`, the same pseudonymous
-- id every other analytics event carries, so it spans the pre-sign-in funnel.
--
-- Source buckets: a Play organic install carries utm_source=google-play, so
-- '(no utm)' means a referrer WAS returned but had no utm_source (rare), and
-- '(unavailable)' means the referrer could not be read at all.
--
-- Distinct-install counts throughout: the event is delivered at-least-once
-- (client retries until an insert is confirmed), so duplicates must not
-- inflate; `distinct on (install_id)` also pins one source per install.
--
-- Read server-side only (SQL editor / service_role) — not exposed to API
-- roles, mirroring onboarding_funnel / paywall_funnel.
-- ============================================================================

create or replace view public.acquisition_funnel
with (security_invoker = true) as
with attributed as (
  select distinct on (install_id)
    install_id,
    coalesce(
      nullif(properties->>'utm_source', ''),
      case when properties->>'status' = 'unavailable'
           then '(unavailable)'
           else '(no utm)'
      end
    )                                        as source,
    coalesce(properties->>'utm_campaign', '(none)') as campaign,
    created_at
  from public.app_events
  where event = 'install_attributed'
  order by install_id, created_at
)
select
  a.source,
  a.campaign,
  count(distinct a.install_id)               as installs,
  count(distinct a.install_id)
    filter (where e.event = 'onboarding_finished')                as onboarded,
  count(distinct a.install_id)
    filter (where e.event in ('daily_vote_cast',
                              'question_vote_cast'))              as voted,
  count(distinct a.install_id)
    filter (where e.event = 'paywall_shown')                      as saw_paywall,
  count(distinct a.install_id)
    filter (where e.event in ('paywall_purchased',
                              'paywall_restored'))                as purchased
from attributed a
left join public.app_events e on e.install_id = a.install_id
group by a.source, a.campaign
order by installs desc, a.source, a.campaign;

revoke all on public.acquisition_funnel from anon, authenticated;
