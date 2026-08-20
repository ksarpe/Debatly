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

The CI (`.github/workflows/ci.yml`) enforces all three and treats **every
analyzer hint as fatal** — a plain `flutter analyze` is weaker than CI. Run the
same commands locally first:

```bash
dart format .
```

```bash
flutter analyze --fatal-infos --fatal-warnings
```

```bash
flutter test
```

Flutter is pinned to **3.44.1** (`.metadata`); CI uses the same version.

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
in-memory mock data (no SDK keys), as a returning FREE account, and walks the
paths a human otherwise re-clicks on a phone after every release:

- the daily loop — splash → daily → vote → contra gate → split → Settings;
- the smaczki sheet's vote gate — before the vote the pill answers with the
  "Najpierw zagłosuj" hook, after it the sheet opens;
- the day wall — a forward swipe lands on it, the back swipe and the system back
  gesture both leave it;
- the wall's paywall rules — never automatically before the daily vote,
  automatically on the first wall hit after it, and only once that local day;
- sign-out — the settings hub falls back to its guest shape.

The manual counterparts (with ids the test's header maps to) live in
[TESTY_MANUALNE.md](TESTY_MANUALNE.md). It's a fast guard that the launch path
and the freemium rules are wired together end to end.

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
  `supabase/migrations/schema/`; question-catalog and copy edits go in
  `supabase/migrations/data/`. Never edit an already-applied migration, and
  never run `supabase db push` — see
  [supabase/migrations/README.md](supabase/migrations/README.md).
  `supabase/schema.sql` is the original bootstrap, **not** the current shape:
  everything from `question_seen` and `user_daily_questions` to the reveal /
  vote / stats RPCs lives only in `migrations/schema/`. Check the live project
  or the newest migration touching that object before assuming a shape.
- **Product rules.** Before changing the feed, reveals or entitlements, read
  [README.md](README.md) § *How the product actually works* — in particular that
  the daily question is a free entry point, not a one-question-a-day cap, and
  that the daily rolls over on the *local* date while credits and the ad cap
  roll over at *UTC* midnight.
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
