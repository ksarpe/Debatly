-- ============================================================================
-- Telegram notifications for the owner (2026-09-01)
-- ----------------------------------------------------------------------------
-- Two things land in the owner's Telegram group:
--
--   1. An instant message on every REAL new purchase (INITIAL_PURCHASE /
--      NON_RENEWING_PURCHASE) — via an AFTER INSERT trigger on
--      `billing_events`. The RevenueCat webhook is untouched: it already
--      writes every event there as its idempotency marker, exactly once per
--      event, so the trigger can never double-fire. Sandbox receipts and
--      promo grants are filtered with the same predicates as
--      `admin_live_sales` (20260822090000).
--
--   2. A daily report at 08:00 Europe/Warsaw covering YESTERDAY (local day):
--      new devices (first app_event — the closest thing to "downloads" the
--      backend can see), votes, purchases/renewals + revenue, active paid
--      subs. Internal accounts are excluded with the same email patterns as
--      `admin_dashboard_stats` (20260814170000).
--
-- Delivery is `pg_net` (async queue): the trigger only ENQUEUES an HTTP call,
-- so a Telegram outage can neither slow down nor 500 the webhook insert; the
-- trigger additionally swallows every exception. Responses can be inspected
-- in `net._http_response`.
--
-- Secrets live in Supabase Vault under the names `telegram_bot_token` and
-- `telegram_chat_id` — inserted out-of-band (SQL editor / MCP), NEVER in this
-- file. Missing secrets = tg_send() silently no-ops; nothing else breaks.
--
-- DST handling for "08:00 Warsaw": pg_cron only speaks UTC, so TWO jobs run
-- (06:00 and 07:00 UTC) and `send_daily_telegram_report()` sends only when
-- the Warsaw wall clock says 8 — one of the two always matches, never both.
-- ============================================================================

create extension if not exists pg_net;

-- ---------------------------------------------------------------- helpers --

-- Telegram is called with parse_mode=HTML; anything dynamic gets escaped.
create or replace function public.tg_escape(p text)
returns text
language sql immutable
as $$
  select replace(replace(replace(coalesce(p, ''), '&', '&amp;'), '<', '&lt;'), '>', '&gt;');
$$;

-- Enqueues one Telegram message. SECURITY DEFINER (owner: postgres) so it may
-- read Vault; execution is locked down to service_role below — clients can
-- never spam the owner's chat through PostgREST.
create or replace function public.tg_send(p_text text)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_token text;
  v_chat  text;
begin
  select ds.decrypted_secret into v_token
    from vault.decrypted_secrets ds where ds.name = 'telegram_bot_token';
  select ds.decrypted_secret into v_chat
    from vault.decrypted_secrets ds where ds.name = 'telegram_chat_id';
  if v_token is null or v_chat is null then
    return; -- not configured — a silent no-op, never an error
  end if;

  perform net.http_post(
    url  := format('https://api.telegram.org/bot%s/sendMessage', v_token),
    body := jsonb_build_object(
      'chat_id',    v_chat,
      'text',       p_text,
      'parse_mode', 'HTML'
    )
  );
end;
$$;

revoke all on function public.tg_escape(text) from public, anon, authenticated;
revoke all on function public.tg_send(text)   from public, anon, authenticated;
grant execute on function public.tg_send(text) to service_role;

-- ----------------------------------------- 1) instant purchase notification --

create or replace function public.billing_event_telegram_notify()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  ev      jsonb := new.payload -> 'event';
  v_price text;
  v_msg   text;
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

  perform public.tg_send(v_msg);
  return new;
exception when others then
  -- The notification is a nice-to-have; the billing_events insert is the
  -- webhook's idempotency marker. Never let Telegram break RevenueCat.
  return new;
end;
$$;

drop trigger if exists billing_events_telegram_notify on public.billing_events;
create trigger billing_events_telegram_notify
  after insert on public.billing_events
  for each row execute function public.billing_event_telegram_notify();

-- ------------------------------------------------------- 2) daily report --

-- p_force skips the 08:00-Warsaw guard for manual testing:
--   select public.send_daily_telegram_report(true);
create or replace function public.send_daily_telegram_report(p_force boolean default false)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_yday      date;
  v_start     timestamptz;
  v_end       timestamptz;
  v_daynames  text[] := array['niedziela','poniedziałek','wtorek','środa',
                              'czwartek','piątek','sobota'];
  -- exclusion sets (same sources as the admin dashboard / live sales)
  v_internal_users    uuid[];
  v_internal_installs uuid[];
  v_test_users        uuid[];
  -- metrics
  v_new_devices  int;
  v_votes        int;
  v_voters       int;
  v_new_subs     int;
  v_renewals     int;
  v_revenue      text;
  v_active_subs  int;
  v_cancelling   int;
  v_msg          text;
begin
  -- Fire only when the Warsaw wall clock says 8 — the two UTC cron slots
  -- (06:00 & 07:00) cover CEST and CET; exactly one matches on any given day.
  if not p_force
     and extract(hour from now() at time zone 'Europe/Warsaw') <> 8 then
    return;
  end if;

  v_yday  := (now() at time zone 'Europe/Warsaw')::date - 1;
  v_start := v_yday::timestamp at time zone 'Europe/Warsaw';
  v_end   := (v_yday + 1)::timestamp at time zone 'Europe/Warsaw';

  -- Internal (owner/test) accounts — patterns mirrored from
  -- admin_dashboard_stats (20260814170000); keep the two lists in sync.
  select coalesce(array_agg(u.id), '{}'::uuid[]) into v_internal_users
  from auth.users u
  where u.email ilike any (array[
    '%janowskicorp%', '%taknormalni%', '%2299kasper%', '%229kasper%',
    '%alicjaszcz00%'
  ]);

  select coalesce(array_agg(distinct e.install_id), '{}'::uuid[])
    into v_internal_installs
  from public.app_events e
  where e.user_id = any (v_internal_users);

  -- Users who ever produced a SANDBOX receipt = test accounts (as in
  -- admin_live_sales, 20260822090000).
  select coalesce(array_agg(distinct b.user_id), '{}'::uuid[]) into v_test_users
  from public.billing_events b
  where b.user_id is not null
    and coalesce(b.payload->'event'->>'environment', 'PRODUCTION') = 'SANDBOX';

  -- "Downloads": devices whose FIRST app_event fell on yesterday's local day.
  select count(*) into v_new_devices
  from (
    select e.install_id, min(e.created_at) as first_seen
    from public.app_events e
    where not (e.install_id = any (v_internal_installs))
    group by e.install_id
  ) f
  where f.first_seen >= v_start and f.first_seen < v_end;

  select count(*), count(distinct v.user_id) into v_votes, v_voters
  from public.question_votes v
  where v.voted_at >= v_start and v.voted_at < v_end
    and not (v.user_id = any (v_internal_users));

  -- Real money only (no sandbox, no promo) — admin_live_sales predicates.
  with money as (
    select b.type,
           (b.payload->'event'->>'price_in_purchased_currency')::numeric as price,
           b.payload->'event'->>'currency' as currency
    from public.billing_events b
    where b.received_at >= v_start and b.received_at < v_end
      and b.type in ('INITIAL_PURCHASE', 'NON_RENEWING_PURCHASE', 'RENEWAL')
      and coalesce(b.payload->'event'->>'environment', 'PRODUCTION') <> 'SANDBOX'
      and coalesce(b.payload->'event'->>'product_id', '') not like 'rc\_promo\_%' escape '\'
      and coalesce(b.payload->'event'->>'store', '') <> 'PROMOTIONAL'
  ),
  agg as (
    select count(*) filter (where m.type <> 'RENEWAL') as new_subs,
           count(*) filter (where m.type = 'RENEWAL')  as renewals
    from money m
  ),
  rev as (
    select string_agg(format('%s %s', x.total, coalesce(x.currency, '?')), ' + ')
             as revenue
    from (
      select round(sum(m.price), 2) as total, m.currency
      from money m
      where m.price is not null
      group by m.currency
    ) x
  )
  select agg.new_subs, agg.renewals, rev.revenue
    into v_new_subs, v_renewals, v_revenue
  from agg, rev;

  select count(*) filter (where s.is_active),
         count(*) filter (where s.is_active and not s.will_renew)
    into v_active_subs, v_cancelling
  from public.subscriptions s
  where not (s.user_id = any (v_test_users))
    and coalesce(s.store, '') <> 'PROMOTIONAL'
    and coalesce(s.product_id, '') not like 'rc\_promo\_%' escape '\';

  v_msg := format(
       E'📊 <b>Debatly — %s %s</b>'
    || E'\n📥 Nowe urządzenia: <b>%s</b>'
    || E'\n🗳 Głosy: <b>%s</b> (%s os.)'
    || E'\n💰 Nowe subskrypcje: <b>%s</b> · odnowienia: %s',
    v_daynames[extract(dow from v_yday)::int + 1],
    to_char(v_yday, 'DD.MM'),
    v_new_devices, v_votes, v_voters, v_new_subs, v_renewals);

  if v_revenue is not null then
    v_msg := v_msg || E'\n   Przychód: ' || public.tg_escape(v_revenue);
  end if;

  v_msg := v_msg || format(E'\n⭐ Aktywne płatne suby: <b>%s</b>', v_active_subs);
  if v_cancelling > 0 then
    v_msg := v_msg || format(' (anuluje: %s)', v_cancelling);
  end if;

  perform public.tg_send(v_msg);
end;
$$;

revoke all on function public.send_daily_telegram_report(boolean)
  from public, anon, authenticated;
grant execute on function public.send_daily_telegram_report(boolean) to service_role;

-- ------------------------------------------------------------------ cron --

-- cron.schedule() upserts by name, so re-running this migration is safe.
select cron.schedule(
  'telegram-daily-report-6utc', '0 6 * * *',
  $job$select public.send_daily_telegram_report()$job$);
select cron.schedule(
  'telegram-daily-report-7utc', '0 7 * * *',
  $job$select public.send_daily_telegram_report()$job$);
