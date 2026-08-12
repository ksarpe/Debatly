-- ============================================================================
-- Grant the service-role edge functions the direct DML their design assumes.
--
-- ROOT CAUSE
--   admob-ssv and revenue-cat-webhook write to these tables as `service_role`
--   (the SUPABASE_SERVICE_ROLE_KEY client). The original design assumed
--   "service_role bypasses RLS/grants" (see init.sql comment on billing_events,
--   and the reveal_ad_question hardening migration). That is only HALF true:
--   service_role bypasses RLS, but NOT table-level GRANTs — the privilege check
--   runs BEFORE any RLS policy. With no grant, every write hit 42501
--   "permission denied" and the function returned 500.
--
-- IMPACT THIS CLOSES
--   * admob-ssv: the verified-reward INSERT always failed, so ad_reward_events
--     stayed empty. reveal_ad_question gates on
--       ad_reveals_used <= verified_ad_rewards + 2,
--     so verified_ad_rewards = 0 capped EVERY user at 2 lifetime ad-reveals,
--     then "ad reward not verified" forever. (Also: AdMob's SSV test ping 500'd.)
--   * revenue-cat-webhook: billing_events (idempotency marker) + subscriptions
--     (upsert) writes failed, so renewals / cancellations / refunds never synced.
--
-- WHY THIS IS SAFE
--   service_role is a server-only role (its key never ships to the client), so
--   granting it DML does not widen client access. anon/authenticated remain
--   unchanged (no INSERT policy, no grant) — the "only Google's signed callback
--   can create a verified reward" property is preserved. Reversible via REVOKE.
--
--   profiles is intentionally omitted: the webhook mutates it only through the
--   SECURITY DEFINER RPC apply_store_entitlement (already EXECUTE-able), never
--   directly — same reason sync-entitlement worked while these two did not.
-- ============================================================================

grant insert         on public.ad_reward_events to service_role;
grant select, insert on public.billing_events   to service_role;
grant insert, update on public.subscriptions    to service_role;
