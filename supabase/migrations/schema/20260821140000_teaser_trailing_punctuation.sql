-- ============================================================================
-- Don't cut a teaser on a dangling comma.
-- ----------------------------------------------------------------------------
-- 2026-08-21. Amends get_upcoming_daily_teasers (20260821130000).
--
-- WHY
--   The 4-word cut lands mid-clause, and on 25 of the 407 seeded picks (~6%,
--   so roughly one reminder in sixteen) the 4th word carries a comma or a dash.
--   The client appends an ellipsis, so the notification title read
--   "Czy rodzic ma rację,…" — which parses as a typo, not as a truncation, in
--   the single most-read string the feature has.
--
--   The day wall is deliberately NOT changed: it blurs its teaser, so nobody
--   reads the punctuation there, and peek_next_question is a different function
--   with a different job. This is a notification-copy fix, not a cut-length one.
--
-- NOT HANDLED (on purpose)
--   Exactly one active pick is short enough that all 4 words are the whole
--   question, so its teaser ends in '?' and the client's ellipsis makes it
--   "Czy warto?…". One row in 407 does not justify a second ARB string and a
--   branch in the message builder; '?' is left alone so the day it comes up the
--   title still reads as a question.
-- ============================================================================

create or replace function public.get_upcoming_daily_teasers(
  p_locale text default 'pl',
  p_from   date default (now() at time zone 'utc')::date,
  p_days   int  default 31
)
returns table (publish_date date, teaser text)
language sql
stable
security definer
set search_path to 'public'
as $$
  with bounds as (
    select
      least(
        greatest(
          coalesce(p_from, (now() at time zone 'utc')::date),
          (now() at time zone 'utc')::date - 1
        ),
        (now() at time zone 'utc')::date + 1
      ) as from_date,
      least(greatest(coalesce(p_days, 31), 1), 31) as days
  )
  select dp.publish_date,
         -- Trailing connector punctuation only: a comma, semicolon, colon or
         -- dash left hanging by the cut. Sentence-enders stay.
         rtrim(
           array_to_string(
             (regexp_split_to_array(
                btrim(coalesce(tr.question_text, en.question_text)), '\s+'))[1:4],
             ' '
           ),
           ' ,;:-' || U&'\2013' || U&'\2014'
         ) as teaser
  from bounds b
  join public.daily_picks dp
    on dp.publish_date between b.from_date and b.from_date + b.days
  join public.questions q
    on q.id = dp.question_id and q.is_active
  left join public.question_translations tr
         on tr.question_id = q.id and tr.locale = p_locale
  left join public.question_translations en
         on en.question_id = q.id and en.locale = 'en'
  where btrim(coalesce(tr.question_text, en.question_text, '')) <> ''
  order by dp.publish_date;
$$;

revoke all on function public.get_upcoming_daily_teasers(text, date, int)
  from public;
grant execute on function public.get_upcoming_daily_teasers(text, date, int)
  to anon, authenticated;
