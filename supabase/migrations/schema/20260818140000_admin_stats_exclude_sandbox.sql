-- ============================================================================
-- Admin stats: exclude sandbox purchases + the hello@aknsoftware.com account
-- ----------------------------------------------------------------------------
-- 2026-08-18. The /stats dashboard showed 2 PRO purchases where only 1 was
-- real. Root cause, verified against live data:
--
--   * `paywall_purchased` app_events are logged by the CLIENT, which cannot
--     tell a sandbox (test-track / TestFlight) purchase from a real one. The
--     phantom purchase was a SANDBOX lifetime buy by hello@aknsoftware.com —
--     an internal account missing from the e-mail exclusion list.
--   * A second sandbox test purchase (anonymous App Store user) was already
--     invisible only by luck: its install later logged events as
--     janowskicorp@gmail.com, which IS on the list.
--   * Sandbox RevenueCat events also leave `subscriptions.is_active = true`
--     rows behind, inflating active_subs in BOTH admin_dashboard_stats and
--     admin_live_sales (the subscriptions table has no environment column).
--
-- Fix, applied to both RPCs:
--   1. '%aknsoftware%' joins the internal e-mail patterns.
--   2. Any user_id that ever produced a SANDBOX billing_event is treated as a
--     test account and excluded the same way internal accounts are — sandbox
--     receipts can only come from dev builds, never from a paying user. In
--     admin_dashboard_stats this folds into v_internal_users, so
--     p_include_internal = true still reveals everything for debugging.
--
-- Raw rows in billing_events / app_events / subscriptions are kept untouched
-- on purpose — this filters at read time, so it is fully reversible.
-- Idempotent: create or replace only. Safe to re-run.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) admin_dashboard_stats
--    (replaces the live version; diff = internal-set construction only)
-- ----------------------------------------------------------------------------
create or replace function public.admin_dashboard_stats(p_days integer default null, p_include_internal boolean default false)
returns jsonb
language plpgsql stable security definer
set search_path to 'public'
as $function$
declare
  v_since      timestamptz := case when p_days is null then null
                                   else now() - make_interval(days => p_days) end;
  -- the time-series always shows a bounded window, even in all-time mode
  v_series_days int := least(coalesce(p_days, 30), 90);
  -- Internal-account exclusion sets. Empty arrays when the filter is off:
  -- `x = any('{}')` is false, so every predicate below degrades to a no-op.
  v_internal_users    uuid[] := '{}';
  v_internal_installs uuid[] := '{}';
  v_totals      jsonb;
  v_onboarding  jsonb;
  v_paywall     jsonb;
  v_acquisition jsonb;
  v_daily       jsonb;
  v_reveals     jsonb;
  v_suspects    jsonb;
  v_velocity    jsonb;
begin
  perform public.admin_require();

  if not p_include_internal then
    -- Internal accounts by e-mail + anyone who ever produced a SANDBOX
    -- RevenueCat event (sandbox receipts only come from dev/test builds).
    select coalesce(array_agg(distinct u.id), '{}'::uuid[]) into v_internal_users
    from (
      select u.id
      from auth.users u
      where u.email ilike any (array[
        '%janowskicorp%',
        '%taknormalni%',
        '%2299kasper%',
        '%229kasper%',
        '%alicjaszcz00%',
        '%aknsoftware%'
      ])
      union
      select b.user_id
      from public.billing_events b
      where b.user_id is not null
        and coalesce(b.payload->'event'->>'environment', 'PRODUCTION') = 'SANDBOX'
    ) u;

    select coalesce(array_agg(distinct e.install_id), '{}'::uuid[])
      into v_internal_installs
    from public.app_events e
    where e.user_id = any (v_internal_users);
  end if;

  -- ------------------------------------------------------------------ totals
  select jsonb_build_object(
    'installs',        (select count(distinct e.install_id) from public.app_events e
                         where (v_since is null or e.created_at >= v_since)
                           and not (e.install_id = any (v_internal_installs))),
    'activated',       (select count(distinct e.install_id) from public.app_events e
                         where e.event = 'daily_vote_cast'
                           and (v_since is null or e.created_at >= v_since)
                           and not (e.install_id = any (v_internal_installs))),
    'votes',           (select count(*) from public.question_votes v
                         where (v_since is null or v.voted_at >= v_since)
                           and not (v.user_id = any (v_internal_users))),
    'voters',          (select count(distinct v.user_id) from public.question_votes v
                         where (v_since is null or v.voted_at >= v_since)
                           and not (v.user_id = any (v_internal_users))),
    'purchases',       (select count(distinct e.install_id) from public.app_events e
                         where e.event = 'paywall_purchased'
                           and (v_since is null or e.created_at >= v_since)
                           and not (e.install_id = any (v_internal_installs))
                           and (e.user_id is null
                                or not (e.user_id = any (v_internal_users)))),
    'active_subs',     (select count(*) from public.subscriptions s
                         where s.is_active
                           and not (s.user_id = any (v_internal_users))),
    'ads_watched',     (select count(*) from public.ad_reward_events a
                         where a.verified
                           and (v_since is null or a.created_at >= v_since)
                           and (a.user_id is null
                                or not (a.user_id = any (v_internal_users)))),
    'ads_unverified',  (select count(*) from public.ad_reward_events a
                         where not a.verified
                           and (v_since is null or a.created_at >= v_since)
                           and (a.user_id is null
                                or not (a.user_id = any (v_internal_users)))),
    'suspects',        (select count(*) from public.admin_vote_farming_suspects s
                         where not (s.user_id = any (v_internal_users))),
    'suspect_votes',   (select coalesce(sum(s.vote_count), 0)
                          from public.admin_vote_farming_suspects s
                         where not (s.user_id = any (v_internal_users)))
  ) into v_totals;

  -- ------------------------------------------------- onboarding funnel (steps)
  select jsonb_agg(jsonb_build_object(
           'step', t.ord, 'event', t.event, 'installs', t.installs)
         order by t.ord)
    into v_onboarding
  from (
    select step.ord, step.event, count(distinct e.install_id) as installs
    from unnest(array[
      'onboarding_started',
      'onboarding_taste_shown',
      'onboarding_taste_voted',
      'onboarding_notify_shown',
      'onboarding_choice_shown',
      'onboarding_finished',
      'daily_vote_cast'
    ]) with ordinality as step(event, ord)
    left join public.app_events e
      on e.event = step.event
     and (v_since is null or e.created_at >= v_since)
     and not (e.install_id = any (v_internal_installs))
    group by step.ord, step.event
  ) t;

  -- ------------------------------------------- paywall funnel, one row/source
  select coalesce(jsonb_agg(jsonb_build_object(
           'source',            t.source,
           'shown',             t.shown,
           'plan_selected',     t.plan_selected,
           'purchase_started',  t.purchase_started,
           'purchased',         t.purchased,
           'abandoned',         t.abandoned,
           'dismissed',         t.dismissed,
           'offer_unavailable', t.offer_unavailable)
         order by t.shown desc), '[]'::jsonb)
    into v_paywall
  from (
    select
      coalesce(e.properties->>'source', '(none)') as source,
      count(distinct e.install_id) filter (where e.event = 'paywall_shown')              as shown,
      count(distinct e.install_id) filter (where e.event = 'paywall_plan_selected')      as plan_selected,
      count(distinct e.install_id) filter (where e.event = 'paywall_purchase_started')   as purchase_started,
      count(distinct e.install_id) filter (where e.event = 'paywall_purchased')          as purchased,
      count(distinct e.install_id) filter (where e.event = 'paywall_purchase_abandoned') as abandoned,
      count(distinct e.install_id) filter (where e.event = 'paywall_dismissed')          as dismissed,
      count(distinct e.install_id) filter (where e.event = 'paywall_offer_unavailable')  as offer_unavailable
    from public.app_events e
    where e.event like 'paywall\_%' escape '\'
      and (v_since is null or e.created_at >= v_since)
      and not (e.install_id = any (v_internal_installs))
      and (e.user_id is null or not (e.user_id = any (v_internal_users)))
    group by 1
  ) t;

  -- --------------------------------------------- acquisition (inline, all-time)
  -- Mirrors public.acquisition_funnel but with the internal-install filter;
  -- stays all-time on purpose (the attribution event is one-shot per install).
  select coalesce(jsonb_agg(to_jsonb(t) order by t.installs desc), '[]'::jsonb)
    into v_acquisition
  from (
    with attributed as (
      select distinct on (install_id)
        install_id,
        coalesce(
          nullif(properties->>'utm_source', ''),
          case when properties->>'status' = 'unavailable'
               then '(unavailable)'
               else '(no utm)'
          end
        )                                               as source,
        coalesce(properties->>'utm_campaign', '(none)') as campaign,
        created_at
      from public.app_events
      where event = 'install_attributed'
        and not (install_id = any (v_internal_installs))
      order by install_id, created_at
    )
    select
      a.source,
      a.campaign,
      count(distinct a.install_id)                                    as installs,
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
  ) t;

  -- --------------------------------------------------- daily series (bounded)
  select coalesce(jsonb_agg(jsonb_build_object(
           'day',             t.day,
           'active_installs', t.active_installs,
           'new_installs',    t.new_installs,
           'votes',           t.votes,
           'ads_watched',     t.ads_watched,
           'purchases',       t.purchases)
         order by t.day), '[]'::jsonb)
    into v_daily
  from (
    select
      d.day,
      (select count(distinct e.install_id) from public.app_events e
        where (e.created_at at time zone 'utc')::date = d.day
          and not (e.install_id = any (v_internal_installs)))         as active_installs,
      (select count(*) from (
         select min((e.created_at at time zone 'utc')::date) as first_day
         from public.app_events e
         where not (e.install_id = any (v_internal_installs))
         group by e.install_id
       ) f where f.first_day = d.day)                                 as new_installs,
      (select count(*) from public.question_votes v
        where (v.voted_at at time zone 'utc')::date = d.day
          and not (v.user_id = any (v_internal_users)))               as votes,
      (select count(*) from public.ad_reward_events a
        where a.verified
          and (a.created_at at time zone 'utc')::date = d.day
          and (a.user_id is null
               or not (a.user_id = any (v_internal_users))))          as ads_watched,
      (select count(distinct e.install_id) from public.app_events e
        where e.event = 'paywall_purchased'
          and (e.created_at at time zone 'utc')::date = d.day
          and not (e.install_id = any (v_internal_installs))
          and (e.user_id is null
               or not (e.user_id = any (v_internal_users))))          as purchases
    from (
      select generate_series(
               (now() at time zone 'utc')::date - (v_series_days - 1),
               (now() at time zone 'utc')::date,
               interval '1 day')::date as day
    ) d
  ) t;

  -- ------------------------------------------------- reveals split by source
  select coalesce(jsonb_agg(jsonb_build_object(
           'source', t.source, 'reveals', t.reveals, 'users', t.users)
         order by t.reveals desc), '[]'::jsonb)
    into v_reveals
  from (
    select q.source, count(*) as reveals, count(distinct q.user_id) as users
    from public.question_seen q
    where (v_since is null or q.unlocked_at >= v_since)
      and not (q.user_id = any (v_internal_users))
    group by q.source
  ) t;

  -- --------------------------------------------- suspect accounts (bounded)
  select coalesce(jsonb_agg(to_jsonb(t) order by t.last_vote_at desc), '[]'::jsonb)
    into v_suspects
  from (
    select s.user_id, s.account_created_at, s.is_anonymous, s.is_premium,
           s.vote_count, s.active_days, s.max_votes_in_one_day,
           s.first_vote_at, s.last_vote_at, s.secs_to_first_vote,
           s.no_app_events, s.instant_first_vote, s.over_free_budget
    from public.admin_vote_farming_suspects s
    where not (s.user_id = any (v_internal_users))
    order by s.last_vote_at desc
    limit 25
  ) t;

  -- ------------------------------- vote velocity, last 7 days, per question
  -- Inline version of admin_question_vote_velocity with the internal filter
  -- (the view aggregates per question/day, so users can't be filtered there).
  select coalesce(jsonb_agg(to_jsonb(t) order by t.votes desc), '[]'::jsonb)
    into v_velocity
  from (
    select
      v.question_id,
      max(qt.question_text)                                     as question_text_pl,
      count(*)::int                                             as votes,
      (count(*) filter (where v.choice = 1))::int               as yes_votes,
      (count(*) filter (where v.choice = 2))::int               as no_votes,
      (count(*) filter (where sus.user_id is not null))::int    as suspect_votes,
      round(100.0 * count(*) filter (where sus.user_id is not null)
            / count(*), 1)                                      as suspect_pct
    from public.question_votes v
    left join public.admin_vote_farming_suspects sus
      on sus.user_id = v.user_id
    left join public.question_translations qt
      on qt.question_id = v.question_id and qt.locale = 'pl'
    where (v.voted_at at time zone 'utc')::date
            >= (now() at time zone 'utc')::date - 7
      and not (v.user_id = any (v_internal_users))
    group by v.question_id
    order by count(*) desc
    limit 10
  ) t;

  return jsonb_build_object(
    'generated_at',      now(),
    'window_days',       p_days,
    'series_days',       v_series_days,
    'internal_excluded', not p_include_internal,
    'internal_installs', coalesce(array_length(v_internal_installs, 1), 0),
    'totals',            v_totals,
    'onboarding',        v_onboarding,
    'paywall',           v_paywall,
    'acquisition',       v_acquisition,
    'daily',             v_daily,
    'reveals',           v_reveals,
    'suspects',          v_suspects,
    'velocity',          v_velocity
  );
end;
$function$;

-- ----------------------------------------------------------------------------
-- 2) admin_live_sales: active_subs / will_renew must not count sandbox subs
--    (the money counters and revenue already filter env <> 'SANDBOX'; the
--    subscriptions table has no environment column, so exclude by user)
-- ----------------------------------------------------------------------------
create or replace function public.admin_live_sales()
returns jsonb
language plpgsql stable security definer
set search_path to 'public'
as $function$
declare
  v_today_start timestamptz :=
    date_trunc('day', now() at time zone 'Europe/Warsaw') at time zone 'Europe/Warsaw';
  -- Users who ever produced a SANDBOX RevenueCat event = test accounts; their
  -- subscriptions rows are sandbox leftovers, not payers.
  v_sandbox_users uuid[];
  v_counters jsonb;
  v_revenue  jsonb;
  v_events   jsonb;
begin
  perform public.admin_require();

  select coalesce(array_agg(distinct b.user_id), '{}'::uuid[])
    into v_sandbox_users
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
  )
  select jsonb_build_object(
    'active_subs',    (select count(*) from public.subscriptions s
                        where s.is_active
                          and not (s.user_id = any (v_sandbox_users))),
    'will_renew',     (select count(*) from public.subscriptions s
                        where s.is_active and s.will_renew
                          and not (s.user_id = any (v_sandbox_users))),
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
$function$;
