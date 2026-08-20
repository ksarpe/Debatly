-- ============================================================================
-- Restore the premium-only-voted questions into the daily calendar.
-- ----------------------------------------------------------------------------
-- 2026-08-20, companion to schema/20260820170000_daily_revote_and_pick_priority.
--
-- WHY
--   The seed (20260820151000) excluded every question with ANY real vote —
--   which threw out 135 questions whose only votes are dev/tester traffic
--   (151 votes from 10 currently-premium accounts, owner included). Those
--   votes are not community pollution: on the pick's day a premium voter sees
--   the result bars (by design), and a free voter — none exist on these —
--   would fall into the one-shot re-vote window anyway.
--
-- WHAT
--   Append them after the current calendar end (2027-06-16 at apply time),
--   same category round-robin as the seed. Questions with at least one vote
--   from a NON-premium account stay out — those are genuinely used.
--
-- SAFE TO RE-RUN
--   Candidates exclude questions already in daily_picks; on conflict do
--   nothing on both constraints. A re-run only appends after the calendar end.
-- ============================================================================

with calendar_end as (
  select coalesce(max(dp.publish_date) + 1, date '2026-08-21') as start_date
  from public.daily_picks dp
),
candidates as (
  select q.id, q.category
  from public.questions q
  join public.question_votes v on v.question_id = q.id
  where q.is_active
    and not exists (
      select 1 from public.daily_picks dp where dp.question_id = q.id
    )
  group by q.id, q.category
  having bool_and(public.is_premium(v.user_id))
),
ranked as (
  select c.id, c.category,
         row_number() over (
           partition by c.category
           order by md5(c.id::text || 'daily-picks-restore-v1')
         ) as rn_in_category
  from candidates c
),
ordered as (
  select r.id,
         row_number() over (
           order by r.rn_in_category, md5(r.category || r.id::text)
         ) as seq
  from ranked r
)
insert into public.daily_picks (publish_date, question_id)
select ce.start_date + (o.seq - 1)::int, o.id
from ordered o
cross join calendar_end ce
on conflict do nothing;
