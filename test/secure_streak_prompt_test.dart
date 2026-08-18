import 'package:debatly/core/locale/app_locale.dart'
    show sharedPreferencesProvider;
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/account/widgets/secure_streak_prompt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/localized_test_app.dart';

/// The "secure your streak" account nudge for guests. What matters for release:
///   * the pure decision — account holders, short streaks and promotion days
///     never see it; a guest at the milestone does, then on a weekly cooldown;
///   * the dialog itself — showing it arms the cooldown even when dismissed,
///     and the CTA leads into the sign-in sheet.
void main() {
  group('shouldPromptToSecureStreak', () {
    test('a real account is never nudged — nothing left to secure', () {
      expect(
        shouldPromptToSecureStreak(
          hasAccount: true,
          streak: 10,
          isPromotionDay: false,
          lastPromptedDay: null,
          todayDay: 100,
        ),
        isFalse,
      );
    });

    test('below the milestone there is nothing worth protecting yet', () {
      expect(
        shouldPromptToSecureStreak(
          hasAccount: false,
          streak: kSecureStreakFirstMilestone - 1,
          isPromotionDay: false,
          lastPromptedDay: null,
          todayDay: 100,
        ),
        isFalse,
      );
    });

    test('a promotion day belongs to the rank-up celebration', () {
      expect(
        shouldPromptToSecureStreak(
          hasAccount: false,
          streak: kSecureStreakFirstMilestone,
          isPromotionDay: true,
          lastPromptedDay: null,
          todayDay: 100,
        ),
        isFalse,
      );
    });

    test('a guest at the milestone is nudged on the first eligible day', () {
      expect(
        shouldPromptToSecureStreak(
          hasAccount: false,
          streak: kSecureStreakFirstMilestone,
          isPromotionDay: false,
          lastPromptedDay: null,
          todayDay: 100,
        ),
        isTrue,
      );
    });

    test('after an ask, the weekly cooldown gates the next one', () {
      bool due(int daysSince) => shouldPromptToSecureStreak(
        hasAccount: false,
        streak: kSecureStreakFirstMilestone,
        isPromotionDay: false,
        lastPromptedDay: 100,
        todayDay: 100 + daysSince,
      );
      expect(due(0), isFalse, reason: 'same day: just asked');
      expect(due(kSecureStreakCooldownDays - 1), isFalse);
      expect(due(kSecureStreakCooldownDays), isTrue);
    });
  });

  group('maybePromptSecureStreak', () {
    Future<ProviderContainer> pumpTrigger(
      WidgetTester tester, {
      required SessionState session,
      required void Function(bool) onResult,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith(() => _FakeSession(session)),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);
      // Resolve the session up front: the prompt reads `.value`, which is null
      // until the AsyncNotifier's first build completes — in the app a vote
      // guarantees that, here we await it explicitly.
      await container.read(sessionProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: LocalizedTestApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => Center(
                  child: TextButton(
                    onPressed: () async {
                      onResult(
                        await maybePromptSecureStreak(
                          context,
                          ref,
                          streak: 4,
                          isPromotionDay: false,
                        ),
                      );
                    },
                    child: const Text('trigger'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('an eligible guest gets the dialog; the CTA opens sign-in', (
      tester,
    ) async {
      bool? shown;
      await pumpTrigger(
        tester,
        session: const SessionState(userId: 'anon', isAnonymous: true),
        onResult: (v) => shown = v,
      );

      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();

      expect(find.text('ZABEZPIECZ SWOJĄ PASSĘ 🔥'), findsOneWidget);
      // The body argues with the CONCRETE streak on the line.
      expect(find.textContaining('4-dniową'), findsOneWidget);

      await tester.tap(find.text('ZAŁÓŻ KONTO'));
      await tester.pumpAndSettle();

      // The sign-in sheet opened (its email/password fields are on screen).
      // The prompt call is still awaiting the sheet, so `shown` resolves only
      // once it closes.
      expect(find.byType(TextField), findsWidgets);
      final navigator = Navigator.of(
        tester.element(find.byType(TextField).first),
      );
      navigator.pop();
      await tester.pumpAndSettle();

      expect(shown, isTrue);
    });

    testWidgets('dismissing still arms the cooldown — no re-ask today', (
      tester,
    ) async {
      bool? shown;
      await pumpTrigger(
        tester,
        session: const SessionState(userId: 'anon', isAnonymous: true),
        onResult: (v) => shown = v,
      );

      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PÓŹNIEJ'));
      await tester.pumpAndSettle();
      expect(shown, isTrue);

      // Same day, second vote: the nudge stays quiet.
      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();
      expect(shown, isFalse);
      expect(find.text('ZABEZPIECZ SWOJĄ PASSĘ 🔥'), findsNothing);
    });

    testWidgets('an account holder is never interrupted', (tester) async {
      bool? shown;
      await pumpTrigger(
        tester,
        session: const SessionState(userId: 'u1', isAnonymous: false),
        onResult: (v) => shown = v,
      );

      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();

      expect(shown, isFalse);
      expect(find.text('ZABEZPIECZ SWOJĄ PASSĘ 🔥'), findsNothing);
    });
  });
}

/// A session fixed to a known identity, so the guest/account branch can be
/// exercised without touching Supabase.
class _FakeSession extends SessionNotifier {
  _FakeSession(this._state);

  final SessionState _state;

  @override
  Future<SessionState> build() async => _state;
}
