-- ============================================================================
-- Per-category progress: total AND how many the caller has answered.
-- ----------------------------------------------------------------------------
-- 2026-09-02. Replaces get_question_category_counts (20260902130000, applied
-- minutes earlier, never shipped in a client build — dropped outright).
--
-- WHY
--   The modes screen's tiles show a progress ring ("odpowiedziałeś na 56%
--   pytań z tego tematu") over the count, and the "Teraz grasz" card says how
--   many questions are still unanswered in the current scope. Both need the
--   caller's own vote count per category next to the total. One GROUP BY,
--   one left join on question_votes scoped to auth.uid(): an anon or
--   sessionless caller gets voted = 0, which is also the truth.
--
--   Still no ids and no text — a free client learns only that it has
--   answered, say, 1 of 77 Relationships questions, which is the number the
--   locked tile is selling with.
-- ============================================================================

drop function if exists public.get_question_category_counts();

create or replace function public.get_question_category_progress()
returns table (category text, total bigint, voted bigint)
language sql
stable
security definer
set search_path to 'public'
as $$
  select q.category,
         count(*)::bigint            as total,
         count(v.question_id)::bigint as voted
  from public.questions q
  left join public.question_votes v
    on v.question_id = q.id
   and v.user_id = auth.uid()
  where q.is_active
  group by q.category
  order by total desc, q.category;
$$;

revoke all on function public.get_question_category_progress() from public;
grant execute on function public.get_question_category_progress()
  to anon, authenticated;

comment on function public.get_question_category_progress() is
  'Active question count per category plus how many of them the caller has '
  'voted on (0 without a session). Feeds the modes screen''s tile rings and '
  'the "N left" line. No ids, no text. See 20260902140000.';
