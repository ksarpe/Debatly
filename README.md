# Debatly

[![CI](https://github.com/ksarpe/questionapp/actions/workflows/ci.yml/badge.svg)](https://github.com/ksarpe/questionapp/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/badge/coverage-%E2%89%A546%25-blue)](https://github.com/ksarpe/questionapp/actions/workflows/ci.yml)

A minimalist mobile app built around **provocative TAK/NIE questions**. One
question fills the screen as styled text; you answer TAK or NIE, immediately see
how the community split, and can open "smaczki" — short arguments for the other
side. Answering keeps a daily streak alive, which climbs a rank ladder from
*Amator kontrowersji* to *Legenda kontrowersji*.

> Only the GitHub repository is still named `questionapp` (the badge above
> points at it); the Dart package, application id and bundle
> id are all **debatly** / `com.aknsoftware.debatly`.

> **Store / console setup:** [KEYS_AND_SERVICES_MAP.md](KEYS_AND_SERVICES_MAP.md)
> maps every console, key and connection between services. The step-by-step
> release checklists were retired once both stores shipped; they live in git
> history (`RELEASE_CHECKLIST.md`, `IOS_RELEASE_CHECKLIST.md`).

## How the product actually works

Read this before changing anything in `features/questions`,
`features/account` or `features/monetization` — most wrong assumptions about
Debatly start here.

**Debatly is a freemium app (since the 2026-08 freemium rework): one free
question a day, PRO for the whole catalog.** Every user — free or paying —
lands on the feed with their personal daily question. The old hard paywall
(`HardPaywallScreen`) is gone; the paywall is now a dismissible fullscreen
dialog (`ProPaywallScreen`), and the free tier's **day wall** (`DayWallView`)
is the main conversion surface. (The 2025 reveal feed — daily credits, rewarded-ad
reveals — remains removed; its server RPCs stay live only for old app
versions. `peek_next_question` was brought back into active use: it powers
the day wall's blurred teaser.)

### The tiers

| Capability | Free | PRO |
|---|---|---|
| Daily question (1/day, rolls at LOCAL midnight) | ✅ | ✅ |
| Community split (all-time TAK/NIE tally) | ✅ | ✅ |
| Streak & ranks | ✅ | ✅ |
| Share card | ✅ | ✅ |
| First smaczek (argument #1) | ✅ | ✅ |
| Rest of the catalog (500+, unlimited) | ❌ | ✅ |
| All smaczki | ❌ | ✅ |
| Vote history | today only | ✅ |
| Favorites | ❌ | ✅ |
| Offline download | ❌ | ✅ |

The free row set is deliberate and **not negotiable**: the community split,
the streak and the share card are the hook and the distribution engine.
Without them a free user has no reason to return and nothing to share.
Scarcity is the product — there are no rewarded ads and no reveal credits; a
free user who wants more than the daily either pays or comes back tomorrow.

### The flow

`AppEntry` routes splash → onboarding (first run) → `HomeGate` → the feed for
**everyone** (the session still resolves first — its tier shapes the deck).
First run: welcome → 2 taste questions (vote → arguments → re-vote → split) →
the **bridge** (`OnboardingBridgeCard`: "To były dwa. Zostało 500." — primary
CTA continues for free, secondary opens the paywall sheet) → reminder opt-in
→ the feed with today's daily. **No wall anywhere in onboarding, and never a
paywall before the user's first vote.**

A free user's deck is `[daily]`. Swiping forward lands on the **day wall**:
a blurred teaser of the next question (first 4 words via the read-only
`peek_next_question` — it consumes nothing), a live countdown to the user's
local midnight and the unlock CTA (the streak stays visible in the app-bar
chip above the wall). The way back to the daily is the back swipe or the
system back gesture — the wall intercepts back so it never exits the app.
The wall is a fork, never a trap.

The **paywall** (a fullscreen dialog) opens: automatically at most once per
local day on the first wall hit *after* the daily vote; always on the
wall/bridge unlock CTAs and on tapping a locked feature (favorites star, the
locked older-history panel, locked smaczki); never at app start, in
onboarding, or before the
first vote. It is always dismissible (the floating X or system back) and
lands the user back where they were. The pitch is identical for every entry
point: the fixed slogan headline ("Bez limitu. / Bez końca. / Globalnie.")
over the catalog subline — no streak escalation, no per-feature headline
(the `PaywallSource` enum only feeds analytics) — with ONE sanctioned
exception: opened from the debate profile's locked rows, the headline is the
portrait line "{n} głosów. Zobacz, co mówią o Tobie." (the paywall then sells
the user's own portrait, not the catalog). The monthly plan comes
preselected (with a weekly-equivalent price subline, "To ok. 4,61 zł
tygodniowo") so the CTA is armed on open; there is no "best value" badge.
The offering is live from RevenueCat: monthly 19,99 zł / lifetime 69,99 zł
(PL) — no weekly plan, no trial.

The in-app review ask (`in_app_review`) rides the vote milestones: once after
the 3rd vote ever cast, and one reminder after the 7th (the OS gives no "did
they review?" signal, so the second ask is unconditional — the native sheet's
own quota suppresses it for users who already rated). At most one ask per
local day; on a rank-promotion day it fires right after the rank-up animation
closes instead of on top of it; past the 7th-vote milestone it never asks
again.

### The account model: buy to play, sign in to secure

Identity and account are separate things, and only the identity gates content:

- **Every user gets an anonymous Supabase UUID at launch.** That is who they
  are; the entitlement rides on it. A guest can hold PRO indefinitely.
- **You buy PRO to play.** The purchase attaches to that anonymous identity —
  no account, no email, no sign-up in front of the paywall.
- **An account only SECURES what the user already has.** It makes PRO, the
  streak, votes and favorites survive a reinstall or a new phone. It is
  pitched right after the buy (`promptSaveProAccount`), after a free player's
  streak reaches three (`maybePromptSecureStreak`), and offered again in
  Settings (`SecureAccountButton`).

The auth sheet offers the register tab to **everyone** — a free player who
wants to keep playing for free can still secure their streak with an account.
Registering upgrades the anonymous user in place (same UUID), so nothing is
lost and no entitlement is gained. The sign-in link on the paywall sheet
remains the returning buyer's route to the account their PRO sits on.

Every user — free included — has Settings and a profile now; account deletion
for signed-in users works in-app again, and the web link
(`DELETE_ACCOUNT_URL`, surfaced on the privacy policy page) remains for
everyone else.

Mock mode (no Supabase/RevenueCat keys) resolves the session as premium so
keyless development lands on the full feed.

### The feed

Position 0 of the deck is **today's personal daily question**: drawn
server-side, per user, from the questions *that user has not voted on yet*,
preferring never-seen ones, stable for the rest of that local date. For PRO,
after it comes the whole catalog, unseen-first, shuffled with a per-launch
seed; forward swipes wrap around. For free users the deck ends there — the
day wall stands where the catalog would continue.

- Every readable question is votable (TAK/NIE), once. The panel then shows
  the community split — an **all-time tally** for that question, not "today's
  result". Free users see it too: the split is the hook, not a premium perk.
- The **streak** advances on *any* successful vote, at most once per UTC day.
  Missing days decay it by one rank per 3 missed days (a "freeze") instead of
  snapping to zero. Ranks are a static ladder keyed on streak length
  (0/3/7/14/30/60/100 days). The daily rolls over on the user's *local* date
  (a countdown + `DailyRolloverWatcher` re-resolve it at midnight without a
  relaunch); the streak on *UTC* days — two clocks, on purpose.
- **Smaczki** are per-question arguments served by `get_question_smaczki`.
  Each one is tagged with the answer it attacks (`side`: `attacks_yes` /
  `attacks_no` / `neutral`, NULL until it is tagged in the admin panel), and
  the RPC orders them by relevance to the caller's OWN vote — the argument
  aimed at the side they actually picked comes first. A free user reads that
  top one on a question they've seen, but ONLY once their vote exists and only
  when it actually aims at them (their side's attacker, a neutral or an
  untagged one — a row that merely defends their answer stays locked: the
  defense is what PRO is sold on); PRO reads them all. Before the vote the
  server returns no readable text to a free caller at all, and the client's
  pre-vote prefetch uses `get_question_smaczki_meta` (positions + lengths
  rounded to 10 chars, no text column) — so a free device holds at most ONE
  readable argument per question, ever. The smaczki sheet is vote-gated for
  both tiers: before the vote the bottom-bar pill stays visible, but tapping
  it shows the "Najpierw zagłosuj" hook instead of the sheet — arguments read
  before taking a side would pollute the reflex the community split measures.
- **The argument comes before the percentages — and the vote is final.** A
  vote does not reveal the split straight away: the smaczek aimed at the side
  just picked falls in word by word, lands on the user's own answer (which
  shakes, with a haptic), and they answer "TRZYMAM SIĘ" / "TO MNIE RUSZYŁO".
  Neither answer re-casts anything — the split measures the reflex, the gate
  measures resilience, and mixing the two made every split drift toward 50/50
  (`p' = p + f·(1−2p)`). The outcome (`held` / `moved` / `dismissed` for
  system back) plus the dwell time is recorded on the vote row by
  `record_smaczek_challenge` (first write wins), never touching `choice`.
  Under the bars a second number appears — "Kontra przewróciła X% głosujących"
  (`moved / (held + moved)`; `dismissed` never enters the denominator) — but
  only once the question has ≥30 answered gates; below that the server
  withholds `flip_pct` entirely. Never a trap: system back resolves as
  "dismissed", and no readable argument means no gate at all.
- **The gate is capped at 3 per session** (cold start; 30+ minutes in the
  background starts a new session) — the valve for PRO, who bought speed;
  a free user's single daily never meets the cap. Gates 2 and 3 are compact:
  the text appears whole and the buttons come right after the tile-shake
  (which stays — it is the whole message). Skipped gates are measured
  (`smaczek_challenge_skipped`: `no_smaczki` / `offline` /
  `no_match_after_refetch` / `slow_fetch` — the post-vote fetch gets a 2.5 s
  budget, past which the split appears and the fetch keeps warming the sheet —
  / `session_cap`). After the gate the bottom bar stops promising "PRZECIWKO
  TOBIE": it says "KONTRA" (PRO), "ARGUMENT ZA TOBĄ" (free — the attack is
  behind them, so the pill sells the locked defense) or "JESZCZE DWA
  ARGUMENTY" (the served smaczek was untagged) — and a free user's smaczki
  sheet then hides the argument they already read, opening straight on the
  locked ones under an attack → defense header ("jeden, który Cię broni, i
  jeden, który komplikuje sprawę") when the locked cards really are a defense
  plus a neutral, or a plain count when that promise can't be kept.
- **The debate profile** extends the conformity axis (same slide-down panel,
  deliberately not a screen of its own) with a 2×2 grid: conformity (with /
  against the crowd) × resilience (how often a qualifying gate ends in "to
  mnie ruszyło"). The four types — FILAR, PŁYNIE Z PRĄDEM, SAMOTNY WILK,
  POSZUKIWACZ — are all written with equal dignity: the moment one reads as a
  punishment, the mechanic teaches people to stop reading smaczki.
  Resilience counts only gate answers with dwell ≥ the configured minimum
  (default 1500 ms — below that nobody read the argument; such a "held" is
  stored as `skipped_fast` and excluded from the personal axis, while the
  question's flip counters keep today's arithmetic). The boundaries live in
  `profile_config` server-side — conformity 0.65 (not 50%: a random voter's
  expected conformity at real splits is ~65%, so a 50% cut would collapse
  the grid) and resilience 0.15 — and `recompute_profile_boundaries()`
  (weekly pg_cron job) re-derives them as medians once ≥200 profiles are
  unlocked. Unlocking needs BOTH ≥6 votes and ≥6 qualifying gate answers
  (the progress bar tracks whichever counter is further behind); 6–11 shows
  the type as "profil wstępny", 12+ drops the tag.
  The free/PRO split follows one rule: **the present is free, the past and
  the comparison are paid.** Free: the type, both current percentages, the
  axis rung and the Stories-ready share poster (`ProfileShareCard`). PRO: the
  monthly trend, the type's rarity ("Twój typ ma X% użytkowników" —
  `get_type_rarity`, NULL below 20 unlocked profiles), "zdania, które Cię
  przewróciły" (`get_moved_smaczki`) and the loneliest vote (computed
  client-side from the PRO vote history). Free sees these as locked rows
  where **the counter is visible and the content is locked** — the flips row
  carries the user's real moved count and is hidden entirely at zero (an
  empty vault teaches the feature is worthless); tapping any row opens the
  paywall with the portrait headline. The category breakdown was pulled from
  the UI (the catalog's category labels are English-only); its RPC stays live
  server-side for when they're localized.
  **Naming rule:** the conformity axis's five rungs are positional PHRASES
  ("Zawsze pod prąd" … "Zawsze z tłumem", same 20-pp thresholds), while the
  2×2 grid keeps the NOUNS — a phrase locates you on a scale, a noun claims
  an identity, so the two vocabularies can never collide again (the axis rung
  "Samotny wilk" used to contradict the grid on the same panel).
  Favorites, the vote-history screen and the offline catalog download are PRO
  features — tapping any of them opens the paywall sheet.

## Tech stack

| Concern            | Choice                                  |
| ------------------ | --------------------------------------- |
| Framework          | Flutter (Dart), pinned to 3.44.1        |
| State management   | Riverpod (`flutter_riverpod`)           |
| Backend / Auth     | Supabase (`supabase_flutter`)           |
| Subscriptions      | RevenueCat (`purchases_flutter`)        |
| Monitoring         | Sentry (`sentry_flutter`)               |
| Animation          | Custom `AnimatedBuilder` + `Transform`  |

## Project layout

```
lib/
├── main.dart                # Entry point — Sentry, SDK init, mounts ProviderScope
├── app.dart                 # MaterialApp: theme, locale, navigation root
├── core/                    # Cross-cutting concerns, no feature knowledge
│   ├── config/              # AppConfig — secrets via --dart-define
│   ├── feedback/            # AppToast (themed sonner overlay)
│   ├── graphics/            # SVG path helpers for the custom glyphs
│   ├── layout/              # Orientation lock
│   ├── locale/              # LocaleController + context.l10n extension
│   ├── monitoring/          # Monitoring facade over Sentry
│   ├── network/             # Connectivity providers + offline-error detection
│   ├── share/               # Widget-to-image capture for share cards
│   ├── startup/             # guardedInit — SDK bring-up that must never throw
│   ├── theme/               # AppTheme + AppColors theme extension
│   ├── time/                # Epoch-day helpers (UTC day boundaries)
│   └── widgets/             # Shared chrome (sub-screen scaffolds)
├── data/                    # Models + data access, no UI
│   ├── models/              # Question, Rank, Smaczek, UserStats, VoteResult, …
│   ├── mock/                # Seed questions (used when Supabase keys absent)
│   └── repositories/        # QuestionRepository + caching decorator
├── features/                # Feature-first: providers / screens / widgets each
│   ├── account/             # Auth sheet, session, stats, rank/streak celebrations
│   ├── monetization/        # Hard paywall screen + paywall sheet
│   ├── onboarding/          # Splash → tutorial (incl. a taste vote) → home gate
│   ├── questions/           # The feed, voting, smaczki, share, history
│   └── settings/            # Settings hub, favorites, reminders, privacy, DEV tools
├── l10n/                    # ARB source strings (en/pl) + gen/ (generated)
└── services/                # SDK wrappers: Supabase, RevenueCat,
                             # notifications + reminder loop, reviews, analytics,
                             # install referrer, caching
supabase/                    # schema.sql, migrations/, edge functions, backups
admin/                       # Next.js admin panel (own package.json / node_modules)
tool/                        # Python helpers (splash generation, regional pricing)
test/                        # Widget + unit tests — all green on master
```

## The feed gestures and the "wind" animation

`WindQuestionView` owns navigation and the signature transition. On a swipe the
current text accelerates off the swiped edge, fading (`easeInCubic`); after a
short beat the next question **assembles word by word, each word dropping in
from above** (see [falling_words_text.dart](lib/features/questions/widgets/falling_words_text.dart)).
No cards, no flips — just text in motion.

- **Swipe left** = forward, wrapping around the catalog.
- **Swipe right** = back, clamped at the daily (index 0) with a small bounce
  so the gesture never silently does nothing or overshoots.
- A slow drag commits on total travel (64 logical px) as well as on flick
  velocity — tablet users drag slowly, and App Review noticed.

See [wind_question_view.dart](lib/features/questions/widgets/wind_question_view.dart).

## Running

The app runs against mock data out of the box — every SDK no-ops gracefully when
its credentials are missing:

```bash
flutter pub get
flutter run
```

To enable the backends, pass keys at build time:

```bash
flutter run --dart-define=SUPABASE_URL=https://xyz.supabase.co --dart-define=SUPABASE_ANON_KEY=... --dart-define=REVENUECAT_API_KEY=...
```

Or copy `env/example.json` to `env/local.json`, fill in the real values, and run:

```bash
flutter run --dart-define-from-file=env/local.json
```

Everything under `env/` except `example.json` is ignored by git, so real keys
stay local. Release builds use `env/prod-android.json` / `env/prod-ios.json`.

## Quality gates

CI ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) runs on every push
and PR, and treats **every analyzer hint as fatal**. A plain `flutter analyze` is
weaker than CI — run the same three gates locally:

```bash
dart format .
```

```bash
flutter analyze --fatal-infos --fatal-warnings
```

```bash
flutter test
```

CI also enforces a **line-coverage floor** (currently 46%) via
[`very_good_coverage`](https://github.com/VeryGoodOpenSource/very_good_coverage) —
no third-party upload, so nothing about this proprietary codebase leaves CI. The
floor is set just below the coverage at the time it was added; **only raise it**,
never lower it without discussion. Reproduce the measurement locally with:

```bash
flutter test --coverage
# overall % = sum(LH) / sum(LF) across coverage/lcov.info
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for conventions (architecture, l10n,
theming, migrations, commit style).

## Supabase

The app uses mock questions when Supabase credentials are missing. When
`SUPABASE_URL` and `SUPABASE_ANON_KEY` are provided, `QuestionRepository`
automatically switches to Supabase.

> **`supabase/schema.sql` is the bootstrap, not the current shape.** It creates
> the base tables (profiles, subscriptions, questions, translations, billing/ad
> events) as they were at the start. Everything the app relies on today —
> `question_seen`, `user_daily_questions`, `question_smaczki`, `ranks`,
> `question_favorites`, the reveal/vote/stats RPCs — arrives through
> `supabase/migrations/schema/`. The remote
> `supabase_migrations.schema_migrations` table is the ground truth; read
> [supabase/migrations/README.md](supabase/migrations/README.md) before touching
> anything database-side, and never run `supabase db push`.

Fresh-project setup:

1. Create a Supabase project.
2. Open the SQL Editor and run `supabase/schema.sql`.
3. Apply `supabase/migrations/schema/` in filename order (DDL, RPCs, RLS,
   grants), then `supabase/migrations/data/` (question catalog + copy edits).
4. Deploy the edge functions in `supabase/functions/` (see below).
5. Run the app with `--dart-define-from-file=env/dev.json`.

The daily itself is the owner-curated `daily_picks` calendar; whatever wins —
the pick or the personal fallback draw — is stored in `user_daily_questions` on
first read of the user's local date. One scheduled job exists:
`compact_daily_picks()` (nightly pg_cron, 02:47 UTC), which re-dates future
picks whose question was deactivated.

### Monitoring the global daily

Every way the global daily degrades fails the *same silent way*: a dead pick, a
gap in `daily_picks`, the calendar running out, the cron not running — each one
falls back to the personal draw, which returns HTTP 200 with a perfectly good
question. Nothing errors, so nothing reaches Sentry or the Supabase logs. The
only symptom is spread: the daily quietly stops being the same question for
everyone.

One query, run on any day that should have a pick — `distinct_q` should be
about 1:

```sql
select assigned_on, count(*) users, count(distinct question_id) distinct_q
from user_daily_questions
where assigned_on >= current_date - 1
group by 1;
```

`daily_vote_cast` carries `question_id` in its properties for the same reason,
so `app_events` can answer "what did the world actually debate today?" without
joining. Check `cron.job_run_details` if the spread appears overnight — an
empty table means the job has never run at all.

Two daily failures are *not* fallbacks, and both now reach Sentry under the
`feature:daily_question` tag:

| What happened | Where it's reported | Payload |
|---|---|---|
| The fetch **threw** — no daily, the user gets the retry screen | `QuestionScreen` listens on `todaysDailyQuestionProvider` | the exception |
| The fetch **returned nothing usable** — HTTP 200, no exception, empty feed | `SupabaseQuestionRepository.fetchDailyQuestion` | `reason` = `no_row` / `blank_text`, plus `has_session`, `locale`, `date`, `question_id` |

The second one has no error object at all, which is why it is constructed at the
point of failure rather than caught somewhere. `no_row` usually means the caller
had no uid (a failed anonymous sign-in — Supabase rate-limits anon sign-ups per
IP); `has_session` in the payload settles that without guessing. It also fires
for a premium user whose catalog loaded fine and who therefore never sees a
dead end — they just silently have no daily.

Connectivity errors are dropped on the way out by `Monitoring`, so what lands
under the tag is a backend failure, not a commute.

### Vocabulary traps

| Term | What it means here |
|---|---|
| `user_daily_questions` | The live mechanism — one personal free question per user per local date. |
| `daily_questions` | **Legacy.** The old global "same question for everyone" calendar. No longer written to; kept only for old history rows and the voted-everything fallback. |
| `question_seen` | Formerly `question_unlocks`. A row means "this user may read this question's text" (landed on in the feed; historically also free-tier reveals). |
| `peek_next_question` | **Live again** — the day wall's blurred teaser. A pure read returning `{id, first-4-words}` for one random unvoted question; consumes nothing, writes nothing. |
| free unlock credit / reveal slot / ad reveals | **Legacy 2025 free-tier machinery.** Still removed from the client; the RPCs (`reveal_free_question`, `reveal_ad_question`) stay live server-side only for old app versions. |
| day wall | The free tier's end-of-deck screen (`DayWallView`): teaser + countdown to local midnight + unlock CTA. Back swipe / system back return to the daily. |
| smaczki | Per-question arguments, tagged with the side they attack. The one aimed at the user's own vote is free on a seen question; the rest are PRO. One is served automatically between the vote and the result; the rest sit behind the bottom-bar CTA. |

### Edge functions

`supabase/functions/` holds the Deno functions: `revenue-cat-webhook` (reflects
entitlement changes onto `profiles.is_premium`), `sync-entitlement`,
`admob-ssv` (ad-reward verification — legacy, kept only for old app versions),
`send-auth-email` (localized auth emails, reading `profiles.locale`) and
`delete-account`.

**Account deletion** is required by both stores. Settings → *Delete account*
calls `delete-account`, which deletes the Supabase user (cascading to all their
data). Deploy it before release.

The mobile app should only ever use the public anon key. Insert/update/delete
access stays in the Supabase dashboard, the `admin/` panel, or a SECURITY
DEFINER RPC — never in the released app. There is no client-writable table: even
the profile language goes through `set_profile_locale`.

### Native config notes

- **No ads, no ad consent.** The AdMob SDK, the UMP consent flow and the iOS
  ATT prompt were removed with the 2026-08 hard-paywall rebuild and stay out
  under freemium — scarcity is the product, so the free tier carries no
  rewarded ads. The AdMob app ids are gone from `AndroidManifest.xml` and
  `Info.plist` along with the SKAdNetwork list.
- Android `minSdk` stays at 23.
- Android `compileSdk` is raised to 36 (required by `package_info_plus`), and
  `android/build.gradle.kts` forces every subproject to compileSdk 36 — some
  transitive plugins (`passkeys_*` via Supabase) pin themselves to 35.
- `kotlin.incremental=false` is set in `android/gradle.properties` to work
  around a Kotlin 2.3.20 Build Tools API crash on Windows ("Could not close
  incremental caches"). Remove it once the toolchain is past that bug.
- The build prints a harmless KGP warning ("plugins that apply Kotlin Gradle
  Plugin") — Flutter 3.44 still supports this path (`android.builtInKotlin=false`);
  it only matters for a future Flutter release.

## Auth & monetization internals

The app is **freemium**: one free daily question, PRO for everything else.
Everything still degrades gracefully when SDK keys are absent — mock mode
resolves as premium and runs on local data.

- **Silent anonymous auth.** On launch `SessionNotifier`
  ([session_providers.dart](lib/features/account/providers/session_providers.dart))
  calls `SupabaseService.ensureSignedIn()`, which signs the user in anonymously
  if `currentUser` is null. Every guest gets a stable Supabase UUID — no email,
  no password — and that UUID is also passed to RevenueCat (`Purchases.logIn`)
  so entitlements follow the same identity. Signing up later upgrades the same
  identity in place, so the streak, votes and PRO survive. A guest who buys
  is nudged right after to attach the purchase to a real account.
- **Premium.** RevenueCat handles billing; the one paywall surface is the
  fullscreen
  [`ProPaywallScreen`](lib/features/monetization/widgets/pro_paywall_screen.dart)
  around [`ProPaywallContent`](lib/features/monetization/widgets/paywall_content.dart),
  opened from the day wall (auto once a day post-vote, or the CTA), the
  bridge, locked features and Settings. Packages and localized prices come
  live from the current RevenueCat offering (monthly / lifetime; monthly
  preselected, no badge); the purchase goes through `Purchases.purchase`.
  The `revenue-cat-webhook` edge function reflects entitlement changes onto
  `profiles.is_premium` (the flag the RLS gate reads). Restore-purchases is
  reachable from Settings and the paywall (guests get a sign-in-first chooser
  so a store restore can't hijack an account-held entitlement).
- **Caching / offline.** In production the Supabase repository is wrapped in
  `CachingQuestionRepository`, scoped to the locale and the signed-in UUID, so
  reads survive a dropped network and PRO users can download the whole catalog
  for offline use. A lapsed subscription wipes the cached content.

## License

Proprietary — Copyright (c) 2026 Kasper Janowski. All rights reserved. See
[LICENSE](LICENSE).
