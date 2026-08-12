-- ============================================================================
-- Entitlement SOURCES — make the database the single source of truth for
-- premium, and stop the store reconciler from clobbering non-store grants.
--
-- The bug this closes: `sync-entitlement` and the RevenueCat webhook both wrote
-- `profiles.is_premium` directly from RevenueCat's view. So ANY premium that did
-- not come from a store purchase — a support comp, a lifetime grant, a QA/admin
-- grant — was silently wiped the moment the app reconciled with RevenueCat
-- (which reports "no purchase" for that identity). There was also no path by
-- which such a grant could exist at all, and the client UI never even read the
-- DB flag.
--
-- The model: premium can come from two independent SOURCES, tracked separately
-- so neither overwrites the other:
--
--   * STORE        — a RevenueCat subscription. Owned by the webhook (renewals,
--                    expiries, refunds) and the on-demand sync-entitlement pull.
--   * PROMOTIONAL  — a comp / lifetime / admin / QA grant with no purchase
--                    behind it. Owned by `set_promotional_premium`. Immune to
--                    store reconciliation.
--
-- `profiles.is_premium` / `premium_until` stay the EFFECTIVE flag the gate
-- (`is_premium(uid)`, read by every question/smaczki RPC) enforces. They are now
-- DERIVED from the two sources by `recompute_premium`, never written ad hoc.
-- Effective premium is active when EITHER source is active; effective expiry is
-- the latest active expiry, or null (never expires) if any active source is
-- lifetime.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Source columns. Idempotent so the file is safe to re-run / `db push`.
-- ----------------------------------------------------------------------------
alter table public.profiles
  add column if not exists store_premium       boolean     not null default false,
  add column if not exists store_premium_until timestamptz,
  add column if not exists promo_premium        boolean     not null default false,
  add column if not exists promo_premium_until  timestamptz;

-- Backfill: we cannot retroactively know the source of an EXISTING grant. Treat
-- every current grant as PROMOTIONAL (sticky) so nobody is wrongly revoked when
-- the store reconciler first runs. A genuine store subscription re-asserts the
-- store source on its very next webhook / sync, so this self-corrects.
update public.profiles
   set promo_premium       = true,
       promo_premium_until = premium_until
 where is_premium
   and not store_premium
   and not promo_premium;

-- ----------------------------------------------------------------------------
-- 2) recompute_premium — fold the two sources into the effective flag.
-- ----------------------------------------------------------------------------
create or replace function public.recompute_premium(p_uid uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_store_active boolean;
  v_promo_active boolean;
  v_store_until  timestamptz;
  v_promo_until  timestamptz;
  v_active       boolean;
  v_until        timestamptz;
begin
  select
    p.store_premium and (p.store_premium_until is null or p.store_premium_until > now()),
    p.promo_premium and (p.promo_premium_until is null or p.promo_premium_until > now()),
    p.store_premium_until,
    p.promo_premium_until
  into v_store_active, v_promo_active, v_store_until, v_promo_until
  from public.profiles p
  where p.id = p_uid;

  if not found then
    return false;
  end if;

  v_active := coalesce(v_store_active, false) or coalesce(v_promo_active, false);

  -- Effective expiry: null when no source is active OR an active source never
  -- expires (lifetime); otherwise the latest active expiry.
  if not v_active then
    v_until := null;
  elsif (v_store_active and v_store_until is null)
     or (v_promo_active and v_promo_until is null) then
    v_until := null;
  else
    v_until := greatest(
      case when v_store_active then v_store_until end,
      case when v_promo_active then v_promo_until end
    );
  end if;

  update public.profiles
     set is_premium    = v_active,
         premium_until = v_until
   where id = p_uid;

  return v_active;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3) apply_store_entitlement — the ONLY way the store side is written. Called by
--    the RevenueCat webhook and the on-demand sync-entitlement pull. Touches the
--    STORE source only; promotional grants are left intact. Returns the
--    resulting EFFECTIVE premium so the caller can echo it to the client.
-- ----------------------------------------------------------------------------
create or replace function public.apply_store_entitlement(
  p_uid    uuid,
  p_active boolean,
  p_until  timestamptz
)
returns boolean
language plpgsql security definer set search_path = public as $$
begin
  update public.profiles
     set store_premium       = p_active,
         store_premium_until = case when p_active then p_until else null end
   where id = p_uid;
  return public.recompute_premium(p_uid);
end;
$$;

-- ----------------------------------------------------------------------------
-- 4) set_promotional_premium — grant/revoke premium WITHOUT a store purchase
--    (support comps, lifetime grants, B2B, QA). Immune to store reconciliation.
--
--    SERVICE-ROLE ONLY. It must never be reachable by anon/authenticated or a
--    user could grant themselves premium. Invoke from the SQL editor, an admin
--    tool, or an edge function using the service-role key, e.g.
--      select public.set_promotional_premium('<uuid>', true);            -- lifetime
--      select public.set_promotional_premium('<uuid>', true, now()+interval '30 days');
--      select public.set_promotional_premium('<uuid>', false);           -- revoke
-- ----------------------------------------------------------------------------
create or replace function public.set_promotional_premium(
  p_uid    uuid,
  p_active boolean,
  p_until  timestamptz default null
)
returns boolean
language plpgsql security definer set search_path = public as $$
begin
  update public.profiles
     set promo_premium       = p_active,
         promo_premium_until = case when p_active then p_until else null end
   where id = p_uid;
  return public.recompute_premium(p_uid);
end;
$$;

-- ----------------------------------------------------------------------------
-- 5) Lock down execution. New functions default to EXECUTE for PUBLIC — revoke
--    that, then grant only to service_role (the edge functions + admin tooling).
--    Regular app users (anon/authenticated) can NEVER call these.
-- ----------------------------------------------------------------------------
revoke all on function public.recompute_premium(uuid)                                  from public;
revoke all on function public.apply_store_entitlement(uuid, boolean, timestamptz)      from public;
revoke all on function public.set_promotional_premium(uuid, boolean, timestamptz)      from public;
grant execute on function public.recompute_premium(uuid)                               to service_role;
grant execute on function public.apply_store_entitlement(uuid, boolean, timestamptz)   to service_role;
grant execute on function public.set_promotional_premium(uuid, boolean, timestamptz)   to service_role;

-- ----------------------------------------------------------------------------
-- 6) Normalise every existing row so the effective flag matches the sources.
-- ----------------------------------------------------------------------------
select public.recompute_premium(p.id) from public.profiles p;
