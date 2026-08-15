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

Read this before changing anything in `features/questions`,
`features/account` or `features/monetization` — most wrong assumptions about
Debatly start here.

**Debatly is a hard-paywall app.** There is no free tier anymore: after
onboarding every non-PRO user lands on a full-screen paywall
(`HardPaywallScreen`) and stays there until they buy, restore, or sign in to
an account that already holds PRO. The feed, voting, streaks — all of it is
PRO-only. (The freemium reveal feed — daily credits, rewarded-ad reveals, the
"reveal slot" — was removed in the 2026-08 hard-paywall rebuild; its server
RPCs remain live only for old app versions.)

### The gate

`AppEntry` routes splash → onboarding (first run) → `HomeGate`. The gate
watches the resolved session:

- session still loading → spinner,
- `isPremium == false` → `HardPaywallScreen` (no way past it),
- `isPremium == true` → `QuestionScreen` (the feed).

The paywall never dismisses itself: a completed purchase/restore refreshes the
session, the entitlement flips, and the gate swaps the screen. The wall is
**identical for everyone**, signed in or not — there is no profile entry on
it. What it does offer, all in the sticky footer, is the two ways back to a
purchase already made: restore purchase (also a store requirement) and
"already have PRO? sign in", plus the terms/privacy links, which must not sit
behind a purchase.

### The account model: buy to play, sign in to secure

Identity and account are separate things, and only the identity gates content:

- **Every user gets an anonymous Supabase UUID at launch.** That is who they
  are; the entitlement rides on it. A guest can hold PRO indefinitely.
- **You buy PRO to play.** The purchase attaches to that anonymous identity —
  no account, no email, no sign-up in front of the paywall.
- **An account only SECURES a purchase that already happened.** It makes PRO
  (and the streak, votes, favorites) survive a reinstall or a new phone. It is
  pitched right after the buy (`promptSaveProAccount`) and offered again in
  Settings (`SecureAccountButton`).

The auth sheet enforces this: before PRO it is **sign-in only** — no register
tab, so no accounts are minted in front of the paywall. Signing in there means
"take me to the purchase I already made", which is why the link is shown to
signed-in users too (it is their only route to a *different*, entitled
account now that the wall has no profile entry).

Consequence worth knowing: an **account without PRO** is not a state the
product creates anymore. A handful of legacy ones exist from before the
rebuild; they hit the same wall as everyone else and can buy, restore, or
sign into another account — Settings is not reachable for them. Account
deletion for those users therefore has to go through the web link
(`DELETE_ACCOUNT_URL`, surfaced on the privacy policy page), not in-app.

Mock mode (no Supabase/RevenueCat keys) resolves the session as premium so
keyless development still lands on the feed.

### The feed (PRO)

Position 0 of the deck is **today's personal daily question**: drawn
server-side, per user, from the questions *that user has not voted on yet*,
preferring never-seen ones, stable for the rest of that local date. After it
comes the whole catalog, unseen-first, shuffled with a per-launch seed;
forward swipes wrap around.

- Every question is votable (TAK/NIE), once. The panel then shows the
  community split — an **all-time tally** for that question, not "today's
  result".
- The **streak** advances on *any* successful vote, at most once per UTC day.
  Missing days decay it by one rank per 3 missed days (a "freeze") instead of
  snapping to zero. Ranks are a static ladder keyed on streak length
  (0/3/7/14/30/60/100 days). The daily rolls over on the user's *local* date;
  the streak on *UTC* days — two clocks, on purpose.
- **Smaczki** are per-question discussion prompts served by
  `get_question_smaczki`; PRO reads them all. Favorites, the vote-history
  screen and the offline catalog download are PRO features too (their old
  free-tier upsell hooks remain as defence in depth for a lapsed entitlement
  mid-session).

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
| `question_seen` | Formerly `question_unlocks`. A row means "this user may read this question's text" (landed on in the feed; historically also free-tier reveals). |
| free unlock credit / reveal slot / ad reveals | **Legacy free-tier machinery.** Removed from the client in the hard-paywall rebuild; the RPCs (`reveal_free_question`, `reveal_ad_question`, `peek_next_question`) stay live server-side only for old app versions. |
| smaczki | Per-question arguments/prompts behind the "go deeper" button. |

### Edge functions

`supabase/functions/` holds the Deno functions: `revenuecat-webhook` (reflects
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
  ATT prompt were removed with the hard-paywall rebuild (no free tier → no
  rewarded ads); the AdMob app ids are gone from `AndroidManifest.xml` and
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

The app is **hard-paywall**: PRO or the wall. Everything still degrades
gracefully when SDK keys are absent — mock mode resolves as premium and runs
on local data.

- **Silent anonymous auth.** On launch `SessionNotifier`
  ([session_providers.dart](lib/features/account/providers/session_providers.dart))
  calls `SupabaseService.ensureSignedIn()`, which signs the user in anonymously
  if `currentUser` is null. Every guest gets a stable Supabase UUID — no email,
  no password — and that UUID is also passed to RevenueCat (`Purchases.logIn`)
  so entitlements follow the same identity. Signing up later upgrades the same
  identity in place, so the streak, votes and PRO survive. A guest who buys on
  the wall is nudged right after to attach the purchase to a real account.
- **Premium.** RevenueCat handles billing; both paywall surfaces share one
  content widget ([`ProPaywallContent`](lib/features/monetization/widgets/paywall_content.dart)):
  the full-screen [`HardPaywallScreen`](lib/features/monetization/screens/hard_paywall_screen.dart)
  (the home gate) and the modal [`ProPaywallSheet`](lib/features/monetization/widgets/pro_paywall_sheet.dart)
  (Settings + defensive upsell hooks). Packages and localized prices come live
  from the current RevenueCat offering; the purchase goes through
  `Purchases.purchase`. The `revenuecat-webhook` edge function reflects
  entitlement changes onto `profiles.is_premium` (the flag the RLS gate
  reads). Restore-purchases is reachable from Settings and from both paywalls
  (guests get a sign-in-first chooser so a store restore can't hijack an
  account-held entitlement).
- **Caching / offline.** In production the Supabase repository is wrapped in
  `CachingQuestionRepository`, scoped to the locale and the signed-in UUID, so
  reads survive a dropped network and PRO users can download the whole catalog
  for offline use. A lapsed subscription wipes the cached content.
