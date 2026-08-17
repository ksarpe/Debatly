import 'package:debatly/core/locale/app_locale.dart';
import 'package:debatly/data/models/question.dart';
import 'package:debatly/data/models/user_stats.dart';
import 'package:debatly/data/models/vote_result.dart';
import 'package:debatly/data/repositories/question_repository.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/account/providers/stats_providers.dart';
import 'package:debatly/features/monetization/widgets/day_wall_view.dart';
import 'package:debatly/features/monetization/widgets/pro_paywall_sheet.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:debatly/features/questions/widgets/question_body.dart';
import 'package:debatly/features/questions/widgets/wind_question_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/localized_test_app.dart';
import 'support/test_prefs.dart';

/// The freemium day wall: a free user's forward swipe off the daily lands on
/// the wall (teaser + live countdown + streak + unlock CTA + a real "come
/// back tomorrow" exit) — and the paywall SHEET auto-opens at most once per
/// local day, only after today's daily has been voted on. The wall must never
/// be a trap: the exit button and a back swipe both return to the daily.
void main() {
  Question q(String id, [String? text]) => Question(
    id: id,
    category: id.toUpperCase(),
    questionText: text ?? 'Question $id?',
  );

  /// Pumps the feed body for a FREE session and returns the container.
  ///
  /// The wall runs a 1-second countdown timer, so tests use bounded [pump]s —
  /// pumpAndSettle would chase the ticking clock forever.
  Future<ProviderContainer> pumpFreeFeed(
    WidgetTester tester, {
    bool voted = true,
    int streak = 3,
  }) async {
    final daily = q('daily', 'Czy pytanie dnia jest darmowe?');
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await mockSharedPreferences(),
        ),
        sessionProvider.overrideWith(() => FakeSession(guestSession())),
        isPremiumProvider.overrideWithValue(false),
        questionsProvider.overrideWith((ref) async => const <Question>[]),
        todaysDailyQuestionProvider.overrideWith((ref) async => daily),
        deckShuffleSeedProvider.overrideWithValue(1),
        questionRepositoryProvider.overrideWithValue(_FreeRepo(voted: voted)),
        userStatsProvider.overrideWith(
          (ref) async => UserStats(
            currentStreak: streak,
            longestStreak: streak,
            rankTier: 0,
            rankName: 'Tester',
            nextRankStreak: 5,
          ),
        ),
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

  /// A forward (leftward) swipe on the feed, then enough bounded pumps for the
  /// wind-out animation, the wall mount and the (possible) sheet route.
  Future<void> swipeForward(WidgetTester tester) async {
    await tester.fling(
      find.byType(WindQuestionView),
      const Offset(-300, 0),
      1200,
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> pumpABit(WidgetTester tester, [int frames = 6]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  testWidgets('a free user swiping forward off the daily lands on the wall — '
      'teaser, countdown, streak, both CTAs', (tester) async {
    final container = await pumpFreeFeed(tester, voted: false);
    // The daily is on screen (the wind view renders it word by word, so
    // assert through the provider).
    expect(container.read(currentQuestionProvider)?.id, 'daily');
    expect(find.byType(DayWallView), findsNothing);

    await swipeForward(tester);

    expect(find.byType(DayWallView), findsOneWidget);
    // The blurred preview leads with the server's 4-word teaser.
    expect(find.textContaining('Czy cztery pierwsze słowa'), findsOneWidget);
    // Live countdown to local midnight and the streak at stake.
    expect(find.textContaining('Następne darmowe pytanie za'), findsOneWidget);
    expect(find.textContaining('Twoja seria: 3 dni'), findsOneWidget);
    // The fork: unlock, or a REAL tappable way back.
    expect(find.text('Nie czekaj — odblokuj wszystkie 500'), findsOneWidget);
    expect(find.text('albo wróć jutro'), findsOneWidget);
  });

  testWidgets('"albo wróć jutro" returns to the daily — the wall is not a '
      'trap', (tester) async {
    final container = await pumpFreeFeed(tester, voted: false);
    await swipeForward(tester);
    expect(find.byType(DayWallView), findsOneWidget);

    await tester.tap(find.text('albo wróć jutro'));
    await tester.pumpAndSettle();

    expect(find.byType(DayWallView), findsNothing);
    expect(find.byType(WindQuestionView), findsOneWidget);
    expect(container.read(currentQuestionProvider)?.id, 'daily');
  });

  testWidgets('after a vote, the first wall hit of the day auto-opens the '
      'sheet — later hits do not', (tester) async {
    await pumpFreeFeed(tester, voted: true);

    await swipeForward(tester);
    expect(find.byType(DayWallView), findsOneWidget);
    expect(
      find.byType(ProPaywallSheet),
      findsOneWidget,
      reason: 'first wall hit of the day + voted → the sheet opens itself',
    );

    // Dismiss it — the sheet is closable and lands the user back on the wall.
    await tester.tap(find.byIcon(Icons.close_rounded));
    await pumpABit(tester);
    expect(find.byType(ProPaywallSheet), findsNothing);
    expect(find.byType(DayWallView), findsOneWidget);

    // Back to the daily and forward again: the wall shows, the sheet stays
    // shut — once per local day means once.
    await tester.tap(find.text('albo wróć jutro'));
    await pumpABit(tester);
    await swipeForward(tester);
    expect(find.byType(DayWallView), findsOneWidget);
    expect(find.byType(ProPaywallSheet), findsNothing);
  });

  testWidgets('the sheet never auto-opens before the daily has been voted on', (
    tester,
  ) async {
    await pumpFreeFeed(tester, voted: false);

    await swipeForward(tester);

    expect(find.byType(DayWallView), findsOneWidget);
    expect(
      find.byType(ProPaywallSheet),
      findsNothing,
      reason: 'no paywall before the first vote of the day',
    );
    // The manual CTA still works, of course.
    await tester.tap(find.text('Nie czekaj — odblokuj wszystkie 500'));
    await pumpABit(tester);
    expect(find.byType(ProPaywallSheet), findsOneWidget);
  });

  testWidgets('a premium user swiping forward gets the next question, '
      'never the wall', (tester) async {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await mockSharedPreferences(),
        ),
        sessionProvider.overrideWith(
          () => FakeSession(guestSession(isPremium: true)),
        ),
        isPremiumProvider.overrideWithValue(true),
        questionsProvider.overrideWith(
          (ref) async => [q('a', 'Czy pytanie z katalogu?')],
        ),
        todaysDailyQuestionProvider.overrideWith(
          (ref) async => q('daily', 'Czy pytanie dnia jest darmowe?'),
        ),
        deckShuffleSeedProvider.overrideWithValue(1),
        questionRepositoryProvider.overrideWithValue(_FreeRepo(voted: false)),
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

    await swipeForward(tester);

    expect(find.byType(DayWallView), findsNothing);
    expect(container.read(questionIndexProvider), 1);
    expect(container.read(currentQuestionProvider)?.id, 'a');
  });
}

/// A mock repo whose vote state and wall teaser the tests control.
class _FreeRepo extends MockQuestionRepository {
  _FreeRepo({required this.voted});

  final bool voted;

  @override
  Future<VoteResult> getDailyVoteState(String questionId) async => voted
      ? const VoteResult(yesCount: 61, noCount: 39, myChoice: VoteResult.yes)
      : VoteResult.empty;

  @override
  Future<String?> peekNextQuestion({
    List<String> excludeIds = const [],
  }) async => 'Czy cztery pierwsze słowa';
}
