-- ============================================================================
-- Marketing journal v2 (2026-08-18): rozbicie wejść na sklepy + automatyczne
-- liczby z naszej bazy (instalacje i zakupy dnia), żeby panel liczył konwersję
-- "zakupy / instalacje" sam, bez przepisywania niczego ręcznie.
--
-- Co się zmienia względem 20260816120000_admin_marketing_stats.sql:
--
--   1. marketing_daily_stats.store_visits (jedna wspólna liczba "wejścia do
--      sklepu") znika. Zamiast niej dwie kolumny — store_visits_google i
--      store_visits_appstore — bo te liczby pochodzą z DWÓCH różnych konsol
--      i tylko rozbite dają sensowną konwersję "wejścia → pobrania" per sklep.
--      BACKFILL: istniejące wartości (2026-08-13: 4, 2026-08-14: 14) trafiają
--      do store_visits_appstore — obie mają w notatkach "google brak danych",
--      więc pochodziły z App Store Connect. Gdyby to była zła interpretacja,
--      wystarczy poprawić wiersz w panelu.
--
--   2. admin_list_marketing_stats() zwraca jsonb zamiast setof tabeli i dokłada
--      do każdego dnia liczby, których nie trzeba (i nie da się) wpisywać ręcznie:
--        * installs_tracked — nowe install_id w app_events tego dnia (czyli ile
--          urządzeń PIERWSZY raz odpaliło apkę). To nasz własny licznik: jest
--          natychmiast, w przeciwieństwie do konsol, które mają 1-2 dni
--          opóźnienia. Nie liczy re-instalacji na tym samym urządzeniu.
--        * purchases   — realne zakupy (INITIAL_PURCHASE + NON_RENEWING_PURCHASE),
--          bez sandboxa, bez grantów promo z dashboardu RevenueCat.
--        * revenue_pln — suma price_in_purchased_currency dla waluty PLN.
--      Zwracane są też dni, które mają tylko dane automatyczne (jeszcze bez
--      wpisu w dzienniku) — sprzedaż nigdy nie chowa się przed adminem.
--
--   3. admin_upsert_marketing_day dostaje nową sygnaturę (dwa pola wejść
--      zamiast jednego). Stara wersja jest kasowana — panel jest lokalny,
--      nie ma starych klientów do utrzymania.
--
-- Konwencje jak w reszcie panelu: doba = Europe/Warsaw (zegar właściciela, ten
-- sam co w admin_live_sales), konta wewnętrzne i sandbox wycięte tak samo jak
-- w admin_dashboard_stats (20260818140000). Wszystko admin-gated, read-only
-- poza upsertem. Idempotentne.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Kolumny: jedna wspólna liczba wejść → dwie, per sklep
-- ----------------------------------------------------------------------------
alter table public.marketing_daily_stats
  add column if not exists store_visits_google   integer,
  add column if not exists store_visits_appstore integer;

update public.marketing_daily_stats
   set store_visits_appstore = store_visits
 where store_visits is not null
   and store_visits_appstore is null;

alter table public.marketing_daily_stats drop column if exists store_visits;

comment on column public.marketing_daily_stats.store_visits_google is
  'Play Console → Statystyki → Pozyskiwanie użytkowników → Wyświetlenia strony w Sklepie (dzień).';
comment on column public.marketing_daily_stats.store_visits_appstore is
  'App Store Connect → Analityka → Wyświetlenia strony produktu (Product Page Views, dzień).';
comment on column public.marketing_daily_stats.downloads_google is
  'Play Console → Pozyskiwanie: Instalacje (unikalni użytkownicy) tego dnia.';
comment on column public.marketing_daily_stats.downloads_appstore is
  'App Store Connect → Analityka: Pobrania (Total Downloads) tego dnia.';

-- ----------------------------------------------------------------------------
-- 2) Lista: wpisy ręczne + automatyczne liczby dnia
-- ----------------------------------------------------------------------------
drop function if exists public.admin_list_marketing_stats();

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
    select e.install_id,
           (min(e.created_at) at time zone 'Europe/Warsaw')::date as day
    from public.app_events e
    where e.install_id is not null
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
                       from public.app_events),
    'rows',           v_rows
  );
end;
$$;

revoke all on function public.admin_list_marketing_stats() from public, anon;
grant execute on function public.admin_list_marketing_stats() to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 3) Upsert: nowa sygnatura (wejścia per sklep)
-- ----------------------------------------------------------------------------
drop function if exists public.admin_upsert_marketing_day(date, text, integer, integer, integer, integer, text);

create or replace function public.admin_upsert_marketing_day(
  p_day date,
  p_video text default null,
  p_video_views integer default null,
  p_store_visits_google integer default null,
  p_store_visits_appstore integer default null,
  p_downloads_google integer default null,
  p_downloads_appstore integer default null,
  p_notes text default null
) returns public.marketing_daily_stats
language plpgsql security definer set search_path = public as $$
declare
  v_row public.marketing_daily_stats;
begin
  perform public.admin_require();

  insert into public.marketing_daily_stats as m (
    day, video, video_views, store_visits_google, store_visits_appstore,
    downloads_google, downloads_appstore, notes, updated_at, updated_by
  )
  values (
    p_day, p_video, p_video_views, p_store_visits_google, p_store_visits_appstore,
    p_downloads_google, p_downloads_appstore, p_notes, now(), auth.uid()
  )
  on conflict (day) do update set
    video                 = excluded.video,
    video_views           = excluded.video_views,
    store_visits_google   = excluded.store_visits_google,
    store_visits_appstore = excluded.store_visits_appstore,
    downloads_google      = excluded.downloads_google,
    downloads_appstore    = excluded.downloads_appstore,
    notes                 = excluded.notes,
    updated_at            = now(),
    updated_by            = auth.uid()
  returning * into v_row;

  return v_row;
end;
$$;

revoke all on function public.admin_upsert_marketing_day(date, text, integer, integer, integer, integer, integer, text) from public, anon;
grant execute on function public.admin_upsert_marketing_day(date, text, integer, integer, integer, integer, integer, text) to authenticated, service_role;
