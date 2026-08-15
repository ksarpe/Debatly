-- ============================================================================
-- Move ad-hoc backup tables out of `public` into a private `archive` schema.
--
-- WHAT THEY ARE
--   Pre-edit row snapshots taken in-database (rather than as a
--   supabase/backups/*.json file) before three catalog edits:
--     * question_smaczki_backup_20260730            3 166 rows, 376 kB
--     * question_smaczki_backup_20260803            3 306 rows, 448 kB
--     * catalog_review_20260804_deleted_backup         32 kB
--         (referenced by migrations/data/20260804120000_review_fix_high_and_dups.sql)
--
-- WHY MOVE RATHER THAN DROP
--   They are not a security hole — RLS is on, no policies exist, and neither
--   anon nor authenticated has SELECT — but they sit in `public`, so the
--   advisor reports each of them under 0008_rls_enabled_no_policy forever, and
--   real findings get read past a wall of known noise. Dropping would silence
--   it too, but these are the ONLY copy of the pre-edit smaczki text (there is
--   no matching .json under supabase/backups/), and 856 kB is not a reason to
--   destroy a rollback source. `archive` is not in the project's exposed
--   schema list, so nothing reaches it over PostgREST; the lint scans `public`
--   and stops reporting.
--
-- CONSEQUENCE
--   Query them as `archive.question_smaczki_backup_20260730` from now on;
--   unqualified names will not resolve (archive is not on the default
--   search_path, deliberately).
-- ============================================================================

create schema if not exists archive;

comment on schema archive is
  'Pre-edit row snapshots for data/ migrations. Not exposed via PostgREST, not '
  'on any search_path, no grants. Data, not schema — nothing in the app reads it.';

-- No grants at all: only the table owner (postgres) and superusers get in.
revoke all on schema archive from public;

alter table if exists public.question_smaczki_backup_20260730
  set schema archive;

alter table if exists public.question_smaczki_backup_20260803
  set schema archive;

alter table if exists public.catalog_review_20260804_deleted_backup
  set schema archive;
