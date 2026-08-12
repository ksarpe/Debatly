# Contributing

Thanks for working on Debatly. This guide keeps the codebase consistent and the
`master` branch always shippable.

## Getting started

```bash
flutter pub get
flutter run                       # runs against mock data, no keys needed
```

To run against the real backends, copy `env/example.json` to `env/local.json`,
fill in the keys, and run:

```bash
flutter run --dart-define-from-file=env/local.json
```

`env/*.json` (except `example.json`) is git-ignored, so real keys stay local.

## Before every commit

The CI (`.github/workflows/ci.yml`) enforces all three — run them locally first:

```bash
dart format .
flutter analyze
flutter test
```

## Conventions

- **Architecture.** Feature-first under `lib/features/<feature>/` with
  `providers/`, `screens/`, `widgets/`. Cross-cutting code lives in `lib/core/`,
  data access in `lib/data/`, and SDK wrappers in `lib/services/`.
- **State.** Riverpod only. Prefer small, focused providers; document non-obvious
  `watch` vs `read` choices (see `question_providers.dart` for the house style).
- **Strings.** Every user-facing string goes through the ARB files in
  `lib/l10n/` and is read via `context.l10n`. After editing an ARB file,
  regenerate with `flutter gen-l10n`. Never hard-code UI text.
- **Theming.** Read colors from `context.colors` (the `AppColors` theme
  extension), never hard-coded `Color(...)` in widgets.
- **Database.** Schema, RLS, and RPC changes ship as a new timestamped file in
  `supabase/migrations/schema/`; question-catalog and copy edits go in
  `supabase/migrations/data/`. Never edit an already-applied migration, and
  never run `supabase db push` — see
  [supabase/migrations/README.md](supabase/migrations/README.md).
- **Errors.** Report through the `Monitoring` facade
  (`lib/core/monitoring/monitoring.dart`), not bare `print`.

## Commits & PRs

- Conventional Commits (`feat:`, `fix:`, `refactor:`, `chore:`, `docs:`,
  `test:`, `style:`). Keep commits atomic — a mechanical reformat does not belong
  in the same commit as a behavior change.
- Branch off `master`; open a PR using the template; keep it focused.

## Releasing

The one-time store bring-up is done. [KEYS_AND_SERVICES_MAP.md](KEYS_AND_SERVICES_MAP.md)
maps the consoles, keys and connections between services; the retired
step-by-step checklists (`RELEASE_CHECKLIST.md`, `IOS_RELEASE_CHECKLIST.md`)
live in git history.
