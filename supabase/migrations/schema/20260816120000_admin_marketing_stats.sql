-- Admin panel: dziennik marketingowy — ręcznie wpisywane statystyki promocji.
--
-- Jeden wiersz na dzień: jaki filmik promujący poszedł, ile zrobił wyświetleń,
-- ile było wejść na stronę sklepu i ile pobrań z Google Play / App Store.
-- Liczby wpisuje admin ręcznie (z TikToka, Play Console, App Store Connect) —
-- nic tu nie jest liczone automatycznie, to notatnik do śledzenia marketingu.
--
-- * Tabela marketing_daily_stats — RLS on, zero grantów dla klienta; dostęp
--   wyłącznie przez security-definer admin_* RPC, jak reszta panelu
--   (20260724130000_admin_panel_foundation.sql).
-- * Kolumny liczbowe są nullable Z ROZMYSŁEM: NULL = "nie wpisałem", 0 = "zero".
-- * admin_upsert_marketing_day nadpisuje cały wiersz (formularz wysyła komplet
--   pól), więc nie ma częściowego merge'a — ostatni zapis wygrywa.

-- ----------------------------------------------------------------------------
-- 1) Tabela
-- ----------------------------------------------------------------------------
create table if not exists public.marketing_daily_stats (
  day                date primary key,
  video              text,          -- co wrzucono: opis / tytuł / link
  video_views        integer,       -- wyświetlenia filmiku (TikTok/Reels/Shorts)
  store_visits       integer,       -- wejścia na stronę sklepu (Play + App Store)
  downloads_google   integer,       -- pobrania Google Play
  downloads_appstore integer,       -- pobrania App Store
  notes              text,          -- dowolne notatki (budżet, hashtagi, wnioski)
  updated_at         timestamptz not null default now(),
  updated_by         uuid references auth.users (id) on delete set null
);

alter table public.marketing_daily_stats enable row level security;
revoke all on table public.marketing_daily_stats from public, anon, authenticated;
grant all on table public.marketing_daily_stats to service_role;

-- ----------------------------------------------------------------------------
-- 2) Lista (całość, najnowsze na górze — to ma być długi spis wierszy)
-- ----------------------------------------------------------------------------
create or replace function public.admin_list_marketing_stats()
returns setof public.marketing_daily_stats
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.admin_require();
  return query
    select * from public.marketing_daily_stats order by day desc;
end;
$$;

revoke all on function public.admin_list_marketing_stats() from public, anon;
grant execute on function public.admin_list_marketing_stats() to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 3) Upsert jednego dnia
-- ----------------------------------------------------------------------------
create or replace function public.admin_upsert_marketing_day(
  p_day date,
  p_video text default null,
  p_video_views integer default null,
  p_store_visits integer default null,
  p_downloads_google integer default null,
  p_downloads_appstore integer default null,
  p_notes text default null
) returns public.marketing_daily_stats
language plpgsql security definer set search_path = public as $$
declare
  v_row public.marketing_daily_stats;
begin
  perform public.admin_require();

  insert into public.marketing_daily_stats as m
    (day, video, video_views, store_visits, downloads_google, downloads_appstore,
     notes, updated_at, updated_by)
  values
    (p_day, nullif(btrim(p_video), ''), p_video_views, p_store_visits,
     p_downloads_google, p_downloads_appstore, nullif(btrim(p_notes), ''),
     now(), auth.uid())
  on conflict (day) do update set
    video              = excluded.video,
    video_views        = excluded.video_views,
    store_visits       = excluded.store_visits,
    downloads_google   = excluded.downloads_google,
    downloads_appstore = excluded.downloads_appstore,
    notes              = excluded.notes,
    updated_at         = now(),
    updated_by         = auth.uid()
  returning * into v_row;

  return v_row;
end;
$$;

revoke all on function public.admin_upsert_marketing_day(date, text, integer, integer, integer, integer, text) from public, anon;
grant execute on function public.admin_upsert_marketing_day(date, text, integer, integer, integer, integer, text) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 4) Usunięcie dnia
-- ----------------------------------------------------------------------------
create or replace function public.admin_delete_marketing_day(p_day date)
returns boolean
language plpgsql security definer set search_path = public as $$
begin
  perform public.admin_require();
  delete from public.marketing_daily_stats where day = p_day;
  return found;
end;
$$;

revoke all on function public.admin_delete_marketing_day(date) from public, anon;
grant execute on function public.admin_delete_marketing_day(date) to authenticated, service_role;
