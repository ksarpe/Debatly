-- ============================================================================
-- The day wall's teaser is ALWAYS tomorrow's pick.
-- ----------------------------------------------------------------------------
-- 2026-09-02. Amends peek_next_question (20260820150000, 20260817160000).
--
-- WHY
--   The day wall now carries the reminder opt-in (moved off the onboarding
--   deck — 18% opt-in there, asked before the user had felt anything), and
--   its line reads "Jutro: „<teaser>…” — przypomnę Ci o 20:00". That is a
--   promise about a specific question, and the reminder that fires tomorrow
--   bakes the SAME calendar teaser via get_upcoming_daily_teasers — which has
--   no per-user filter at all. peek_next_question did: it dropped tomorrow's
--   pick when the caller had voted it (or held it as a personal assignment
--   within a day) and quietly served a random unvoted question instead. Then
--   the wall promised one question and the notification named another.
--
--   Both exclusions were protecting a case get_daily_question already
--   handles: a free caller with an OLD vote on the pick still lands on it
--   tomorrow (the one-shot re-vote window, 20260820210000), and a fresh vote
--   on tomorrow's pick cannot exist before tomorrow. So the pick branch keeps
--   only p_exclude_ids (the served daily — a collision the personal draw's
--   future-pick exclusion makes impossible, kept as a belt) and loses the
--   auth.uid() lookups. The random fallback keeps every exclusion it had; it
--   is the gap-date path and still must not tease a question the caller has
--   already met.
--
--   The teaser also gets the trailing-connector trim get_upcoming_daily_teasers
--   received in 20260821140000. That migration left the wall alone because the
--   wall blurred its teaser; the reminder line renders it in plain type, so
--   "Czy rodzic ma rację,…" would now be read.
--
-- NOT CHANGED
--   Signature, return shape, the UTC ±1 clamp before the +1, the 4-word cut,
--   grants. Still a single SELECT that writes nothing.
-- ============================================================================

create or replace function public.peek_next_question(
  p_locale      text  default 'pl',
  p_date        date  default (now() at time zone 'utc')::date,
  p_exclude_ids uuid[] default '{}'
)
returns table (id uuid, teaser text)
language sql
security definer
set search_path to 'public'
as $$
  with bounds as (
    select least(greatest(coalesce(p_date, (now() at time zone 'utc')::date),
                          (now() at time zone 'utc')::date - 1),
                 (now() at time zone 'utc')::date + 1) + 1 as peek_date
  )
  select x.id, x.teaser
  from (
    (
      -- Tomorrow's pick, for everyone: no vote / assignment lookups, so the
      -- wall's promise and tomorrow's reminder name the same question.
      select 0 as pri, q.id,
             rtrim(
               array_to_string(
                 (regexp_split_to_array(
                    btrim(coalesce(tr.question_text, en.question_text)), '\s+'))[1:4],
                 ' '
               ),
               ' ,;:-' || U&'\2013' || U&'\2014'
             ) as teaser
      from bounds b
      join public.daily_picks dp on dp.publish_date = b.peek_date
      join public.questions q on q.id = dp.question_id and q.is_active
      left join public.question_translations tr
             on tr.question_id = q.id and tr.locale = p_locale
      left join public.question_translations en
             on en.question_id = q.id and en.locale = 'en'
      where not (q.id = any (p_exclude_ids))
        and btrim(coalesce(tr.question_text, en.question_text, '')) <> ''
    )
    union all
    (
      -- Gap date (no pick tomorrow, or an inactive one): a random question
      -- the caller has not met, as before.
      select 1 as pri, q.id,
             rtrim(
               array_to_string(
                 (regexp_split_to_array(
                    btrim(coalesce(tr.question_text, en.question_text)), '\s+'))[1:4],
                 ' '
               ),
               ' ,;:-' || U&'\2013' || U&'\2014'
             ) as teaser
      from public.questions q
      left join public.question_translations tr
             on tr.question_id = q.id and tr.locale = p_locale
      left join public.question_translations en
             on en.question_id = q.id and en.locale = 'en'
      where q.is_active
        and not (q.id = any (p_exclude_ids))
        and btrim(coalesce(tr.question_text, en.question_text, '')) <> ''
        and not exists (
          select 1 from public.user_daily_questions ud
          where ud.user_id = auth.uid()
            and ud.question_id = q.id
            and ud.assigned_on between p_date - 1 and p_date + 1
        )
        and not exists (
          select 1 from public.question_votes v
          where v.user_id = auth.uid() and v.question_id = q.id
        )
      order by random()
      limit 1
    )
  ) x
  order by x.pri
  limit 1;
$$;

revoke all on function public.peek_next_question(text, date, uuid[]) from public;
grant execute on function public.peek_next_question(text, date, uuid[])
  to anon, authenticated;

comment on function public.peek_next_question(text, date, uuid[]) is
  'Day-wall teaser (first 4 words, trailing connector punctuation trimmed): '
  'TOMORROW''S daily_picks question for everyone — no per-user exclusions, so '
  'it matches get_upcoming_daily_teasers and the reminder it feeds — falling '
  'back to a random question the caller has not met on a gap date. Pure read. '
  'See 20260902120000.';
