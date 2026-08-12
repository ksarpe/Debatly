-- ============================================================================
-- Security-audit follow-up (2026-06-22): least-privilege on internal functions
-- + a stronger "real account" gate. Pairs with the dashboard-only auth toggles
-- (leaked-password protection + email confirmation) noted in RELEASE_CHECKLIST.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) is_premium(uuid) — INTERNAL HELPER, not API.
--    It is called inside the SECURITY DEFINER content RPCs (which run as the
--    owner, so they don't need the *caller* to hold EXECUTE). It was left
--    callable by anon/authenticated, exposing /rest/v1/rpc/is_premium?uid=<any>
--    — anyone could probe whether an arbitrary uuid is premium. Lock it down.
-- ----------------------------------------------------------------------------
revoke execute on function public.is_premium(uuid) from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 2) Trigger / event-trigger functions are never meant to be API-callable.
--    PostgREST can't even invoke functions returning trigger/event_trigger, and
--    triggers fire independently of the caller's EXECUTE grant — so dropping the
--    default PUBLIC execute changes no behavior, it just clears the linter and
--    shrinks the exposed surface.
-- ----------------------------------------------------------------------------
revoke execute on function public.handle_new_user() from public;
revoke execute on function public.rls_auto_enable() from public;
revoke execute on function public.set_updated_at()  from public;

-- ----------------------------------------------------------------------------
-- 3) Tidy: the public content RPCs only need the API roles (anon + authenticated
--    are granted explicitly). The extra blanket PUBLIC grant is redundant.
-- ----------------------------------------------------------------------------
revoke execute on function public.get_questions(text, date)        from public;
revoke execute on function public.get_daily_question(text, date)   from public;
revoke execute on function public.get_question_smaczki(uuid, text) from public;

-- ----------------------------------------------------------------------------
-- 4) Stronger anti-farm: a "real account" must have a CONFIRMED email/phone, not
--    merely be non-anonymous.
--
--    The hole: registerWithPassword upgrades an anonymous user in place via
--    updateUser(), which flips auth.users.is_anonymous to false IMMEDIATELY —
--    before the user proves they own the address. So an unconfirmed upgrade used
--    to satisfy is_real_account() and earn the daily free-unlock credit, which
--    weakens the whole anti-farm stance (mint throwaway emails -> daily credits).
--
--    OAuth (Google) sets confirmed_at at creation (the provider asserts the
--    email), so those users are unaffected. This is forward-compatible: with
--    email confirmation OFF (autoconfirm) confirmed_at is set at signup and this
--    is a no-op; turn confirmation ON in the dashboard and the credit gate starts
--    honoring it automatically — no further code change.
--
--    is_real_account stays INTERNAL (no API grant): it's only called from inside
--    sync_user_state / reveal_free_question, which run as the owner.
-- ----------------------------------------------------------------------------
create or replace function public.is_real_account(p_uid uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(not u.is_anonymous and u.confirmed_at is not null, false)
  from auth.users u
  where u.id = p_uid;
$$;
revoke all on function public.is_real_account(uuid) from public;
