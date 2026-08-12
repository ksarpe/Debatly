-- ============================================================================
-- Prune "obvious" (non-debatable) questions from the catalog
-- ----------------------------------------------------------------------------
-- 2026-06-27. This is a YES/NO ("TAK/NIE") DEBATE app: every question is meant
-- to split people roughly ~50/50. A content audit (a 5-way review covering all
-- 500 questions, then a manual pass over the borderline pile) found 18 that have
-- an essentially OBVIOUS answer and therefore make poor debate prompts:
--   * settled facts / debunked health myths -- e.g. "Is the occasional cigarette
--     really that harmful?", "Is breakfast really the most important meal?",
--     "Do you really need a gym to get in great shape?", "Is a daily glass of
--     wine a harmless pleasure?", "Is no pain, no gain a healthy way to train?",
--     "Should rest days matter as much as training days?", "Is a certain amount
--     of stress actually good for you?";
--   * platitudes / loaded absolutes where the opposite side is indefensible --
--     e.g. "Should you always choose the harder right over the easier wrong?",
--     "Is winning the only thing that makes sport worth playing?", "Is taking big
--     financial risks the only real path to wealth?", "Should you always give
--     money to people begging?", "Should you always cover the bill for a friend?",
--     "Should a parent always take the teacher's side?", "Is buying new always
--     worse for the planet than repairing?", "Should you accept the very first
--     salary offer without negotiating?", "Should a child be told they were
--     adopted?", "Would you rather be strong than just look strong?", "Is it worth
--     going into debt just to keep up with your friends' lifestyle?".
--
-- The genuinely 50/50 (if "leaning") dilemmas were deliberately kept -- they
-- each ship an intentional counter-angle (smaczek) and a real minority defends
-- the other side.
--
-- Deleting a question CASCADES to its translations and its smaczki (+ smaczki
-- translations), plus question_seen / question_votes / question_favorites. Only
-- daily_questions is ON DELETE RESTRICT, so we clear/rebuild the calendar here.
--
-- Safety: all 18 were FAR-FUTURE dailies (earliest 2026-12-26) with 0 votes and
-- 0 views at audit time -- no user data is lost and no near-term daily changes.
-- A full snapshot of the deleted rows lives next to this file:
--   20260627140000_prune_obvious_questions.backup.json
--
-- Keyed on EN question text => idempotent and portable: safe to re-run, and on a
-- fresh rebuild it prunes whatever the seed migrations inserted.
-- ============================================================================

begin;

-- The 18 questions to prune, identified by their English text.
create temporary table _prune_en (en text) on commit drop;
insert into _prune_en (en) values
  ('Should you always give money to people begging on the street?'),
  ('Is breakfast really the most important meal of the day?'),
  ('Do you really need a gym to get in great shape?'),
  ('Should you always choose the harder right over the easier wrong?'),
  ('Is the occasional cigarette really that harmful?'),
  ('Would you rather be strong than just look strong?'),
  ('Is taking big financial risks the only real path to wealth?'),
  ('Is it worth going into debt just to keep up with your friends'' lifestyle?'),
  ('Should you always cover the bill for a friend who can''t afford it?'),
  ('Is buying something new always worse for the planet than repairing the old?'),
  ('Should you accept the very first salary offer without negotiating?'),
  ('Is winning the only thing that makes sport worth playing?'),
  ('Should a child be told they were adopted?'),
  ('Is a certain amount of stress actually good for you?'),
  ('Is a daily glass of wine a harmless pleasure?'),
  ('Should rest days matter as much as training days?'),
  ('Is no pain, no gain a healthy way to train?'),
  ('Should a parent always take the teacher''s side over their child''s?');

create temporary table _prune_ids on commit drop as
select distinct t.question_id as id
from public.question_translations t
join _prune_en p on p.en = t.question_text
where t.locale = 'en';

-- 1) Free the calendar. Drop the entire FUTURE schedule (past the free-window
--    upper bound of today+1, which covers all timezones). Past/current dailies
--    stay untouched so already-served days and their votes are preserved.
delete from public.daily_questions
where publish_date > (now() at time zone 'utc')::date + 1;

-- 1b) Belt-and-suspenders: clear any remaining calendar slot for a pruned id
--     (e.g. if one ever sat inside the protected window), so the RESTRICT FK
--     below can never block the delete.
delete from public.daily_questions d
using _prune_ids p
where d.question_id = p.id;

-- 2) Delete the obvious questions. FK cascade removes translations + smaczki
--    (+ their translations) + seen/votes/favorites automatically.
delete from public.questions q
using _prune_ids p
where q.id = p.id;

-- 3) Rebuild the future calendar with no gaps and no repeats: assign every
--    remaining active, currently-unscheduled question to a contiguous date,
--    starting the day after the last protected daily.
with anchor as (
  select coalesce(max(publish_date), (now() at time zone 'utc')::date) as last_day
  from public.daily_questions
),
pool as (
  select q.id, (row_number() over (order by random()))::int as rn
  from public.questions q
  where q.is_active
    and not exists (
      select 1 from public.daily_questions d where d.question_id = q.id
    )
)
insert into public.daily_questions (publish_date, question_id)
select (select last_day from anchor) + pool.rn, pool.id
from pool;

commit;
