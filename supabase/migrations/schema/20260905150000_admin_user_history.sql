-- ============================================================================
-- Admin: one account's history — "who just bought?" (2026-09-05)
-- ----------------------------------------------------------------------------
-- WHY
--   A purchase ping names an account id and nothing else. The owner wants to
--   know, the moment the money lands, whether the buyer is a player who came
--   back for days and finally paid, or a brand-new install that unlocked the
--   catalog on the spot — the two stories mean different things for the
--   funnel. Until now that answer took hand-written SQL.
--
-- WHAT
--   admin_user_history_core(p_user_id uuid) → jsonb   (internal, no client)
--     Everything the backend knows about ONE account, split at the FIRST real
--     purchase (same "real money" predicates as admin_user_pro_window):
--       account   — anonymous / registered, provider, created_at, locale,
--                   profile premium flags
--       purchase  — first real purchase (when, product, store, price, country)
--                   + the current subscription row + the pro window
--       before    — what happened BEFORE that purchase: first seen, minutes
--                   from first launch to the purchase, votes, active days,
--                   paywall views, wall hits, gates, the run of consecutive
--                   UTC vote days ending at the purchase ("streak at purchase")
--       totals    — all-time votes / days / gates / installs / events, the
--                   live streak + rank the app shows the user
--       days[]    — per Warsaw day (newest first, ≤ 120 rows): events, votes,
--                   gates, paywall views, wall hits, purchased flag
--       recent[]  — the last 80 raw app_events (event + the few properties
--                   worth reading: source, trigger, outcome, plan, day_number)
--     `first_seen_at` = the earlier of auth.users.created_at (the anonymous
--     UUID is minted at first launch) and the first app_event.
--
--   admin_user_history(p_user text) → jsonb   (admin panel)
--     admin_require() + resolves the id: a full UUID, or a PREFIX of at least
--     6 hex chars (the panel and Telegram show the first 8). Returns
--     {found:false} for no match and {found:false, ambiguous:n} when a prefix
--     matches several accounts. Never raises for a bad input.
--
--   billing_event_telegram_notify() — the purchase ping now carries the
--     account line + a verdict: "🆕 Nowy — kupił 12 min po pierwszym
--     uruchomieniu, 1 głosów wcześniej" (new = bought on the first day it
--     was seen) or "🎮 Grał wcześniej — 7 głosów w 9 dni, streak 4,
--     paywall 3×". The history part is wrapped in its
--     own exception block: if it fails, the ping still goes out as before.
--     Everything else in the trigger is the 20260901120000 text.
--
-- Read-only. No client grants change: the core is executable by nobody but
-- the definer chain (trigger, wrapper) and service_role; the wrapper is
-- granted to authenticated with admin_require inside. Idempotent.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) core — one account, split at the first purchase
-- ----------------------------------------------------------------------------
create or replace function public.admin_user_history_core(p_user_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path to 'public'
as $function$
declare
  v_tz          text := 'Europe/Warsaw';
  v_today_utc   date := (now() at time zone 'UTC')::date;
  v_account     jsonb;
  v_purchase    jsonb;
  v_before      jsonb;
  v_totals      jsonb;
  v_days        jsonb;
  v_recent      jsonb;
  v_first_seen  timestamptz;
  v_purchase_at timestamptz;
  v_created_at  timestamptz;
begin
  if p_user_id is null then
    return jsonb_build_object('found', false);
  end if;

  select u.created_at into v_created_at from auth.users u where u.id = p_user_id;
  if not found then
    return jsonb_build_object('found', false);
  end if;

  -- ---------------------------------------------------------------- account
  select jsonb_build_object(
    'user_id',        u.id,
    'is_anonymous',   coalesce(u.is_anonymous, false),
    'has_account',    (u.email is not null and not coalesce(u.is_anonymous, false)),
    'provider',       coalesce(pr.provider, u.raw_app_meta_data ->> 'provider'),
    'created_at',     u.created_at,
    'last_sign_in_at', u.last_sign_in_at,
    'locale',         pr.locale,
    'is_premium',     coalesce(pr.is_premium, false),
    'premium_until',  pr.premium_until,
    'promo_premium',  coalesce(pr.promo_premium, false),
    'store_premium',  coalesce(pr.store_premium, false)
  ) into v_account
  from auth.users u
  left join public.profiles pr on pr.id = u.id
  where u.id = p_user_id;

  -- --------------------------------------------------------------- purchase
  -- first REAL purchase — the same predicates admin_user_pro_window uses
  select b.received_at into v_purchase_at
  from public.billing_events b
  where b.user_id = p_user_id
    and b.type in ('INITIAL_PURCHASE', 'NON_RENEWING_PURCHASE')
    and coalesce(b.payload->'event'->>'environment', 'PRODUCTION') <> 'SANDBOX'
    and coalesce(b.payload->'event'->>'product_id', '') not like 'rc\_promo\_%' escape '\'
    and coalesce(b.payload->'event'->>'store', '') <> 'PROMOTIONAL'
  order by b.received_at
  limit 1;

  select jsonb_build_object(
    'purchased_at',  v_purchase_at,
    'product_id',    fp.product_id,
    'store',         fp.store,
    'price',         fp.price,
    'currency',      fp.currency,
    'country',       fp.country,
    'tier',          t.tier,
    'pro_since',     case when t.tier = 'paid' then t.pro_since end,
    'pro_until',     case when t.pro_until = 'infinity'::timestamptz then null else t.pro_until end,
    'pro_live',      (t.tier = 'paid' and t.pro_until > now()),
    'sub_status',    s.status,
    'sub_product',   s.product_id,
    'sub_store',     s.store,
    'will_renew',    s.will_renew,
    'period_end',    s.current_period_end,
    'billing_events', (select count(*) from public.billing_events b where b.user_id = p_user_id),
    'sandbox_events', (select count(*) from public.billing_events b
                        where b.user_id = p_user_id
                          and coalesce(b.payload->'event'->>'environment', 'PRODUCTION') = 'SANDBOX')
  ) into v_purchase
  from public.admin_user_pro_window t
  left join lateral (
    select b.payload->'event'->>'product_id'                     as product_id,
           b.payload->'event'->>'store'                          as store,
           (b.payload->'event'->>'price_in_purchased_currency')::numeric as price,
           b.payload->'event'->>'currency'                       as currency,
           b.payload->'event'->>'country_code'                   as country
    from public.billing_events b
    where b.user_id = p_user_id and b.received_at = v_purchase_at
      and b.type in ('INITIAL_PURCHASE', 'NON_RENEWING_PURCHASE')
    limit 1
  ) fp on true
  left join lateral (
    select s.status, s.product_id, s.store, s.will_renew, s.current_period_end
    from public.subscriptions s
    where s.user_id = p_user_id
    order by s.updated_at desc nulls last
    limit 1
  ) s on true
  where t.user_id = p_user_id;

  -- ------------------------------------------------------------- first seen
  select least(v_created_at, min(e.created_at)) into v_first_seen
  from public.app_events e
  where e.user_id = p_user_id;
  v_first_seen := coalesce(v_first_seen, v_created_at);

  -- ----------------------------------------------------------------- totals
  with ev as (
    select e.install_id, e.event, e.created_at,
           (e.created_at at time zone v_tz)::date as day
    from public.app_events e
    where e.user_id = p_user_id
  ), vt as (
    select v.voted_at, v.challenge_outcome,
           (v.voted_at at time zone v_tz)::date as day
    from public.question_votes v
    where v.user_id = p_user_id
  )
  select jsonb_build_object(
    'first_seen_at',   v_first_seen,
    'last_seen_at',    greatest((select max(created_at) from ev), (select max(voted_at) from vt)),
    'events',          (select count(*) from ev),
    'installs',        (select count(distinct install_id) from ev),
    'active_days',     (select count(distinct day) from ev),
    'votes',           (select count(*) from vt),
    'vote_days',       (select count(distinct day) from vt),
    'first_vote_at',   (select min(voted_at) from vt),
    'last_vote_at',    (select max(voted_at) from vt),
    'gates_held',      (select count(*) from vt where challenge_outcome = 'held'),
    'gates_moved',     (select count(*) from vt where challenge_outcome = 'moved'),
    'gates_dismissed', (select count(*) from vt where challenge_outcome = 'dismissed'),
    'gates_fast',      (select count(*) from vt where challenge_outcome = 'skipped_fast'),
    'paywall_shown',   (select count(*) from ev where event = 'paywall_shown'),
    'wall_reached',    (select count(*) from ev where event = 'wall_reached'),
    'onboarding_finished', (select bool_or(event in ('onboarding_finished', 'onboarding_completed')) from ev),
    'reminder_enabled',    (select bool_or(event in ('onboarding_notify_enabled', 'wall_notify_enabled')) from ev),
    'favorites',       (select count(*) from public.question_favorites f where f.user_id = p_user_id),
    'stored_streak',   coalesce(pr.current_streak, 0),
    'longest_streak',  coalesce(pr.longest_streak, 0),
    'last_vote_date',  pr.last_vote_date,
    'live_streak',     public.decayed_streak(coalesce(pr.current_streak, 0), pr.last_vote_date, v_today_utc),
    'streak_alive',    coalesce(pr.last_vote_date >= v_today_utc - 1, false),
    'rank_name',       (select rk.name_pl from public.ranks rk
                         where rk.min_streak <= public.decayed_streak(coalesce(pr.current_streak, 0), pr.last_vote_date, v_today_utc)
                         order by rk.min_streak desc limit 1)
  ) into v_totals
  from (select 1) one
  left join public.profiles pr on pr.id = p_user_id;

  -- ----------------------------------------------------------------- before
  -- Only meaningful with a purchase; NULL otherwise so the panel hides it.
  if v_purchase_at is not null then
    with ev as (
      select e.event, e.created_at, (e.created_at at time zone v_tz)::date as day
      from public.app_events e
      where e.user_id = p_user_id and e.created_at < v_purchase_at
    ), vt as (
      select v.voted_at, v.challenge_outcome,
             (v.voted_at at time zone 'UTC')::date as uday
      from public.question_votes v
      where v.user_id = p_user_id and v.voted_at < v_purchase_at
    ), runs as (
      -- consecutive UTC vote days; the run that touches the purchase day (or
      -- the day before — the grace day) is the streak the buyer held
      select uday, uday - (row_number() over (order by uday))::int as grp
      from (select distinct uday from vt) d
    )
    select jsonb_build_object(
      'minutes_to_purchase', round(extract(epoch from (v_purchase_at - v_first_seen)) / 60.0),
      'events',          (select count(*) from ev),
      'active_days',     (select count(distinct day) from ev),
      'votes',           (select count(*) from vt),
      'vote_days',       (select count(distinct uday) from vt),
      'first_vote_at',   (select min(voted_at) from vt),
      'last_vote_at',    (select max(voted_at) from vt),
      'gates_answered',  (select count(*) from vt where challenge_outcome in ('held', 'moved')),
      'gates_moved',     (select count(*) from vt where challenge_outcome = 'moved'),
      'paywall_shown',   (select count(*) from ev where event = 'paywall_shown'),
      'paywall_dismissed', (select count(*) from ev where event = 'paywall_dismissed'),
      'wall_reached',    (select count(*) from ev where event = 'wall_reached'),
      'purchase_started',(select count(*) from ev where event = 'paywall_purchase_started'),
      'purchase_abandoned', (select count(*) from ev where event = 'paywall_purchase_abandoned'),
      'onboarding_finished', (select coalesce(bool_or(event in ('onboarding_finished', 'onboarding_completed')), false) from ev),
      'last_paywall_source', (select e.properties ->> 'source' from public.app_events e
                               where e.user_id = p_user_id and e.event = 'paywall_shown'
                                 and e.created_at < v_purchase_at
                               order by e.created_at desc limit 1),
      'streak_at_purchase', coalesce((
        select count(*) from runs
        where grp = (select r2.grp from runs r2
                     where r2.uday >= (v_purchase_at at time zone 'UTC')::date - 1
                     order by r2.uday desc limit 1)), 0)
    ) into v_before;
  end if;

  -- ------------------------------------------------------------------- days
  with ev as (
    select (e.created_at at time zone v_tz)::date as day, e.event
    from public.app_events e
    where e.user_id = p_user_id
  ), vt as (
    select (v.voted_at at time zone v_tz)::date as day, v.challenge_outcome
    from public.question_votes v
    where v.user_id = p_user_id
  ), all_days as (
    select day from ev union select day from vt
  ), per_day as (
    select d.day,
           (select count(*) from ev where ev.day = d.day)::int                                   as events,
           (select count(*) from vt where vt.day = d.day)::int                                   as votes,
           (select count(*) from vt where vt.day = d.day
                                      and vt.challenge_outcome in ('held', 'moved'))::int        as gates,
           (select count(*) from vt where vt.day = d.day
                                      and vt.challenge_outcome = 'moved')::int                   as moved,
           (select count(*) from ev where ev.day = d.day and ev.event = 'paywall_shown')::int    as paywall_shown,
           (select count(*) from ev where ev.day = d.day and ev.event = 'wall_reached')::int     as wall_reached,
           (v_purchase_at is not null
              and (v_purchase_at at time zone v_tz)::date = d.day)                               as purchased,
           (v_purchase_at is not null
              and d.day < (v_purchase_at at time zone v_tz)::date)                               as before_purchase
    from all_days d
  )
  select coalesce(jsonb_agg(to_jsonb(p) order by p.day desc), '[]'::jsonb) into v_days
  from (select * from per_day order by day desc limit 120) p;

  -- ----------------------------------------------------------------- recent
  select coalesce(jsonb_agg(jsonb_build_object(
           'at',        r.created_at,
           'event',     r.event,
           'install',   left(r.install_id::text, 8),
           'source',    r.properties ->> 'source',
           'trigger',   r.properties ->> 'trigger',
           'outcome',   r.properties ->> 'outcome',
           'plan',      r.properties ->> 'plan',
           'day_number', r.properties ->> 'day_number',
           'status',    r.properties ->> 'status',
           'utm_source', r.properties ->> 'utm_source'
         ) order by r.created_at desc), '[]'::jsonb) into v_recent
  from (
    select e.created_at, e.event, e.install_id, e.properties
    from public.app_events e
    where e.user_id = p_user_id
    order by e.created_at desc
    limit 80
  ) r;

  return jsonb_build_object(
    'found',        true,
    'generated_at', now(),
    'account',      v_account,
    'purchase',     v_purchase,
    'before',       v_before,
    'totals',       v_totals,
    'days',         v_days,
    'recent',       v_recent
  );
end;
$function$;

comment on function public.admin_user_history_core(uuid) is
  'Internal: one account''s full history split at its first real purchase (account, purchase, before, totals, days[], recent[]). Called by admin_user_history and the Telegram purchase ping. Never granted to client roles.';

revoke all on function public.admin_user_history_core(uuid) from public, anon, authenticated;
grant execute on function public.admin_user_history_core(uuid) to service_role;

-- ----------------------------------------------------------------------------
-- 2) admin wrapper — id or prefix, admin only
-- ----------------------------------------------------------------------------
create or replace function public.admin_user_history(p_user text)
returns jsonb
language plpgsql stable security definer
set search_path to 'public'
as $function$
declare
  v_q   text := lower(regexp_replace(coalesce(p_user, ''), '[^0-9a-fA-F-]', '', 'g'));
  v_id  uuid;
  v_n   int;
begin
  perform public.admin_require();

  if v_q = '' then
    return jsonb_build_object('found', false);
  end if;

  if v_q ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    v_id := v_q::uuid;
  else
    if length(replace(v_q, '-', '')) < 6 then
      return jsonb_build_object('found', false, 'too_short', true);
    end if;
    select count(*), min(u.id::text)::uuid into v_n, v_id
    from auth.users u
    where u.id::text like v_q || '%';
    if v_n = 0 then
      return jsonb_build_object('found', false);
    elsif v_n > 1 then
      return jsonb_build_object('found', false, 'ambiguous', v_n);
    end if;
  end if;

  return public.admin_user_history_core(v_id);
end;
$function$;

comment on function public.admin_user_history(text) is
  'Admin-only: history of one account by full UUID or a ≥6-char prefix — what it did before and after its first purchase. Read-only.';

revoke all on function public.admin_user_history(text) from public, anon;
grant execute on function public.admin_user_history(text) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 3) Telegram purchase ping — "who is this?"
-- ----------------------------------------------------------------------------
create or replace function public.billing_event_telegram_notify()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  ev      jsonb := new.payload -> 'event';
  v_price text;
  v_msg   text;
  v_who   text := '';
  h       jsonb;
  b       jsonb;
  t       jsonb;
  v_min   numeric;
  v_ago   text;
begin
  -- New money only: no renewals, no sandbox, no dashboard promo grants.
  if new.type not in ('INITIAL_PURCHASE', 'NON_RENEWING_PURCHASE') then
    return new;
  end if;
  if coalesce(ev ->> 'environment', 'PRODUCTION') = 'SANDBOX' then
    return new;
  end if;
  if coalesce(ev ->> 'store', '') = 'PROMOTIONAL'
     or coalesce(ev ->> 'product_id', '') like 'rc\_promo\_%' escape '\' then
    return new;
  end if;

  if ev ->> 'price_in_purchased_currency' is not null then
    v_price := format('%s %s',
                      ev ->> 'price_in_purchased_currency',
                      coalesce(ev ->> 'currency', ''));
  end if;

  v_msg := '💰 <b>Nowa subskrypcja Debatly!</b>'
        || E'\nProdukt: ' || public.tg_escape(coalesce(ev ->> 'product_id', '?'))
        || E'\nSklep: '   || public.tg_escape(coalesce(ev ->> 'store', '?'))
        || case when v_price is not null
                then E'\nCena: ' || public.tg_escape(v_price) else '' end
        || case when ev ->> 'country_code' is not null
                then E'\nKraj: ' || public.tg_escape(ev ->> 'country_code') else '' end;

  -- Who bought — a nice-to-have on top of a nice-to-have: any failure here
  -- leaves the ping exactly as it was before this migration.
  begin
    if new.user_id is not null then
      h := public.admin_user_history_core(new.user_id);
      if coalesce((h ->> 'found')::boolean, false) then
        b := h -> 'before';
        t := h -> 'totals';
        v_who := E'\n\n👤 Konto: <code>' || left(new.user_id::text, 8) || '</code>'
              || case when (h -> 'account' ->> 'has_account')::boolean
                      then ' (z kontem)' else ' (anonim)' end;
        v_min := (b ->> 'minutes_to_purchase')::numeric;
        v_ago := case
                   when v_min is null then '?'
                   when v_min < 60 then v_min::int || ' min'
                   when v_min < 48 * 60 then round(v_min / 60) || ' h'
                   else round(v_min / 1440) || ' dni'
                 end;
        -- "new" = bought on the first day it was seen; the vote count tells
        -- whether the daily was even tried before the wallet came out
        if coalesce((b ->> 'active_days')::int, 0) <= 1 then
          v_who := v_who || E'\n🆕 <b>Nowy</b> — kupił ' || v_ago
                || ' po pierwszym uruchomieniu, '
                || coalesce(b ->> 'votes', '0') || ' głosów wcześniej'
                || case when coalesce((b ->> 'onboarding_finished')::boolean, false)
                        then ', po onboardingu' else ', bez onboardingu' end;
        else
          v_who := v_who || E'\n🎮 <b>Grał wcześniej</b> — '
                || coalesce(b ->> 'votes', '0') || ' głosów w '
                || coalesce(b ->> 'active_days', '0') || ' dni'
                || ', streak ' || coalesce(b ->> 'streak_at_purchase', '0')
                || ', paywall ' || coalesce(b ->> 'paywall_shown', '0') || '×'
                || case when coalesce((b ->> 'wall_reached')::int, 0) > 0
                        then ', ściana ' || (b ->> 'wall_reached') || '×' else '' end
                || E'\nPierwsze uruchomienie: '
                || to_char((t ->> 'first_seen_at')::timestamptz at time zone 'Europe/Warsaw', 'DD.MM HH24:MI')
                || ' (' || v_ago || ' temu)';
        end if;
        if b ->> 'last_paywall_source' is not null then
          v_who := v_who || E'\nOstatni paywall: ' || public.tg_escape(b ->> 'last_paywall_source');
        end if;
      end if;
    end if;
  exception when others then
    v_who := '';
  end;

  perform public.tg_send(v_msg || v_who);
  return new;
exception when others then
  -- The notification is a nice-to-have; the billing_events insert is the
  -- webhook's idempotency marker. Never let Telegram break RevenueCat.
  return new;
end;
$$;
