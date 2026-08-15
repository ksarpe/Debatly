import 'package:debatly/app.dart';
import 'package:debatly/core/locale/app_locale.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/account/screens/auth_screen.dart';
import 'package:debatly/features/onboarding/providers/onboarding_providers.dart';
import 'package:debatly/features/onboarding/screens/onboarding_screen.dart';
import 'package:debatly/features/questions/widgets/go_deeper_button.dart';
import 'package:debatly/features/settings/screens/settings_screen.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/localized_test_app.dart';

/// The Polish label of the "go deeper" pill (was `GoDeeperButton.label` before
/// the string moved into the ARB localizations). Tests pin the locale to Polish
/// (see [_mockPrefs] / [LocalizedTestApp]), so this is what renders.
const _goDeeperLabelPl = 'WEJDŹ GŁĘBIEJ';

/// In-memory SharedPreferences pinned to Polish so [localeControllerProvider]
/// (read by DebatlyApp/SettingsScreen) resolves deterministically to `pl`
/// regardless of the host device locale — the assertions below are in Polish.
///
/// Onboarding is marked complete so `AppEntry` behaves like a returning user:
/// after the brief launch splash it drops straight to the daily rather than the
/// first-run tutorial (which has its own test below).
Future<SharedPreferences> _mockPrefs() async {
  SharedPreferences.setMockInitialValues({
    kLocalePrefKey: 'pl',
    kOnboardingCompletePrefKey: true,
  });
  return SharedPreferences.getInstance();
}

/// Pumps past the launch splash so the routed-to screen (the daily, or the
/// tutorial) is on screen. Driven by fixed pumps rather than `pumpAndSettle`
/// because the splash logo runs a looping glow that never settles.
Future<void> _passSplash(WidgetTester tester) async {
  await tester.pump(); // first frame: the splash
  await tester.pump(const Duration(milliseconds: 2000)); // splash timer fires
  await tester.pump(const Duration(milliseconds: 500)); // phase cross-fade
}

void main() {
  testWidgets('App renders the first question', (WidgetTester tester) async {
    final prefs = await _mockPrefs();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const DebatlyApp(),
      ),
    );

    // Returning user (onboarding complete): the splash gives way to the daily.
    await _passSplash(tester);

    // Let the mock repository's simulated delay resolve.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    // Mock mode resolves to a guest: the person icon opens the profile hub for
    // everyone now — there is no separate "Zaloguj" affordance in the top bar.
    // The streak chip shows for guests too (their streak rides the anonymous
    // identity) — muted at 0 before the first vote. The "go deeper" action is
    // still present.
    expect(find.text('Zaloguj'), findsNothing);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    expect(find.byIcon(Icons.local_fire_department_rounded), findsOneWidget);
    expect(find.text(_goDeeperLabelPl), findsOneWidget);

    // A guest's profile leads with the secure-account action right under the
    // guest-session header — signing in is a labelled fix, not a gate.
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    expect(find.text('Sesja gościa'), findsOneWidget);
    expect(find.text('Zabezpiecz konto'), findsOneWidget);
  });

  testWidgets('First launch shows onboarding; skip finishes it directly', (
    WidgetTester tester,
  ) async {
    // A brand-new install: no onboarding flag, so AppEntry runs the tutorial.
    SharedPreferences.setMockInitialValues({kLocalePrefKey: 'pl'});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const DebatlyApp(),
      ),
    );

    await _passSplash(tester);

    // The welcome card opens the deck, with a "Skip" affordance.
    expect(find.text('Myślisz, że znasz odpowiedź?'), findsOneWidget);
    expect(find.text('Pomiń'), findsOneWidget);

    // Skip ends the tutorial immediately — there is no account step anymore
    // (the session is anonymous by default; sign-in lives on the paywall).
    await tester.tap(find.text('Pomiń'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(prefs.getBool(kOnboardingCompletePrefKey), isTrue);
    expect(find.byType(OnboardingScreen), findsNothing);

    // Drain the daily's mock-load timers so the test ends without a pending one.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  });

  testWidgets('Auth screen renders when Supabase is not configured', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: LocalizedTestApp(home: AuthScreen())),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Brakuje konfiguracji Supabase. Uruchom aplikację z SUPABASE_URL i SUPABASE_ANON_KEY.',
      ),
      findsOneWidget,
    );
    expect(find.text('Zaloguj się'), findsOneWidget);
    // Tests report as Android, so the sheet offers Google (Apple is iOS-only).
    expect(find.text('Kontynuuj z Google'), findsOneWidget);
  });

  testWidgets('Auth sheet offers Apple (not Google) on iOS', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(
        const ProviderScope(child: LocalizedTestApp(home: AuthScreen())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Kontynuuj z Apple'), findsOneWidget);
      expect(find.text('Kontynuuj z Google'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Register tab shows the terms/privacy consent line', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: LocalizedTestApp(home: AuthScreen())),
    );
    await tester.pumpAndSettle();

    // Sign-in tab: no consent line (existing user, not creating an account).
    expect(
      find.text(
        'Kontynuując, akceptujesz Regulamin oraz Politykę prywatności.',
      ),
      findsNothing,
    );

    // Switch to the register tab — the consent line (one Text.rich with the
    // Terms + Privacy links) now renders.
    await tester.tap(find.text('ZAŁÓŻ KONTO'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Kontynuując, akceptujesz Regulamin oraz Politykę prywatności.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Auth sheet is sign-in only before PRO (no register tab)', (
    WidgetTester tester,
  ) async {
    // Registration is a post-purchase feature: a non-premium session (the hard
    // paywall's sign-in link) must not offer account creation at all.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith(() => FakeSession(guestSession())),
        ],
        child: const LocalizedTestApp(home: AuthScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ZAŁÓŻ KONTO'), findsNothing);
    expect(find.text('ZALOGUJ SIĘ'), findsNothing); // no tab bar at all
    expect(find.text('Zaloguj się'), findsOneWidget); // the sign-in CTA stays
    // Social sign-in stays available — existing Google users have no password.
    expect(find.text('Kontynuuj z Google'), findsOneWidget);
  });

  testWidgets('Settings screen renders the profile hub', (
    WidgetTester tester,
  ) async {
    final prefs = await _mockPrefs();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const LocalizedTestApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('USTAWIENIA APLIKACJI'), findsOneWidget);
    expect(find.text('KONTO'), findsOneWidget);
    expect(find.text('Przypomnienia'), findsOneWidget);
    // Mock mode resolves to a PREMIUM guest (the hard paywall would otherwise
    // wall off keyless development), so the account card shows the premium row
    // and the secure-account action leads the page.
    expect(find.text('Sesja gościa'), findsOneWidget);
    expect(find.text('Premium aktywne'), findsOneWidget);
    expect(find.text('Zabezpiecz konto'), findsOneWidget);
  });

  testWidgets('Premium user can open the Manage subscription sheet', (
    WidgetTester tester,
  ) async {
    final prefs = await _mockPrefs();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          // Force a signed-in, premium session so the account card shows the
          // "Premium active" row instead of the upsell.
          sessionProvider.overrideWith(_PremiumSessionNotifier.new),
        ],
        child: const LocalizedTestApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // The premium row replaces the "Go Premium" upsell.
    expect(find.text('Premium aktywne'), findsOneWidget);
    expect(find.text('Przejdź na Premium'), findsNothing);

    // Tapping it opens the manage-subscription sheet, which deep-links out to
    // the store rather than trying to cancel in-app. The row sits below the fold
    // on the test viewport, so scroll it into view first.
    await tester.ensureVisible(find.text('Premium aktywne'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Premium aktywne'));
    await tester.pumpAndSettle();

    // Sheet title + (RevenueCat unconfigured in tests, so the generic) manage
    // button both read "Zarządzaj subskrypcją".
    expect(find.text('Zarządzaj subskrypcją'), findsNWidgets(2));
    expect(find.text('Później'), findsOneWidget);
  });

  testWidgets('GoDeeperButton uses the requested label and tappable glow', (
    WidgetTester tester,
  ) async {
    var taps = 0;

    await tester.pumpWidget(
      LocalizedTestApp(
        home: Scaffold(
          body: Center(child: GoDeeperButton(onTap: () => taps++)),
        ),
      ),
    );

    expect(find.text(_goDeeperLabelPl), findsOneWidget);

    final buttonTopLeft = tester.getTopLeft(find.byType(GoDeeperButton));
    await tester.tapAt(buttonTopLeft + const Offset(2, 2));

    expect(taps, 1);
  });
}

/// A session pinned to a signed-in, premium account. Overriding [build] skips
/// the real notifier's Supabase/RevenueCat wiring (unavailable in tests) while
/// keeping the same provider type the UI watches.
class _PremiumSessionNotifier extends SessionNotifier {
  @override
  Future<SessionState> build() async => SessionState(
    userId: 'test-user',
    email: 'premium@example.com',
    isAnonymous: false,
    isPremium: true,
    createdAt: DateTime.utc(2026, 1, 1),
  );
}
