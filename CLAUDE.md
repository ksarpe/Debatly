# Debatly — agent brief

Flutter app (Dart) + Supabase backend. TAK/NIE questions with a community split.
Riverpod state, RevenueCat subscriptions, AdMob rewarded ads, Sentry monitoring.
Package / app id: `debatly` / `com.aknsoftware.debatly` (the GitHub repo is still
named `questionapp` — same project).

## Product model — get this right before touching the feed

**Debatly is NOT a "one question per day" app.** The daily question is only the
free entry point of a feed that keeps going. Getting this wrong is the single
most common bad assumption about this codebase.

- **Personal daily question** — position 0 of the deck. Drawn server-side per
  user from questions *that user has not voted on yet*, stored in
  `user_daily_questions`, stable for that **local** date. Free for everyone,
  guests included. It is *personal*, not the same for everybody.
- **Past it, free users reveal more questions one at a time:** 1 free credit per
  **UTC** day (real accounts only — `is_real_account`, guests get none) plus up
  to **3 rewarded-ad reveals** per UTC day (`ad_reveal_daily_cap()`). So a free
  user reads up to 4 (guest) / 5 (with an account) questions a day, not 1.
- **PRO** walks the entire catalog, wrapping; all smaczki, favorites, vote
  history, offline download. Free gets smaczek #1 only, and the star is a
  paywall hook rather than a write.
- **Two clocks on purpose:** the daily rolls over at the user's *local*
  midnight; credits and the ad cap roll over at *UTC* midnight. Don't "fix" one
  to match the other.
- Revealed text lives in session memory (`revealedFeedProvider`) — gone on
  restart, and RLS won't serve it again.
- Voting is allowed on any question the user has seen; the split shown is the
  **all-time** tally, not "today's result". The streak advances on any vote, at
  most once per UTC day, and decays one rank per 3 missed days.
- `daily_questions` (global calendar) is **legacy** — no longer written to.
  `question_seen` is the old `question_unlocks`.

Full narrative: [README.md](README.md) § *How the product actually works*.

## Quality gates — run before claiming done

CI (`.github/workflows/ci.yml`) runs these exact commands and treats every
analyzer hint as fatal. Run all three locally; a plain `flutter analyze` is
*weaker* than CI:

```bash
dart format .
flutter analyze --fatal-infos --fatal-warnings
flutter test
```

Flutter is pinned to **3.44.1** (`.metadata`) — CI matches it.

## Hard rules (breaking these breaks prod or CI)

- **Never `supabase db push`.** Migrations are applied via the Supabase MCP
  (`apply_migration`) / SQL editor, which stamps its own timestamps. Files under
  `supabase/migrations/` are *reference copies*, not a replayable history — the
  remote `supabase_migrations.schema_migrations` table is the ground truth.
  Read [supabase/migrations/README.md](supabase/migrations/README.md) before
  touching anything database-side.
- **`supabase/schema.sql` is the bootstrap, NOT the current shape.** It only
  creates the original base tables (profiles, subscriptions, questions,
  question_translations, billing/ad events, the legacy `daily_questions`).
  Everything the app actually runs on — `question_seen`, `user_daily_questions`,
  `question_smaczki`, `ranks`, `question_favorites`, and every reveal / vote /
  stats RPC — exists only in `migrations/schema/`. To answer "what does the DB
  look like now", query the live project (Supabase MCP `list_tables` /
  `execute_sql`) or grep `migrations/schema/` for the newest definition of the
  object; reading `schema.sql` alone will give a wrong answer.
- **Never edit an already-applied migration.** New timestamped file instead:
  `migrations/schema/` if it contains any DDL, `migrations/data/` if it is a
  pure catalog/content edit.
- **No hard-coded UI text.** Every user-facing string lives in `lib/l10n/app_en.arb`
  + `app_pl.arb` and is read via `context.l10n`. After editing an ARB, run
  `flutter gen-l10n` — `lib/l10n/gen/` is generated, never hand-edit it.
- **No hard-coded `Color(...)` in widgets.** Read from `context.colors` (the
  `AppColors` theme extension in `lib/core/theme/`).
- **No bare `print`.** Report through the `Monitoring` facade
  (`lib/core/monitoring/monitoring.dart`).
- **No secrets in the repo.** Keys come from `--dart-define` / `env/*.json`;
  everything under `env/` except `example.json` is git-ignored.

## Layout

```
lib/
  main.dart / app.dart   Entry point, MaterialApp root
  core/                  Cross-cutting, no feature knowledge
                         config · feedback · locale · monitoring · network
                         share · theme · widgets · graphics · layout
  data/                  models · mock (used when Supabase keys absent)
                         repositories (QuestionRepository + caching decorator)
  features/<name>/       providers/ · screens/ · widgets/
                         account · monetization · onboarding · questions · settings
  l10n/                  ARB sources + gen/ (generated)
  services/              SDK wrappers: Supabase, RevenueCat, AdMob, consent,
                         notifications + reminder loop, reviews, analytics,
                         install referrer, caching
supabase/
  schema.sql             Bootstrap only — the ORIGINAL base tables, not today's
                         shape (see the hard rule above)
  migrations/schema/     42 files: tables, RPCs, views, RLS, grants (has DDL).
                         The real schema; newest file wins per object
  migrations/data/       30 files: question seeds + catalog edits (no DDL, 3× bigger)
  functions/             Edge functions (Deno/TS): revenuecat-webhook,
                         sync-entitlement, admob-ssv, send-auth-email,
                         delete-account
  backups/               Pre-edit row snapshots for data/ migrations — data, not code
admin/                   Next.js admin panel (own package.json, own node_modules)
tool/                    Python helper scripts (splash gen, regional pricing)
test/                    47 widget/unit test files — all green on master
```

## Running

Runs against mock data with no keys — every SDK no-ops when its credentials are
missing:

```bash
flutter pub get
flutter run
```

With real backends: copy `env/example.json` → `env/local.json`, then
`flutter run --dart-define-from-file=env/local.json`.

## Where to look before asking

| Question | File |
|---|---|
| Consoles, keys, product ids, service wiring | [KEYS_AND_SERVICES_MAP.md](KEYS_AND_SERVICES_MAP.md) |
| Conventions, commit style, PR flow | [CONTRIBUTING.md](CONTRIBUTING.md) |
| Architecture narrative, monetization/reveal flow | [README.md](README.md) |
| Migration drift, what is/isn't applied to prod | [supabase/migrations/README.md](supabase/migrations/README.md) |
| Sentry DSN, symbol upload, quota | [SENTRY_SETUP.md](SENTRY_SETUP.md) |

## Environment notes

- Primary dev machine is **Windows**; the default shell is PowerShell 5.1
  (no `&&`, no ternary, `2>$null` not `2>/dev/null`). A Bash tool is available
  for POSIX scripts.
- `build/`, `.dart_tool/`, `android/.gradle/`, `admin/node_modules/` are large
  and git-ignored — never grep or glob into them.
- Commits: Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`,
  `test:`, `style:`). Branch off `master`; keep mechanical reformats out of
  behaviour commits.
