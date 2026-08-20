-- ============================================================================
-- Top up the daily calendar with the seed's leftovers.
-- ----------------------------------------------------------------------------
-- 2026-08-20, third and final batch of the day (after 20260820151000 and
-- 20260820171000).
--
-- The original seed capped at 300, leaving 23 active zero-real-vote questions
-- outside the calendar for no reason other than the cap. Owner call: maximum
-- runway — append them all. Same candidate rule and category round-robin as
-- the seed; same append-after-calendar-end, re-runnable shape.
-- ============================================================================

with calendar_end as (
  select coalesce(max(dp.publish_date) + 1, date '2026-08-21') as start_date
  from public.daily_picks dp
),
candidates as (
  select q.id, q.category,
         row_number() over (
           partition by q.category
           order by md5(q.id::text || 'daily-picks-v1')
         ) as rn_in_category
  from public.questions q
  where q.is_active
    and not exists (
      select 1 from public.question_votes v where v.question_id = q.id
    )
    and not exists (
      select 1 from public.daily_picks dp where dp.question_id = q.id
    )
),
ordered as (
  select c.id,
         row_number() over (
           order by c.rn_in_category, md5(c.category || c.id::text)
         ) as seq
  from candidates c
)
insert into public.daily_picks (publish_date, question_id)
select ce.start_date + (o.seq - 1)::int, o.id
from ordered o
cross join calendar_end ce
on conflict do nothing;
