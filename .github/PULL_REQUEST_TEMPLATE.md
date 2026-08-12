<!-- Keep PRs small and focused. A reviewer should grasp the "why" in 30 seconds. -->

## What & why

<!-- One or two sentences: what does this change and what problem does it solve? -->

## Changes

-

## Screenshots / recordings

<!-- For any UI change, attach before/after. Delete this section otherwise. -->

## Checklist

- [ ] `dart format .` applied
- [ ] `flutter analyze` is clean
- [ ] `flutter test` passes
- [ ] User-facing strings go through the ARB files (`lib/l10n/`), not hard-coded
- [ ] DB / RLS / RPC changes ship as a new `supabase/migrations/schema/` file
      (catalog / content edits go in `supabase/migrations/data/`)
- [ ] `KEYS_AND_SERVICES_MAP.md` updated if this adds/changes a key, console setting or service connection
