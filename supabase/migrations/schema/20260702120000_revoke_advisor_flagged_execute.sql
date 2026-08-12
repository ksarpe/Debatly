-- Quiet two security-advisor findings; no behavioral change for the app.
-- (Applied to prod as TWO history entries, 2026-07-02: the first pass revoked
-- only from anon/authenticated, which was a no-op because EXECUTE came via the
-- default PUBLIC grant; the follow-up pulled PUBLIC. This file is the combined
-- end state.)

-- handle_user_identity_update is a TRIGGER function (fires on auth.users
-- updates) — it was never legitimately callable via /rest/v1/rpc, but the
-- default PUBLIC EXECUTE surfaced it there as an anon-executable SECURITY
-- DEFINER function. Triggers keep firing: EXECUTE is only checked at trigger
-- creation time, not per-fire.
revoke all on function public.handle_user_identity_update() from public, anon, authenticated;

-- get_daily_history is premium-gated internally and the app only ever calls it
-- with a session; anon gets zero rows anyway — drop the PUBLIC path and grant
-- only the roles that actually call it.
revoke all on function public.get_daily_history(text, date) from public, anon;
grant execute on function public.get_daily_history(text, date) to authenticated, service_role;
