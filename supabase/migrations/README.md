# Migrations — read before touching prod

**These files are reference copies, not a replayable history.** Migrations are
applied to prod via the Supabase MCP (`apply_migration`), which stamps its own
timestamp — so the remote `supabase_migrations.schema_migrations` versions do
NOT match these filenames. The remote history table is the ground truth:

```sql
select version, name from supabase_migrations.schema_migrations order by version;
```

## Two folders: `schema/` and `data/`

Split on **2026-08-12** so the 41 files that define the database aren't buried
under the 30 one-shot content edits (which are 3× their size):

| | what's in it | when you want it |
|---|---|---|
| [`schema/`](schema/) | 41 files, 258 KB — tables, RPCs, views, RLS policies, grants, indexes | "where is `reveal_free_question` defined?" |
| [`data/`](data/) | 30 files, 788 KB — question seeds, catalog edits, copy-editing passes, rank-ladder reseeds | "when did question nr 7 change wording?" |

The rule: **any file containing DDL is `schema/`**, even if it also seeds rows
(e.g. `vote_seed_baseline.sql` creates a table *and* prefills it). `data/` is
pure `insert` / `update` / `delete` against the catalog. Filenames did not
change, so `<migration>.sql` in `data/` still pairs with
`<migration>.backup.json` in [`../backups/`](../backups/).

For the current shape of the database, read [`../schema.sql`](../schema.sql)
first — it is 8 KB and current. Reach for `schema/` only when you need the
history of *how* something got that way.

## Where the `.backup.json` files went

Several migrations here have a header comment pointing at a "sibling" or
"next to this file" `.backup.json`. Those 15 row snapshots moved to
[`../backups/`](../backups/) on **2026-08-12** — same filenames, so
`<migration>.sql` still pairs with `<migration>.backup.json`, just one folder
over. The comments inside the SQL were deliberately left stale rather than
edited, because these files are reference copies of what actually ran on prod.

## Do NOT `supabase db push`

A fresh `supabase link` + `db push` would try to re-apply every file here (the
remote history doesn't know these versions) and fail or duplicate seeds. Apply
new changes the same way as before (MCP / SQL editor) and drop a copy of the
SQL in `schema/` or `data/` for reference.

Since the split, the CLI no longer sees any of these files — it only scans
`supabase/migrations/*.sql`, not subfolders. That is a happy side effect, not
the reason for the split: an accidental `db push` is now a no-op instead of a
catastrophe. Do not "fix" it by flattening the folders back.

## Known gaps between this folder and prod (as of 2026-07-09)

- `20260709160000_spicy_third_smaczek.sql` (adds a PRO-gated third "pod włos"
  smaczek to 992 questions + backfills position 2 for 3 questions) was applied
  to prod NOT as a single remote migration but as **4 chunked `execute_sql`
  batches** (the full VALUES list was too large for one MCP call). The reference
  file here is the complete, idempotent version — treat it as the source of
  truth. Every INSERT is guarded by `ON CONFLICT (question_id, position) DO
  NOTHING`, so re-running is a no-op. Verified live: positions 1/2/3 = 1000 each,
  0 questions with <3 active smaczki, 0 smaczki missing a pl/en translation.


- `20260709120000_polish_copy_editing_pass.sql` (PL copy-editing pass, 61
  guarded UPDATEs) was applied via MCP as remote version `20260709120114`. The
  SQL sent to MCP had a hand-paste typo in the LAST statement's guard
  (`…nie ma czego ukrycia?` instead of the real prior text `…nie ma czego
  ukrywać?`), so that one row was a no-op remotely; it was then fixed by a
  standalone `execute_sql`. The reference file in this folder has the CORRECT
  guard and is fully idempotent — treat it, not the recorded remote statements,
  as the accurate copy. All 61 edits verified live on prod.


- `seed_global_dilemmas_batch_2` (98 questions, remote version 20260627071251)
  and `seed_global_dilemmas_batch_3` (276 questions, remote version
  20260627093317) were applied to prod under names that do not match any
  filename here. The files themselves were missing from this folder until
  **2026-08-12**, when they were restored byte-for-byte from commit `a3a04a0`;
  they are now tracked on `master` like every other reference copy. Their full
  SQL is also recoverable from prod:

  ```sql
  select name, array_to_string(statements, E'\n')
  from supabase_migrations.schema_migrations
  where name like 'seed_global_dilemmas_batch_%';
  ```

- `public.admin_approve_draft` was, between roughly **2026-07-31 and
  2026-08-13**, a hand-pasted no-op stub on prod — `begin return
  jsonb_build_object('disabled', true); end;` — installed straight through the
  SQL editor with no migration behind it. Nothing in this folder recorded it,
  so the repo looked correct while every "Zatwierdź" click in `/admin`
  published nothing and left the draft in *Oczekujące*. It was an emergency
  killswitch after a request flood (see below) and nobody undid it. Restored,
  with a delete-path fix, by
  `20260813150000_admin_approve_draft_restore.sql` (remote:
  `admin_approve_draft_restore`). **The lesson is the drift, not the bug:** a
  `create or replace function` typed into the SQL editor leaves no trace
  anywhere except `pg_proc`. When prod behaviour contradicts the repo, diff
  `pg_get_functiondef()` against the newest file here before believing either.
- The flood that motivated that killswitch is still visible in
  `pg_stat_database`: **118.2M rolled-back transactions, 98% of every
  transaction on this project** since the 2026-06-17 counter reset. In
  `pg_stat_statements` they appear only as PostgREST's per-request
  `set_config(...)` preamble — 1957s of exec time across all 118M, and no
  application statement behind them. So it was request *volume* from a
  client-side retry storm, not slow SQL and not lock contention: every table
  hanging off `questions` is a few hundred rows. The counter has been frozen
  since at least 2026-08-13, i.e. the storm is over, but its trigger was never
  identified. If it returns, the signature to look for is a climbing
  `xact_rollback` with a flat `xact_commit`.
- `20260618120000_init.sql` predates migration tracking on the remote — it is
  applied (the schema exists) but absent from the remote history table.
- `20260622140000_entitlement_sources.sql` sat unapplied on prod until
  **2026-07-02** (while the deployed `sync-entitlement` function already
  depended on its `apply_store_entitlement`). Applied 2026-07-02.
- `20260625120000_fix_reveal_ad_question_ambiguous_id.sql` has no remote
  history entry; its effect is superseded by
  `20260701120000_open_premium_questions_to_unlock_pool.sql`, which recreated
  the RPC.
- The batch 2-3 files carry local timestamps (`20260627120000` /
  `20260627130000`) that are unrelated to the remote versions above — like every
  file in this folder, the name is a label, not a version.
- `20260713150000_vote_farming_monitoring.sql` (admin-only views
  `admin_vote_farming_suspects` + `admin_question_vote_velocity` for spotting
  vote-farming bot accounts) — applied to prod 2026-07-13 via MCP. Idempotent
  (create-or-replace), safe to re-run. Smoke test
  `select * from admin_vote_farming_suspects limit 20;` returned only
  no-app-events test accounts, as expected on a clean base.
- `20260713120000_personal_daily_question.sql` (personal per-user daily +
  streak on any vote; retires the shared calendar daily) applied to prod
  2026-07-13 via MCP as `personal_daily_question` — file and remote content
  match 1:1. `daily_questions` is legacy from this point: read-only fallback,
  nothing writes it.
- `20260713170000_paywall_funnel_analytics.sql` (read-side `paywall_funnel`
  view over `app_events`; the client logs `paywall_*` events since app version
  1.0.3+) — **NOT yet applied to prod**. Idempotent (`create or replace view`),
  no schema change; apply via MCP / SQL editor whenever.
- `20260812120000_grant_service_role_subscriptions_select.sql` — **applied to
  prod 2026-08-12** via Management API `execute_sql` as remote version
  `20260812085758`. Fixes the recurring 42501 "permission denied for table
  subscriptions" from the RevenueCat webhook's PostgREST upsert (ON CONFLICT DO
  UPDATE needs SELECT on top of the INSERT+UPDATE granted on 2026-07-05).
  Verified live: the exact webhook upsert re-run as `service_role` succeeds.
- `20260812130000_reseed_rank_ladder_v3.sql` (16-tier renamed rank ladder,
  first promotion at streak 1, max gap 30 days) — **applied to prod
  2026-08-12** via MCP as `reseed_rank_ladder_v3`. Verified live: 16 rows,
  thresholds 0/1/3/5/7/10/14/18/23/30/40/50/65/80/100/130. Every new
  threshold <= its old counterpart, so no user demoted. NOT idempotent in
  isolation (DELETE + re-INSERT), but safe to re-run as a whole.
- `20260713160000_vote_seed_baseline.sql` (hand-curated phantom-vote baseline:
  client-invisible `question_vote_seeds` table prefilled 50/0 for every
  question + all four tally RPCs add the seeds) — **applied to prod 2026-07-13**
  via MCP as remote version `vote_seed_baseline`. Verified live: 1000 seed rows
  (one per question), 0 active seeds (`seed_total<>0`), 0 orphans, all four RPCs
  (`cast_daily_vote`, `get_daily_vote_state`, `get_vote_history`,
  `get_daily_history`) reference `question_vote_seeds`, RLS on with zero client
  grants. Idempotent (guarded DDL + `on conflict do nothing` prefill), so
  re-running is a no-op. With every `seed_total = 0` there is zero behaviour
  change until the values are curated by hand. The seed values themselves are
  curated manually (Excel round-trip; export query in the file header) and are
  NOT tracked as migrations.
- `20260815130000_rls_auth_uid_initplan.sql` (wraps `auth.uid()` in a scalar
  subselect in the 8 RLS policies the advisor flagged with
  `0003_auth_rls_initplan`) — **applied to prod 2026-08-15** via MCP as
  `rls_auth_uid_initplan`. `alter policy` only, so names / commands / roles are
  untouched and there is no instant with a policy missing. Verified live: the
  advisor's 8 `auth_rls_initplan` WARNs are gone, and a session impersonating a
  real user still sees exactly its own rows (40 votes, 0 belonging to anyone
  else, 1 profile). Idempotent.
  Found on the way, fixed separately in
  `20260815150000_question_translations_policy_without_is_premium.sql` (below):
  the `read question text (gated)` policy on `question_translations` called
  `public.is_premium(...)`, whose EXECUTE is postgres-only since the 2026-07-02
  least-privilege pass, so a direct PostgREST read of that table by
  `anon`/`authenticated` raised 42501 instead of returning zero rows.
- `20260818120000_vote_history_free_today.sql` (free callers of
  `get_vote_history` now get their last 48 hours of votes instead of zero rows
  — the redesigned history screen shows a free user "today" with older history
  behind the locked PRO panel; premium output unchanged) — **applied to prod
  2026-08-18** via MCP as `vote_history_free_today`. Verified live by
  impersonation: a free user with 2 votes (1 recent) got 1 row, a premium user
  with 11 votes got their full record (10 rows — 1 vote sits on an inactive
  question, same as before). Idempotent (`create or replace`).
- `20260815150000_question_translations_policy_without_is_premium.sql` (inlines
  the premium check into the `read question text (gated)` policy and narrows it
  to `authenticated`) — **applied to prod 2026-08-15** via MCP as
  `question_translations_policy_without_is_premium`. The 42501 above was
  pre-existing and inert (all question text is read through the SECURITY
  DEFINER RPCs) and fail-closed, so nothing leaked; the fix is *not* a grant,
  because `grant execute on is_premium to authenticated` would publish
  `/rest/v1/rpc/is_premium?uid=<any uuid>` as an entitlement oracle for other
  people's accounts. The inlined predicate is the body of `is_premium`
  verbatim, `premium_until` included, and reads `profiles` as the invoker, so
  profiles' own "read own profile" policy keeps the subquery to the caller's
  row. `anon` is dropped from the policy on purpose: it has no SELECT grant on
  `profiles`, so keeping it would only swap one 42501 for another, and with no
  policy covering it a keyless read now returns zero rows. Verified live
  against real accounts: PRO user 1120 rows (was 42501), non-PRO 0 rows, anon
  0 rows, both without error; `get_questions('pl', today)` as the PRO user
  still returns 560/560 rows with text. Idempotent (`drop policy if exists` +
  `create policy`).
- `20260819120000_smaczek_side.sql` (`question_smaczki.side` —
  `attacks_yes` / `attacks_no` / `neutral`, NULL = not tagged yet;
  `get_question_smaczki` returns it and orders the rows by relevance to the
  CALLER'S OWN vote, with the free row moving from "position 1" to "the
  top-ranked one"; `question_snapshot` + `_admin_write_smaczki` carry the tag
  through the admin draft flow; `admin_list_questions` gains
  `smaczki_untagged` + `p_only_untagged`) — **applied to prod 2026-08-19** via
  MCP as `smaczek_side`. Two functions change result shape
  (`get_question_smaczki`, `admin_list_questions`), so both are dropped and
  recreated with their grants re-asserted. The snapshot gaining a key changes
  `question_content_hash` for every question, which would have made all 38 open
  drafts fail `admin_approve_draft`'s conflict guard on an edit nobody made —
  the same statement re-bases their `base_hash`, content untouched. Verified
  live: both signatures show the new columns, and the ranking expression
  returns position order for a caller with no vote (today's behaviour), the
  `attacks_no` row first for a NIE voter, `attacks_yes` first for a TAK voter.
  All 1676 live smaczki start untagged, i.e. served exactly as before until the
  catalog is tagged. Idempotent.
