# Catalog backups — data snapshots, not migrations

These files used to sit alongside the migrations, where they were easy to
mistake for schema changes. They are **not** migrations and nothing replays
them: each one is a JSON snapshot of the affected `questions` rows (with their
`smaczki`) taken **immediately before** the migration of the same name edited
them.

Shape — a flat array of the rows as they were *before* the edit:

```json
[
  {
    "id": "27771fe7-…",
    "nr": 7,
    "pl": "…", "en": "…",
    "smaczki": [{ "pos": 1, "pl": "…", "en": "…" }, …]
  }
]
```

## What they are for

Undoing a bad catalog edit. `20260714120000_catalog_edit_batch2.backup.json`
holds the pre-edit text for every row that
`supabase/migrations/data/20260714120000_catalog_edit_batch2.sql` touched, so a
revert is a mechanical write-back of those values — no guessing, no prod
archaeology.

## Rules

- **Never** apply anything here to prod directly. Restoring means writing a new
  timestamped migration in `supabase/migrations/data/` that sets the old values
  back.
- **Never** edit a snapshot. It is a record of a past state; changing it
  destroys the only reason it exists.
- When a future migration does a destructive catalog edit, drop its snapshot
  here under the migration's own filename, `<migration>.backup.json`.

See [../migrations/README.md](../migrations/README.md) for how migrations
actually reach prod (short version: via the Supabase MCP, never `db push`).
