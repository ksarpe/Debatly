-- ============================================================================
-- Follow-up to 20260815160000: turn RLS OFF on the archived backup tables.
--
-- WHY A SECOND FILE
--   20260815160000 assumed 0008_rls_enabled_no_policy only scans `public`, so
--   moving the three tables into `archive` would silence it. It does not — the
--   advisor scans every schema and simply re-reported them as
--   `archive.question_smaczki_backup_20260730` etc. The move was still the
--   right half of the fix (it takes them off PostgREST and out of the app's
--   namespace); this is the other half.
--
-- WHY OFF IS CORRECT HERE, NOT A REGRESSION
--   The lint fires on "RLS enabled + zero policies", which is a warning about
--   a table nobody can read — a shape that is a bug in `public` (someone meant
--   to write a policy) and the intended state in `archive`. Access is already
--   denied structurally: the schema has no grants, so PUBLIC/anon/authenticated
--   cannot reach these tables regardless of RLS, and the only roles that can
--   are the owner and superusers — who bypass RLS anyway. Enabled-with-no-
--   policies was therefore never doing any work; it was only generating noise.
--
--   Nothing in `archive` is exposed, so 0009_rls_disabled_in_public does not
--   apply and does not take its place.
-- ============================================================================

alter table archive.question_smaczki_backup_20260730     disable row level security;
alter table archive.question_smaczki_backup_20260803     disable row level security;
alter table archive.catalog_review_20260804_deleted_backup disable row level security;
