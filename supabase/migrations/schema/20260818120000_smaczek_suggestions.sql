-- Propozycje smaczków od użytkowników ("Zaproponuj własny" w panelu Argumentów).
--
-- Ta sama skrzynka wejściowa co propozycje pytań (question_suggestions,
-- 20260817150000) — wiersz dostaje kind='smaczek' i podpięte pytanie, admin
-- przegląda wszystko razem w panelu /suggestions. Przyjęty smaczek przepisuje
-- się do katalogu zwykłym flow treści; ta tabela nadal niczego nie publikuje.
--
-- * Wejście wyłącznie przez submit_smaczek_suggestion (security definer):
--   parametryzowany INSERT (zero sklejania SQL), twarde limity długości
--   (5–80 znaków), odrzucenie znaków sterujących, sprawdzenie że pytanie
--   istnieje i wspólny z propozycjami pytań rate-limit 10/dobę.
-- * RLS/granty tabeli bez zmian: klient nadal nie ma żadnego bezpośredniego
--   dostępu do question_suggestions.

-- ----------------------------------------------------------------------------
-- 1) Rozszerzenie tabeli: rodzaj propozycji + kontekst (którego pytania dotyczy)
-- ----------------------------------------------------------------------------
alter table public.question_suggestions
  add column if not exists kind text not null default 'question'
    check (kind in ('question', 'smaczek')),
  add column if not exists question_id uuid
    references public.questions (id) on delete set null;

-- ----------------------------------------------------------------------------
-- 2) Wysyłka smaczka z aplikacji (każdy zalogowany, także anonimowy)
-- ----------------------------------------------------------------------------
-- Zwraca id nowego wiersza. Błędy tekstowe, które klient rozróżnia:
--   NOT_AUTHENTICATED / BAD_TEXT / TOO_SHORT / TOO_LONG / BAD_QUESTION /
--   RATE_LIMITED
create or replace function public.submit_smaczek_suggestion(
  p_question_id uuid,
  p_text text,
  p_locale text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  -- Normalizacja: każdy ciąg białych znaków (spacje, taby, nowe linie) do
  -- pojedynczej spacji + trim. Smaczek to jedna linijka tekstu.
  v_text text := btrim(regexp_replace(coalesce(p_text, ''), '\s+', ' ', 'g'));
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  -- Znaki sterujące nie mają tu czego szukać (białe znaki już znormalizowane
  -- wyżej) — defensywnie, obok parametryzacji i escapowania w panelu.
  if v_text ~ '[\x01-\x1F\x7F]' then
    raise exception 'BAD_TEXT';
  end if;
  if char_length(v_text) < 5 then
    raise exception 'TOO_SHORT';
  end if;
  if char_length(v_text) > 80 then
    raise exception 'TOO_LONG';
  end if;

  -- Smaczek bez istniejącego pytania to śmieć — odrzucamy zamiast zapisywać.
  if not exists (select 1 from public.questions q where q.id = p_question_id) then
    raise exception 'BAD_QUESTION';
  end if;

  -- Wspólny bezpiecznik antyspamowy z propozycjami pytań: 10 wpisów na
  -- kroczącą dobę na konto, niezależnie od rodzaju.
  if (select count(*) from public.question_suggestions
      where user_id = auth.uid()
        and created_at > now() - interval '24 hours') >= 10 then
    raise exception 'RATE_LIMITED';
  end if;

  insert into public.question_suggestions (user_id, suggestion, locale, kind, question_id)
  values (
    auth.uid(),
    v_text,
    nullif(btrim(coalesce(p_locale, '')), ''),
    'smaczek',
    p_question_id
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.submit_smaczek_suggestion(uuid, text, text) from public, anon;
grant execute on function public.submit_smaczek_suggestion(uuid, text, text) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 3) Panel: lista z kontekstem pytania (dla smaczków)
-- ----------------------------------------------------------------------------
-- Zamiast `setof question_suggestions` zwracamy tabelę z doklejonym
-- question_text (PL, awaryjnie EN), żeby admin widział, do którego pytania
-- smaczek został zgłoszony. Zmiana typu zwrotki wymaga DROP przed CREATE.
drop function if exists public.admin_list_question_suggestions(text);

create function public.admin_list_question_suggestions(
  p_status text default null
) returns table (
  id            uuid,
  user_id       uuid,
  suggestion    text,
  locale        text,
  status        text,
  admin_note    text,
  created_at    timestamptz,
  reviewed_at   timestamptz,
  reviewed_by   uuid,
  kind          text,
  question_id   uuid,
  question_text text
)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.admin_require();
  return query
    select s.id, s.user_id, s.suggestion, s.locale, s.status, s.admin_note,
           s.created_at, s.reviewed_at, s.reviewed_by, s.kind, s.question_id,
           (select t.question_text
              from public.question_translations t
             where t.question_id = s.question_id
             order by case t.locale when 'pl' then 0 when 'en' then 1 else 2 end
             limit 1)
    from public.question_suggestions s
    where p_status is null or s.status = p_status
    order by s.created_at desc;
end;
$$;

revoke all on function public.admin_list_question_suggestions(text) from public, anon;
grant execute on function public.admin_list_question_suggestions(text) to authenticated, service_role;
