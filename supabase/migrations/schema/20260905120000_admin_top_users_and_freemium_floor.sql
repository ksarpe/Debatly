-- ============================================================================
-- Admin: top users leaderboard + every /stats number starts at freemium (2026-09-05)
-- ----------------------------------------------------------------------------
-- WHY
--   Two owner asks for the admin panel:
--     1. "Who are my best users?" — the biggest live streaks, the PRO accounts
--        that vote the most, the most loyal free players, the people the
--        arguments actually flip. /stats has a 20-row "who burns votes" table
--        built for abuse review; there was no view built for appreciation.
--     2. "Drop everything from before freemium." The hard-paywall week
--        (2026-08-14 → 17) and the 2025 credits/ads era produced votes,
--        reveals and paywall events under a product that no longer exists.
--        In the "od początku" window they leaked into every tile and made the
--        conversion and activation numbers describe two different apps.
--   Plus a layout fix to "Głosy wg pytania": the owner reads it to check the
--   daily — how did today's and yesterday's pick land — and the catalog rows
--   PRO users vote on were burying those two. The rows now carry the pick
--   date, so the panel can lead with the recent picks and fold the rest.
--
-- FREEMIUM FLOOR
--   v_freemium_since = 2026-08-18 00:00 Europe/Warsaw. That is the first
--   local day a NON-internal install reached the day wall (`wall_reached`) —
--   the 17th was our own devices testing the build. Every window in
--   admin_dashboard_stats is now clamped to it (p_days = NULL means "since
--   freemium", not "since telemetry"), the daily series never draws a bar
--   before it, acquisition only counts installs attributed after it, and the
--   suspects list/count only keeps accounts whose LAST vote is after it.
--   Nothing is deleted — the rows stay in the tables, the dashboard just
--   stops reading them. The response carries `freemium_since` so the panel
--   can label the window honestly.
--
-- WHAT CHANGES
--   admin_dashboard_stats(p_days, p_include_internal)
--     * v_since is never NULL any more: greatest(now() - p_days, freemium).
--     * daily[] starts at max(today - series_days + 1, freemium day).
--     * acquisition[]: attribution events before the floor are dropped.
--     * suspects / suspect_votes / suspects[]: last_vote_at >= floor.
--     * velocity[]: rows = every question voted in the last 7 days UNION the
--       picks of today and yesterday (so a zero-vote pick still shows), each
--       with `pick_date` (NULL = never the daily) and `is_recent_pick`
--       (today's or yesterday's pick). Sorted today's pick, yesterday's,
--       then the rest by votes. Limit 10 → 40; the panel folds everything
--       past the picks.
--     * response: + freemium_since.
--     Everything else is byte-identical to 20260903120000.
--
--   admin_top_users(p_include_internal, p_limit)  — NEW, read-only
--     One account row set (voted since the floor, internal filtered exactly
--     like /stats), then p_limit (default 3, max 20) rows per board:
--       streaks   — biggest LIVE streak (decayed_streak on the UTC clock —
--                   the same value the app shows the user), with the rank
--                   name resolved from public.ranks.
--       records   — longest_streak ever, among accounts active since the floor
--                   (the column itself is all-time; it cannot be dated).
--       pro       — PRO accounts by votes cast WHILE PRO (admin_user_pro_window
--                   window, so a lapsed monthly stops counting), tier paid /
--                   granted named — a tester grant is expected volume.
--       free      — free accounts by votes cast as free (= active days: one
--                   daily per day is the whole free deck).
--       movers    — most `moved` gate outcomes (the arguments flipped them).
--       readers   — most qualifying gates (held + moved, i.e. the ones that
--                   count toward the debate profile).
--     plus `summary`: voters, voted today (Warsaw), live streaks ≥3/≥7/≥14
--     (streak alive = last vote today or yesterday UTC), PRO live (paid,
--     entitlement not lapsed), granted accounts, gates answered, moved share.
--
-- Both functions stay admin-only (admin_require inside, security definer,
-- execute granted to authenticated — the check is in the body). No client
-- grants change, no data moves. Idempotent: create or replace only.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) admin_dashboard_stats — freemium floor + pick-aware velocity
-- ----------------------------------------------------------------------------
create or replace function public.admin_dashboard_stats(p_days integer default null, p_include_internal boolean default false)
returns jsonb
language plpgsql stable security definer
set search_path to 'public'
as $function$
declare
  -- First local day a real (non-internal) install reached the day wall. The
  -- dashboard describes the freemium product only — see the header.
  v_freemium_since timestamptz := '2026-08-18 00:00:00 Europe/Warsaw'::timestamptz;
  v_freemium_day   date        := date '2026-08-18';
  -- The window floor: "od początku" = since freemium; a shorter window is
  -- clamped to it too (harmless today, honest once the app is years old).
  v_since      timestamptz := greatest(
                                coalesce(case when p_days is null then null
                                              else now() - make_interval(days => p_days) end,
                                         v_freemium_since),
                                v_freemium_since);
  -- the time-series always shows a bounded window, even in all-time mode
  v_series_days int := least(coalesce(p_days, 30), 90);
  v_tz          text := 'Europe/Warsaw';
  v_today       date := (now() at time zone 'Europe/Warsaw')::date;
  v_series_from date;
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
  v_top_voters  jsonb;
begin
  perform public.admin_require();

  v_series_from := greatest(v_today - (v_series_days - 1), v_freemium_day);

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
    where f.first_at >= v_since
  ), tiered_votes as (
    -- every vote in the window, tagged with the tier that was active when it
    -- was cast (see admin_user_pro_window)
    select v.user_id,
           (v.voted_at at time zone v_tz)::date as day,
           (t.pro_since is not null
             and v.voted_at >= t.pro_since
             and v.voted_at <  t.pro_until) as pro
    from public.question_votes v
    join public.admin_user_pro_window t on t.user_id = v.user_id
    where v.voted_at >= v_since
      and not (v.user_id = any (v_internal_users))
  ), free_per_day as (
    select user_id, day, count(*)::int as n
    from tiered_votes
    where not pro
    group by user_id, day
  )
  select jsonb_build_object(
    'installs_new',     (select count(*) from cohort),
    'installs_active',  (select count(distinct e.install_id) from public.app_events e
                          where e.event not like 'landing\_%' escape '\'
                            and e.created_at >= v_since
                            and not (e.install_id = any (v_internal_installs))),
    'activated',        (select count(*) from cohort c where c.ever_voted),
    'votes',            (select count(*) from public.question_votes v
                          where v.voted_at >= v_since
                            and not (v.user_id = any (v_internal_users))),
    'voters',           (select count(distinct v.user_id) from public.question_votes v
                          where v.voted_at >= v_since
                            and not (v.user_id = any (v_internal_users))),
    -- tier split of the same two numbers (votes_pro + votes_free = votes;
    -- voters_pro + voters_free can exceed voters — an account that bought
    -- mid-window voted on both sides of the line)
    'votes_pro',        (select count(*) from tiered_votes where pro),
    'votes_free',       (select count(*) from tiered_votes where not pro),
    'voters_pro',       (select count(distinct user_id) from tiered_votes where pro),
    'voters_free',      (select count(distinct user_id) from tiered_votes where not pro),
    -- abuse signal: free = one vote row per day, so anything above that is
    -- either a script or a bug worth looking at
    'free_multi_vote_days',  (select count(*) from free_per_day where n > 1),
    'free_max_votes_in_day', (select coalesce(max(n), 0) from free_per_day),
    'purchases',        (select count(distinct e.install_id) from public.app_events e
                          where e.event = 'paywall_purchased'
                            and e.created_at >= v_since
                            and not (e.install_id = any (v_internal_installs))
                            and (e.user_id is null
                                 or not (e.user_id = any (v_internal_users)))),
    'purchases_paid',   (select count(*) from public.billing_events b
                          where b.type in ('INITIAL_PURCHASE', 'NON_RENEWING_PURCHASE')
                            and coalesce(b.payload->'event'->>'environment', 'PRODUCTION') <> 'SANDBOX'
                            and coalesce(b.payload->'event'->>'product_id', '') not like 'rc\_promo\_%' escape '\'
                            and coalesce(b.payload->'event'->>'store', '') <> 'PROMOTIONAL'
                            and b.received_at >= v_since
                            and (b.user_id is null
                                 or not (b.user_id = any (v_internal_users)))),
    'active_subs',      (select count(*) from public.subscriptions s
                          where s.is_active
                            and not (s.user_id = any (v_internal_users))
                            and coalesce(s.store, '') <> 'PROMOTIONAL'
                            and coalesce(s.product_id, '') not like 'rc\_promo\_%' escape '\'),
    'landing_views',    (select count(distinct e.install_id) from public.app_events e
                          where e.event = 'landing_q_view'
                            and e.created_at >= v_since),
    'landing_votes',    (select count(distinct e.install_id) from public.app_events e
                          where e.event = 'landing_q_vote'
                            and e.created_at >= v_since),
    'ads_watched',      (select count(*) from public.ad_reward_events a
                          where a.verified
                            and a.created_at >= v_since
                            and (a.user_id is null
                                 or not (a.user_id = any (v_internal_users)))),
    'ads_unverified',   (select count(*) from public.ad_reward_events a
                          where not a.verified
                            and a.created_at >= v_since
                            and (a.user_id is null
                                 or not (a.user_id = any (v_internal_users)))),
    -- the suspects view is all-time; keep only accounts still voting under
    -- freemium (a farm that stopped before the floor is history, not a signal)
    'suspects',         (select count(*) from public.admin_vote_farming_suspects s
                          where not (s.user_id = any (v_internal_users))
                            and s.last_vote_at >= v_freemium_since),
    'suspect_votes',    (select coalesce(sum(s.vote_count), 0)
                           from public.admin_vote_farming_suspects s
                          where not (s.user_id = any (v_internal_users))
                            and s.last_vote_at >= v_freemium_since)
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
    where f.first_at >= v_since
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
      and e.created_at >= v_since
      and not (e.install_id = any (v_internal_installs))
      and (e.user_id is null or not (e.user_id = any (v_internal_users)))
    group by 1
  ) t;

  -- ------------------------------------ acquisition (inline, since freemium)
  -- Mirrors public.acquisition_funnel but with the internal-install filter;
  -- ignores the period selector on purpose (the attribution event is one-shot
  -- per install) — but not the freemium floor.
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
        and created_at >= v_freemium_since
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
  -- marketing journal use. Never a day before the freemium floor.
  with app_first_seen as (
    select e.install_id,
           (min(e.created_at) at time zone v_tz)::date as first_day
    from public.app_events e
    where e.event not like 'landing\_%' escape '\'
      and not (e.install_id = any (v_internal_installs))
    group by e.install_id
  ), tiered_votes as (
    select (v.voted_at at time zone v_tz)::date as day,
           (t.pro_since is not null
             and v.voted_at >= t.pro_since
             and v.voted_at <  t.pro_until) as pro
    from public.question_votes v
    join public.admin_user_pro_window t on t.user_id = v.user_id
    where not (v.user_id = any (v_internal_users))
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'day',             t.day,
           'new_installs',    t.new_installs,
           'active_installs', t.active_installs,
           'votes',           t.votes,
           'votes_pro',       t.votes_pro,
           'votes_free',      t.votes_free,
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
      (select count(*) from tiered_votes tv
        where tv.day = d.day and tv.pro)                              as votes_pro,
      (select count(*) from tiered_votes tv
        where tv.day = d.day and not tv.pro)                          as votes_free,
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
               v_series_from,
               v_today,
               interval '1 day')::date as day
    ) d
  ) t;

  -- ---------------------------------- who actually votes (window, top 20)
  -- The review list behind the split: one row per account, its tier, how much
  -- it voted and how concentrated that was. `tier = 'granted'` is a promo /
  -- tester grant — heavy usage there is expected, not a finding.
  with tiered_votes as (
    select v.user_id,
           t.tier,
           t.is_anonymous,
           (v.voted_at at time zone v_tz)::date as day,
           v.voted_at,
           (t.pro_since is not null
             and v.voted_at >= t.pro_since
             and v.voted_at <  t.pro_until) as pro
    from public.question_votes v
    join public.admin_user_pro_window t on t.user_id = v.user_id
    where v.voted_at >= v_since
      and not (v.user_id = any (v_internal_users))
  ), per_day as (
    select user_id, tier, is_anonymous, day,
           count(*)::int                        as n,
           count(*) filter (where pro)::int     as n_pro,
           max(voted_at)                        as last_vote_at
    from tiered_votes
    group by user_id, tier, is_anonymous, day
  )
  select coalesce(jsonb_agg(to_jsonb(t) order by t.votes desc), '[]'::jsonb)
    into v_top_voters
  from (
    select user_id,
           tier,
           is_anonymous,
           sum(n)::int          as votes,
           sum(n_pro)::int      as votes_pro,
           count(*)::int        as active_days,
           max(n)::int          as max_votes_in_one_day,
           max(last_vote_at)    as last_vote_at
    from per_day
    group by user_id, tier, is_anonymous
    order by sum(n) desc, max(last_vote_at) desc
    limit 20
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
      and e.created_at >= v_since
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
    where q.unlocked_at >= v_since
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
      and s.last_vote_at >= v_freemium_since
    order by s.last_vote_at desc
    limit 25
  ) t;

  -- ------------------------------- vote velocity, last 7 days, per question
  -- Rows: every question voted in the last 7 days PLUS today's and
  -- yesterday's daily pick (a pick nobody voted on yet still gets a row —
  -- that zero is the point of the table). `pick_date` names the day the
  -- question was/is the daily (NULL = a catalog question), `is_recent_pick`
  -- marks the two the owner reads first; the panel folds the rest.
  with recent_votes as (
    select v.question_id, v.user_id, v.choice
    from public.question_votes v
    where (v.voted_at at time zone v_tz)::date >= v_today - 7
      and not (v.user_id = any (v_internal_users))
  ), recent_picks as (
    select dp.question_id, dp.publish_date
    from public.daily_picks dp
    where dp.publish_date between v_today - 1 and v_today
  ), qs as (
    select question_id from recent_votes
    union
    select question_id from recent_picks
  )
  select coalesce(jsonb_agg(to_jsonb(t)
           order by t.is_recent_pick desc, t.pick_date desc, t.votes desc), '[]'::jsonb)
    into v_velocity
  from (
    select
      q.question_id,
      (select qt.question_text from public.question_translations qt
        where qt.question_id = q.question_id and qt.locale = 'pl' limit 1) as question_text_pl,
      dp.publish_date                                                     as pick_date,
      coalesce(dp.publish_date between v_today - 1 and v_today, false)    as is_recent_pick,
      count(rv.user_id)::int                                              as votes,
      (count(*) filter (where rv.choice = 1))::int                        as yes_votes,
      (count(*) filter (where rv.choice = 2))::int                        as no_votes,
      (count(*) filter (where sus.user_id is not null))::int              as suspect_votes,
      case when count(rv.user_id) > 0
           then round(100.0 * count(*) filter (where sus.user_id is not null)
                      / count(rv.user_id), 1)
      end                                                                 as suspect_pct
    from qs q
    left join recent_votes rv on rv.question_id = q.question_id
    left join public.admin_vote_farming_suspects sus
      on sus.user_id = rv.user_id
    left join public.daily_picks dp on dp.question_id = q.question_id
    group by q.question_id, dp.publish_date
    -- today's pick, yesterday's pick, then the rest by volume (a PRO user
    -- voting the catalog touches FUTURE picks — their date must not outrank
    -- a hot catalog question)
    order by coalesce(dp.publish_date between v_today - 1 and v_today, false) desc,
             case when coalesce(dp.publish_date between v_today - 1 and v_today, false)
                  then dp.publish_date end desc,
             count(rv.user_id) desc
    limit 40
  ) t;

  return jsonb_build_object(
    'generated_at',      now(),
    'window_days',       p_days,
    'series_days',       v_series_days,
    'timezone',          v_tz,
    'freemium_since',    v_freemium_day,
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
    'top_voters',        v_top_voters,
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
-- 2) admin_top_users — the leaderboard behind /users
-- ----------------------------------------------------------------------------
create or replace function public.admin_top_users(p_include_internal boolean default false, p_limit integer default 3)
returns jsonb
language plpgsql stable security definer
set search_path to 'public'
as $function$
declare
  v_freemium_since timestamptz := '2026-08-18 00:00:00 Europe/Warsaw'::timestamptz;
  v_freemium_day   date        := date '2026-08-18';
  v_tz             text        := 'Europe/Warsaw';
  -- The streak ledger runs on UTC days (CLAUDE.md: two clocks on purpose) —
  -- decayed_streak must be fed the same clock the app feeds it, or the number
  -- shown here disagrees with the one on the user's phone.
  v_today_utc      date := (now() at time zone 'UTC')::date;
  v_today_local    date := (now() at time zone 'Europe/Warsaw')::date;
  v_limit          int  := greatest(1, least(coalesce(p_limit, 3), 20));
  v_internal_users uuid[] := '{}';
  v_summary  jsonb;
  v_streaks  jsonb;
  v_records  jsonb;
  v_pro      jsonb;
  v_free     jsonb;
  v_movers   jsonb;
  v_readers  jsonb;
begin
  perform public.admin_require();

  if not p_include_internal then
    -- Same roster as admin_dashboard_stats: our e-mails + anyone who ever
    -- produced a SANDBOX RevenueCat event.
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
  end if;

  -- One row per account that cast at least one vote since the freemium
  -- floor. Materialised once into a temp result via a CTE per section would
  -- repeat the scan; the population is small (hundreds), so a single CTE
  -- feeding every board through jsonb sub-selects is the simplest correct
  -- shape.
  with acct as (
    select
      u.id                                                  as user_id,
      coalesce(u.is_anonymous, false)                       as is_anonymous,
      (u.email is not null and not coalesce(u.is_anonymous, false)) as has_account,
      t.tier,
      t.pro_since,
      t.pro_until,
      (t.tier = 'paid' and t.pro_until > now())              as pro_live,
      coalesce(pr.current_streak, 0)                        as stored_streak,
      coalesce(pr.longest_streak, 0)                        as longest_streak,
      pr.last_vote_date,
      public.decayed_streak(coalesce(pr.current_streak, 0), pr.last_vote_date, v_today_utc) as live_streak,
      -- "alive" = the app would still count tomorrow's vote as day N+1
      -- without a gap: last vote today or yesterday (UTC)
      coalesce(pr.last_vote_date >= v_today_utc - 1, false) as streak_alive,
      s.votes, s.votes_pro, s.votes_free, s.active_days,
      s.first_vote_at, s.last_vote_at, s.voted_today,
      s.gates_held, s.gates_moved, s.gates_dismissed, s.gates_fast,
      (s.gates_held + s.gates_moved)                        as gates_qualifying
    from auth.users u
    join public.admin_user_pro_window t on t.user_id = u.id
    left join public.profiles pr on pr.id = u.id
    join lateral (
      select
        count(*)::int                                                          as votes,
        (count(*) filter (where t.pro_since is not null
                            and v.voted_at >= t.pro_since
                            and v.voted_at <  t.pro_until))::int               as votes_pro,
        (count(*) filter (where not (t.pro_since is not null
                                 and v.voted_at >= t.pro_since
                                 and v.voted_at <  t.pro_until)))::int         as votes_free,
        count(distinct (v.voted_at at time zone v_tz)::date)::int              as active_days,
        min(v.voted_at)                                                        as first_vote_at,
        max(v.voted_at)                                                        as last_vote_at,
        bool_or((v.voted_at at time zone v_tz)::date = v_today_local)          as voted_today,
        (count(*) filter (where v.challenge_outcome = 'held'))::int            as gates_held,
        (count(*) filter (where v.challenge_outcome = 'moved'))::int           as gates_moved,
        (count(*) filter (where v.challenge_outcome = 'dismissed'))::int       as gates_dismissed,
        (count(*) filter (where v.challenge_outcome = 'skipped_fast'))::int    as gates_fast
      from public.question_votes v
      where v.user_id = u.id
        and v.voted_at >= v_freemium_since
    ) s on true
    where s.votes > 0
      and not (u.id = any (v_internal_users))
  ), ranked as (
    select a.*,
           r.name_pl as rank_name,
           r.tier    as rank_tier
    from acct a
    left join lateral (
      select rk.name_pl, rk.tier
      from public.ranks rk
      where rk.min_streak <= a.live_streak
      order by rk.min_streak desc
      limit 1
    ) r on true
  ),
  -- one jsonb shape for every board, so the panel renders them with one row
  -- component; each board decides its own ORDER and filter
  row_json as (
    select r.user_id,
           r.live_streak, r.longest_streak, r.votes_pro, r.votes_free,
           r.gates_moved, r.gates_qualifying, r.last_vote_at, r.tier,
           jsonb_build_object(
             'user_id',           r.user_id,
             'is_anonymous',      r.is_anonymous,
             'has_account',       r.has_account,
             'tier',              r.tier,
             'pro_live',          r.pro_live,
             'pro_since',         case when r.tier = 'paid' then r.pro_since end,
             'live_streak',       r.live_streak,
             'stored_streak',     r.stored_streak,
             'longest_streak',    r.longest_streak,
             'streak_alive',      r.streak_alive,
             'rank_name',         r.rank_name,
             'rank_tier',         r.rank_tier,
             'last_vote_date',    r.last_vote_date,
             'votes',             r.votes,
             'votes_pro',         r.votes_pro,
             'votes_free',        r.votes_free,
             'active_days',       r.active_days,
             'first_vote_at',     r.first_vote_at,
             'last_vote_at',      r.last_vote_at,
             'voted_today',       r.voted_today,
             'gates_held',        r.gates_held,
             'gates_moved',       r.gates_moved,
             'gates_dismissed',   r.gates_dismissed,
             'gates_fast',        r.gates_fast,
             'gates_qualifying',  r.gates_qualifying,
             'flip_pct',          case when r.gates_qualifying > 0
                                       then round(100.0 * r.gates_moved / r.gates_qualifying)
                                  end
           ) as j
    from ranked r
  )
  select
    jsonb_build_object(
      'voters',           (select count(*) from acct),
      'voted_today',      (select count(*) from acct where voted_today),
      'accounts',         (select count(*) from acct where has_account),
      'streak_alive_3',   (select count(*) from acct where streak_alive and live_streak >= 3),
      'streak_alive_7',   (select count(*) from acct where streak_alive and live_streak >= 7),
      'streak_alive_14',  (select count(*) from acct where streak_alive and live_streak >= 14),
      'pro_live',         (select count(*) from acct where pro_live),
      'pro_granted',      (select count(*) from acct where tier = 'granted'),
      'votes',            (select coalesce(sum(votes), 0) from acct),
      'votes_pro',        (select coalesce(sum(votes_pro), 0) from acct),
      'gates_answered',   (select coalesce(sum(gates_qualifying), 0) from acct),
      'gates_moved',      (select coalesce(sum(gates_moved), 0) from acct),
      'moved_pct',        (select case when sum(gates_qualifying) > 0
                                       then round(100.0 * sum(gates_moved) / sum(gates_qualifying))
                                  end from acct)
    ),
    (select coalesce(jsonb_agg(j order by live_streak desc, longest_streak desc, last_vote_at desc), '[]'::jsonb)
       from (select * from row_json where live_streak > 0
             order by live_streak desc, longest_streak desc, last_vote_at desc limit v_limit) x),
    (select coalesce(jsonb_agg(j order by longest_streak desc, live_streak desc, last_vote_at desc), '[]'::jsonb)
       from (select * from row_json where longest_streak > 0
             order by longest_streak desc, live_streak desc, last_vote_at desc limit v_limit) x),
    (select coalesce(jsonb_agg(j order by votes_pro desc, last_vote_at desc), '[]'::jsonb)
       from (select * from row_json where votes_pro > 0
             order by votes_pro desc, last_vote_at desc limit v_limit) x),
    (select coalesce(jsonb_agg(j order by votes_free desc, last_vote_at desc), '[]'::jsonb)
       from (select * from row_json where tier = 'free' and votes_free > 0
             order by votes_free desc, last_vote_at desc limit v_limit) x),
    (select coalesce(jsonb_agg(j order by gates_moved desc, gates_qualifying desc, last_vote_at desc), '[]'::jsonb)
       from (select * from row_json where gates_moved > 0
             order by gates_moved desc, gates_qualifying desc, last_vote_at desc limit v_limit) x),
    (select coalesce(jsonb_agg(j order by gates_qualifying desc, last_vote_at desc), '[]'::jsonb)
       from (select * from row_json where gates_qualifying > 0
             order by gates_qualifying desc, last_vote_at desc limit v_limit) x)
  into v_summary, v_streaks, v_records, v_pro, v_free, v_movers, v_readers;

  return jsonb_build_object(
    'generated_at',      now(),
    'timezone',          v_tz,
    'freemium_since',    v_freemium_day,
    'limit',             v_limit,
    'internal_excluded', not p_include_internal,
    'summary',           v_summary,
    'streaks',           v_streaks,
    'records',           v_records,
    'pro',               v_pro,
    'free',              v_free,
    'movers',            v_movers,
    'readers',           v_readers
  );
end;
$function$;

comment on function public.admin_top_users(boolean, integer) is
  'Admin-only leaderboard: top accounts since the freemium floor (2026-08-18) by live streak, longest streak, PRO votes, free votes, gates moved and gates answered, plus a population summary. Internal accounts filtered like admin_dashboard_stats.';

revoke all on function public.admin_top_users(boolean, integer) from public, anon;
grant execute on function public.admin_top_users(boolean, integer) to authenticated, service_role;
