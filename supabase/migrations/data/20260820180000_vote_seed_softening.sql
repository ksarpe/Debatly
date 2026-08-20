-- ============================================================================
-- Vote seed softening — smaller baseline, no more brutal splits.
--
-- WHY
--   After 20260817120000_vote_seed_recuration every active question carried
--   seed_total ≈ 20 (19..24) and a hand-judged seed_yes_pct spanning 5..85.
--   Against 229 real votes catalog-wide (max 3 on any single question) that
--   meant two things the owner did not want:
--
--   1) The phantom baseline outweighed reality ~40:1. One real vote moved a
--      split by ~4.8%, so it took ~21 real votes before the crowd owned its
--      own bar. Seeding was meant as a cold-start bootstrap, not a permanent
--      majority.
--   2) 114 questions sat outside 30..70 and a handful outside 10..90 — a free
--      user spending their ONE daily vote could be told 95% of the world
--      disagrees with them, on a number nobody voted for. Our own question
--      style guide calls a 90/10 question a bad question; some scheduled
--      daily_picks were seeded worse than that.
--
-- WHAT THIS DOES (seeds only — no real vote is read, written or moved)
--   * seed_total := 12 for every seeded question, uniform. The magnitude was
--     never visible to clients (the UI renders percentages only), so its only
--     job is deciding how fast reality takes over: a real vote is now worth
--     ~7.7% of the tally and 12 real votes reach parity with the baseline,
--     down from ~21. Catalog phantom total 11 489 → 6 708.
--   * seed_yes_pct := tails pulled in, middle left exactly as curated:
--         dev = abs(pct - 50)
--         dev <= 20            -> unchanged          (359 questions, untouched)
--         dev >  20            -> 20 + (dev-20)*0.25 (112 questions)
--     Stored range becomes 24..74; at seed_total = 12 that renders as a hard
--     25/75 floor and ceiling. Direction and ordering of every hand-judged
--     lean are preserved — a question the owner called 80/20 still reads as
--     the strongest kind of lean there is, just no longer as a landslide.
--
--   Rendered pre-vote splits across the active catalog afterwards:
--     25% (79)  33% (78)  42% (111)  50% (4)  58% (122)  67% (44)  75% (33)
--   Coarser than before by design — 12 phantom votes can only draw twelfths,
--   and the first real vote breaks the grid anyway.
--
--   Pre-edit snapshot: supabase/backups/20260820_question_vote_seeds_pre_softening.sql
--   (559 rows, md5-verified against the live table before this ran).
--   Applied via MCP apply_migration (never db push).
--
-- NOT CHANGED HERE (open decisions, deliberately left alone):
--   * get_debate_profile / get_conformity_stats still derive "majority" from
--     seed-inclusive tallies. Softening shrinks the distortion; it does not
--     remove it.
--   * admin_approve_draft still seeds brand-new questions at (50, 0), i.e.
--     no baseline at all, so their first voter sees 100/0.
--
-- Idempotent: the guard matches only the pre-softening range (19..24); a
-- re-run finds nothing, because every row is at 12 afterwards.
-- ============================================================================

update public.question_vote_seeds s
   set seed_total   = 12,
       seed_yes_pct = (
         50 + sign(s.seed_yes_pct::numeric - 50)
            * least(
                abs(s.seed_yes_pct - 50),
                round(20 + (abs(s.seed_yes_pct - 50) - 20) * 0.25)
              )
       )::smallint
 where s.seed_total between 19 and 24;
