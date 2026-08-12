import 'package:debatly/core/locale/app_locale.dart'
    show sharedPreferencesProvider;
import 'package:debatly/core/time/epoch_day.dart';
import 'package:debatly/data/models/rank.dart';
import 'package:debatly/data/models/user_stats.dart';
import 'package:debatly/data/repositories/question_repository.dart';
import 'package:debatly/features/account/providers/rank_celebration_providers.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_prefs.dart';

/// Guards for small, load-bearing contracts that have no natural home in the
/// feature suites — each one is a spot where two pieces of code (or two days,
/// or two identities) must agree, and a silent drift would not fail loudly.
void main() {
  group('dateOnlyKey', () {
    // ONE shared definition feeds both the `p_date` RPC params and the daily
    // cache key — these pin its exact shape so neither side can drift.
    test('formats as yyyy-MM-dd with zero-padding', () {
      expect(dateOnlyKey(DateTime(2026, 1, 5)), '2026-01-05');
      expect(dateOnlyKey(DateTime(2026, 12, 31)), '2026-12-31');
    });

    test('uses the calendar date, ignoring the time of day', () {
      expect(dateOnlyKey(DateTime(2026, 3, 7, 23, 59, 59)), '2026-03-07');
      expect(dateOnlyKey(DateTime(2026, 3, 7)), '2026-03-07');
    });
  });

  group('epochDay', () {
    test('anchors at the Unix epoch', () {
      expect(epochDay(DateTime.utc(1970, 1, 1)), 0);
      expect(epochDay(DateTime.utc(1970, 1, 2)), 1);
    });

    test('consecutive calendar days differ by exactly one, all year round', () {
      // The cooldowns subtract these indices; a DST hiccup that made two
      // neighbouring days differ by 0 or 2 would shorten/stretch a cooldown.
      final base = epochDay(DateTime(2026, 1, 1));
      for (var i = 1; i < 365; i++) {
        expect(
          epochDay(DateTime(2026, 1, 1 + i)),
          base + i,
          reason: 'day offset $i must be exactly $i days after Jan 1',
        );
      }
    });
  });

  group('SessionState.hasAccount', () {
    test('a guest (anonymous) has no account', () {
      const guest = SessionState(userId: 'u1', isAnonymous: true);
      expect(guest.isSignedIn, isTrue);
      expect(guest.hasAccount, isFalse);
    });

    test('a signed-in non-anonymous user has an account', () {
      const user = SessionState(userId: 'u1', isAnonymous: false);
      expect(user.hasAccount, isTrue);
    });

    test('no session — neither signed in nor an account', () {
      const none = SessionState();
      expect(none.isSignedIn, isFalse);
      expect(none.hasAccount, isFalse);
    });

    test(
      'mock mode (isAnonymous unknown/null) counts as having an account',
      () {
        // Documented on purpose: with no backend there is nothing to secure,
        // so the "secure your account" prompts must stay silent — hasAccount
        // true is what silences them.
        const mock = SessionState(userId: 'u1');
        expect(mock.isAnonymous, isNull);
        expect(mock.hasAccount, isTrue);
      },
    );
  });

  group('RankCelebrationController.evaluate', () {
    UserStats statsAtTier(int tier) => UserStats.fromJson({
      'current_streak': 10,
      'longest_streak': 10,
      'free_unlock_credits': 0,
      'rank_tier': tier,
      'rank_name': 'x',
    });

    Future<ProviderContainer> containerWithPrefs() async {
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await mockSharedPreferences(),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('seeds silently, then celebrates a genuine climb once', () async {
      final container = await containerWithPrefs();
      final controller = container.read(
        rankCelebrationControllerProvider.notifier,
      );

      // First observation only seeds the baseline.
      expect(await controller.evaluate(statsAtTier(3), kDefaultRanks), isNull);
      // The climb celebrates, exactly once.
      final rank = await controller.evaluate(statsAtTier(4), kDefaultRanks);
      expect(rank?.tier, 4);
      expect(await controller.evaluate(statsAtTier(4), kDefaultRanks), isNull);
    });

    test(
      'a promotion the ladder cannot name is held, not consumed invisibly',
      () async {
        final container = await containerWithPrefs();
        final controller = container.read(
          rankCelebrationControllerProvider.notifier,
        );
        await controller.evaluate(statsAtTier(3), kDefaultRanks); // seed

        // Stale/partial ladder without the new tier: no celebration NOW…
        final holed = kDefaultRanks.where((r) => r.tier != 4).toList();
        expect(await controller.evaluate(statsAtTier(4), holed), isNull);

        // …but the moment is not lost: once the full ladder loads, the same
        // promotion still fires.
        final rank = await controller.evaluate(statsAtTier(4), kDefaultRanks);
        expect(rank?.tier, 4, reason: 'the held promotion fires on retry');
      },
    );

    test('a freeze drop re-arms the celebration for the re-climb', () async {
      final container = await containerWithPrefs();
      final controller = container.read(
        rankCelebrationControllerProvider.notifier,
      );
      await controller.evaluate(statsAtTier(4), kDefaultRanks); // seed at 4

      // The freeze decays a rank: no celebration, baseline drops with it.
      expect(await controller.evaluate(statsAtTier(3), kDefaultRanks), isNull);
      // Recovering the lost rank celebrates again — the reward the freeze
      // mechanic sets up.
      final rank = await controller.evaluate(statsAtTier(4), kDefaultRanks);
      expect(rank?.tier, 4);
    });
  });

  group('MockQuestionRepository favorites isolation', () {
    // The mock favorites store must not leak state between repository
    // instances created by different tests (or locale switches).
    test('a fresh repository starts with no favorites', () async {
      final first = MockQuestionRepository();
      await first.toggleFavorite('q-leak');
      expect(await first.fetchFavoriteIds(), contains('q-leak'));

      final second = MockQuestionRepository();
      expect(await second.fetchFavoriteIds(), isEmpty);
    });
  });
}
