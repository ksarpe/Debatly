-- ============================================================================
-- Force-update gate: app_update_gate + get_min_supported_version().
-- ----------------------------------------------------------------------------
-- 2026-08-20, shipping with v2.1.0 (the global-daily release).
--
-- WHY
--   Neither store offers a real remote kill switch: an installed build can
--   only be forced to update by code that ALREADY ships inside it. v2 changes
--   a lot of shared logic at once, so v2 is the moment the mechanism goes in
--   — from this release on, the owner can retire any too-old version by
--   raising one row here. Versions BEFORE v2 have no gate and can never be
--   forced; the server therefore keeps their RPC contracts working (see the
--   compatibility notes in 20260820150000/170000).
--
-- HOW IT IS USED
--   The client (HomeGate) asks get_min_supported_version('android'|'ios') on
--   launch and compares it against its own pubspec version name (e.g.
--   '2.1.0' — the SEMANTIC version, not the Codemagic build counter, which
--   auto-increments and is nothing the owner tracks). Older → a fullscreen
--   "update required" screen with the store button; no way into the feed.
--   FAIL-OPEN by design: no backend, RPC error, unparsable value, mock mode —
--   the app simply runs. A user must never be locked out by a network blip.
--
-- OWNER OPS
--   Raise the bar ONLY once the new build is live in BOTH stores (staged
--   rollouts count — a gated user must be able to actually download):
--
--     update public.app_update_gate
--        set min_version = '2.1.0', updated_at = now()
--      where platform in ('android', 'ios');
--
--   '0.0.0' = gate off (the default). Per-platform rows exist because App
--   Review and Play review rarely finish the same day.
-- ============================================================================

create table if not exists public.app_update_gate (
  platform    text primary key check (platform in ('android', 'ios')),
  min_version text not null default '0.0.0',
  updated_at  timestamptz not null default now()
);

alter table public.app_update_gate enable row level security;

revoke all on table public.app_update_gate from anon, authenticated;

comment on table public.app_update_gate is
  'Force-update bar per platform: builds with a pubspec version below '
  'min_version get the blocking update screen (v2.1.0+ clients only). '
  '0.0.0 = off. Written only via the SQL editor / service_role.';

insert into public.app_update_gate (platform) values ('android'), ('ios')
on conflict (platform) do nothing;

-- Read side. Granted to anon as well: the check runs at launch, before any
-- session exists, on the publishable key.
create or replace function public.get_min_supported_version(p_platform text)
returns text
language sql stable security definer set search_path = public as $$
  select g.min_version
  from public.app_update_gate g
  where g.platform = lower(btrim(p_platform));
$$;

revoke all on function public.get_min_supported_version(text) from public;
grant execute on function public.get_min_supported_version(text)
  to anon, authenticated;

comment on function public.get_min_supported_version(text) is
  'The minimum supported app version for ''android''/''ios'' (text, e.g. '
  '2.1.0). No row / null = no gate. See 20260820200000.';
