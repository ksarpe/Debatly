-- ============================================================================
-- Covering indexes for every unindexed foreign key in `public`.
-- Advisor lint 0001_unindexed_foreign_keys (8 hits before this file, 0 after).
--
-- THE PROBLEM
--   A foreign key is enforced in BOTH directions. The child side is cheap (the
--   parent's PK is looked up on insert), but every DELETE or key-UPDATE on the
--   PARENT has to prove no child row still references the row being removed.
--   With no index leading on the FK column that proof is a sequential scan of
--   the whole child table, taken under a lock, once per parent row touched.
--
--   Concretely: deactivating or deleting one question would seq-scan
--   question_seen — the table that gets one row per (user, question shown) and
--   is the fastest-growing thing in this schema. It is 226 rows today, so
--   nothing is on fire; it is millions of rows at any real user count, and by
--   then the fix is a lock-taking DDL on a hot table instead of this no-op.
--
-- WHY question_id AND NOT (user_id, question_id)
--   The FK check filters on question_id ALONE. A composite index only serves
--   it if question_id is the LEADING column, so `(user_id, question_id)` —
--   the shape the composite PKs already have — is useless here. Hence the
--   single-column indexes below; they are additionally the right shape for the
--   admin panel's "who has seen / favourited this question" reads.
--
-- WHAT IS DELIBERATELY *NOT* HERE
--   * user_daily_questions (user_id, question_id): proposed for the
--     `not exists` anti-join in peek_next_question / reveal_free_question /
--     reveal_ad_question. Not needed — those subqueries also carry
--     `assigned_on between p_date - 1 and p_date + 1`, which the existing PK
--     (user_id, assigned_on) already satisfies as a range scan bounded to at
--     most three rows per candidate question. The index this table actually
--     lacks is the FK one, on question_id, which is below.
--   * ad_reward_events (user_id) where verified: ad_reward_events_user_id_idx
--     already exists and covers that FK. The partial variant would only trim
--     an already-indexed count(*) over one user's lifetime rewards, on a
--     legacy path (reveal-by-ad is served for old app versions only) and a
--     64 kB table. Not worth the write cost.
--
-- All five tables are under 104 kB, so plain CREATE INDEX is instant and there
-- is no case for CONCURRENTLY (which cannot run inside a migration's
-- transaction anyway). IF NOT EXISTS makes re-running this file a no-op.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Product tables — these are the ones that grow with users.
-- ----------------------------------------------------------------------------

-- One row per (user, question shown). Grows fastest of anything here.
create index if not exists question_seen_question_id_idx
  on public.question_seen (question_id);

-- One row per user per local day.
create index if not exists user_daily_questions_question_id_idx
  on public.user_daily_questions (question_id);

create index if not exists question_favorites_question_id_idx
  on public.question_favorites (question_id);

-- RevenueCat webhook append log; also the shape the admin panel reads it by.
create index if not exists billing_events_user_id_idx
  on public.billing_events (user_id);

-- ----------------------------------------------------------------------------
-- 2) Admin-panel tables. Tiny and staff-only, so this is lint hygiene rather
--    than a measurable win — but the indexes cost nothing at these sizes and
--    leaving them out means the advisor never reads clean.
-- ----------------------------------------------------------------------------

create index if not exists admin_question_favorites_question_id_idx
  on public.admin_question_favorites (question_id);

create index if not exists admin_users_created_by_idx
  on public.admin_users (created_by);

create index if not exists question_drafts_created_by_idx
  on public.question_drafts (created_by);

create index if not exists question_drafts_reviewed_by_idx
  on public.question_drafts (reviewed_by);
