import 'package:flutter/material.dart';
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
        // The launch flow: brand splash → first-run tutorial → the live daily.
        // After onboarding has run once, this drops straight through to the
        // question screen (see AppEntry).
        home: const AppEntry(),
      ),
    );
  }
}
