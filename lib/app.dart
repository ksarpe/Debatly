import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'core/layout/orientation_lock.dart';
import 'core/locale/app_locale.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/onboarding/screens/app_entry.dart';
import 'l10n/gen/app_localizations.dart';

/// Root widget. Riverpod's `ProviderScope` is mounted in `main()`.
class DebatlyApp extends ConsumerWidget {
  const DebatlyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The chosen app language drives the whole UI: setting `locale` explicitly
    // makes `Localizations.localeOf(context)` return it, so every widget that
    // branches on the locale follows the same source of truth as the question
    // content (see `questionRepositoryProvider`). Changing it rebuilds the app
    // into the new language.
    final locale = ref.watch(localeControllerProvider);

    // The chosen appearance (light / dark / follow-system) drives `themeMode`,
    // exactly as `locale` drives the language — a single persisted source of
    // truth, mutated from the settings screen (see `themeControllerProvider`).
    final themeMode = ref.watch(themeControllerProvider);

    // Phones stay in portrait; tablets keep every orientation. The feed simply
    // has no room for its chrome on a ~375pt-tall phone window, and the app has
    // been advertising landscape on iPhone without ever laying out for it.
    return OrientationLock(
      child: MaterialApp(
        title: 'Debatly',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: kSupportedLocales,
        // Feeds Sentry navigation breadcrumbs (which screen the user was on when
        // an error fired) and per-route performance transactions. Harmless when
        // Sentry is disabled — the observer just produces no-op events.
        navigatorObservers: [SentryNavigatorObserver()],
        // Baseline system-bar style for screens WITHOUT an AppBar (splash,
        // onboarding, the paywall dialog): the app draws edge-to-edge, so the
        // bars must be transparent with theme-matched icon brightness
        // everywhere, not only where an AppBar happens to annotate them. The
        // style lives on the AppBar theme (app_theme.dart) so both paths stay
        // identical; screens with an AppBar re-annotate with the same value.
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: Theme.of(context).appBarTheme.systemOverlayStyle!,
          child: child!,
        ),
        // The launch flow: brand splash → first-run tutorial → the live daily.
        // After onboarding has run once, this drops straight through to the
        // question screen (see AppEntry).
        home: const AppEntry(),
        // The app has exactly one route, so any name other than "/" is a deep
        // link the platform tried to route (a password-reset URI arrives as
        // "/?code=..."). Those are consumed by app_links inside
        // supabase_flutter, not by the Navigator — the engine's own deep-link
        // routing is switched off (AndroidManifest / Info.plist). This is the
        // last line of defence: without it an unroutable name is a FATAL
        // "could not find a generator for route", so send it to the one screen
        // the app has instead of crashing.
        onUnknownRoute: (_) =>
            MaterialPageRoute<void>(builder: (_) => const AppEntry()),
      ),
    );
  }
}
