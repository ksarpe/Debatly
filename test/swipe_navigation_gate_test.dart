import 'package:debatly/core/locale/app_locale.dart';
import 'package:debatly/data/models/question.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:debatly/features/questions/widgets/wind_question_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/localized_test_app.dart';
import 'support/test_prefs.dart';

/// Navigation rules of the feed ([WindQuestionView._advance]) under the hard
/// paywall (only entitled sessions ever render the feed):
///   * forward walks the full catalog and wraps around — never walled,
///   * backward retraces the deck and is clamped at the daily (index 0).
void main() {
  Question q(String id) => Question(
    id: id,
    category: id.toUpperCase(),
    questionText: 'Question $id?',
  );

  Future<ProviderContainer> pumpFeed(
    WidgetTester tester, {
    required Question daily,
    List<Question> pool = const [],
  }) async {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await mockSharedPreferences(),
        ),
        questionsProvider.overrideWith((ref) async => pool),
        todaysDailyQuestionProvider.overrideWith((ref) async => daily),
        isPremiumProvider.overrideWithValue(true),
        deckShuffleSeedProvider.overrideWithValue(1),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const LocalizedTestApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                height: 600,
                child: WindQuestionView(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> swipe(WidgetTester tester, double dx) async {
    await tester.fling(find.byType(WindQuestionView), Offset(dx, 0), 1000);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
  }

  Future<void> swipeLeft(WidgetTester tester) => swipe(tester, -300);
  Future<void> swipeRight(WidgetTester tester) => swipe(tester, 300);

  testWidgets('forward swipes walk the catalog', (tester) async {
    final daily = q('daily');
    final container = await pumpFeed(
      tester,
      daily: daily,
      pool: [daily, q('a'), q('b')],
    );

    await swipeLeft(tester);
    expect(container.read(questionIndexProvider), 1);
    await swipeLeft(tester);
    expect(container.read(questionIndexProvider), 2);
  });

  testWidgets('forward wraps around at the end of the deck', (tester) async {
    final daily = q('daily');
    final container = await pumpFeed(
      tester,
      daily: daily,
      pool: [daily, q('a')],
    );

    await swipeLeft(tester);
    expect(container.read(questionIndexProvider), 1);
    // Off the last question the deck loops back to the daily.
    await swipeLeft(tester);
    expect(container.read(questionIndexProvider), 0);
  });

  testWidgets('back swipe retraces the deck and clamps at the daily', (
    tester,
  ) async {
    final daily = q('daily');
    final container = await pumpFeed(
      tester,
      daily: daily,
      pool: [daily, q('a'), q('b')],
    );

    await swipeLeft(tester);
    await swipeLeft(tester);
    expect(container.read(questionIndexProvider), 2);

    await swipeRight(tester);
    expect(container.read(questionIndexProvider), 1);
    await swipeRight(tester);
    expect(container.read(questionIndexProvider), 0);

    // At the daily there is nothing behind — the swipe bounces, never wraps.
    await swipeRight(tester);
    expect(container.read(questionIndexProvider), 0);
  });

  testWidgets('toLatest jumps back to the furthest question reached', (
    tester,
  ) async {
    final daily = q('daily');
    final container = await pumpFeed(
      tester,
      daily: daily,
      pool: [daily, q('a'), q('b')],
    );

    await swipeLeft(tester);
    await swipeLeft(tester);
    await swipeRight(tester);
    await swipeRight(tester);
    expect(container.read(questionIndexProvider), 0);
    expect(container.read(canJumpToLatestProvider), isTrue);

    container.read(questionIndexProvider.notifier).toLatest();
    expect(container.read(questionIndexProvider), 2);
  });
}
