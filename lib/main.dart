import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/locale/app_locale.dart';
import 'core/monitoring/monitoring.dart';
import 'core/startup/guarded_init.dart';
import 'features/settings/providers/reminder_providers.dart';
import 'l10n/gen/app_localizations.dart';
import 'services/analytics.dart';
import 'services/install_referrer_service.dart';
import 'services/notification_service.dart';
import 'services/purchases_service.dart';
import 'services/reminder_scheduler.dart';
import 'services/supabase_service.dart';

Future<void> main() async {
  await SentryFlutter.init(Monitoring.configureOptions, appRunner: _startApp);
}

/// Boots the app: persisted prefs, then external SDKs, then the widget tree.
/// Runs inside Sentry's guarded zone (see [main]).
///
/// The contract here is: **`runApp` MUST be reached.** A third-party SDK init
/// must never be able to keep the app stuck on the native splash. Two failure
/// modes have bitten release/R8 builds specifically — an unguarded exception
/// (which aborts the async chain before `runApp`) and, worse, a platform-channel
/// call whose native handler R8 stripped, so the `await` never returns at all.
/// A plain `try/catch` catches the first but NOT the second. So every init runs
/// through [guardedInit] (timeout + guard + Sentry report), and everything not
/// needed for the first frame is kicked off in the background after `runApp`.
Future<void> _startApp() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Resolve persisted preferences before the first frame so the chosen language
  // (or the device-detected one) is available synchronously to MaterialApp and
  // the question repository — no loading flash, no wrong-language first paint.
  // This is the one genuinely-required await: the ProviderScope override below
  // needs the instance. It's a first-party Flutter plugin (unlikely to be the
  // R8 casualty), so we let it run unguarded rather than fabricate a fake store.
  final prefs = await SharedPreferences.getInstance();

  // Resolve (or mint) the pseudonymous install id for product analytics —
  // synchronous, so it can't delay startup, and before the first screens so
  // even the earliest events (onboarding funnel) carry it.
  Analytics.init(prefs);

  // Initialise the SDKs the first screens actually read: Supabase backs the
  // question repository, RevenueCat gates premium. Guarded + bounded so a hang
  // or throw in either degrades that feature instead of walling the splash.
  await guardedInit('supabase', SupabaseService.initialise);
  await guardedInit('purchases', PurchasesService.initialise);

  // SentryWidget enables view-hierarchy/screenshot context and binds the app to
  // the SDK; it's a transparent passthrough when Sentry is disabled.
  runApp(
    SentryWidget(
      child: ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const DebatlyApp(),
      ),
    ),
  );

  // Everything below is irrelevant to the first frame, so it runs AFTER the UI
  // is on screen — the splash can never wait on it. Consent + AdMob are NOT
  // here any more: their bring-up (the app's only interrupting legal dialogs)
  // is deferred to the first home-screen entry so it can never land on top of
  // the onboarding funnel — see [AdsBootstrap] and [AppEntry].
  unawaited(_initBackgroundServices(prefs));
}

/// Non-blocking startup: SDKs and housekeeping that the UI doesn't need to
/// paint its first frame. Fired from [_startApp] after `runApp`.
Future<void> _initBackgroundServices(SharedPreferences prefs) async {
  await guardedInit('notifications', NotificationService.initialise);

  // Re-arm the daily reminder on every launch: schedules survive app restarts
  // but not necessarily a device reboot, and re-scheduling also refreshes the
  // notification text to the user's current language. Runs after the
  // notification plugin is up (it no-ops otherwise).
  await guardedInit('reminder', () => _rescheduleReminderIfEnabled(prefs));

  // One-shot install attribution: read the Play Install Referrer (utm_source
  // et al.) and log `install_attributed` to app_events. Deliberately NOT under
  // guardedInit — the insert legitimately needs the network and may outlive
  // kInitTimeout on a flaky first launch, which must not raise a bogus
  // StartupInitException. The service does its own bounding (platform-channel
  // read timeout, retry-next-launch on failure) and never throws.
  await InstallReferrerService.reportIfNeeded(prefs);
}

/// Re-schedules the daily reminder from persisted prefs, in the user's current
/// language. No-ops when the user hasn't enabled reminders. Mirrors the locale
/// resolution in [LocaleController] (saved choice → device language → fallback)
/// so the notification text matches what the UI will show.
Future<void> _rescheduleReminderIfEnabled(SharedPreferences prefs) async {
  final reminder = ReminderPrefs.fromPrefs(prefs);
  if (!reminder.enabled) return;

  final savedCode = prefs.getString(kLocalePrefKey);
  final deviceCode =
      WidgetsBinding.instance.platformDispatcher.locale.languageCode;
  final locale = kSupportedLocales.firstWhere(
    (l) => l.languageCode == savedCode,
    orElse: () => kSupportedLocales.firstWhere(
      (l) => l.languageCode == deviceCode,
      orElse: () => kFallbackLocale,
    ),
  );

  final l10n = await AppLocalizations.delegate.load(locale);
  await rescheduleReminderLoop(prefs: prefs, l10n: l10n);
}
