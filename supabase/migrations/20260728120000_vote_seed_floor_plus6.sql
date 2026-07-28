-- ============================================================================
-- Vote seed floor: +6 phantom votes on every question (user request 2026-07-28).
--
-- WHY
--   With seed_total = 0 the first real voter still sees 100%–0%. The user wants
--   a universal baseline of 6 votes at 50/50 so a split is always plausible.
--
-- WHAT
--   * Safety prefill: any question missing a question_vote_seeds row gets the
--     (50, 0) default first (currently none are missing).
--   * Then a uniform increment: seed_total = seed_total + 6 on EVERY row.
--       - the 525 default rows (pct 50, total 0)  -> total 6  = 3 TAK / 3 NIE
--       - the 8 rows already at (50, 6)           -> total 12 = 6 / 6
--       - the 17 hand-curated rows (total 30)     -> total 36, split keeps
--         their curated pct (they never had the 100–0 problem)
--   seed_yes / seed_no are generated columns and recompute automatically.
--
-- NOT idempotent: re-running adds another 6 per row. Apply exactly once.
--
-- NOTE new questions created via admin_approve still start at (50, 0); bumping
-- that default is a separate change.
-- ============================================================================

insert into public.question_vote_seeds (question_id, seed_yes_pct, seed_total)
select q.id, 50, 0
from public.questions q
on conflict (question_id) do nothing;

update public.question_vote_seeds
   set seed_total = seed_total + 6;
