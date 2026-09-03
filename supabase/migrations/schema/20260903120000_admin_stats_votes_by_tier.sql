-- ============================================================================
-- Admin stats: split the votes by tier — PRO vs free (2026-09-03)
-- ----------------------------------------------------------------------------
-- WHY
--   The /stats daily chart drew ONE bar per day: "głosy". On a day like
--   2026-08-29 that bar read 48 while only 3 accounts voted — which looks
--   exactly like vote farming until you know that two of those accounts hold
--   PRO and PRO has the whole catalog. Without the split the owner cannot
--   tell "a PRO subscriber read 40 questions in one sitting" (the product
--   working) from "one free account cast 40 votes" (a script), and the
--   suspects heuristics only fire past a fixed budget.
--
--   The free tier can legitimately produce exactly ONE vote row per user per
--   day (the daily; the one-shot re-vote UPDATEs that row, it does not insert
--   a second one). So "a free account with >1 vote in a day" is the honest
--   abuse signal, and it is counted here per user-day.
--
-- WHAT COUNTS AS PRO AT VOTE TIME
--   public.admin_user_pro_window — one row per account, the interval during
--   which the account held PRO:
--     tier 'paid'    — a real first purchase exists in billing_events (no
--                      sandbox, no rc_promo_%, no PROMOTIONAL store, i.e. the
--                      same predicate /live and the purchases_paid tile use).
--                      pro_since = that purchase; pro_until = the known
--                      period end when the entitlement has since lapsed,
--                      'infinity' while it is live — so votes cast after a
--                      monthly sub expired count as free again.
--     tier 'granted' — premium right now with no paid purchase behind it:
--                      an owner/tester promo grant. We do not know when the
--                      grant started, so pro_since = '-infinity' (all of
--                      their votes read as PRO). Their volume is expected —
--                      that is the point of naming the tier in the table.
--     tier 'free'    — never premium. Every vote counts as free.
--   A vote is PRO when pro_since <= voted_at < pro_until.
--
-- WHAT CHANGES (read-time only; no data, no app behaviour, no client grants)
--   admin_dashboard_stats(p_days, p_include_internal)
--     * totals: votes_pro / votes_free / voters_pro / voters_free, plus the
--       abuse pair free_multi_vote_days (user-days where a FREE account cast
--       more than one vote) and free_max_votes_in_day.
--     * daily[]: votes_pro / votes_free — they sum to the existing `votes`,
--       so the chart can stack them without changing the bar's height.
--     * top_voters[]: the 20 heaviest accounts of the window with their tier,
--       votes (and how many of them were PRO), active days, max votes in one
--       day and last vote — the review list behind the split.
--   Everything else in the function is byte-identical to 20260902120000.
--
-- The view is admin-only: no grants to anon/authenticated. It is read from
-- inside a security-definer function, which runs with the definer's rights.
-- Idempotent: create or replace only. Safe to re-run.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) admin_user_pro_window — when did each account hold PRO
-- ----------------------------------------------------------------------------
create or replace view public.admin_user_pro_window as
with paid as (
  select b.user_id, min(b.received_at) as paid_at
  from public.billing_events b
  where b.type in ('INITIAL_PURCHASE', 'NON_RENEWING_PURCHASE')
    and coalesce(b.payload->'event'->>'environment', 'PRODUCTION') <> 'SANDBOX'
    and coalesce(b.payload->'event'->>'product_id', '') not like 'rc\_promo\_%' escape '\'
    and coalesce(b.payload->'event'->>'store', '') <> 'PROMOTIONAL'
    and b.user_id is not null
  group by b.user_id
),
-- Latest known expiry across the account's subscription rows. NULL for a
-- lifetime purchase (no period end) — coalesced to 'infinity' below.
sub_end as (
  select s.user_id, max(s.current_period_end) as period_end
  from public.subscriptions s
  group by s.user_id
)
select
  u.id                                        as user_id,
  coalesce(u.is_anonymous, false)             as is_anonymous,
  case
    when p.paid_at is not null then 'paid'
    when pr.id is not null     then 'granted'
    else 'free'
  end                                         as tier,
  case
    when p.paid_at is not null then p.paid_at
    when pr.id is not null     then '-infinity'::timestamptz
  end                                         as pro_since,
  case
    when pr.id is not null then 'infinity'::timestamptz
    else coalesce(e.period_end, 'infinity'::timestamptz)
  end                                         as pro_until
from auth.users u
left join paid p    on p.user_id = u.id
left join sub_end e on e.user_id = u.id
-- premium right now, by the same rule public.is_premium() uses
left join public.profiles pr
  on pr.id = u.id
 and pr.is_premium
 and (pr.premium_until is null or pr.premium_until > now());

comment on view public.admin_user_pro_window is
  'Admin-only: per account, the interval it held PRO (tier paid/granted/free, pro_since, pro_until). Used by admin_dashboard_stats to date a vote against the tier that cast it. Never granted to client roles.';

revoke all on public.admin_user_pro_window from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 2) admin_dashboard_stats — same function plus the tier split
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
  v_top_voters  jsonb;
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
    where (v_since is null or v.voted_at >= v_since)
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
                            and (v_since is null or e.created_at >= v_since)
                            and not (e.install_id = any (v_internal_installs))),
    'activated',        (select count(*) from cohort c where c.ever_voted),
    'votes',            (select count(*) from public.question_votes v
                          where (v_since is null or v.voted_at >= v_since)
                            and not (v.user_id = any (v_internal_users))),
    'voters',           (select count(distinct v.user_id) from public.question_votes v
                          where (v_since is null or v.voted_at >= v_since)
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
               v_today - (v_series_days - 1),
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
    where (v_since is null or v.voted_at >= v_since)
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
