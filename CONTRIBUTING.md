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

## Pre-commit hook

The first two of those gates can run automatically on `git commit` via
[lefthook](https://lefthook.dev) (a single static binary — no Node runtime). The
shared config lives in [`lefthook.yml`](lefthook.yml): it checks `dart format` on
the staged Dart files and runs `flutter analyze`, and only does the latter when a
commit actually touches Dart, so it stays fast.

Install the binary, then wire it into this repo's `.git/hooks/` once:

```bash
brew install lefthook            # macOS / Linux
scoop install lefthook           # Windows (or: winget install evilmartians.lefthook)
# no package manager? grab a binary from the releases page linked above

lefthook install                 # run from the repo root, installs the git hook
```

It's opt-in and local — `flutter test` and the full gates still live in CI, so
skipping the hook never lets a red build merge.

**Skipping it for a WIP commit** — use any of:

```bash
git commit --no-verify ...                  # git's own bypass (-n)
LEFTHOOK=0 git commit ...                    # skip every lefthook hook
LEFTHOOK_EXCLUDE=analyze git commit ...      # skip just the analyzer
```

## Integration smoke test

`integration_test/app_smoke_test.dart` boots the real app widget tree against the
in-memory mock data (no SDK keys) and walks the core daily loop: it passes the
splash, asserts the daily question renders, casts a TAK/NIE vote, and opens
Settings. It's a fast guard that the launch path is wired together end to end.

`flutter test` only scans `test/`, so this is **not** part of the normal suite or
CI — run it on demand. It touches no platform channels, so it runs on the desktop
host (`flutter-tester`), no emulator required:

```bash
flutter test integration_test/app_smoke_test.dart -d flutter-tester
```

To exercise it on a real device or emulator instead, target that device:

```bash
flutter test integration_test/app_smoke_test.dart -d <device-id>
```

There's no emulator job in CI today. If you want this to gate merges on a real
device, add a separate workflow job that boots an Android emulator (e.g. via
`reactivecircus/android-emulator-runner`) and runs the device command above.

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
  `supabase/migrations/`. Never edit an already-applied migration.
- **Errors.** Report through the `Monitoring` facade
  (`lib/core/monitoring/monitoring.dart`), not bare `print`.

## Commits & PRs

- Conventional Commits (`feat:`, `fix:`, `refactor:`, `chore:`, `docs:`,
  `test:`, `style:`). Keep commits atomic — a mechanical reformat does not belong
  in the same commit as a behavior change.
- Branch off `master`; open a PR using the template; keep it focused.
- Update `CHANGELOG.md` under `[Unreleased]` for any user-facing change.

## Releasing

[`docs/RELEASE_CHECKLIST.md`](docs/RELEASE_CHECKLIST.md) is the single source of truth for the manual steps
(Supabase deploys, store console setup, native config, signing).
