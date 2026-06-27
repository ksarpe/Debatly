# Sentry — crash & error reporting setup

This app is wired for [Sentry](https://sentry.io) end to end, but ships **inert**:
with no `SENTRY_DSN` the SDK initialises in a disabled state and the whole app
runs exactly as before (mock data, no network calls to Sentry). Paste a DSN and
it lights up. This doc is the human-side setup: where the key goes, what to click
in the dashboard, and how to verify it.

> TL;DR: create a Flutter project in Sentry → copy its **DSN** → paste into
> `SENTRY_DSN` in `env/local.json` (dev) and `env/prod-android.json` /
> `env/prod-ios.json` (release) → run → trigger a test error → see it in **Issues**.

---

## 1. Create the project (Developer plan)

1. Sign in at <https://sentry.io>. Your **Developer** plan (free, 1 user) is plenty
   to start — it includes error monitoring, **tracing/performance**, **alerts**,
   **releases**, and a monthly events/spans quota.
2. **Create Project** → platform **Flutter** → give it a name (e.g. `debatly`).
3. Sentry shows you a code snippet — **ignore the code**, it's already written in
   this repo (`lib/main.dart` + `lib/core/monitoring/monitoring.dart`). You only
   need one value from it: the **DSN**.

### Where to find the DSN later

**Settings → Projects → _your project_ → Client Keys (DSN)**. It looks like:

```
https://<publicKey>@o<orgId>.ingest.de.sentry.io/<projectId>
```

The DSN is **not a password** — it only allows *sending* events, not reading
them — but we still keep it out of git like every other key.

---

## 2. Where the key goes

All secrets in this project are read from `--dart-define` via
`lib/core/config/app_config.dart`, and the run/build configs read them from the
git-ignored `env/*.json` files. Sentry follows the same pattern. Three keys:

| Key                         | What it does                                          | Default if unset            |
| --------------------------- | ----------------------------------------------------- | --------------------------- |
| `SENTRY_DSN`                | The project ingest URL. **Empty = Sentry disabled.**  | `''` (off)                  |
| `SENTRY_ENVIRONMENT`        | Label on every event to split dev vs prod.            | `development` debug / `production` release |
| `SENTRY_TRACES_SAMPLE_RATE` | Fraction (0.0–1.0) of transactions traced for perf.   | `0.2`                       |

Paste your DSN into the relevant file(s):

- **`env/local.json`** — your dev machine. Leave `SENTRY_DSN` empty to keep dev
  noise out of Sentry, or paste the DSN to test the integration. Already set to
  `SENTRY_ENVIRONMENT=development` and a `1.0` trace rate (trace everything in dev).
- **`env/prod-android.json`** and **`env/prod-ios.json`** — release builds. Paste
  the DSN here before you ship. Already set to `SENTRY_ENVIRONMENT=production`.

> `env/example.json` (the committed template) shows the shape with a fake DSN.
> The real `env/*.json` files are git-ignored — your DSN never lands in git.

Nothing else to change. The app reads these at build time.

---

## 3. Run / build with it

Exactly the existing commands — the keys are already in the env files:

```bash
# Dev (VS Code "questionapp (local env)" launch config already uses this file)
flutter run --dart-define-from-file=env/local.json

# Release
flutter build appbundle --dart-define-from-file=env/prod-android.json
flutter build ipa        --dart-define-from-file=env/prod-ios.json
```

On launch you'll see `Monitoring`/Sentry come up only when a DSN is present; with
an empty DSN it stays silent.

---

## 4. Verify it works (do this once)

Add a throwaway button somewhere visible (e.g. the Settings screen) and tap it:

```dart
import 'package:sentry_flutter/sentry_flutter.dart';
// ...
ElevatedButton(
  onPressed: () => throw StateError('Sentry test crash'),
  child: const Text('Throw test error'),
)
```

Run with a DSN set, tap it, then open **Issues** in Sentry — the error appears
within a few seconds, tagged with `environment`, the user's pseudonymous id, and
the `premium`/`guest` tags. Delete the button afterwards.

> Prefer not to add UI? From anywhere in the app you can call
> `Monitoring.captureException(StateError('test'), feature: 'manual-test');`
> The unhandled-throw path above is the better smoke test, though — it proves the
> global Flutter/zone handlers are armed.

---

## 5. Readable stack traces in release builds (recommended)

Release builds are tree-shaken/obfuscated, so raw crash traces are unreadable
numbers. Upload **debug symbols** so Sentry de-obfuscates them. This is a build
step, not app code — it never runs during a normal `flutter run`.

1. **Auth token** (different from the DSN): Sentry → **Settings → Auth Tokens** →
   create one with `project:releases` + `org:read` scope. Export it (and your org
   / project slugs) in the shell that runs the build — never commit it:

   ```bash
   export SENTRY_AUTH_TOKEN=sntrys_...
   export SENTRY_ORG=your-org-slug
   export SENTRY_PROJECT=debatly
   ```

2. Build with obfuscation + split debug info:

   ```bash
   flutter build appbundle --dart-define-from-file=env/prod-android.json \
     --obfuscate --split-debug-info=build/debug-info
   ```

3. Upload symbols + create the release in Sentry:

   ```bash
   dart run sentry_dart_plugin
   ```

The `sentry:` config block in `pubspec.yaml` tells the plugin where the debug
info lives. (If `sentry_dart_plugin` isn't in `dev_dependencies` yet, add it with
`flutter pub add --dev sentry_dart_plugin` — see the note at the bottom.)

---

## 6. What's already wired (the integration map)

You don't need to add capture calls for the common cases — these are live:

| Area                         | What's captured                                                            | Where |
| ---------------------------- | -------------------------------------------------------------------------- | ----- |
| **Uncaught Flutter errors**  | Every `FlutterError` (build/layout/paint) + widget errors                  | `SentryFlutter.init` in `lib/main.dart` |
| **Uncaught async / zone**    | Anything thrown outside a `try` during the whole app run, incl. SDK init   | `appRunner` in `lib/main.dart` |
| **Native crashes**           | Android/iOS native crashes (ANRs, signals)                                 | Sentry native layer (automatic) |
| **Auth failures**            | Guest sign-in failure (`ensureSignedIn`)                                   | `services/supabase_service.dart` |
| **Premium/entitlement**      | `sync-entitlement` + `fetchIsPremium` failures ("paid but free" class)     | `services/supabase_service.dart` |
| **Purchases (revenue)**      | RevenueCat configure / paywall / restore failures; paywall-result crumbs   | `services/purchases_service.dart` |
| **Rewarded ads**             | Load/show/SSV failures as **breadcrumbs** (no-fill is normal, not an issue)| `services/rewarded_ad_service.dart` |
| **Navigation**               | Screen-to-screen breadcrumbs + per-route performance transactions          | `SentryNavigatorObserver` in `lib/app.dart` |
| **User identity**            | Pseudonymous Supabase UUID + `premium`/`guest` tags on every event         | `features/account/providers/session_providers.dart` |

Everything funnels through **`lib/core/monitoring/monitoring.dart`** — the only
file that imports `sentry_flutter` (besides `main.dart`/`app.dart`). To report a
new error elsewhere:

```dart
import '../core/monitoring/monitoring.dart';

try {
  ...
} catch (e, st) {
  await Monitoring.captureException(e, stackTrace: st, feature: 'my-feature');
}

// or a low-cost trail entry for context:
Monitoring.addBreadcrumb('user did X', category: 'my-feature');
```

**Offline errors are filtered out** in `Monitoring` (and again in `beforeSend`),
so a user on a flaky connection never floods your quota — the app already handles
those as "offline" with a banner + cache fallback.

---

## 7. Dashboard features worth turning on

With the Developer plan you get these out of the box:

- **Issues** — your main inbox. Filter by the tags this app sets:
  `feature:purchases`, `premium:true`, `environment:production`, etc.
- **Alerts** (Settings → Alerts) — create a rule like *"a new issue in
  `environment:production`"* → email/Slack. The single highest-value thing to set
  up after the DSN.
- **Releases** — populated automatically when you do the symbol upload in §5
  (release = app version `1.0.0+1`). Lets you see "this crash started in build N"
  and tracks crash-free-session rate.
- **Performance / Tracing** — the `SentryNavigatorObserver` already feeds screen
  transactions; sampled at `SENTRY_TRACES_SAMPLE_RATE` (0.2 in prod). Watch slow
  screen loads here.
- **(Optional) Session Replay** — Sentry's mobile replay can record a redacted
  screen capture around a crash. It's off by default here for privacy/quota. To
  enable, set `options.replay.sessionSampleRate` / `onErrorSampleRate` in
  `Monitoring.configureOptions`. Recommended to leave off until you need it.

---

## 8. Privacy / store-compliance notes

- **No PII is sent.** `options.sendDefaultPii = false`, and we attach only the
  **pseudonymous Supabase UUID** as the user id — never email or name. Good for
  GDPR and the Play/App Store data-safety forms.
- If you list data collection in the store forms, Sentry counts as **"Crash logs
  / Diagnostics"** — not linked to identity beyond the random UUID.
- The DSN in the binary is fine to ship (send-only). The **auth token** from §5 is
  the real secret — keep it in CI env vars, never in the app or git.

---

## 9. Developer-plan quota tips

- Keep `SENTRY_ENVIRONMENT=development` locally (or an empty DSN) so dev runs don't
  eat your event budget.
- The offline filter already drops the noisiest non-bug errors.
- Lower `SENTRY_TRACES_SAMPLE_RATE` (e.g. `0.05`) in prod if performance units run
  low — error reporting is unaffected by it.

---

### Note: `sentry_dart_plugin` (symbol upload) is opt-in

The runtime SDK (`sentry_flutter`) is installed and wired. The **symbol-upload
plugin** (§5) is a separate dev-only tool. It's intentionally not required for the
app to build or report errors — add it only when you're ready to ship readable
release traces:

```bash
flutter pub add --dev sentry_dart_plugin
```

then add to `pubspec.yaml` (top level, not under `flutter:`):

```yaml
sentry:
  upload_debug_symbols: true
  upload_source_maps: false
  project: debatly          # your project slug
  org: your-org-slug
  # auth_token is read from the SENTRY_AUTH_TOKEN env var (don't hard-code it)
```
