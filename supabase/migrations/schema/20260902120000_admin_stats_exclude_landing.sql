-- ============================================================================
-- Admin stats: the web landing page is not an install (2026-09-02)
-- ----------------------------------------------------------------------------
-- The /stats tile "Instalacje" showed 429 on 2026-09-02 while RevenueCat saw
-- ~280 devices. Verified against live data: since 2026-08-16 the web landing
-- page (TikTok bio link, separate repo) logs `landing_q_view` /
-- `landing_q_vote` into public.app_events with a per-BROWSER install_id that
-- never overlaps an app install (0 shared ids). Every visitor therefore
-- counted as one "install": 429 = 212 app installs + 217 landing browsers.
-- The same inflated denominator dragged "Aktywacja" and "Konwersja PRO" down
-- by half, and the marketing journal's installs_tracked column carried the
-- same landing rows.
--
-- What changes (read-time only — raw rows untouched, fully reversible):
--
--   admin_dashboard_stats(p_days, p_include_internal)
--     * Every install-based count ignores `landing_%` events. Landing gets its
--       own numbers instead: totals.landing_views / landing_votes, a per-day
--       `landing_views` series, and a `landing` breakdown per variant (`v`)
--       and question slug — so the TikTok-bio funnel is visible, just not
--       mixed into the app's.
--     * Two install counters instead of one ambiguous "≥1 event in period":
--         installs_new    — devices whose FIRST app event falls in the window
--                           (a cohort; this is what "installs" means to the
--                           stores and to RevenueCat),
--         installs_active — devices with ≥1 app event in the window (new +
--                           returning). Equal in all-time mode.
--     * activated is a cohort rate: of installs_new, how many ever cast a
--       vote (daily_vote_cast / question_vote_cast). Before, it divided
--       "anyone who voted this week" by "anyone active this week", which mixed
--       old users into a metric that is supposed to describe new ones.
--     * purchases_paid — real-money first purchases from billing_events in
--       the window (INITIAL_PURCHASE + NON_RENEWING_PURCHASE, no sandbox, no
--       promo, no internal accounts) — the same predicate /live uses, so the
--       two pages agree. The client-side `paywall_purchased` count stays as
--       `purchases` for the paywall funnel.
--     * The daily series and the marketing journal now share one clock:
--       Europe/Warsaw (the owner's, same as /live). It was UTC here and
--       Warsaw in the journal, so the same day showed different numbers.
--     * The onboarding funnel lists the steps the CURRENT app logs
--       (started → taste shown → taste voted → bridge → finished → first
--       vote); notify_shown / choice_shown only exist in pre-freemium builds
--       and read as dead steps.
--     * tracking_since is returned so the page can say from when the
--       telemetry exists (2026-08-13) instead of implying an all-time count.
--
--   admin_list_marketing_stats()
--     * installs_tracked ignores `landing_%` events (first APP launch of the
--       day, as the column was documented to mean).
--
-- Idempotent: create or replace only. Safe to re-run.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) admin_dashboard_stats
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
  v_tz          text := 'Europe/Warsaw';
  v_today       date := (now() at time zone 'Europe/Warsaw')::date;
  -- Internal-account exclusion sets. Empty arrays when the filter is off:
  -- `x = any('{}')` is false, so every predicate below degrades to a no-op.
  v_internal_users    uuid[] := '{}';
  v_internal_installs uuid[] := '{}';
  v_totals      jsonb;
  v_onboarding  jsonb;
  v_paywall     jsonb;
  v_acquisition jsonb;
  v_daily       jsonb;
  v_landing     jsonb;
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
  with app_first_seen as (
    -- one row per APP install (landing browsers excluded), with its first event
    select e.install_id,
           min(e.created_at) as first_at,
           bool_or(e.event in ('daily_vote_cast', 'question_vote_cast')) as ever_voted
    from public.app_events e
    where e.event not like 'landing\_%' escape '\'
      and not (e.install_id = any (v_internal_installs))
    group by e.install_id
  ), cohort as (
    select * from app_first_seen f
    where v_since is null or f.first_at >= v_since
  )
  select jsonb_build_object(
    'installs_new',     (select count(*) from cohort),
    'installs_active',  (select count(distinct e.install_id) from public.app_events e
                          where e.event not like 'landing\_%' escape '\'
                            and (v_since is null or e.created_at >= v_since)
                            and not (e.install_id = any (v_internal_installs))),
    'activated',        (select count(*) from cohort c where c.ever_voted),
    'votes',            (select count(*) from public.question_votes v
                          where (v_since is null or v.voted_at >= v_since)
                            and not (v.user_id = any (v_internal_users))),
    'voters',           (select count(distinct v.user_id) from public.question_votes v
                          where (v_since is null or v.voted_at >= v_since)
                            and not (v.user_id = any (v_internal_users))),
    'purchases',        (select count(distinct e.install_id) from public.app_events e
                          where e.event = 'paywall_purchased'
                            and (v_since is null or e.created_at >= v_since)
                            and not (e.install_id = any (v_internal_installs))
                            and (e.user_id is null
                                 or not (e.user_id = any (v_internal_users)))),
    'purchases_paid',   (select count(*) from public.billing_events b
                          where b.type in ('INITIAL_PURCHASE', 'NON_RENEWING_PURCHASE')
                            and coalesce(b.payload->'event'->>'environment', 'PRODUCTION') <> 'SANDBOX'
                            and coalesce(b.payload->'event'->>'product_id', '') not like 'rc\_promo\_%' escape '\'
                            and coalesce(b.payload->'event'->>'store', '') <> 'PROMOTIONAL'
                            and (v_since is null or b.received_at >= v_since)
                            and (b.user_id is null
                                 or not (b.user_id = any (v_internal_users)))),
    'active_subs',      (select count(*) from public.subscriptions s
                          where s.is_active
                            and not (s.user_id = any (v_internal_users))
                            and coalesce(s.store, '') <> 'PROMOTIONAL'
                            and coalesce(s.product_id, '') not like 'rc\_promo\_%' escape '\'),
    'landing_views',    (select count(distinct e.install_id) from public.app_events e
                          where e.event = 'landing_q_view'
                            and (v_since is null or e.created_at >= v_since)),
    'landing_votes',    (select count(distinct e.install_id) from public.app_events e
                          where e.event = 'landing_q_vote'
                            and (v_since is null or e.created_at >= v_since)),
    'ads_watched',      (select count(*) from public.ad_reward_events a
                          where a.verified
                            and (v_since is null or a.created_at >= v_since)
                            and (a.user_id is null
                                 or not (a.user_id = any (v_internal_users)))),
    'ads_unverified',   (select count(*) from public.ad_reward_events a
                          where not a.verified
                            and (v_since is null or a.created_at >= v_since)
                            and (a.user_id is null
                                 or not (a.user_id = any (v_internal_users)))),
    'suspects',         (select count(*) from public.admin_vote_farming_suspects s
                          where not (s.user_id = any (v_internal_users))),
    'suspect_votes',    (select coalesce(sum(s.vote_count), 0)
                           from public.admin_vote_farming_suspects s
                          where not (s.user_id = any (v_internal_users)))
  ) into v_totals;

  -- ------------------------------------------------- onboarding funnel (steps)
  -- The steps the current app logs, in the order a new install meets them.
  -- Counted over the window's install COHORT (first app event in the window),
  -- so a returning old user voting today does not show up as "activated".
  with app_first_seen as (
    select e.install_id, min(e.created_at) as first_at
    from public.app_events e
    where e.event not like 'landing\_%' escape '\'
      and not (e.install_id = any (v_internal_installs))
    group by e.install_id
  ), cohort as (
    select f.install_id from app_first_seen f
    where v_since is null or f.first_at >= v_since
  )
  select jsonb_agg(jsonb_build_object(
           'step', t.ord, 'event', t.event, 'installs', t.installs)
         order by t.ord)
    into v_onboarding
  from (
    select step.ord, step.event,
           (select count(distinct e.install_id)
              from public.app_events e
              join cohort c on c.install_id = e.install_id
             where e.event = any (step.events)) as installs
    from unnest(array[
      'onboarding_started',
      'onboarding_taste_shown',
      'onboarding_taste_voted',
      'bridge_shown',
      'onboarding_finished',
      'daily_vote_cast'
    ]) with ordinality as s(event, ord)
    cross join lateral (
      select s.ord, s.event,
             case s.event
               when 'daily_vote_cast' then array['daily_vote_cast', 'question_vote_cast']
               else array[s.event]
             end as events
    ) step
  ) t;

  -- ------------------------------------------- paywall funnel, one row/source
  select coalesce(jsonb_agg(jsonb_build_object(
           'source',            t.source,
           'shown',             t.shown,
           'plan_selected',     t.plan_selected,
           'purchase_started',  t.purchase_started,
           'purchased',         t.purchased,
           'failed',            t.failed,
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
      count(distinct e.install_id) filter (where e.event = 'paywall_purchase_failed')    as failed,
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
  -- Days in Europe/Warsaw — the owner's clock, the same one /live and the
  -- marketing journal use.
  with app_first_seen as (
    select e.install_id,
           (min(e.created_at) at time zone v_tz)::date as first_day
    from public.app_events e
    where e.event not like 'landing\_%' escape '\'
      and not (e.install_id = any (v_internal_installs))
    group by e.install_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'day',             t.day,
           'new_installs',    t.new_installs,
           'active_installs', t.active_installs,
           'votes',           t.votes,
           'purchases',       t.purchases,
           'landing_views',   t.landing_views)
         order by t.day), '[]'::jsonb)
    into v_daily
  from (
    select
      d.day,
      (select count(*) from app_first_seen f where f.first_day = d.day)  as new_installs,
      (select count(distinct e.install_id) from public.app_events e
        where e.event not like 'landing\_%' escape '\'
          and (e.created_at at time zone v_tz)::date = d.day
          and not (e.install_id = any (v_internal_installs)))         as active_installs,
      (select count(*) from public.question_votes v
        where (v.voted_at at time zone v_tz)::date = d.day
          and not (v.user_id = any (v_internal_users)))               as votes,
      (select count(*) from public.billing_events b
        where b.type in ('INITIAL_PURCHASE', 'NON_RENEWING_PURCHASE')
          and coalesce(b.payload->'event'->>'environment', 'PRODUCTION') <> 'SANDBOX'
          and coalesce(b.payload->'event'->>'product_id', '') not like 'rc\_promo\_%' escape '\'
          and coalesce(b.payload->'event'->>'store', '') <> 'PROMOTIONAL'
          and (b.received_at at time zone v_tz)::date = d.day
          and (b.user_id is null
               or not (b.user_id = any (v_internal_users))))          as purchases,
      (select count(distinct e.install_id) from public.app_events e
        where e.event = 'landing_q_view'
          and (e.created_at at time zone v_tz)::date = d.day)         as landing_views
    from (
      select generate_series(
               v_today - (v_series_days - 1),
               v_today,
               interval '1 day')::date as day
    ) d
  ) t;

  -- ------------------------------------ landing page, per variant + question
  select coalesce(jsonb_agg(to_jsonb(t) order by t.views desc), '[]'::jsonb)
    into v_landing
  from (
    select
      coalesce(nullif(e.properties->>'v', ''), '(brak)')     as variant,
      coalesce(nullif(e.properties->>'slug', ''), '(brak)')  as slug,
      count(distinct e.install_id) filter (where e.event = 'landing_q_view') as views,
      count(distinct e.install_id) filter (where e.event = 'landing_q_vote') as votes
    from public.app_events e
    where e.event like 'landing\_%' escape '\'
      and (v_since is null or e.created_at >= v_since)
    group by 1, 2
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
    where (v.voted_at at time zone v_tz)::date >= v_today - 7
      and not (v.user_id = any (v_internal_users))
    group by v.question_id
    order by count(*) desc
    limit 10
  ) t;

  return jsonb_build_object(
    'generated_at',      now(),
    'window_days',       p_days,
    'series_days',       v_series_days,
    'timezone',          v_tz,
    'tracking_since',    (select (min(e.created_at) at time zone v_tz)::date
                            from public.app_events e
                           where e.event not like 'landing\_%' escape '\'),
    'internal_excluded', not p_include_internal,
    'internal_installs', coalesce(array_length(v_internal_installs, 1), 0),
    'totals',            v_totals,
    'onboarding',        v_onboarding,
    'paywall',           v_paywall,
    'acquisition',       v_acquisition,
    'daily',             v_daily,
    'landing',           v_landing,
    'reveals',           v_reveals,
    'suspects',          v_suspects,
    'velocity',          v_velocity
  );
end;
$function$;

revoke all on function public.admin_dashboard_stats(integer, boolean) from public, anon;
grant execute on function public.admin_dashboard_stats(integer, boolean) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2) admin_list_marketing_stats: installs_tracked = first APP launch of the day
-- ----------------------------------------------------------------------------
create or replace function public.admin_list_marketing_stats()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_internal_users    uuid[] := '{}';
  v_internal_installs uuid[] := '{}';
  v_rows              jsonb;
begin
  perform public.admin_require();

  -- Te same dwa zbiory co w admin_dashboard_stats: konta wewnętrzne po mailu
  -- + każdy, kto kiedykolwiek wygenerował event SANDBOX (paragon sandboxowy
  -- może przyjść tylko z builda deweloperskiego).
  select coalesce(array_agg(distinct u.id), '{}'::uuid[]) into v_internal_users
  from (
    select u.id
    from auth.users u
    where u.email ilike any (array[
      '%janowskicorp%', '%taknormalni%', '%2299kasper%',
      '%229kasper%', '%alicjaszcz00%', '%aknsoftware%'
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
  where e.install_id is not null
    and e.user_id = any (v_internal_users);

  with first_seen as (
    -- Landing page rows (`landing_%`) carry a per-browser id, not a device —
    -- a visitor is not an install (20260902120000).
    select e.install_id,
           (min(e.created_at) at time zone 'Europe/Warsaw')::date as day
    from public.app_events e
    where e.install_id is not null
      and e.event not like 'landing\_%' escape '\'
      and not (e.install_id = any (v_internal_installs))
    group by e.install_id
  ),
  installs_by_day as (
    select day, count(*)::int as n from first_seen group by day
  ),
  sales as (
    select (b.received_at at time zone 'Europe/Warsaw')::date            as day,
           (b.payload->'event'->>'price_in_purchased_currency')::numeric as price,
           b.payload->'event'->>'currency'                               as currency
    from public.billing_events b
    where b.type in ('INITIAL_PURCHASE', 'NON_RENEWING_PURCHASE')
      and coalesce(b.payload->'event'->>'environment', 'PRODUCTION') <> 'SANDBOX'
      and coalesce(b.payload->'event'->>'product_id', '') not like 'rc\_promo\_%' escape '\'
      and (b.user_id is null or not (b.user_id = any (v_internal_users)))
  ),
  sales_by_day as (
    select day,
           count(*)::int                                                as n,
           coalesce(round(sum(price) filter (where currency = 'PLN'), 2), 0) as revenue_pln
    from sales group by day
  ),
  days as (
    select day from public.marketing_daily_stats
    union select day from installs_by_day
    union select day from sales_by_day
  )
  select coalesce(jsonb_agg(to_jsonb(t) order by t.day desc), '[]'::jsonb)
    into v_rows
  from (
    select d.day,
           m.video,
           m.video_views,
           m.store_visits_google,
           m.store_visits_appstore,
           m.downloads_google,
           m.downloads_appstore,
           m.notes,
           m.updated_at,
           coalesce(i.n, 0)           as installs_tracked,
           coalesce(s.n, 0)           as purchases,
           coalesce(s.revenue_pln, 0) as revenue_pln,
           (m.day is not null)        as has_entry
    from days d
    left join public.marketing_daily_stats m on m.day = d.day
    left join installs_by_day               i on i.day = d.day
    left join sales_by_day                  s on s.day = d.day
  ) t;

  return jsonb_build_object(
    -- Przed tym dniem nie było telemetrii — panel pokazuje "—" zamiast zera,
    -- żeby brak danych nie wyglądał jak zero instalacji.
    'tracking_since', (select (min(created_at) at time zone 'Europe/Warsaw')::date
                       from public.app_events
                       where event not like 'landing\_%' escape '\'),
    'rows',           v_rows
  );
end;
$$;

revoke all on function public.admin_list_marketing_stats() from public, anon;
grant execute on function public.admin_list_marketing_stats() to authenticated, service_role;
