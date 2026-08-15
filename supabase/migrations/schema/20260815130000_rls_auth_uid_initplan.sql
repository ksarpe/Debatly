-- ============================================================================
-- RLS: wrap auth.uid() in a scalar subselect so it is an InitPlan, not a
-- per-row call. Advisor lint 0003_auth_rls_initplan.
--
-- THE PROBLEM
--   `using (user_id = auth.uid())` puts a function call in the row filter, and
--   the planner has no licence to hoist it: auth.uid() is STABLE, not
--   IMMUTABLE, so it is legal to call once per row and Postgres does exactly
--   that. Scanning N rows costs N calls to a function that reads
--   current_setting('request.jwt.claims'), parses the JSON and casts a uuid.
--   The value is identical for every row of the statement.
--
--   `(select auth.uid())` is an uncorrelated subquery, so the planner turns it
--   into an InitPlan: evaluated ONCE per statement, the result reused as a
--   constant. Same semantics, same rows in and out, O(1) instead of O(rows).
--   As a bonus the constant can then be pushed into an index condition rather
--   than sitting in a per-row filter.
--
-- WHAT IS **NOT** CHANGED
--   Every policy keeps its name, command, roles and truth table. `auth.uid()`
--   is stable within a statement, so `x = auth.uid()` and
--   `x = (select auth.uid())` select the same rows — including the null case
--   (anon session → null → no match / NULL predicate → denied), which is
--   unchanged in both directions.
--
-- WHY `alter policy` AND NOT drop+create
--   ALTER is one atomic catalog update per policy: there is no instant, not
--   even inside a transaction, where the table sits with one policy fewer.
--   It also cannot silently widen `to <roles>` or the command by a typo in the
--   recreated statement — those parts are simply not restated here.
--
-- user_daily_questions ("read own personal daily") already had the subselect
-- form from 20260713120000 and is therefore absent below.
--
-- Re-running this file is a no-op: assigning an expression a policy already
-- has changes nothing.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) The six plain "own row" policies. Mechanical: auth.uid() → (select auth.uid()).
-- ----------------------------------------------------------------------------
alter policy "read own profile" on public.profiles
  using (id = (select auth.uid()));

alter policy "read own subscription" on public.subscriptions
  using (user_id = (select auth.uid()));

alter policy "read own ad rewards" on public.ad_reward_events
  using (user_id = (select auth.uid()));

alter policy "read own votes" on public.question_votes
  using (user_id = (select auth.uid()));

alter policy "read own seen" on public.question_seen
  using (user_id = (select auth.uid()));

alter policy "read own favorites" on public.question_favorites
  using (user_id = (select auth.uid()));

-- ----------------------------------------------------------------------------
-- 2) app_events — INSERT policy, so the expression lives in WITH CHECK.
--    Pre-auth onboarding events still carry a null user_id and still pass.
-- ----------------------------------------------------------------------------
alter policy "clients append their own events" on public.app_events
  with check (user_id is null or user_id = (select auth.uid()));

-- ----------------------------------------------------------------------------
-- 3) question_translations — the expensive one. The premium gate called
--    is_premium(auth.uid()) per row: a SECURITY DEFINER function doing a
--    subscriptions lookup, once per translation row considered. Wrapping the
--    WHOLE call (not just its argument) makes the entitlement check an InitPlan
--    too — one lookup per statement.
--
--    The `exists` half stays per-row on purpose: it is correlated to
--    question_translations.question_id and must be.
--
--    In practice the hot read paths (get_questions & co.) are SECURITY DEFINER
--    and bypass RLS entirely, so this policy only bites on direct PostgREST
--    reads of the table — but that is exactly the path an unpaid client would
--    take to probe question text, and it is now cheap to deny.
-- ----------------------------------------------------------------------------
alter policy "read question text (gated)" on public.question_translations
  using (
    exists (
      select 1
      from public.questions q
      where q.id = question_translations.question_id
        and q.is_active
    )
    and (select public.is_premium((select auth.uid())))
  );
