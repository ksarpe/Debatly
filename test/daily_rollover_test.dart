import 'package:clock/clock.dart';
import 'package:debatly/data/models/question.dart';
import 'package:debatly/data/repositories/question_repository.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Local midnight, for a user who never closed the app.
///
/// The daily rolls over on the user's own wall clock, not on a restart, so a
/// session held across midnight has to notice on its own — otherwise yesterday's
/// question stays on screen, already voted, with no way to reach today's short
/// of killing the app. The rollover was entirely uncovered, which is awkward for
/// a mechanic whose whole job is to fire while nobody is looking.
class _CountingRepo extends MockQuestionRepository {
  int dailyFetches = 0;

  @override
  Future<Question?> fetchDailyQuestion(DateTime date) async {
    dailyFetches++;
    return super.fetchDailyQuestion(date);
  }
}

void main() {
  /// Pumps a widget that hands back its [WidgetRef], with the clock under the
  /// test's control so "tomorrow" is a decision rather than a wait.
  Future<({WidgetRef ref, ProviderContainer container, _CountingRepo repo})>
  pumpFeed(WidgetTester tester) async {
    final repo = _CountingRepo();
    final container = ProviderContainer(
      overrides: [
        // PRO: the free deck is a single question, so there is nowhere to
        // swipe to and nothing for the rollover to snap back FROM.
        sessionProvider.overrideWith(
          () => FakeSession(accountSession(isPremium: true)),
        ),
        questionRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);

    late WidgetRef captured;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              captured = ref;
              // Watching is what stamps the fetch day — the rollover check
              // compares that stamp against the wall clock.
              ref.watch(dailyFetchDayProvider);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    // The mock repo answers after a beat; drain it so the fetch counter means
    // "fetches that finished" rather than "fetches that were started".
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    return (ref: captured, container: container, repo: repo);
  }

  testWidgets('a session held across local midnight redraws the daily and '
      'snaps the reader home', (tester) async {
    var now = DateTime(2026, 8, 20, 23, 59);
    await withClock(Clock(() => now), () async {
      final feed = await pumpFeed(tester);
      final fetchesBefore = feed.repo.dailyFetches;

      // The user has swiped a few questions deep and is still reading.
      // Bumped directly rather than by swiping: the deck's length is the
      // catalog's business, and this test is about the clock.
      feed.container.read(furthestIndexProvider.notifier).bump(3);
      expect(feed.container.read(furthestIndexProvider), 3);

      now = DateTime(2026, 8, 21, 0, 1);
      maybeRolloverDaily(feed.ref);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(
        feed.repo.dailyFetches,
        greaterThan(fetchesBefore),
        reason: 'yesterday’s question is not today’s',
      );
      expect(
        feed.container.read(questionIndexProvider),
        0,
        reason: 'the new daily is what the user came back for',
      );
      // The debug counter, so a failure here says WHY.
      expect(feed.repo.dailyFetches, isNonZero);
      expect(
        feed.container.read(furthestIndexProvider),
        0,
        reason: '"back to latest" must not point into yesterday’s deck',
      );
    });
  });

  testWidgets('the same day is left alone — the reader keeps their place', (
    tester,
  ) async {
    var now = DateTime(2026, 8, 20, 9);
    await withClock(Clock(() => now), () async {
      final feed = await pumpFeed(tester);
      final fetchesBefore = feed.repo.dailyFetches;

      feed.container.read(furthestIndexProvider.notifier).bump(3);

      // Hours pass. Same day, so nothing about the deck has expired, and
      // yanking the user back to the daily mid-read would be the bug.
      now = DateTime(2026, 8, 20, 23, 58);
      maybeRolloverDaily(feed.ref);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(feed.repo.dailyFetches, fetchesBefore, reason: 'no refetch owed');
      expect(
        feed.container.read(furthestIndexProvider),
        3,
        reason: 'nothing about the deck has expired, so nothing is reset',
      );
    });
  });

  testWidgets('the rollover follows the LOCAL date, not a 24-hour timer', (
    tester,
  ) async {
    // Two hours apart, but on opposite sides of local midnight. A "+24h" rule
    // would see two hours and do nothing; the daily is a calendar day.
    var now = DateTime(2026, 8, 20, 23, 0);
    await withClock(Clock(() => now), () async {
      final feed = await pumpFeed(tester);
      final fetchesBefore = feed.repo.dailyFetches;

      now = DateTime(2026, 8, 21, 1, 0);
      maybeRolloverDaily(feed.ref);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(feed.repo.dailyFetches, greaterThan(fetchesBefore));
    });
  });
}
