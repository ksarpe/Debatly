import 'dart:math';

import 'package:debatly/data/models/user_stats.dart';
import 'package:debatly/l10n/gen/app_localizations.dart';
import 'package:debatly/services/reminder_messages.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The text the reminder loop produces is the retention payload, so we pin the
/// state-switching contract: a user who already voted is never told to go vote,
/// the time-sensitive hooks (rank decay, exact streak day) only appear on the
/// nearest fire, and the personalised "you were in the minority" line surfaces
/// when we know the split.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  UserStats stats({int streak = 0, int? grace, int? nextRank}) => UserStats(
    currentStreak: streak,
    longestStreak: streak,
    rankTier: 1,
    rankName: 'Provocateur',
    nextRankStreak: nextRank,
    graceDaysLeft: grace,
  );

  /// Every distinct body the builder can return across many random draws for the
  /// given inputs — lets a test assert what is (or isn't) ever reachable.
  Set<String> bodiesAcross(
    int seeds, {
    required bool votedToday,
    required bool isToday,
    UserStats? userStats,
    int? disagreePct,
  }) => {
    for (var seed = 0; seed < seeds; seed++)
      buildReminderMessage(
        l10n: l10n,
        stats: userStats,
        votedToday: votedToday,
        isToday: isToday,
        disagreePct: disagreePct,
        random: Random(seed),
      ).body,
  };

  group('not voted', () {
    test('streak 0, rank intact → only evergreen controversy nudges', () {
      final bodies = bodiesAcross(
        50,
        votedToday: false,
        isToday: true,
        userStats: stats(),
      );
      expect(
        bodies,
        everyElement(
          isIn(<String>{
            l10n.notifNudgeBody1,
            l10n.notifNudgeBody2,
            l10n.notifNudgeBody3,
          }),
        ),
      );
    });

    test('mid-grace today → the rank-decay warning is reachable', () {
      final bodies = bodiesAcross(
        50,
        votedToday: false,
        isToday: true,
        userStats: stats(streak: 5, grace: 1),
      );
      expect(bodies, contains(l10n.notifGraceBodyTomorrow));
    });

    test('a running streak today → the exact-day keep-alive is reachable', () {
      final bodies = bodiesAcross(
        50,
        votedToday: false,
        isToday: true,
        userStats: stats(streak: 7),
      );
      expect(bodies, contains(l10n.notifStreakBody(7)));
    });

    test('future-day slot never uses the time-sensitive grace hook', () {
      // The scheduler can only know today's state, so a future day must fall back
      // to the evergreen pool rather than claim a stale countdown.
      final bodies = bodiesAcross(
        50,
        votedToday: false,
        isToday: false,
        userStats: stats(streak: 5, grace: 1),
      );
      expect(bodies, isNot(contains(l10n.notifGraceBodyTomorrow)));
      expect(bodies, isNot(contains(l10n.notifGraceBodyDays(1))));
    });
  });

  group('voted today', () {
    test('never produces a "go vote" nudge', () {
      final goVote = <String>{
        l10n.notifNudgeBody1,
        l10n.notifNudgeBody2,
        l10n.notifNudgeBody3,
        l10n.notifStreakBody(9),
        l10n.notifGraceBodyTomorrow,
      };
      final bodies = bodiesAcross(
        100,
        votedToday: true,
        isToday: true,
        userStats: stats(streak: 9, grace: 1),
        disagreePct: 71,
      );
      expect(bodies.intersection(goVote), isEmpty);
    });

    test('with a known split → the "X% disagreed" line is reachable', () {
      final bodies = bodiesAcross(
        50,
        votedToday: true,
        isToday: true,
        userStats: stats(streak: 3),
        disagreePct: 71,
      );
      expect(bodies, contains(l10n.notifMinorityBody(71)));
    });

    test('a unanimous split (0% disagreed) drops the minority line', () {
      final bodies = bodiesAcross(
        50,
        votedToday: true,
        isToday: true,
        userStats: stats(streak: 3),
        disagreePct: 0,
      );
      expect(bodies, isNot(contains(l10n.notifMinorityBody(0))));
    });
  });
}
