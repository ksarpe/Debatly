import 'package:debatly/core/locale/app_locale.dart';
import 'package:debatly/data/models/question.dart';
import 'package:debatly/data/repositories/question_repository.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:debatly/features/questions/screens/question_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/localized_test_app.dart';
import 'support/test_prefs.dart';

/// The identity listener on [QuestionScreen]: what happens to per-user state
/// when the signed-in identity changes. Two regressions live here:
///
///  * the initial null→guest resolution at launch must NOT invalidate anything
///    (the fetches already wait on the session; invalidating again was the
///    "double reload" that refetched everything and flashed the deck);
///  * a genuine identity SWITCH (guest→account, or sign-out onto a fresh
///    guest) must drop every per-user cache — revealed feed, deck position —
///    so the new user never inherits the previous user's feed or votes.
void main() {
  const guest = SessionState(userId: 'guest-1', isAnonymous: true);
  const account = SessionState(userId: 'user-2', isAnonymous: false);

  Question q(String id) => Question(
    id: id,
    category: id.toUpperCase(),
    questionText: 'Question $id?',
  );

  late int questionsFetches;
  late int dailyFetches;

  Future<(ProviderContainer, _MutableSession)> pumpHome(
    WidgetTester tester,
  ) async {
    questionsFetches = 0;
    dailyFetches = 0;
    final session = _MutableSession(guest);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await mockSharedPreferences(),
        ),
        sessionProvider.overrideWith(() => session),
        questionsProvider.overrideWith((ref) async {
          questionsFetches++;
          return const <Question>[];
        }),
        todaysDailyQuestionProvider.overrideWith((ref) async {
          dailyFetches++;
          return q('daily');
        }),
        questionRepositoryProvider.overrideWithValue(MockQuestionRepository()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const LocalizedTestApp(home: QuestionScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return (container, session);
  }

  testWidgets(
    'launch (null→guest) and a same-identity re-emission invalidate nothing',
    (tester) async {
      final (_, session) = await pumpHome(tester);

      // The session resolved null→guest during the pump; that transition must
      // not have re-triggered the fetches the launch already ran.
      expect(questionsFetches, 1);
      expect(dailyFetches, 1);

      // A refresh that lands on the SAME identity (e.g. entitlement reconcile)
      // is not an identity switch either.
      session.emit(guest.copyWith(isPremium: false));
      await tester.pumpAndSettle();

      expect(questionsFetches, 1, reason: 'same userId — no reload');
      expect(dailyFetches, 1);
    },
  );

  testWidgets('a genuine identity switch drops every per-user cache', (
    tester,
  ) async {
    final (container, session) = await pumpHome(tester);

    // Simulate a session that revealed a question and moved onto it.
    container.read(revealedFeedProvider.notifier).append(q('revealed-1'));
    container.read(questionIndexProvider.notifier).forwardLinear();
    await tester.pumpAndSettle();
    expect(container.read(questionIndexProvider), 1);
    expect(container.read(revealedFeedProvider), hasLength(1));

    // The guest signs into a real account (different UUID).
    session.emit(account);
    await tester.pumpAndSettle();

    expect(
      questionsFetches,
      2,
      reason: 'the catalog must be refetched for the new identity',
    );
    expect(dailyFetches, 2);
    expect(
      container.read(revealedFeedProvider),
      isEmpty,
      reason: 'the new user must not inherit the previous user\'s reveals',
    );
    expect(
      container.read(questionIndexProvider),
      0,
      reason: 'snapped back to the daily',
    );
  });

  testWidgets('signing out onto a fresh guest clears the account\'s feed', (
    tester,
  ) async {
    final (container, session) = await pumpHome(tester);

    // Move the session to a signed-in account first (this switch also clears).
    session.emit(account);
    await tester.pumpAndSettle();

    container.read(revealedFeedProvider.notifier).append(q('revealed-2'));
    container.read(questionIndexProvider.notifier).forwardLinear();
    await tester.pumpAndSettle();

    final fetchesBefore = questionsFetches;

    // Sign-out: the auth layer mints a fresh guest with a NEW uuid.
    session.emit(const SessionState(userId: 'guest-9', isAnonymous: true));
    await tester.pumpAndSettle();

    expect(questionsFetches, fetchesBefore + 1);
    expect(container.read(revealedFeedProvider), isEmpty);
    expect(container.read(questionIndexProvider), 0);
  });
}

/// A [SessionNotifier] whose state the test drives directly — no Supabase, no
/// RevenueCat, no auth subscriptions.
class _MutableSession extends SessionNotifier {
  _MutableSession(this._initial);

  final SessionState _initial;

  @override
  Future<SessionState> build() async => _initial;

  void emit(SessionState next) {
    state = AsyncValue.data(next);
  }
}
