-- ============================================================================
-- Admin panel: product dashboard RPC (2026-08-14).
--
-- One read-only, admin-gated RPC feeding the panel's /stats page, so the
-- funnels and health signals that so far lived only in the SQL editor
-- (onboarding_funnel / paywall_funnel / acquisition_funnel /
-- admin_vote_farming_suspects / admin_question_vote_velocity) are visible in
-- the panel without a service_role key.
--
-- Security model matches 20260724130000_admin_panel_foundation.sql: the panel
-- holds no table grants; this is a security-definer function that first runs
-- admin_require(). It is the ONLY client-reachable read path into app_events,
-- billing/ad events and the farming views — and it returns aggregates plus a
-- bounded suspect list, never raw event trails.
--
-- p_days = null means all-time; otherwise only events from the last p_days
-- days count (the daily series is independently capped at 90 rows).
--
-- Idempotent: create-or-replace + guarded grants. Safe to re-run.
-- ============================================================================

create or replace function public.admin_dashboard_stats(p_days int default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_since      timestamptz := case when p_days is null then null
                                   else now() - make_interval(days => p_days) end;
  -- the time-series always shows a bounded window, even in all-time mode
  v_series_days int := least(coalesce(p_days, 30), 90);
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

  -- ------------------------------------------------------------------ totals
  select jsonb_build_object(
    'installs',        (select count(distinct e.install_id) from public.app_events e
                         where v_since is null or e.created_at >= v_since),
    'activated',       (select count(distinct e.install_id) from public.app_events e
                         where e.event = 'daily_vote_cast'
                           and (v_since is null or e.created_at >= v_since)),
    'votes',           (select count(*) from public.question_votes v
                         where v_since is null or v.voted_at >= v_since),
    'voters',          (select count(distinct v.user_id) from public.question_votes v
                         where v_since is null or v.voted_at >= v_since),
    'purchases',       (select count(distinct e.install_id) from public.app_events e
                         where e.event = 'paywall_purchased'
                           and (v_since is null or e.created_at >= v_since)),
    'active_subs',     (select count(*) from public.subscriptions s where s.is_active),
    'ads_watched',     (select count(*) from public.ad_reward_events a
                         where a.verified
                           and (v_since is null or a.created_at >= v_since)),
    'ads_unverified',  (select count(*) from public.ad_reward_events a
                         where not a.verified
                           and (v_since is null or a.created_at >= v_since)),
    'suspects',        (select count(*) from public.admin_vote_farming_suspects),
    'suspect_votes',   (select coalesce(sum(s.vote_count), 0)
                          from public.admin_vote_farming_suspects s)
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
    group by 1
  ) t;

  -- ------------------------------------------------ acquisition (all-time view)
  -- The attribution event is one-shot per install, so windowing would only
  -- hide older cohorts; the view stays all-time on purpose.
  select coalesce(jsonb_agg(to_jsonb(a) order by a.installs desc), '[]'::jsonb)
    into v_acquisition
  from public.acquisition_funnel a;

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
        where (e.created_at at time zone 'utc')::date = d.day)          as active_installs,
      (select count(*) from (
         select min((e.created_at at time zone 'utc')::date) as first_day
         from public.app_events e group by e.install_id
       ) f where f.first_day = d.day)                                   as new_installs,
      (select count(*) from public.question_votes v
        where (v.voted_at at time zone 'utc')::date = d.day)            as votes,
      (select count(*) from public.ad_reward_events a
        where a.verified
          and (a.created_at at time zone 'utc')::date = d.day)          as ads_watched,
      (select count(distinct e.install_id) from public.app_events e
        where e.event = 'paywall_purchased'
          and (e.created_at at time zone 'utc')::date = d.day)          as purchases
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
    where v_since is null or q.unlocked_at >= v_since
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
    order by s.last_vote_at desc
    limit 25
  ) t;

  -- ------------------------------- vote velocity, last 7 days, per question
  select coalesce(jsonb_agg(to_jsonb(t) order by t.votes desc), '[]'::jsonb)
    into v_velocity
  from (
    select
      w.question_id,
      max(w.question_text_pl)   as question_text_pl,
      sum(w.votes)::int         as votes,
      sum(w.yes_votes)::int     as yes_votes,
      sum(w.no_votes)::int      as no_votes,
      sum(w.suspect_votes)::int as suspect_votes,
      round(100.0 * sum(w.suspect_votes) / nullif(sum(w.votes), 0), 1)
                                as suspect_pct
    from public.admin_question_vote_velocity w
    where w.vote_day >= (now() at time zone 'utc')::date - 7
    group by w.question_id
    order by sum(w.votes) desc
    limit 10
  ) t;

  return jsonb_build_object(
    'generated_at', now(),
    'window_days',  p_days,
    'series_days',  v_series_days,
    'totals',       v_totals,
    'onboarding',   v_onboarding,
    'paywall',      v_paywall,
    'acquisition',  v_acquisition,
    'daily',        v_daily,
    'reveals',      v_reveals,
    'suspects',     v_suspects,
    'velocity',     v_velocity
  );
end;
$$;

revoke all on function public.admin_dashboard_stats(int) from public, anon;
grant execute on function public.admin_dashboard_stats(int) to authenticated, service_role;
