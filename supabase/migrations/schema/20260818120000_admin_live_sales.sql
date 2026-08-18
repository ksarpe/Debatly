-- ============================================================================
-- Admin live-sales feed (2026-08-18): admin_live_sales() for the /live page
-- in the local admin panel — a "cha-ching" dashboard that polls this RPC and
-- plays a sound when a new purchase lands.
--
-- Reads only what the RevenueCat webhook already records:
--   * billing_events — one row per webhook event, full payload in `payload`
--     (the whole webhook body; the event object lives at payload->'event').
--   * subscriptions  — current entitlement state per user.
--
-- Conventions:
--   * "Sale"   = INITIAL_PURCHASE or NON_RENEWING_PURCHASE (lifetime).
--   * "Renewal"= RENEWAL.
--   * Counters and revenue EXCLUDE sandbox events (environment = 'SANDBOX')
--     and dashboard promo grants (product_id 'rc_promo_%', which arrive as
--     PRODUCTION NON_RENEWING_PURCHASE with price 0); the feed includes both,
--     flagged, so they are visible but never ring the bell or bend the numbers.
--   * "Today" is Europe/Warsaw — this is the owner's wall-clock day, unrelated
--     to the app's local-midnight daily or the UTC streak day.
--   * Revenue sums price_in_purchased_currency grouped by currency (no FX).
--
-- Read-only, admin-gated (admin_require()), idempotent. Safe to re-run.
-- ============================================================================

create or replace function public.admin_live_sales()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_today_start timestamptz :=
    date_trunc('day', now() at time zone 'Europe/Warsaw') at time zone 'Europe/Warsaw';
  v_counters jsonb;
  v_revenue  jsonb;
  v_events   jsonb;
begin
  perform public.admin_require();

  -- ---------------------------------------------------------------- counters
  with money as (
    select b.received_at,
           b.type,
           coalesce(b.payload->'event'->>'environment', 'PRODUCTION') as env
    from public.billing_events b
    where b.type in ('INITIAL_PURCHASE', 'NON_RENEWING_PURCHASE', 'RENEWAL')
      and coalesce(b.payload->'event'->>'product_id', '') not like 'rc\_promo\_%' escape '\'
  )
  select jsonb_build_object(
    'active_subs',    (select count(*) from public.subscriptions s where s.is_active),
    'will_renew',     (select count(*) from public.subscriptions s
                        where s.is_active and s.will_renew),
    'sales_today',    (select count(*) from money m
                        where m.type <> 'RENEWAL' and m.env <> 'SANDBOX'
                          and m.received_at >= v_today_start),
    'sales_7d',       (select count(*) from money m
                        where m.type <> 'RENEWAL' and m.env <> 'SANDBOX'
                          and m.received_at >= now() - interval '7 days'),
    'sales_30d',      (select count(*) from money m
                        where m.type <> 'RENEWAL' and m.env <> 'SANDBOX'
                          and m.received_at >= now() - interval '30 days'),
    'sales_total',    (select count(*) from money m
                        where m.type <> 'RENEWAL' and m.env <> 'SANDBOX'),
    'renewals_today', (select count(*) from money m
                        where m.type = 'RENEWAL' and m.env <> 'SANDBOX'
                          and m.received_at >= v_today_start),
    'renewals_30d',   (select count(*) from money m
                        where m.type = 'RENEWAL' and m.env <> 'SANDBOX'
                          and m.received_at >= now() - interval '30 days')
  ) into v_counters;

  -- ------------------------------------------- revenue by currency (no FX)
  select coalesce(jsonb_agg(to_jsonb(t) order by t.total_30d desc), '[]'::jsonb)
    into v_revenue
  from (
    select
      coalesce(b.payload->'event'->>'currency', '?')                    as currency,
      round(sum((b.payload->'event'->>'price_in_purchased_currency')::numeric)
            filter (where b.received_at >= v_today_start), 2)           as total_today,
      round(sum((b.payload->'event'->>'price_in_purchased_currency')::numeric)
            filter (where b.received_at >= now() - interval '30 days'), 2) as total_30d
    from public.billing_events b
    where b.type in ('INITIAL_PURCHASE', 'NON_RENEWING_PURCHASE', 'RENEWAL')
      and coalesce(b.payload->'event'->>'environment', 'PRODUCTION') <> 'SANDBOX'
      and coalesce(b.payload->'event'->>'product_id', '') not like 'rc\_promo\_%' escape '\'
      and (b.payload->'event'->>'price_in_purchased_currency') is not null
    group by 1
  ) t;

  -- --------------------------------------------------- feed: last 50 events
  select coalesce(jsonb_agg(to_jsonb(t) order by t.received_at desc), '[]'::jsonb)
    into v_events
  from (
    select
      b.id,
      b.received_at,
      b.type,
      b.user_id,
      b.payload->'event'->>'product_id'                  as product_id,
      b.payload->'event'->>'store'                       as store,
      b.payload->'event'->>'period_type'                 as period_type,
      b.payload->'event'->>'country_code'                as country,
      (b.payload->'event'->>'price_in_purchased_currency')::numeric as price,
      b.payload->'event'->>'currency'                    as currency,
      coalesce(b.payload->'event'->>'environment', 'PRODUCTION') = 'SANDBOX'
                                                         as is_sandbox
    from public.billing_events b
    order by b.received_at desc
    limit 50
  ) t;

  return jsonb_build_object(
    'generated_at', now(),
    'counters',     v_counters,
    'revenue',      v_revenue,
    'events',       v_events
  );
end;
$$;

revoke all on function public.admin_live_sales() from public, anon;
grant execute on function public.admin_live_sales() to authenticated, service_role;
