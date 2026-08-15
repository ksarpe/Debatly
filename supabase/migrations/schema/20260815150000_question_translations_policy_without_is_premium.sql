-- ============================================================================
-- RLS: "read question text (gated)" stops calling public.is_premium(uuid).
--
-- THE PROBLEM
--   The policy's USING clause called `public.is_premium((select auth.uid()))`.
--   A policy expression is evaluated with the INVOKER's privileges, and since
--   the 2026-07-02 least-privilege pass is_premium has EXECUTE for `postgres`
--   only. So a direct PostgREST read of question_translations as
--   anon/authenticated did not return zero rows — it raised
--   `42501: permission denied for function is_premium`.
--
--   Pre-existing and inert in practice: every client read of question text goes
--   through the SECURITY DEFINER RPCs (get_questions / get_daily_question /
--   get_smaczki), and the RPC path is untouched by this file. Fail-closed, so
--   nothing ever leaked — the table was simply unreadable rather than filtered.
--
-- WHY NOT JUST GRANT EXECUTE
--   is_premium is SECURITY DEFINER and takes the uuid as an argument, so
--   `grant execute ... to authenticated` would publish it on PostgREST as
--   /rest/v1/rpc/is_premium?uid=<any uuid> — an entitlement oracle for other
--   people's accounts. The gate is inlined instead; the predicate below is the
--   body of is_premium verbatim (including the premium_until check).
--
-- WHY THE ROLE LIST SHRINKS TO `authenticated`
--   profiles has no SELECT grant for anon, so keeping anon on this policy would
--   only trade "permission denied for function is_premium" for "permission
--   denied for table profiles". With no policy covering anon, a keyless read
--   returns zero rows — properly fail-closed. Every real client holds a session
--   (anonymous sign-in ⇒ role `authenticated`), so no app path loses anything.
--
--   The nested read of profiles also runs as the invoker, so profiles' own
--   "read own profile" policy still applies: the subquery can only ever see the
--   caller's row. No oracle, no recursion (that policy touches auth.uid() only).
--
-- WHY drop+create AND NOT `alter policy`
--   ALTER cannot change `to <roles>`. Both statements run in one transaction,
--   so there is no committed instant with the policy missing; and the failure
--   direction is fewer rows, never more.
--
-- Applied to prod 2026-08-15 via MCP as `question_translations_policy_without_is_premium`.
-- Verified live, impersonating real accounts:
--   * PRO authenticated user     → 1120 rows (was: 42501)
--   * non-PRO authenticated user →    0 rows, no error
--   * anon                        →    0 rows, no error
--   * get_questions('pl', today) as the PRO user → 560/560 rows with text
-- ============================================================================

drop policy if exists "read question text (gated)" on public.question_translations;

create policy "read question text (gated)" on public.question_translations
  for select to authenticated
  using (
    exists (
      select 1 from public.questions q
      where q.id = question_translations.question_id and q.is_active
    )
    and exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid())
        and p.is_premium
        and (p.premium_until is null or p.premium_until > now())
    )
  );
