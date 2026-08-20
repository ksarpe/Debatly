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

  /// Catalog ids that come back marked seen. The deck sorts unseen-before-seen,
  /// so which side of that line the OUTGOING and INCOMING dailies fall on is
  /// what decides whether the tail merely swaps one question for another or
  /// shifts wholesale under the reader.
  Set<String> seenIds = const {};

  @override
  Future<Question?> fetchDailyQuestion(DateTime date) async {
    dailyFetches++;
    return super.fetchDailyQuestion(date);
  }

  @override
  Future<List<Question>> fetchQuestions() async {
    final all = await super.fetchQuestions();
    return [for (final q in all) q.copyWith(seen: seenIds.contains(q.id))];
  }
}

void main() {
  /// Lets every in-flight mock fetch land. Twice over the repo's 300 ms beat,
  /// because the fetches chain: the catalog only STARTS once the session has
  /// resolved, and the rollover's redraw only starts once its invalidation has
  /// propagated — one pump leaves the deck a single question long.
  Future<void> drain(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  /// Pumps a widget that hands back its [WidgetRef], with the clock under the
  /// test's control so "tomorrow" is a decision rather than a wait.
  Future<({WidgetRef ref, ProviderContainer container, _CountingRepo repo})>
  pumpFeed(WidgetTester tester, {Set<String> seenIds = const {}}) async {
    final repo = _CountingRepo()..seenIds = seenIds;
    final container = ProviderContainer(
      overrides: [
        // PRO: the free deck is a single question, so there is nowhere to
        // swipe to and nothing for the rollover to snap back FROM.
        sessionProvider.overrideWith(
          () => FakeSession(accountSession(isPremium: true)),
        ),
        questionRepositoryProvider.overrideWithValue(repo),
        // A fixed seed so the tail order is the same on every run — otherwise
        // "the reader stayed on their question" would be a coin toss between
        // two shuffles.
        deckShuffleSeedProvider.overrideWithValue(7),
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
              // The feed's own watch, so the deck (and the pool behind it) is
              // built and drained by the pumps below — a rollover that lands
              // on an empty deck would prove nothing about where the reader
              // ends up.
              ref.watch(questionDeckProvider);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    // The mock repo answers after a beat; drain it so the fetch counter means
    // "fetches that finished" rather than "fetches that were started".
    await drain(tester);
    return (ref: captured, container: container, repo: repo);
  }

  testWidgets('a session held across local midnight redraws the daily but '
      'leaves a reader who is deep in the catalog exactly where they were', (
    tester,
  ) async {
    var now = DateTime(2026, 8, 20, 23, 59);
    await withClock(Clock(() => now), () async {
      // Half the catalog is archive. Today's daily is one of the seen ones and
      // tomorrow's is not, so when they trade places the unseen run shortens by
      // one and the whole seen half slides — the real shape of a rollover, and
      // the reason holding an INDEX is not the same as holding a question.
      final feed = await pumpFeed(tester, seenIds: const {'1', '3', '5'});
      final fetchesBefore = feed.repo.dailyFetches;
      final dailyBefore = feed.container
          .read(todaysDailyQuestionProvider)
          .value;

      // The user has swiped a few questions deep and is still reading.
      feed.container.read(questionIndexProvider.notifier).jumpTo(3);
      final reading = feed.container.read(currentQuestionProvider);
      expect(reading, isNotNull);
      expect(feed.container.read(furthestIndexProvider), 3);

      now = DateTime(2026, 8, 21, 0, 1);
      maybeRolloverDaily(feed.ref);
      await drain(tester);

      expect(
        feed.repo.dailyFetches,
        greaterThan(fetchesBefore),
        reason: 'yesterday’s question is not today’s',
      );
      expect(
        feed.container.read(todaysDailyQuestionProvider).value?.id,
        isNot(dailyBefore?.id),
        reason: 'the new day really did draw a different daily',
      );
      expect(
        feed.container.read(questionDeckProvider)[3].id,
        isNot(reading!.id),
        reason: 'the deck really did shift — otherwise this proves nothing',
      );
      // Which is why the reader is held by their QUESTION, not by their index.
      expect(
        feed.container.read(currentQuestionProvider)?.id,
        reading.id,
        reason:
            'the new daily is advertised by the jump link, not forced on '
            'someone mid-read',
      );
      expect(
        feed.container.read(furthestIndexProvider),
        greaterThanOrEqualTo(feed.container.read(questionIndexProvider)),
        reason: '"back to the latest" still reaches where they are standing',
      );
    });
  });

  testWidgets('a reader sitting on the daily is carried to the new one', (
    tester,
  ) async {
    var now = DateTime(2026, 8, 20, 23, 59);
    await withClock(Clock(() => now), () async {
      final feed = await pumpFeed(tester);
      // Index 0 — nobody is mid-read, so the whole point of opening the app
      // across midnight is the question that just landed.
      expect(feed.container.read(isShowingDailyProvider), isTrue);
      feed.container.read(furthestIndexProvider.notifier).bump(3);

      now = DateTime(2026, 8, 21, 0, 1);
      maybeRolloverDaily(feed.ref);
      await drain(tester);

      expect(feed.container.read(questionIndexProvider), 0);
      expect(feed.container.read(isShowingDailyProvider), isTrue);
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
      await drain(tester);

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
      await drain(tester);

      expect(feed.repo.dailyFetches, greaterThan(fetchesBefore));
    });
  });
}
