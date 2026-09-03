-- ============================================================================
-- Admin /live: real money only (2026-08-22)
-- ----------------------------------------------------------------------------
-- The owner wants the live dashboard to show PAYING users — purchases,
-- renewals, cancellations — and nothing else. Two leaks were left:
--
--   1. The event FEED showed everything, flagged: sandbox (TestFlight / test
--      track) receipts and dashboard promo grants. On live data that is 15
--      sandbox rows + 6 promo grants against 3 real events, so the 50-row
--      window was ~90% noise and the real cancellation was buried.
--   2. `active_subs` / `will_renew` counted PROMO grants as subscriptions.
--      A `rc_promo_%` grant writes a subscriptions row with is_active and
--      will_renew = true, so the tile read 8 active / 8 renewing where only
--      2 users had ever paid (and one of those had already cancelled).
--
-- What counts as a TEST event here (all four, unioned):
--   * environment = 'SANDBOX'                       — dev/test build receipt
--   * type = 'TEST'                                 — RevenueCat dashboard ping
--   * store = 'PROMOTIONAL' or product_id 'rc_promo_%' — manual grant
--   * any event of a user who ever produced a SANDBOX event (their later
--     PRODUCTION-flagged TRANSFER/EXPIRATION rows are test debris too)
--
-- The feed hides them by default; `p_include_test => true` brings them back
-- for debugging, and the payload carries `hidden_test` so the UI can say how
-- many were dropped. Counters and revenue keep their old money-only meaning
-- and are NOT affected by the flag — they never showed test rows to begin
-- with; only the promo-subscription leak in active_subs/will_renew is fixed,
-- with the grant count surfaced separately as `promo_grants`.
--
-- Also new: `cancelling` = active subs with auto-renew off (a real payer on
-- the way out) — the signal the owner actually watches for.
--
-- Rows in billing_events / subscriptions are untouched; this filters at read
-- time and is fully reversible. The old zero-arg function must be DROPPED
-- (a default-valued parameter makes a NEW signature — keeping both would make
-- `admin_live_sales()` ambiguous).
-- ============================================================================

drop function if exists public.admin_live_sales();

create or replace function public.admin_live_sales(p_include_test boolean default false)
returns jsonb
language plpgsql stable security definer
set search_path to 'public'
as $function$
declare
  v_today_start timestamptz :=
    date_trunc('day', now() at time zone 'Europe/Warsaw') at time zone 'Europe/Warsaw';
  -- Users who ever produced a SANDBOX RevenueCat event = test accounts; their
  -- subscriptions rows are sandbox leftovers, not payers.
  v_test_users uuid[];
  v_counters jsonb;
  v_revenue  jsonb;
  v_events   jsonb;
  v_hidden   integer;
begin
  perform public.admin_require();

  select coalesce(array_agg(distinct b.user_id), '{}'::uuid[])
    into v_test_users
  from public.billing_events b
  where b.user_id is not null
    and coalesce(b.payload->'event'->>'environment', 'PRODUCTION') = 'SANDBOX';

  -- ---------------------------------------------------------------- counters
  with money as (
    select b.received_at,
           b.type,
           coalesce(b.payload->'event'->>'environment', 'PRODUCTION') as env
    from public.billing_events b
    where b.type in ('INITIAL_PURCHASE', 'NON_RENEWING_PURCHASE', 'RENEWAL')
      and coalesce(b.payload->'event'->>'product_id', '') not like 'rc\_promo\_%' escape '\'
      and coalesce(b.payload->'event'->>'store', '') <> 'PROMOTIONAL'
  ), subs as (
    -- paid subscriptions only: no sandbox testers, no dashboard grants
    select s.*
    from public.subscriptions s
    where not (s.user_id = any (v_test_users))
      and coalesce(s.store, '') <> 'PROMOTIONAL'
      and coalesce(s.product_id, '') not like 'rc\_promo\_%' escape '\'
  )
  select jsonb_build_object(
    'active_subs',    (select count(*) from subs s where s.is_active),
    'will_renew',     (select count(*) from subs s where s.is_active and s.will_renew),
    'cancelling',     (select count(*) from subs s where s.is_active and not s.will_renew),
    'promo_grants',   (select count(*) from public.subscriptions s
                        where s.is_active
                          and not (s.user_id = any (v_test_users))
                          and (coalesce(s.store, '') = 'PROMOTIONAL'
                               or coalesce(s.product_id, '') like 'rc\_promo\_%' escape '\')),
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
      and coalesce(b.payload->'event'->>'store', '') <> 'PROMOTIONAL'
      and (b.payload->'event'->>'price_in_purchased_currency') is not null
    group by 1
  ) t;

  -- ------------------------- feed: last 50 REAL events (+ how many we hid)
  with tagged as (
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
                                                         as is_sandbox,
      (coalesce(b.payload->'event'->>'store', '') = 'PROMOTIONAL'
       or coalesce(b.payload->'event'->>'product_id', '') like 'rc\_promo\_%' escape '\')
                                                         as is_promo
    from public.billing_events b
  ), flagged as (
    select t.*,
           (t.is_sandbox
            or t.is_promo
            or t.type = 'TEST'
            or t.user_id = any (v_test_users))           as is_test
    from tagged t
  )
  select
    coalesce((
      select jsonb_agg(to_jsonb(e) order by e.received_at desc)
      from (
        select f.id, f.received_at, f.type, f.user_id, f.product_id, f.store,
               f.period_type, f.country, f.price, f.currency,
               f.is_sandbox, f.is_promo, f.is_test
        from flagged f
        where p_include_test or not f.is_test
        order by f.received_at desc
        limit 50
      ) e
    ), '[]'::jsonb),
    (select count(*)::int from flagged f where f.is_test)
  into v_events, v_hidden;

  return jsonb_build_object(
    'generated_at', now(),
    'include_test', p_include_test,
    'hidden_test',  case when p_include_test then 0 else v_hidden end,
    'counters',     v_counters,
    'revenue',      v_revenue,
    'events',       v_events
  );
end;
$function$;

revoke all on function public.admin_live_sales(boolean) from public, anon;
grant execute on function public.admin_live_sales(boolean) to authenticated, service_role;
