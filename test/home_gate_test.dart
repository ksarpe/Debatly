import 'package:debatly/core/locale/app_locale.dart';
import 'package:debatly/data/models/question.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/monetization/screens/hard_paywall_screen.dart';
import 'package:debatly/features/onboarding/screens/app_entry.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:debatly/features/questions/screens/question_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/localized_test_app.dart';
import 'support/test_prefs.dart';

/// The hard-paywall gate in front of the feed ([HomeGate]): the app's content
/// is PRO-only, so the resolved session decides what "home" is.
void main() {
  Question q(String id) => Question(
    id: id,
    category: id.toUpperCase(),
    questionText: 'Question $id?',
  );

  Future<(ProviderContainer, _MutableSession)> pumpGate(
    WidgetTester tester, {
    required SessionState session,
  }) async {
    final mutable = _MutableSession(session);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await mockSharedPreferences(),
        ),
        sessionProvider.overrideWith(() => mutable),
        questionsProvider.overrideWith((ref) async => [q('a')]),
        todaysDailyQuestionProvider.overrideWith((ref) async => q('daily')),
        deckShuffleSeedProvider.overrideWithValue(1),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const LocalizedTestApp(home: HomeGate()),
      ),
    );
    await tester.pumpAndSettle();
    return (container, mutable);
  }

  testWidgets('a non-premium session lands on the hard paywall', (
    tester,
  ) async {
    await pumpGate(tester, session: guestSession());

    expect(find.byType(HardPaywallScreen), findsOneWidget);
    expect(find.byType(QuestionScreen), findsNothing);
    // The wall's offer can't load (RevenueCat unconfigured in tests) — it
    // shows the retry state, never a way through to the feed.
    expect(find.text('Zobacz, jak zagłosował cały świat'), findsOneWidget);
  });

  testWidgets('a premium session lands on the feed', (tester) async {
    await pumpGate(tester, session: guestSession(isPremium: true));

    expect(find.byType(QuestionScreen), findsOneWidget);
    expect(find.byType(HardPaywallScreen), findsNothing);
  });

  testWidgets('a resolved free→premium flip swaps the wall for the feed '
      'and nudges the guest to save their PRO', (tester) async {
    final (_, session) = await pumpGate(tester, session: guestSession());
    expect(find.byType(HardPaywallScreen), findsOneWidget);

    session.emit(guestSession(isPremium: true));
    await tester.pumpAndSettle();

    expect(find.byType(QuestionScreen), findsOneWidget);
    // The guest save-your-PRO dialog fires from the gate (the paywall itself
    // unmounted on the flip).
    expect(find.text('PRO aktywne 🎉'), findsOneWidget);
    await tester.tap(find.text('Później'));
    await tester.pumpAndSettle();
  });

  testWidgets('launching straight into a premium session never prompts', (
    tester,
  ) async {
    // An already-entitled guest opening the app: loading→premium must NOT be
    // read as a fresh purchase (it used to re-prompt on every launch).
    await pumpGate(tester, session: guestSession(isPremium: true));

    expect(find.text('PRO aktywne 🎉'), findsNothing);
  });

  testWidgets('a session that failed to load offers a retry, not the wall', (
    tester,
  ) async {
    // `isPremiumProvider` reads an errored session as "not premium", which
    // under a hard paywall means a transient failure shows a PAYING user the
    // wall — whose only affordance is buying the thing they already own.
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await mockSharedPreferences(),
        ),
        sessionProvider.overrideWith(_FailingSession.new),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const LocalizedTestApp(home: HomeGate()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HardPaywallScreen), findsNothing);
    expect(find.byType(QuestionScreen), findsNothing);
    expect(find.text('Spróbuj ponownie'), findsOneWidget);
  });

  testWidgets('an entitlement lapse swaps the feed back for the wall', (
    tester,
  ) async {
    final (_, session) = await pumpGate(
      tester,
      session: guestSession(isPremium: true),
    );
    expect(find.byType(QuestionScreen), findsOneWidget);

    session.emit(guestSession());
    await tester.pumpAndSettle();

    expect(find.byType(HardPaywallScreen), findsOneWidget);
    expect(find.byType(QuestionScreen), findsNothing);
  });
}

/// A [SessionNotifier] whose load never resolves to a state — the offline /
/// backend-down launch.
class _FailingSession extends SessionNotifier {
  @override
  Future<SessionState> build() async => throw StateError('no session');
}

/// A [SessionNotifier] whose state the test drives directly.
class _MutableSession extends SessionNotifier {
  _MutableSession(this._initial);

  final SessionState _initial;

  @override
  Future<SessionState> build() async => _initial;

  void emit(SessionState next) {
    state = AsyncValue.data(next);
  }
}
