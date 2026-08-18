import 'package:debatly/core/locale/app_locale.dart';
import 'package:debatly/data/models/question.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/onboarding/screens/app_entry.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:debatly/features/questions/screens/question_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/localized_test_app.dart';
import 'support/test_prefs.dart';

/// [HomeGate] under the freemium model: EVERY resolved session lands on the
/// feed — a free user gets their daily (the day wall waits behind a swipe),
/// premium gets the catalog. There is no hard paywall screen anymore.
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

  testWidgets('a non-premium session lands on the feed with its daily — '
      'not on any wall', (tester) async {
    final (container, _) = await pumpGate(tester, session: guestSession());

    expect(find.byType(QuestionScreen), findsOneWidget);
    // The daily question is on screen, votable — the free tier's whole point.
    // (The wind view renders it word by word, so assert through the provider.)
    expect(container.read(currentQuestionProvider)?.id, 'daily');
  });

  testWidgets('a premium session lands on the feed', (tester) async {
    await pumpGate(tester, session: guestSession(isPremium: true));

    expect(find.byType(QuestionScreen), findsOneWidget);
  });

  testWidgets('a resolved free→premium flip keeps the feed '
      'and nudges the guest to save their PRO', (tester) async {
    final (_, session) = await pumpGate(tester, session: guestSession());
    expect(find.byType(QuestionScreen), findsOneWidget);

    session.emit(guestSession(isPremium: true));
    await tester.pumpAndSettle();

    expect(find.byType(QuestionScreen), findsOneWidget);
    // The guest save-your-PRO dialog fires from the gate.
    expect(find.text('PRO AKTYWNE 🎉'), findsOneWidget);
    await tester.tap(find.text('PÓŹNIEJ'));
    await tester.pumpAndSettle();
  });

  testWidgets('launching straight into a premium session never prompts', (
    tester,
  ) async {
    // An already-entitled guest opening the app: loading→premium must NOT be
    // read as a fresh purchase (it used to re-prompt on every launch).
    await pumpGate(tester, session: guestSession(isPremium: true));

    expect(find.text('PRO AKTYWNE 🎉'), findsNothing);
  });

  testWidgets('a session that failed to load offers a retry, not the feed', (
    tester,
  ) async {
    // An errored session resolves to "not premium", which would silently
    // reshape a paying user's feed over a transient failure — so the gate
    // surfaces the retry instead of guessing a tier.
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

    expect(find.byType(QuestionScreen), findsNothing);
    expect(find.text('SPRÓBUJ PONOWNIE'), findsOneWidget);
  });

  testWidgets('an entitlement lapse keeps the user on the feed '
      '(the deck reshapes; no wall screen appears)', (tester) async {
    final (container, session) = await pumpGate(
      tester,
      session: guestSession(isPremium: true),
    );
    expect(find.byType(QuestionScreen), findsOneWidget);

    session.emit(guestSession());
    await tester.pumpAndSettle();

    expect(find.byType(QuestionScreen), findsOneWidget);
    // Their daily is still there — the free tier's feed, not a dead end.
    expect(container.read(currentQuestionProvider)?.id, 'daily');
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
