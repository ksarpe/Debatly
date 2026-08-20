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
| Rest of the catalog (500+), all smaczki, full history (free: today only), favorites, offline | ❌ | ✅ |

- **The free rows are the growth engine — don't paywall them.** Community
  split, streak and the share card must stay free; without them a free user
  has no reason to return and nothing to share.
- **Scarcity is the product.** No rewarded ads, no reveal credits — a free
  user who wants more than the daily pays or comes back tomorrow. Do not
  reintroduce ad reveals.
- **The daily is GLOBAL again (2026-08-20): `daily_picks`.** An owner-curated
  calendar table — one question pinned per date (question UNIQUE — a question
  is the daily at most once), written only via SQL editor/service_role.
  Seeded 2026-08-21 → 2027-11-15 with 452 picks (every active question with
  zero real votes + every one whose only votes were premium/tester accounts),
  categories round-robined; the owner appends. **Deactivating a pick's
  question is safe:** `compact_daily_picks()` (nightly pg_cron 02:47 UTC, or
  run by hand) removes dead FUTURE picks and re-dates the survivors onto
  consecutive days from tomorrow — past/today never move. **The pick outranks the caller's vote history**
  (20260820170000): PRO always lands on it (voted = result bars; their feed
  has the catalog anyway); FREE lands on it when unvoted OR inside the
  **one-shot re-vote window** — the single sanctioned exception to
  vote-finality: `_daily_pick_revote_ok` = free caller + the pick of the
  current UTC±1 day + a vote OLDER than the pick day's earliest possible
  start anywhere (publish_date UTC − 14h) + `now()` already PAST that same
  instant (20260820210000 — without it the window reopened for ten hours a
  day on a pick dated UTC tomorrow, because the closing write stamped a
  `voted_at` that was still below its own threshold). Inside the window
  `get_daily_vote_state` returns `my_choice` NULL (shipped clients show the
  buttons on their own) and `cast_daily_vote` UPDATEs choice + voted_at —
  which closes the window, so one flip per pick ever; the streak counts the
  re-vote, the tally trigger handles the delta, a used smaczek gate is NOT
  re-armed. A free caller with a FRESH vote on the pick (cast on its day)
  gets the personal fallback draw — which since the same migration
  **excludes future picks** (it used to burn the shared calendar one
  user-day at a time). Gap date = personal draw for everyone; nothing
  bricks. The winner still lands in `user_daily_questions`, so text gating,
  peek/reveal exclusions and history are untouched. The daily card wears the
  "PYTANIE DNIA" pill (`DailyQuestionBadge`, precedence over "NOWE"); PRO
  away from index 0 gets a "Pytanie dnia" jump link beside "Wróć do
  najnowszego" (`canJumpToDailyProvider` → `toDaily()`).
- **The free deck is `[daily]`.** A forward swipe off it shows the day wall:
  blurred teaser of the next question (`peek_next_question` — a pure read,
  first 4 words, consumes nothing; since 2026-08-20 it teases TOMORROW'S
  pick, falling back to a random unvoted question), live countdown to LOCAL
  midnight and the unlock CTA (the streak stays in the app-bar chip). Back
  swipe or system back return to the daily — the wall intercepts back. Never
  a trap.
- **Paywall-opening rules:** auto at most once per local day, on the first
  wall hit AFTER the daily vote; always on the wall/bridge unlock CTAs and on
  tapping a locked feature (star / the history screen's locked older-history
  panel / locked smaczki); never at app start, in onboarding, or before the
  user's first vote. Always dismissible (floating X / system back). The
  history screen itself is open to everyone: free sees today's card(s) — the
  daily is always free — plus the locked panel.
- **Onboarding:** welcome → 2 taste questions (ARB text + hard-coded ids for
  the live split; votes are NOT cast) → the bridge (`OnboardingBridgeCard`,
  free path is the dominant CTA) → reminder opt-in → the feed. No wall.
- **Paywall:** fullscreen dialog, identical copy for EVERY entry point — the
  fixed slogan headline ("Bez limitu. / Bez końca. / Globalnie.") + catalog
  subline; no streak escalation, no per-feature headlines (`PaywallSource`
  feeds analytics only) — with ONE owner-approved exception (2026-08-19): the
  debate profile's locked rows pass the portrait headline "{n} głosów.
  Zobacz, co mówią o Tobie." (`paywallProfileHeadline` via
  `showProPaywall(headline:)`). Do not add further variants without the
  owner's sign-off. Monthly plan preselected, with a weekly-equivalent
  price subline ("To ok. X zł tygodniowo"); no "best value" badge. Offering
  live from RevenueCat: monthly 19,99 zł / lifetime 69,99 zł (PL) — no
  weekly, no annual, no trial.
- **Review ask:** on the vote milestones — after the 3rd vote ever cast, and
  once more after the 7th (no "did they review?" signal exists, so the second
  ask is unconditional; the OS quota shields users who already rated). Max one
  ask per local day; on a promotion day it rides right behind the rank-up
  celebration (`RankCelebrationListener`) instead of on top of it; never
  again past the last milestone.
- **Buy to play; sign in to secure.** Every user gets an anonymous Supabase
  UUID at launch and the entitlement rides on THAT — a guest can hold PRO
  indefinitely. An account exists only to make progress survive a reinstall
  or a new phone — the purchase for PRO (pitched AFTER the buy,
  `promptSaveProAccount`), the streak for free players
  (`maybePromptSecureStreak`). The register tab is open to everyone;
  registering upgrades the anonymous user in place (same UUID). **Account
  DELETION is open to everyone too** — a guest holds votes, a streak and a
  profile, which is exactly the personal data App Review 5.1.1(v) and Play
  require an in-app way to erase, and `delete-account` works off the JWT. Do
  not put the row back behind `hasAccount`.
- **The 2025 reveal tier stays gone from the client** — no daily credits, no
  rewarded-ad reveals, no `revealedFeedProvider`, no AdMob/UMP. The server
  RPCs (`reveal_free_question`, `reveal_ad_question`, `admob-ssv`) are
  **still live for old app versions** — do not revoke or repurpose them.
  (`peek_next_question` is live again — the day wall uses it.)
- **Mock mode is premium — and only ever means "no keys".** With no
  Supabase/RevenueCat keys the session resolves `isPremium: true` so keyless
  dev and widget tests see the feed. A build that DOES ship credentials whose
  `Supabase.initialize` failed must never fall back to mock: that gave real
  users a fake app (invented questions, fabricated split, votes discarded,
  nothing in Sentry). **Anything deciding "should I serve mock data?" branches
  on `SupabaseInitStatus` / `supabaseInitProvider`, never on
  `SupabaseService.isInitialised`** (which stays a legitimate "is the client
  usable yet" check — four call sites read it for exactly that). `failed` is an
  error state `HomeGate` renders with a retry. That retry re-awaits the
  ORIGINAL init future and never starts a second one: `Supabase.initialize`
  flips its own internal flag *before* it restores the persisted session, so a
  second call returns instantly having restored nothing — and the app then
  mints a fresh anonymous UUID over the returning user's account.
- **Force-update gate (v2.1.0+):** `app_update_gate` (platform → `min_version`,
  '0.0.0' = off) + `get_min_supported_version` (granted to anon — runs at
  launch, pre-session). HomeGate compares it against the pubspec version name
  (SEMANTIC version, not the Codemagic build counter) and swaps the feed for
  the blocking `UpdateRequiredScreen` (store button only). **FAIL-OPEN
  everywhere** — no backend / RPC error / unparsable version = the app runs;
  the gate is for retiring versions deliberately, never by accident. Raise the
  bar only when the new build is live in BOTH stores:
  `update app_update_gate set min_version='2.1.0', updated_at=now() where platform in ('android','ios');`
  Builds older than v2.1.0 have no gate code and can never be forced — that is
  why the daily/vote RPCs keep their old contracts working.
- **Two clocks on purpose:** the daily rolls over at the user's *local*
  midnight (countdown + `DailyRolloverWatcher` handle it in-session); the
  streak counts *UTC* days. Don't "fix" one to match the other.
- **The argument sits between the vote and the result — and the vote is
  FINAL.** Casting a vote does not reveal the split: the smaczek tagged
  against the side just picked (`question_smaczki.side` — `attacks_yes` /
  `attacks_no` / `neutral`, NULL = untagged, served as neutral) falls in word
  by word, hits the user's own answer tile, and they answer "TRZYMAM SIĘ" /
  "TO MNIE RUSZYŁO". Neither answer re-casts the vote (that used to drag every
  split toward 50/50): the outcome (`held`/`moved`/`dismissed` = system back)
  + dwell is recorded on the vote row via `record_smaczek_challenge`, which
  never touches `choice`. `cast_daily_vote` is **first-write-wins** since
  2026-08-20 (it used to upsert `choice`, which left the vote — and with it
  the free argument it unlocks — rewritable straight from the anon key): a
  repeat cast writes nothing and returns the STORED choice as `my_choice`, and
  only a real insert advances the streak. Trust the returned `myChoice` over
  the one you sent. Only then do the bars appear, plus — at ≥30 answered
  gates on the question (server-enforced, `flip_pct` is NULL below) — the
  "Kontra przewróciła X%" line (`moved/(held+moved)`, `dismissed` excluded).
  Max 10 gates per session (cold start, reset after 30 min backgrounded —
  `challengeSessionProvider`; was 3 until 2026-08-20 — the arguments are the
  reason to stay in the feed, so the valve sits well past a normal session);
  every gate after the first is compact (text whole, tile-shake stays).
  Post-gate the bar label and the free sheet change (no repeat of the
  read argument — see `challengeRecordsProvider`). `get_question_smaczki`
  orders by relevance to the caller's own vote and the FREE row is the
  top-ranked one, not position 1 — and it is readable ONLY once the caller's
  vote exists and only when it aims at them (attacker of their side, neutral,
  or untagged; a row that merely defends their answer stays locked). Pre-vote
  the client prefetches `get_question_smaczki_meta` (positions + rounded
  lengths, NO text) — a free device never holds more than one readable
  argument per question. The post-vote fetch has a 2.5 s budget
  (`slow_fetch` skip): past it, bars immediately. The smaczki SHEET is
  vote-gated for BOTH tiers: before the vote the bottom-bar pill stays
  visible but a tap shows the "Najpierw zagłosuj" toast instead of opening it
  (arguments read pre-vote would pollute the reflex the split measures).
  Never a trap: system back = `dismissed`, and no readable argument means no
  gate (skips logged as `smaczek_challenge_skipped`). **A `dismissed` gate is
  recorded but never counts as READ** (`ChallengeRecord.wasRead`): a back press
  inside the first second must not spend the free tier's one readable argument,
  so the sheet keeps its free row and the bottom bar keeps its pre-gate promise.
  (Server-side the dismissal still claims the vote row's challenge slot
  permanently — no client path can re-offer that gate, so a dismissed daily
  still costs a day of profile progress. Open.)
- **The debate profile is an extension of the conformity axis, not a screen.**
  Under the axis panel sits a 2×2 grid (conformity × resilience): FILAR /
  PŁYNIE Z PRĄDEM / SAMOTNY WILK / POSZUKIWACZ — all four names equal in
  dignity, none a punishment (or gamification teaches people to stop reading
  smaczki). Resilience counts ONLY qualifying gate results: `held`/`moved`
  with dwell ≥ the server minimum (1500 ms default; a faster "held" is stored
  as `skipped_fast` and excluded — but still bumps the question's
  `challenge_held_count`, so the under-question flip line is untouched).
  **The dwell is measured from the gate OPENING, not from the last word
  landing** — the falling words are ~1 s of reading on a median argument, and
  charging that second to nobody filed honest fast readers as `skipped_fast`
  with no way to discover the rule. The answers stay inert until the argument
  lands, so the head start cannot be gamed.
  Boundaries are **server-side config** (`profile_config`: conformity 0.65 —
  deliberately NOT 50%, expected random-voter conformity is ~65% — resilience
  0.15), re-derived as population medians by `recompute_profile_boundaries()`
  (weekly pg_cron; no-op under 200 unlocked profiles). Unlock needs BOTH ≥6
  votes AND ≥6 qualifying gates (progress bar shows the counter further
  behind); 6–11 = "profil wstępny", 12+ = full. Free/PRO rule: **the present
  is free, the past and the comparison are paid.** Free: type, both current
  percentages, axis rung, share card. PRO: trend, type rarity
  (`get_type_rarity`, NULL under 20 unlocked profiles → block hidden),
  "zdania, które Cię przewróciły" (`get_moved_smaczki`) and the loneliest
  vote (client-side off the PRO vote history). Free sees locked rows with
  VISIBLE counters (the flips row shows the real `gate_moved` and is hidden
  at zero — never show an empty vault); a tap opens the paywall with the
  portrait headline. The category breakdown is UI-removed (English labels);
  `get_profile_categories` stays live server-side. Data RPC:
  `get_debate_profile` (not premium-gated). **Naming rule:** the conformity
  axis's five rungs are positional PHRASES ("Zawsze pod prąd" … "Zawsze z
  tłumem", thresholds unchanged), the 2×2 grid keeps the NOUNS — never give
  a rung a noun name, that's how "Samotny wilk" ended up meaning two things
  on one panel.
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
  migrations/schema/     75 files: tables, RPCs, views, RLS, grants (has DDL).
                         The real schema; newest file wins per object
  migrations/data/       35 files: question seeds + catalog edits (no DDL, 3× bigger)
  functions/             Edge functions (Deno/TS): revenue-cat-webhook,
                         sync-entitlement, admob-ssv, send-auth-email,
                         delete-account
  backups/               Pre-edit row snapshots for data/ migrations — data, not code
admin/                   Next.js admin panel (own package.json, own node_modules)
tool/                    Python helper scripts (splash gen, regional pricing)
test/                    63 top-level test files (68 incl. golden/ + support/)
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
