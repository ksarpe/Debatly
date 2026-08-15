-- ============================================================================
-- Partial index for the SSV budget gate in reveal_ad_question.
--
-- THE READ
--   reveal_ad_question runs, on every reveal:
--
--     select count(*) from public.ad_reward_events e
--     where e.user_id = v_uid and e.verified;
--
--   i.e. it re-counts the caller's ENTIRE lifetime reward history to decide a
--   single ">= used + grace" comparison. ad_reward_events_user_id_idx already
--   keeps that off a seq scan, but the plan is index scan + one heap fetch per
--   row to re-check `verified`, so the cost grows linearly with how long the
--   user has been watching ads.
--
-- WHY THIS AND NOT AN O(1) COUNTER
--   The exact O(1) fix is a denormalised counter on profiles maintained by a
--   trigger (or by admob-ssv). That is new mutable state and a new trigger on
--   the write path of a LEGACY flow — reveal-by-ad is served only for app
--   versions older than the hard-paywall rebuild, and nothing new will ever
--   call it. Paying that risk to optimise a path with no future is the wrong
--   trade; a partial index turns the count into an index-only scan over one
--   user's verified rows and adds nothing to reason about.
--
--   This supersedes the "WHAT IS DELIBERATELY *NOT* HERE" note in
--   20260815140000, which skipped this index on the grounds that the plain
--   user_id index "covers that FK". True for the FK check, but the FK is not
--   what this read is: the `verified` predicate is exactly what makes the heap
--   fetch necessary, and it is the only filter the existing index cannot serve.
--
-- SCALE
--   8 rows across 1 user today. The cap is 3/day, so a daily ad-watcher adds
--   ~1k rows/year — slow enough that this was never urgent, big enough that it
--   should not be left to grow unbounded behind a full count(*).
-- ============================================================================

create index if not exists ad_reward_events_user_id_verified_idx
  on public.ad_reward_events (user_id)
  where verified;
