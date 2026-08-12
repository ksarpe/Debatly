-- ============================================================================
-- get_questions: the swipe deck's catalog source
--
-- The home screen builds its swipe deck from the full question CATALOG, not
-- from the gated text. This RPC returns EVERY active question (catalog metadata
-- is public) with its text in the requested locale -- but only when the caller
-- is allowed to read it.
--
-- It runs SECURITY INVOKER (default), so the "read question text (gated)" RLS
-- policy on question_translations stays the single source of truth for the gate:
-- for a locked question both the locale and the 'en' fallback rows are filtered
-- out by RLS, leaving question_text NULL. `locked` is derived from exactly that,
-- so the client can render a locked placeholder + unlock prompt instead of
-- dropping the question from the deck entirely (which is what a plain
-- question_translations query did -- a free user simply never saw locked
-- questions, so the deck silently shrank to whatever fell in the free daily
-- band).
-- ============================================================================

create or replace function public.get_questions(
  p_locale text default 'pl'
)
returns table (
  id            uuid,
  category      text,
  is_premium    boolean,
  question_text text,
  locked        boolean
)
language sql stable set search_path = public as $$
  select
    q.id,
    q.category,
    q.is_premium,
    coalesce(tr.question_text, en.question_text)         as question_text,
    coalesce(tr.question_text, en.question_text) is null as locked
  from public.questions q
  left join public.question_translations tr
         on tr.question_id = q.id and tr.locale = p_locale
  left join public.question_translations en
         on en.question_id = q.id and en.locale = 'en'
  where q.is_active
  order by q.created_at, q.id;
$$;

grant execute on function public.get_questions(text) to anon, authenticated;
