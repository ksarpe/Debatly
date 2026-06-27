# Release checklist

The app runs on mock data with no keys. A **store release** needs the manual,
outside-the-code steps below. This file is the single source of truth for
"things a human has to do in a console". Tick them off per platform before
submitting.

> Legend: 🔑 secret/key · ☁️ console · 📱 native file · ✅ already done

---

## ✅ Already done (don't redo)

- **App identity** — name **"Debatly"** on Android + iOS; launcher icons + splash
  generated from `assets/images/`.
- **AdMob App IDs** — real ids in both `AndroidManifest.xml` and iOS `Info.plist`.
- **Question content** — 126 questions, each EN + PL; daily calendar pre-filled
  through **2026-10-21**. (Top it up before then.)
- **Legal URLs** — baked into `AppConfig` → `https://debatly.app/{privacy,terms,delete-account}`,
  surfaced on the Privacy & data screen and the register consent line.
- **Sentry** — DSN wired in `env/prod-*.json`; Kotlin-2.0 override in
  `android/build.gradle.kts`. (Symbol upload + a test event still pending — see §8.)
- **Edge functions** — all four deployed (`revenuecat-webhook`, `admob-ssv`,
  `sync-entitlement`, `delete-account`).
- **Backend** — RLS on every table; consent (GDPR + ATT), local daily reminders,
  share, in-app review, account deletion all wired in code.

---

## 🔴 Blockers — must do before you can ship

### 1. Android signing 🔑
Without an upload keystore the release build is debug-signed and **Play rejects
it**.
- [ ] Generate the upload keystore (`keytool`) and create `android/key.properties`
      (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`). It's git-ignored;
      `build.gradle.kts` picks it up automatically.

### 2. RevenueCat ☁️🔑 (Premium)
`REVENUECAT_API_KEY` in `env/prod-android.json` is still the `goog_REPLACE_…`
placeholder.
- [ ] Create the entitlement (`premium`) + products (App Store + Play).
- [ ] Build the Paywall in the RevenueCat dashboard.
- [ ] Put the **public SDK key** in `env/prod-*.json` (`REVENUECAT_API_KEY`).
- [ ] Set the **secret REST key** + **webhook secret** as Supabase secrets
      (`REVENUECAT_REST_API_KEY`, `REVENUECAT_WEBHOOK_SECRET`) and point the
      webhook at the deployed `revenuecat-webhook` URL.

### 3. AdMob ☁️📱
- [ ] Create a real **banner unit** and replace the test id
      (`…3940256099942544/6300978111`) in `env/prod-*.json`. (Rewarded is real.)
- [ ] **SSV callback URL (required)** on the rewarded unit →
      `https://<project-ref>.functions.supabase.co/admob-ssv`. Without it, no free
      reveal-by-ad ever validates.
- [ ] Create a **GDPR consent message** (and an iOS **ATT** message) in the
      Privacy & messaging section — without them the consent form is blank.
- [ ] Paste Google's **full SKAdNetwork list** into iOS `Info.plist` (only one
      stub entry is there now): https://developers.google.com/admob/ios/3p-skadnetworks

### 4. Supabase Auth (dashboard toggles) ☁️
Can't be set by a migration.
- [ ] **Confirm email ON** (Providers → Email) — activates the anti-farm credit
      guard.
- [ ] **Leaked-password protection ON** (Sign In → Passwords) — still flagged by
      the security advisor.

### 5. Sign-in providers ☁️📱
- [ ] **Google** — create OAuth clients (Web → `GOOGLE_SERVER_CLIENT_ID`, iOS,
      Android+SHA-1); enable Google in Supabase Auth (Web client id in Authorized
      Client IDs).
- [ ] **Apple (iOS, required by App Store 4.8)** — enable *Sign in with Apple* on
      the App ID; add the capability in Xcode (wires `Runner.entitlements`); enable
      the Apple provider in Supabase with bundle id `com.aknsoftware.questionapp`.

### 6. Legal pages live ☁️
- [ ] Publish the actual pages at `https://debatly.app/{privacy,terms,delete-account}`.
- [ ] Paste the delete-account URL into the Play **Data safety** deletion field.

### 7. iOS build 📱
- [ ] `pod install` on a Mac (ATT + local-notifications plugins), then archive in
      Xcode.

### 8. Store submission ☁️
- [ ] Store listings: screenshots (use `tool/export_store_screenshots.dart`),
      descriptions, data-safety / privacy forms.
- [ ] (Recommended) Upload Sentry debug symbols (`SENTRY_AUTH_TOKEN`,
      `SENTRY_SETUP.md` §5) and verify a test event reaches the dashboard.

---

## Build & run

Secrets come from `--dart-define` (`lib/core/config/app_config.dart`). Copy
`env/example.json` → `env/local.json` (git-ignored), fill it, then:

```bash
flutter run   --dart-define-from-file=env/local.json
flutter build appbundle --dart-define-from-file=env/prod-android.json
flutter build ipa       --dart-define-from-file=env/prod-ios.json
```

| Key | For | Required |
| --- | --- | --- |
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` 🔑 | Backend / auth | Yes |
| `GOOGLE_SERVER_CLIENT_ID` 🔑 | Native Google sign-in | If Google login |
| `REVENUECAT_API_KEY` 🔑 | Subscriptions / paywall | If Premium |
| `ADMOB_BANNER_ID`, `ADMOB_REWARDED_ID` 🔑 | Ads | If ads |
| `SENTRY_DSN` 🔑 | Crash / error reporting | If monitoring |
| `PRIVACY_POLICY_URL`, `TERMS_OF_SERVICE_URL`, `DELETE_ACCOUNT_URL` | Legal links | Default to debatly.app ✅ |

Supabase secrets (server-side): `REVENUECAT_WEBHOOK_SECRET`,
`REVENUECAT_REST_API_KEY`, optional `PREMIUM_ENTITLEMENT` (default `premium`).

---

## Where it's wired

| Concern | Entry point |
| --- | --- |
| Secrets | `lib/core/config/app_config.dart` |
| Consent (GDPR + ATT) | `lib/services/consent_service.dart` |
| Account deletion | `supabase/functions/delete-account/` + `SupabaseService.deleteAccount` |
| Daily reminder | `lib/services/notification_service.dart` |
| In-app review | `lib/services/review_service.dart` + `review_providers.dart` |
| Premium gate | `sync-entitlement` / `revenuecat-webhook` + `profiles.is_premium` |
| Crash / error reporting | `lib/core/monitoring/monitoring.dart` + `SentryFlutter.init` in `main.dart` |
