-- ============================================================================
-- Add a `teaser` to get_questions: the first two words of the question text,
-- returned even for LOCKED questions so the swipe deck can show a "Czy
-- miliarderzy…" tease above the unlock CTA instead of a generic "locked" label.
--
-- The function is SECURITY DEFINER, so it can read the full text to derive the
-- teaser regardless of the gate -- only the FULL question_text stays withheld
-- for locked rows. The teaser is intentionally tiny (two words): enough to bait
-- the unlock, not enough to be the question. The client appends the ellipsis.
--
-- The return signature changes (a new column), which CREATE OR REPLACE cannot
-- do, so the function is dropped and recreated.
-- ============================================================================

drop function if exists public.get_questions(text, date);
create or replace function public.get_questions(
  p_locale text default 'pl',
  p_date   date default (now() at time zone 'utc')::date
)
returns table (
  id            uuid,
  category      text,
  is_premium    boolean,
  question_text text,
  locked        boolean,
  teaser        text
)
language sql stable security definer set search_path = public as $$
  select
    q.id,
    q.category,
    q.is_premium,
    case when public.can_read_question_text(q.id, p_date)
         then coalesce(tr.question_text, en.question_text)
         else null end                              as question_text,
    not public.can_read_question_text(q.id, p_date) as locked,
    -- First two words of the (full) text, regardless of the gate. NULL when the
    -- question has no translation at all, so the client can fall back gracefully.
    array_to_string(
      (regexp_split_to_array(
         btrim(coalesce(tr.question_text, en.question_text)), '\s+'))[1:2],
      ' '
    )                                               as teaser
  from public.questions q
  left join public.question_translations tr
         on tr.question_id = q.id and tr.locale = p_locale
  left join public.question_translations en
         on en.question_id = q.id and en.locale = 'en'
  where q.is_active
  order by q.created_at, q.id;
$$;
grant execute on function public.get_questions(text, date) to anon, authenticated;
