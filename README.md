# Debatly

[![CI](https://github.com/ksarpe/questionapp/actions/workflows/ci.yml/badge.svg)](https://github.com/ksarpe/questionapp/actions/workflows/ci.yml)

A minimalist, modern mobile app designed to spark conversation. It shows a
single thought-provoking question as styled text, with a fast "wind" animation
when swiping to the next one.

> Only the GitHub repository is still named `questionapp` (the badge above
> points at it); the Dart package, application id and bundle
> id are all **debatly** / `com.aknsoftware.debatly`.

> **Shipping to the stores?** [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) is the
> single source of truth for every manual step left to do (Supabase function
> deploys, AdMob/consent console setup, keys, native config).

## Tech stack

| Concern            | Choice                                  |
| ------------------ | --------------------------------------- |
| Framework          | Flutter (Dart)                          |
| State management   | Riverpod (`flutter_riverpod`)           |
| Backend / Auth     | Supabase (`supabase_flutter`)           |
| Subscriptions      | RevenueCat (`purchases_flutter`)        |
| Ads                | Google AdMob (`google_mobile_ads`)      |
| Animation          | Custom `AnimatedBuilder` + `Transform`  |

## Project layout

```
lib/
├── main.dart                # Entry point — Sentry, SDK init, mounts ProviderScope
├── app.dart                 # MaterialApp: theme, locale, navigation root
├── core/                    # Cross-cutting concerns, no feature knowledge
│   ├── config/              # AppConfig — secrets via --dart-define
│   ├── feedback/            # AppToast (themed sonner overlay)
│   ├── locale/              # LocaleController + context.l10n extension
│   ├── monitoring/          # Monitoring facade over Sentry
│   ├── network/             # Connectivity providers + offline-error detection
│   ├── share/              # Widget-to-image capture for share cards
│   ├── theme/               # AppTheme + AppColors theme extension
│   └── widgets/             # Shared chrome (sub-screen scaffolds)
├── data/                    # Models + data access, no UI
│   ├── models/              # Question, Rank, UserStats, VoteResult, …
│   ├── mock/                # Seed questions (used when Supabase keys absent)
│   └── repositories/        # QuestionRepository + caching decorator
├── features/                # Feature-first: providers / screens / widgets each
│   ├── account/             # Auth, session, stats, rank/streak celebrations
│   ├── monetization/        # Paywall + entitlement providers
│   ├── onboarding/          # Splash → first-run tutorial → app entry
│   ├── questions/           # The home deck, voting, reveals, share, history
│   └── settings/            # Settings hub, favorites, privacy & data, about
├── l10n/                    # ARB source strings (en/pl) + generated delegates
└── services/                # SDK wrappers: Supabase, RevenueCat, AdMob,
                             # notifications, consent, reviews, caching
```

## The "wind" animation

`WindQuestionView` owns the transition. On a horizontal swipe the current text
accelerates off the left edge (fading, `easeInCubic`), then after a short beat
the next question flies in from the right and settles centre (`easeOutCubic`).
No cards, no flips — just text in motion. See
[wind_question_view.dart](lib/features/questions/widgets/wind_question_view.dart).

## Running

The app runs against mock data out of the box — every SDK no-ops gracefully when
its credentials are missing:

```bash
flutter pub get
flutter run
```

To enable the backends, pass keys at build time:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://xyz.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=... \
  --dart-define=REVENUECAT_API_KEY=... \
  --dart-define=ADMOB_BANNER_ID=ca-app-pub-.../... \
  --dart-define=ADMOB_REWARDED_ID=ca-app-pub-.../...
```

Or copy `env/example.json` to `env/local.json`, fill in the real values, and run:

```bash
flutter run --dart-define-from-file=env/local.json
```

Everything under `env/` except `example.json` is ignored by git, so real keys
stay local. Release builds use `env/prod-android.json` / `env/prod-ios.json`.

## Quality gates

CI ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) runs on every push
and PR. Run the same gates locally before pushing:

```bash
dart format .
flutter analyze
flutter test
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for conventions (architecture, l10n,
theming, migrations, commit style).

## Supabase questions

The app uses mock questions when Supabase credentials are missing. When
`SUPABASE_URL` and `SUPABASE_ANON_KEY` are provided, `QuestionRepository`
automatically switches to Supabase.

Initial setup:

1. Create a Supabase project.
2. Open SQL Editor in Supabase.
3. Run `supabase/schema.sql`.
4. Add question rows to `questions`.
5. Add daily schedule rows to `daily_questions` by linking `publish_date` to a
   `question_id`.
6. Run the app with `--dart-define-from-file=env/dev.json`.

The mobile app should only use the public anon key. Insert/update/delete access
should stay in Supabase Dashboard or a protected admin tool, never in the
released app.

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
- **Account deletion** is required by both stores. Settings → *Delete account*
  calls the `delete-account` edge function, which deletes the Supabase user
  (cascading to all their data). Deploy it before release.
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

## Auth & monetization

The app uses a *freemium with rewarded ads* model. Everything degrades
gracefully when SDK keys are absent, so it still runs against mock data.

- **Silent anonymous auth.** On launch `SessionNotifier`
  ([session_providers.dart](lib/features/account/providers/session_providers.dart))
  calls `SupabaseService.ensureSignedIn()`, which signs the user in anonymously
  if `currentUser` is null. Every guest gets a stable Supabase UUID — no email,
  no password — and that UUID is also passed to RevenueCat (`Purchases.logIn`)
  so entitlements follow the same identity.
- **The reveal feed.** Today's daily question is free for everyone. Beyond it
  the tiers diverge in `WindQuestionView`
  ([wind_question_view.dart](lib/features/questions/widgets/wind_question_view.dart)):
  *premium* walks the whole catalog (every question reads); a *free* user walks
  a forward feed — the daily, then the questions they reveal one at a time.
  Swiping past the last item lands on the **reveal slot**: a free user with the
  daily credit auto-reveals one new question (once per day), otherwise a paywall
  offers a rewarded ad or PRO. Revealed text is held in session memory only
  (`revealedFeedProvider`) — it is not re-readable after the app closes.
- **Server-mediated reveals.** Question text is gated by Supabase RLS, so the
  reveal goes through SECURITY DEFINER RPCs: `peek_next_question` teases the
  next pick, `reveal_free_question` charges the daily credit, and
  `reveal_ad_question` reveals after a [`RewardedAdService`](lib/services/rewarded_ad_service.dart)
  ad. The reward is captured authoritatively inside the service (decoupled from
  the ad-dismiss callback) and a live session is ensured before the RPC, so a
  watched ad never resolves to a generic error.
- **Premium.** RevenueCat handles billing; the paywall itself is in-app
  ([`ProPaywallSheet`](lib/features/monetization/widgets/pro_paywall_sheet.dart)) — packages
  and localized prices come live from the current RevenueCat offering, the
  purchase goes through `Purchases.purchase`. A Supabase edge function
  (`revenue-cat-webhook`) reflects entitlement changes onto `profiles.is_premium`
  (the flag the RLS gate reads). Restore-purchases is reachable from Settings,
  the paywall sheet and the reveal-slot paywall (the latter two for guests, who
  can't open Settings).
