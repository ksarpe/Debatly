-- ============================================================================
-- Admin dashboard: filter out internal (owner/test) accounts (2026-08-14).
--
-- The team's own accounts inflate every number on /stats — at this scale a
-- single test purchase or ad view visibly bends the funnel. This replaces
-- admin_dashboard_stats(int) with admin_dashboard_stats(int, boolean):
--
--   * Internal accounts are auth.users whose email matches one of the
--     patterns below (owner's personal/test mailboxes).
--   * Exclusion is transitive to DEVICES: any install_id that ever sent an
--     app_event as an internal user is excluded wholesale, so the pre-sign-in
--     part of an internal session (onboarding, guest voting) disappears too.
--     Limitation: a test device that NEVER signed in stays counted — there is
--     nothing to recognise it by.
--   * p_include_internal := true turns the filter off (UI checkbox), so the
--     unfiltered picture stays one click away.
--
-- Acquisition and vote-velocity are computed inline (the underlying views
-- aggregate before a per-user filter can be applied); the view definitions
-- they mirror are 20260729150000_install_attribution_funnel.sql and
-- 20260713150000_vote_farming_monitoring.sql.
--
-- Idempotent: drop-if-exists + create + guarded grants. Safe to re-run.
-- ============================================================================

-- The old single-parameter overload must go, or PostgREST calls passing only
-- p_days would be ambiguous between the two signatures.
drop function if exists public.admin_dashboard_stats(int);

create or replace function public.admin_dashboard_stats(
  p_days int default null,
  p_include_internal boolean default false
)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
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
    select coalesce(array_agg(u.id), '{}'::uuid[]) into v_internal_users
    from auth.users u
    where u.email ilike any (array[
      '%janowskicorp%',
      '%taknormalni%',
      '%2299kasper%',
      '%229kasper%',
      '%alicjaszcz00%'
    ]);

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
                           and not (e.install_id = any (v_internal_installs))),
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
          and not (e.install_id = any (v_internal_installs)))         as purchases
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
$$;

revoke all on function public.admin_dashboard_stats(int, boolean) from public, anon;
grant execute on function public.admin_dashboard_stats(int, boolean) to authenticated, service_role;
