# Debatly

[![CI](https://github.com/ksarpe/questionapp/actions/workflows/ci.yml/badge.svg)](https://github.com/ksarpe/questionapp/actions/workflows/ci.yml)

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

Read this before changing anything in `features/questions`, `features/account`
or the reveal RPCs — most wrong assumptions about Debatly start here.

**Debatly is not a "one question per day" app.** A free user can read several
questions every day; the daily question is only the *free entry point* of a feed
that keeps going.

### The feed

Position 0 of the deck is **today's personal daily question**: drawn
server-side, per user, from the questions *that user has not voted on yet*,
preferring never-seen ones. It is free for everyone (guests included), needs no
ad and no account, and is stable for the rest of that local date. It is
**personal** — two users almost never see the same one.

Past it, the tiers diverge:

- **PRO** walks the entire catalog, wrapping around; every question reads.
- **Free** walks a forward feed: the daily, then the questions they reveal one
  at a time this session. Swiping past the last item lands on the **reveal
  slot**, where a question is unlocked by the daily credit or by a rewarded ad.

Revealed text lives in memory only (`revealedFeedProvider`). Close the app and
it is gone — the RLS gate does not serve it again.

### What each tier gets

| | Guest (anonymous) | Free + real account | PRO |
|---|---|---|---|
| Personal daily question | 1 / day | 1 / day | 1 / day |
| Free unlock credit | — | 1 / UTC day | n/a |
| Rewarded-ad reveals | up to 3 / UTC day | up to 3 / UTC day | n/a |
| **Questions readable per day** | **up to 4** | **up to 5** | **whole catalog** |
| Voting + community split | yes | yes | yes |
| Streak & ranks | yes | yes | yes |
| Smaczki (arguments) | first one only | first one only | all |
| Vote history screen | — | — | yes |
| Favorites | star is a paywall hook | star is a paywall hook | add + keep forever |
| Offline catalog | — | — | yes |

Numbers that matter, and where they are enforced:

- The **free unlock credit** is topped up server-side by `sync_user_state`,
  once per UTC day, capped at 1, and **only for real accounts**
  (`is_real_account` — email/Google). Anonymous guests get no credit; that is
  the anti-farming gate, since a fresh anonymous identity is free to mint.
  It is spent automatically on the forward swipe onto the reveal slot, never
  while merely reading the daily.
- The **ad-reveal cap is 3 per UTC day**, defined once in
  `ad_reveal_daily_cap()` and enforced by `reveal_ad_question` before anything
  is spent. When it is hit, the paywall drops the ad button, pitches PRO and
  shows a live countdown to the UTC-midnight reset.
- The **daily question rolls over on the user's local date**; the credit and the
  ad cap roll over at **UTC midnight**. They are deliberately different clocks —
  do not "fix" one to match the other.

### Voting, streaks, smaczki

- Every question the user has actually seen is votable (TAK/NIE), once. The
  panel then shows the community split — an **all-time tally** for that
  question, not "today's result".
- The **streak** advances on *any* successful vote, at most once per UTC day.
  Missing days decay it by one rank per 3 missed days (a "freeze") instead of
  snapping to zero. Ranks are a static ladder keyed on streak length
  (0/3/7/14/30/60/100 days).
- **Smaczki** are per-question discussion prompts served by
  `get_question_smaczki`: a free user gets smaczek #1 plus locked placeholders,
  PRO gets them all.

## Tech stack

| Concern            | Choice                                  |
| ------------------ | --------------------------------------- |
| Framework          | Flutter (Dart), pinned to 3.44.1        |
| State management   | Riverpod (`flutter_riverpod`)           |
| Backend / Auth     | Supabase (`supabase_flutter`)           |
| Subscriptions      | RevenueCat (`purchases_flutter`)        |
| Ads                | Google AdMob (`google_mobile_ads`)      |
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
│   ├── monetization/        # Paywall sheet + entitlement providers
│   ├── onboarding/          # Splash → tutorial (incl. a taste vote) → app entry
│   ├── questions/           # The feed, voting, reveals, smaczki, share, history
│   └── settings/            # Settings hub, favorites, reminders, privacy, DEV tools
├── l10n/                    # ARB source strings (en/pl) + gen/ (generated)
└── services/                # SDK wrappers: Supabase, RevenueCat, AdMob, consent,
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

- **Swipe left** = forward. PRO wraps around the catalog; a free user advances
  through their revealed feed and then onto the reveal slot.
- **Swipe right** = back, on both tiers, clamped at the daily (index 0) with a
  small bounce so the gesture never silently does nothing or overshoots.
- A slow drag commits on total travel (64 logical px) as well as on flick
  velocity — tablet users drag slowly, and App Review noticed.
- Landing on the reveal slot with a credit auto-reveals: the padlock flourish
  ([lock_reveal.dart](lib/features/questions/widgets/lock_reveal.dart)) plays,
  then the question falls in. Without a credit the paywall shows, teased with the
  first words of the next question (non-consuming `peek_next_question`, eagerly
  prefetched while the user still lingers on the last item).

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
flutter run --dart-define=SUPABASE_URL=https://xyz.supabase.co --dart-define=SUPABASE_ANON_KEY=... --dart-define=REVENUECAT_API_KEY=... --dart-define=ADMOB_BANNER_ID=ca-app-pub-.../... --dart-define=ADMOB_REWARDED_ID=ca-app-pub-.../...
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

No scheduling job is needed: each user's free question is drawn on first read of
their local date and stored in `user_daily_questions`.

### Vocabulary traps

| Term | What it means here |
|---|---|
| `user_daily_questions` | The live mechanism — one personal free question per user per local date. |
| `daily_questions` | **Legacy.** The old global "same question for everyone" calendar. No longer written to; kept only for old history rows and the voted-everything fallback. |
| `question_seen` | Formerly `question_unlocks`. A row means "this user may read this question's text" (revealed, or landed on by PRO). |
| free unlock credit | The 1-per-UTC-day auto-spent reveal, real accounts only. Not the daily question. |
| smaczki | Per-question arguments/prompts behind the "go deeper" button. |
| reveal slot | The virtual index one past the free user's last question, where the paywall or auto-reveal lives. |

### Edge functions

`supabase/functions/` holds the Deno functions: `revenuecat-webhook` (reflects
entitlement changes onto `profiles.is_premium`), `sync-entitlement`,
`admob-ssv` (server-side ad reward verification), `send-auth-email` (localized
auth emails, reading `profiles.locale`) and `delete-account`.

**Account deletion** is required by both stores. Settings → *Delete account*
calls `delete-account`, which deletes the Supabase user (cascading to all their
data). Deploy it before release.

The mobile app should only ever use the public anon key. Insert/update/delete
access stays in the Supabase dashboard, the `admin/` panel, or a SECURITY
DEFINER RPC — never in the released app. There is no client-writable table: even
the profile language goes through `set_profile_locale`.

### Native config notes

- **AdMob app id** is set to Google's public *test* id in
  `android/app/src/main/AndroidManifest.xml` and `ios/Runner/Info.plist`.
  Replace both with your real id before release.
- **Ad consent.** `ConsentService` ([consent_service.dart](lib/services/consent_service.dart))
  runs before `AdsService.initialise`, both sequenced by `AdsBootstrap` on the
  first home-screen entry (after onboarding — never over the welcome funnel):
  it gathers GDPR consent via
  Google's UMP (configure the message in the AdMob console → *Privacy & messaging*)
  and, on iOS, requests App Tracking Transparency (`NSUserTrackingUsageDescription`
  is set in `Info.plist`). Before release, add Google's full SKAdNetwork list to
  `Info.plist` ([3p-skadnetworks](https://developers.google.com/admob/ios/3p-skadnetworks)).
- Android `minSdk` is raised to 23 (required by `google_mobile_ads`).
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

The app is *freemium with rewarded ads*. Everything degrades gracefully when SDK
keys are absent, so it still runs against mock data.

- **Silent anonymous auth.** On launch `SessionNotifier`
  ([session_providers.dart](lib/features/account/providers/session_providers.dart))
  calls `SupabaseService.ensureSignedIn()`, which signs the user in anonymously
  if `currentUser` is null. Every guest gets a stable Supabase UUID — no email,
  no password — and that UUID is also passed to RevenueCat (`Purchases.logIn`)
  so entitlements follow the same identity. Signing up later upgrades the same
  identity in place, so the streak, votes and PRO survive.
- **Server-mediated reveals.** Question text is gated by RLS, so reveals go
  through SECURITY DEFINER RPCs: `peek_next_question` teases the next pick
  without consuming anything, `reveal_free_question` charges the daily credit,
  and `reveal_ad_question` reveals after a
  [`RewardedAdService`](lib/services/rewarded_ad_service.dart) ad — checking the
  3-per-day cap *before* anything is spent. The reward is captured
  authoritatively inside the service (decoupled from the ad-dismiss callback)
  and a live session is ensured before the RPC, so a watched ad never resolves
  to a generic error.
- **Premium.** RevenueCat handles billing; the paywall itself is in-app
  ([`ProPaywallSheet`](lib/features/monetization/widgets/pro_paywall_sheet.dart)) — packages
  and localized prices come live from the current RevenueCat offering, the
  purchase goes through `Purchases.purchase`. The `revenuecat-webhook` edge
  function reflects entitlement changes onto `profiles.is_premium` (the flag the
  RLS gate reads). Restore-purchases is reachable from Settings, the paywall
  sheet and the reveal-slot paywall (the latter two for guests, who can't open
  Settings).
- **Caching / offline.** In production the Supabase repository is wrapped in
  `CachingQuestionRepository`, scoped to the locale and the signed-in UUID, so
  reads survive a dropped network and PRO users can download the whole catalog
  for offline use. A lapsed subscription wipes the cached content.
