// End-to-end smoke test: boot the real app widget tree and walk the core daily
// loop — splash → daily question → vote → settings — against the in-memory mock
// data, with no SDK keys.
//
// Why this lives here and not in test/: `flutter test` only scans test/, so this
// stays out of the unit suite (and CI) and is run on demand —
//   flutter test integration_test/app_smoke_test.dart
// It runs on the desktop host (flutter_tester) since nothing here touches a real
// platform channel, and on a connected device/emulator with `-d <device>`. See
// CONTRIBUTING.md → "Integration smoke test".
//
// It pumps the genuine [QuestionApp] (the same `home: AppEntry()` launch state
// machine `main()` boots) rather than a stubbed screen, so the splash timer, the
// AppEntry → QuestionScreen routing, the mock repository's simulated delays and
// the real gestures are all exercised. Two overrides keep it deterministic and
// hermetic:
//   * [sharedPreferencesProvider] — an in-memory store pinned to Polish with
//     onboarding marked complete, so AppEntry behaves like a returning user and
//     drops straight to the daily (no first-run tutorial) and the Polish strings
//     asserted below render regardless of the host device language;
//   * [sessionProvider] — a signed-in (free) account. Without SDK keys the real
//     session resolves to a GUEST, who can neither cast a daily vote (a tap opens
//     the sign-in sheet) nor reach the Settings hub (the gear is a "Zaloguj"
//     button instead). A fixed account session is the minimal seam that lets the
//     vote and settings legs run, exactly as the widget tests do; everything
//     downstream is the real tree backed by [MockQuestionRepository].
import 'package:debatly/app.dart';
import 'package:debatly/core/locale/app_locale.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/onboarding/providers/onboarding_providers.dart';
import 'package:debatly/features/questions/widgets/falling_words_text.dart';
import 'package:debatly/features/settings/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory SharedPreferences pinned to Polish, with onboarding already
/// complete so [AppEntry] routes the post-splash phase straight to the daily
/// (the first-run tutorial has its own coverage in test/widget_test.dart). The
/// pinned locale makes the Polish assertions below deterministic on any host.
Future<SharedPreferences> _mockPrefs() async {
  SharedPreferences.setMockInitialValues({
    kLocalePrefKey: 'pl',
    kOnboardingCompletePrefKey: true,
  });
  return SharedPreferences.getInstance();
}

/// Pumps past the launch splash so the routed-to daily is on screen. Driven by
/// fixed pumps rather than `pumpAndSettle` because the splash logo runs a looping
/// glow that never settles; once on the question screen the streak flame is still
/// (streak 0) so `pumpAndSettle` is safe again.
Future<void> _passSplash(WidgetTester tester) async {
  await tester.pump(); // first frame: the splash
  await tester.pump(const Duration(milliseconds: 2000)); // splash timer fires
  await tester.pump(const Duration(milliseconds: 500)); // phase cross-fade
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('daily loop: splash → daily question → vote → settings', (
    tester,
  ) async {
    final prefs = await _mockPrefs();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          // A signed-in free account so the vote casts and the Settings gear
          // shows (see file header for why a guest can't do either).
          sessionProvider.overrideWith(_FreeAccountSession.new),
        ],
        child: const QuestionApp(),
      ),
    );

    // 1. Pass the splash, then let the mock repository's simulated delays resolve
    //    so the daily question paints.
    await _passSplash(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    // 2. The daily question renders: the "Daily" pill marks it, and the question
    //    text is on the canvas (FallingWordsText holds the live string — it is
    //    assembled word-by-word, so we read the widget rather than the full text).
    expect(find.text('PYTANIE DNIA'), findsOneWidget);
    final daily = tester.widget<FallingWordsText>(
      find.byType(FallingWordsText),
    );
    expect(
      daily.text.trim(),
      isNotEmpty,
      reason: 'the daily question text should be rendered',
    );

    // 3. Cast a vote. Before voting the panel shows the TAK / NIE buttons; after,
    //    it animates to the community split (green % / red % with a "VS" seam and
    //    a check on the chosen side).
    expect(find.text('TAK'), findsOneWidget);
    expect(find.text('NIE'), findsOneWidget);
    expect(
      find.textContaining('%'),
      findsNothing,
      reason: 'no community split is shown before voting',
    );

    await tester.tap(find.text('TAK'));
    await tester.pumpAndSettle();

    expect(find.text('VS'), findsOneWidget);
    expect(
      find.textContaining('%'),
      findsWidgets,
      reason: 'the community split appears after voting',
    );
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    // 4. Open Settings from the top-right gear (shown only for an account).
    final settingsButton = find.byIcon(Icons.person_outline);
    expect(settingsButton, findsOneWidget);
    await tester.tap(settingsButton);
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('USTAWIENIA APLIKACJI'), findsOneWidget);
  });
}

/// A session pinned to a signed-in, non-premium account. Overriding [build]
/// skips the real notifier's Supabase / RevenueCat wiring (unavailable without
/// SDK keys) while keeping the provider type the UI watches — so `hasAccount` is
/// true (the vote casts, the Settings gear shows) and `isPremium` is false (the
/// free daily-only deck, the path most users are on).
class _FreeAccountSession extends SessionNotifier {
  @override
  Future<SessionState> build() async => SessionState(
    userId: 'smoke-test-user',
    email: 'smoke@example.com',
    isAnonymous: false,
    createdAt: DateTime.utc(2026, 1, 1),
  );
}
