-- Propozycje pytań od użytkowników ("Zaproponuj pytanie").
--
-- Użytkownik (także anonimowy — każda sesja ma UUID w auth.users) wysyła z
-- aplikacji surowy pomysł na pytanie; trafia on tutaj i jest przeglądany w
-- panelu admina (/suggestions), gdzie dostaje status. Przyjęta propozycja jest
-- potem przepisywana na porządne pytanie PL/EN + smaczki zwykłym flow treści —
-- ta tabela to skrzynka wejściowa, nie katalog.
--
-- * RLS on, zero grantów dla klienta. Jedyna droga do środka to
--   submit_question_suggestion (security definer, rate-limit 10/dobę), jedyna
--   droga do odczytu to admin_* RPC z admin_require() — jak reszta panelu
--   (20260724130000_admin_panel_foundation.sql).
-- * user_id celowo `on delete set null`: kasacja konta nie może wysypać
--   skrzynki, a tekst propozycji nie jest danymi osobowymi.
-- * Statusy: 'new' | 'accepted' | 'rejected'. "accepted" znaczy "bierzemy do
--   katalogu" — samo w sobie niczego nie publikuje.

-- ----------------------------------------------------------------------------
-- 1) Tabela
-- ----------------------------------------------------------------------------
create table if not exists public.question_suggestions (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users (id) on delete set null,
  suggestion  text not null,
  locale      text,                          -- język aplikacji w chwili wysyłki ('pl'/'en')
  status      text not null default 'new'
              check (status in ('new', 'accepted', 'rejected')),
  admin_note  text,                          -- notatka admina (np. powód odrzucenia)
  created_at  timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users (id) on delete set null
);

-- Pod rate-limit (count po user_id + doba) i pod listę panelu (status + data).
create index if not exists question_suggestions_user_created_idx
  on public.question_suggestions (user_id, created_at desc);
create index if not exists question_suggestions_status_created_idx
  on public.question_suggestions (status, created_at desc);

alter table public.question_suggestions enable row level security;
revoke all on table public.question_suggestions from public, anon, authenticated;
grant all on table public.question_suggestions to service_role;

-- ----------------------------------------------------------------------------
-- 2) Wysyłka z aplikacji (każdy zalogowany, także anonimowy)
-- ----------------------------------------------------------------------------
-- Zwraca id nowego wiersza. Błędy tekstowe, które klient rozróżnia:
--   NOT_AUTHENTICATED / TOO_SHORT / TOO_LONG / RATE_LIMITED
create or replace function public.submit_question_suggestion(
  p_text text,
  p_locale text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_text text := btrim(coalesce(p_text, ''));
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  if char_length(v_text) < 10 then
    raise exception 'TOO_SHORT';
  end if;
  if char_length(v_text) > 500 then
    raise exception 'TOO_LONG';
  end if;

  -- Prosty bezpiecznik antyspamowy: 10 propozycji na kroczącą dobę na konto.
  if (select count(*) from public.question_suggestions
      where user_id = auth.uid()
        and created_at > now() - interval '24 hours') >= 10 then
    raise exception 'RATE_LIMITED';
  end if;

  insert into public.question_suggestions (user_id, suggestion, locale)
  values (auth.uid(), v_text, nullif(btrim(coalesce(p_locale, '')), ''))
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.submit_question_suggestion(text, text) from public, anon;
grant execute on function public.submit_question_suggestion(text, text) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 3) Panel: lista (opcjonalny filtr po statusie), najnowsze na górze
-- ----------------------------------------------------------------------------
create or replace function public.admin_list_question_suggestions(
  p_status text default null
) returns setof public.question_suggestions
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.admin_require();
  return query
    select * from public.question_suggestions
    where p_status is null or status = p_status
    order by created_at desc;
end;
$$;

revoke all on function public.admin_list_question_suggestions(text) from public, anon;
grant execute on function public.admin_list_question_suggestions(text) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 4) Panel: zmiana statusu (+ opcjonalna notatka)
-- ----------------------------------------------------------------------------
-- p_note = null → notatka zostaje jaka była; pusty string → czyści notatkę.
-- Powrót do 'new' zeruje znacznik przejrzenia.
create or replace function public.admin_set_question_suggestion_status(
  p_id uuid,
  p_status text,
  p_note text default null
) returns public.question_suggestions
language plpgsql security definer set search_path = public as $$
declare
  v_row public.question_suggestions;
begin
  perform public.admin_require();

  if p_status not in ('new', 'accepted', 'rejected') then
    raise exception 'BAD_STATUS';
  end if;

  update public.question_suggestions set
    status      = p_status,
    admin_note  = case when p_note is null then admin_note
                       else nullif(btrim(p_note), '') end,
    reviewed_at = case when p_status = 'new' then null else now() end,
    reviewed_by = case when p_status = 'new' then null else auth.uid() end
  where id = p_id
  returning * into v_row;

  if v_row.id is null then
    raise exception 'NOT_FOUND';
  end if;

  return v_row;
end;
$$;

revoke all on function public.admin_set_question_suggestion_status(uuid, text, text) from public, anon;
grant execute on function public.admin_set_question_suggestion_status(uuid, text, text) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 5) Panel: usunięcie (spam)
-- ----------------------------------------------------------------------------
create or replace function public.admin_delete_question_suggestion(p_id uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
begin
  perform public.admin_require();
  delete from public.question_suggestions where id = p_id;
  return found;
end;
$$;

revoke all on function public.admin_delete_question_suggestion(uuid) from public, anon;
grant execute on function public.admin_delete_question_suggestion(uuid) to authenticated, service_role;
