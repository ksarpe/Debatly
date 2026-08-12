-- ============================================================================
-- Fix get_question_smaczki after the question_unlocks -> question_seen rename.
--
-- get_question_smaczki was never part of the tracked migrations (it predates
-- them / lives in schema.sql), so the rename in 20260620120000 left its access
-- check pointing at the now-missing public.question_unlocks. A SQL function that
-- references a dropped table fails at execution, so EVERY "go deeper" (smaczki)
-- call errored — even on the daily. Repoint the check at question_seen.
--
-- Semantics: a question the user has revealed this session is in question_seen,
-- so smaczki stay available for it (same as the old "unlocked" behaviour). Daily
-- (±1 UTC) and premium are unchanged.
-- ============================================================================

create or replace function public.get_question_smaczki(
  p_question_id uuid,
  p_locale text default 'pl'
)
returns table ("position" smallint, is_locked boolean, text text)
language sql stable security definer set search_path = public as $$
  with access as (
    select
      public.is_premium(auth.uid()) as full_smaczki,
      (
        exists (
          select 1 from public.daily_questions d
          where d.question_id = p_question_id
            and d.publish_date between (now() at time zone 'utc')::date - 1
                                   and (now() at time zone 'utc')::date + 1
        )
        or public.is_premium(auth.uid())
        or exists (
          select 1 from public.question_seen u
          where u.user_id = auth.uid() and u.question_id = p_question_id
        )
      ) as can_access
  )
  select
    s.position,
    not (a.full_smaczki or s.position = 1) as is_locked,
    case
      when a.full_smaczki or s.position = 1
        then coalesce(tr.text, en.text)
      else null
    end as text
  from access a
  join public.question_smaczki s
    on s.question_id = p_question_id and s.is_active
  left join public.question_smaczki_translations tr
    on tr.smaczek_id = s.id and tr.locale = p_locale
  left join public.question_smaczki_translations en
    on en.smaczek_id = s.id and en.locale = 'en'
  where a.can_access
  order by s.position;
$$;
