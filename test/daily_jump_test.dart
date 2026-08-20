import 'package:debatly/core/locale/app_locale.dart';
import 'package:debatly/data/models/question.dart';
import 'package:debatly/data/repositories/question_repository.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:debatly/features/questions/widgets/daily_question_badge.dart';
import 'package:debatly/features/questions/widgets/question_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/localized_test_app.dart';
import 'support/test_prefs.dart';

/// The shared daily's feed affordances: the "PYTANIE DNIA" pill on the daily
/// card itself, and the bottom-of-feed jump link back to it whenever the user
/// (in practice PRO — a free deck is just the daily) is elsewhere in the
/// catalog. Tapping the link lands on deck index 0, where the pill takes over
/// and the link disappears.
void main() {
  Question q(String id) => Question(
    id: id,
    category: id.toUpperCase(),
    questionText: 'Question $id?',
  );

  Future<ProviderContainer> pumpFeed(
    WidgetTester tester, {
    required bool premium,
    List<Question> pool = const [],
  }) async {
    final daily = q('daily');
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await mockSharedPreferences(),
        ),
        sessionProvider.overrideWith(() => FakeSession(guestSession())),
        isPremiumProvider.overrideWithValue(premium),
        questionsProvider.overrideWith((ref) async => pool),
        todaysDailyQuestionProvider.overrideWith((ref) async => daily),
        deckShuffleSeedProvider.overrideWithValue(1),
        questionRepositoryProvider.overrideWithValue(MockQuestionRepository()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const LocalizedTestApp(home: Scaffold(body: QuestionBody())),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
    'the daily wears the pill and, being on it, offers no jump link',
    (tester) async {
      final container = await pumpFeed(
        tester,
        premium: true,
        pool: [q('a'), q('b')],
      );

      expect(container.read(questionIndexProvider), 0);
      expect(container.read(canJumpToDailyProvider), isFalse);
      expect(find.byType(DailyQuestionBadge), findsOneWidget);
      // Exactly one "PYTANIE DNIA" on screen: the pill, no link.
      expect(find.text('PYTANIE DNIA'), findsOneWidget);
    },
  );

  testWidgets('PRO mid-catalog gets the jump link; tapping it lands on the '
      'daily', (tester) async {
    final container = await pumpFeed(
      tester,
      premium: true,
      pool: [q('a'), q('b')],
    );

    container.read(questionIndexProvider.notifier).next();
    await tester.pumpAndSettle();

    expect(container.read(canJumpToDailyProvider), isTrue);
    // Away from the daily the pill is gone — the one "PYTANIE DNIA" is the link.
    expect(find.byType(DailyQuestionBadge), findsNothing);
    final link = find.text('PYTANIE DNIA');
    expect(link, findsOneWidget);

    await tester.tap(link);
    await tester.pumpAndSettle();

    expect(container.read(questionIndexProvider), 0);
    expect(container.read(canJumpToDailyProvider), isFalse);
    expect(find.byType(DailyQuestionBadge), findsOneWidget);
  });

  testWidgets('a free deck is the daily itself — pill on, link never', (
    tester,
  ) async {
    final container = await pumpFeed(tester, premium: false);

    expect(container.read(questionIndexProvider), 0);
    expect(container.read(canJumpToDailyProvider), isFalse);
    expect(find.byType(DailyQuestionBadge), findsOneWidget);
    expect(find.text('PYTANIE DNIA'), findsOneWidget);
  });
}
