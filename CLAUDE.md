# Debatly — agent brief

Flutter app (Dart) + Supabase backend. TAK/NIE questions with a community split.
Riverpod state, RevenueCat subscriptions (freemium: 1 free daily question),
Sentry monitoring.
Package / app id: `debatly` / `com.aknsoftware.debatly` (the GitHub repo is still
named `questionapp` — same project).

## Product model — get this right before touching the feed

**Debatly is a FREEMIUM app (since the 2026-08 freemium rework): one free
question a day, PRO for the whole catalog.** Every session — free or PRO —
lands on the feed (`HomeGate` → `QuestionScreen`). There is no hard paywall
screen anymore; the paywall is the dismissible fullscreen `ProPaywallScreen`,
and the free tier's `DayWallView` (the "day wall") is the main conversion
surface.

| | Free | PRO |
|---|---|---|
| Daily question (1/day, local-midnight rollover) | ✅ | ✅ |
| Community split, streak & ranks, share card, smaczek #1 | ✅ | ✅ |
| Rest of the catalog (500+), all smaczki, history, favorites, offline | ❌ | ✅ |

- **The free rows are the growth engine — don't paywall them.** Community
  split, streak and the share card must stay free; without them a free user
  has no reason to return and nothing to share.
- **Scarcity is the product.** No rewarded ads, no reveal credits — a free
  user who wants more than the daily pays or comes back tomorrow. Do not
  reintroduce ad reveals.
- **The free deck is `[daily]`.** A forward swipe off it shows the day wall:
  blurred teaser of the next question (`peek_next_question` — a pure read,
  first 4 words, consumes nothing), live countdown to LOCAL midnight and the
  unlock CTA (the streak stays in the app-bar chip). Back swipe or system
  back return to the daily — the wall intercepts back. Never a trap.
- **Paywall-opening rules:** auto at most once per local day, on the first
  wall hit AFTER the daily vote; always on the wall/bridge unlock CTAs and on
  tapping a locked feature (star / history / locked smaczki); never at app
  start, in onboarding, or before the user's first vote. Always dismissible
  (floating X / system back).
- **Onboarding:** welcome → 2 taste questions (ARB text + hard-coded ids for
  the live split; votes are NOT cast) → the bridge (`OnboardingBridgeCard`,
  free path is the dominant CTA) → reminder opt-in → the feed. No wall.
- **Paywall:** fullscreen dialog, identical copy for EVERY entry point — the
  fixed slogan headline ("Bez limitu. / Bez końca. / Globalnie.") + catalog
  subline; no streak escalation, no per-feature headlines (`PaywallSource`
  feeds analytics only). Monthly plan preselected, with a weekly-equivalent
  price subline ("To ok. X zł tygodniowo"); no "best value" badge. Offering
  live from RevenueCat: monthly 19,99 zł / lifetime 69,99 zł (PL) — no
  weekly, no annual, no trial.
- **Review ask:** exactly once per milestone — the day the streak completes
  3, right after the rank-up celebration (`RankCelebrationListener`), and
  nowhere else.
- **Buy to play; sign in to secure.** Every user gets an anonymous Supabase
  UUID at launch and the entitlement rides on THAT — a guest can hold PRO
  indefinitely. An account exists only to make progress survive a reinstall
  or a new phone — the purchase for PRO (pitched AFTER the buy,
  `promptSaveProAccount`), the streak for free players
  (`maybePromptSecureStreak`). The register tab is open to everyone;
  registering upgrades the anonymous user in place (same UUID).
- **The 2025 reveal tier stays gone from the client** — no daily credits, no
  rewarded-ad reveals, no `revealedFeedProvider`, no AdMob/UMP. The server
  RPCs (`reveal_free_question`, `reveal_ad_question`, `admob-ssv`) are
  **still live for old app versions** — do not revoke or repurpose them.
  (`peek_next_question` is live again — the day wall uses it.)
- **Mock mode is premium.** With no Supabase/RevenueCat keys the session
  resolves `isPremium: true` so keyless dev and widget tests see the feed.
- **Two clocks on purpose:** the daily rolls over at the user's *local*
  midnight (countdown + `DailyRolloverWatcher` handle it in-session); the
  streak counts *UTC* days. Don't "fix" one to match the other.
- Voting is allowed on any readable question; the split shown is the
  **all-time** tally, not "today's result". The streak advances on any vote,
  at most once per UTC day, and decays one rank per 3 missed days.
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
  services/              SDK wrappers: Supabase, RevenueCat, notifications +
                         reminder loop, reviews, analytics, install referrer,
                         caching
supabase/
  schema.sql             Bootstrap only — the ORIGINAL base tables, not today's
                         shape (see the hard rule above)
  migrations/schema/     58 files: tables, RPCs, views, RLS, grants (has DDL).
                         The real schema; newest file wins per object
  migrations/data/       32 files: question seeds + catalog edits (no DDL, 3× bigger)
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
