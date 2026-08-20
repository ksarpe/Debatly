-- ============================================================================
-- Seed the global daily calendar (daily_picks) — ~300 fresh questions.
-- ----------------------------------------------------------------------------
-- 2026-08-20, companion to schema/20260820150000_global_daily_picks.sql.
--
-- WHAT
--   Pin one question per date from 2026-08-21 onward, drawn from the active
--   catalog questions NOBODY has really voted on yet (seed baselines don't
--   count — they are synthetic). At apply time that pool was 324 strong; the
--   seed takes 300 and leaves the rest in the regular catalog. The owner
--   appends future dates by hand as new questions land.
--
-- HOW THE ORDER IS BUILT
--   Round-robin across categories (each category's 1st question before any
--   category's 2nd), deterministic pseudo-random within a category via
--   md5(id). That interleaves the big categories (Family 53, Relationships
--   47) with the small ones instead of front-loading a month of one topic.
--
-- SAFE TO RE-RUN
--   Candidates exclude questions already in daily_picks, and the insert is
--   on conflict do nothing on both constraints (date PK, question UNIQUE).
--   A re-run only APPENDS days after the current calendar end.
-- ============================================================================

with calendar_end as (
  -- Append after whatever is already pinned; first run starts at 2026-08-21.
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
  -- Category round-robin: every category's rank-1 question (in hashed order)
  -- before any category's rank-2, and so on.
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
where o.seq <= 300
on conflict do nothing;
