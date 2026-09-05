-- Opinie o aplikacji z pre-promptu przed prośbą o ocenę (2026-09-05).
--
-- Prośba o ocenę w sklepie nie odpala już od razu natywnego arkusza: najpierw
-- własna karta "Jak Ci się gra w Debatly?". Odpowiedź "świetnie" → arkusz
-- systemu (SKStoreReviewController / Play In-App Review); "mogłoby być
-- lepiej" → formularz opinii, który ląduje TU — w tej samej skrzynce co
-- propozycje pytań i smaczków (question_suggestions), z kind='feedback'.
-- Admin widzi wszystko razem w panelu /suggestions ("Opinia").
--
-- Żadnej nagrody za ocenę i żadnej weryfikacji oceny — obie polityki sklepów
-- zabraniają zachęt, a OS i tak nie mówi, czy ktoś ocenił. Ten formularz
-- przechwytuje tylko niezadowolonych, zanim trafią do sklepu.
--
-- * Wejście wyłącznie przez submit_app_feedback (security definer):
--   parametryzowany INSERT, 10–500 znaków, odrzucenie znaków sterujących
--   (poza tab/CR/LF — opinia może mieć akapity) i wspólny z propozycjami
--   rate-limit 10/dobę na konto.
-- * RLS/granty tabeli bez zmian: klient nadal nie czyta question_suggestions.
-- * admin_list_question_suggestions zwraca `kind` od 20260818120000 —
--   panel rozróżnia wiersz po nim, bez zmian po stronie RPC.

-- ----------------------------------------------------------------------------
-- 1) Trzeci rodzaj wiersza w skrzynce
-- ----------------------------------------------------------------------------
alter table public.question_suggestions
  drop constraint if exists question_suggestions_kind_check;
alter table public.question_suggestions
  add constraint question_suggestions_kind_check
    check (kind in ('question', 'smaczek', 'feedback'));

-- ----------------------------------------------------------------------------
-- 2) Wysyłka opinii z aplikacji (każdy zalogowany, także anonimowy)
-- ----------------------------------------------------------------------------
-- Zwraca id nowego wiersza. Błędy tekstowe, które klient rozróżnia:
--   NOT_AUTHENTICATED / BAD_TEXT / TOO_SHORT / TOO_LONG / RATE_LIMITED
create or replace function public.submit_app_feedback(
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

  -- Znaki sterujące poza tab / CR / LF nie mają tu czego szukać.
  if v_text ~ '[\x01-\x08\x0B\x0C\x0E-\x1F\x7F]' then
    raise exception 'BAD_TEXT';
  end if;
  if char_length(v_text) < 10 then
    raise exception 'TOO_SHORT';
  end if;
  if char_length(v_text) > 500 then
    raise exception 'TOO_LONG';
  end if;

  -- Wspólny bezpiecznik antyspamowy ze skrzynką propozycji: 10 wpisów na
  -- kroczącą dobę na konto, niezależnie od rodzaju.
  if (select count(*) from public.question_suggestions
      where user_id = auth.uid()
        and created_at > now() - interval '24 hours') >= 10 then
    raise exception 'RATE_LIMITED';
  end if;

  insert into public.question_suggestions (user_id, suggestion, locale, kind)
  values (
    auth.uid(),
    v_text,
    nullif(btrim(coalesce(p_locale, '')), ''),
    'feedback'
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.submit_app_feedback(text, text) from public, anon;
grant execute on function public.submit_app_feedback(text, text) to authenticated, service_role;
