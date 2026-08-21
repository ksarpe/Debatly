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
    required ReminderHorizon horizon,
    UserStats? userStats,
    int? disagreePct,
    String? teaser,
  }) => {
    for (var seed = 0; seed < seeds; seed++)
      buildReminderMessage(
        l10n: l10n,
        stats: userStats,
        votedToday: votedToday,
        horizon: horizon,
        disagreePct: disagreePct,
        teaser: teaser,
        random: Random(seed),
      ).body,
  };

  /// Every distinct TITLE the builder can return — the teaser rides in the
  /// title, so the body-only helper can't see it.
  Set<String> titlesAcross(
    int seeds, {
    required bool votedToday,
    required ReminderHorizon horizon,
    UserStats? userStats,
    int? disagreePct,
    String? teaser,
  }) => {
    for (var seed = 0; seed < seeds; seed++)
      buildReminderMessage(
        l10n: l10n,
        stats: userStats,
        votedToday: votedToday,
        horizon: horizon,
        disagreePct: disagreePct,
        teaser: teaser,
        random: Random(seed),
      ).title,
  };

  group('not voted', () {
    test('streak 0, rank intact → only evergreen controversy nudges', () {
      final bodies = bodiesAcross(
        50,
        votedToday: false,
        horizon: ReminderHorizon.today,
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
        horizon: ReminderHorizon.today,
        userStats: stats(streak: 5, grace: 1),
      );
      expect(bodies, contains(l10n.notifGraceBodyTomorrow));
    });

    test('a running streak today → the exact-day keep-alive is reachable', () {
      final bodies = bodiesAcross(
        50,
        votedToday: false,
        horizon: ReminderHorizon.today,
        userStats: stats(streak: 7),
      );
      expect(bodies, contains(l10n.notifStreakBody(7)));
    });

    test('the tomorrow slot never uses the time-sensitive grace hook', () {
      // The scheduler can only know today's state, so a future day must fall back
      // to the evergreen pool rather than claim a stale countdown.
      final bodies = bodiesAcross(
        50,
        votedToday: false,
        horizon: ReminderHorizon.tomorrow,
        userStats: stats(streak: 5, grace: 1),
      );
      expect(bodies, isNot(contains(l10n.notifGraceBodyTomorrow)));
      expect(bodies, isNot(contains(l10n.notifGraceBodyDays(1))));
    });

    test('the tomorrow slot never bakes in the exact streak day', () {
      // The cached number describes today; by the time a far slot fires the
      // streak may be long broken, and "day 5 of your streak" would be a lie.
      final bodies = bodiesAcross(
        50,
        votedToday: false,
        horizon: ReminderHorizon.tomorrow,
        userStats: stats(streak: 5),
      );
      expect(bodies, isNot(contains(l10n.notifStreakBody(5))));
      expect(bodies, contains(l10n.notifStreakSoftBody));
    });

    test('the streak-free soft hook stays out of the streak-0 pool', () {
      final bodies = bodiesAcross(
        50,
        votedToday: false,
        horizon: ReminderHorizon.tomorrow,
        userStats: stats(),
      );
      expect(bodies, isNot(contains(l10n.notifStreakSoftBody)));
    });
  });

  group('drifting away', () {
    test('a drifting slot drops every streak claim, soft one included', () {
      // Two-plus days of silence: the rank decay has started and the streak is
      // past saving, so selling it would be selling something already lost.
      final bodies = bodiesAcross(
        50,
        votedToday: false,
        horizon: ReminderHorizon.drifting,
        userStats: stats(streak: 9, grace: 1),
      );
      expect(bodies, isNot(contains(l10n.notifStreakBody(9))));
      expect(bodies, isNot(contains(l10n.notifStreakSoftBody)));
      expect(bodies, isNot(contains(l10n.notifGraceBodyTomorrow)));
      expect(bodies, contains(l10n.notifDriftBody1));
    });

    test('a win-back slot talks only about the debate', () {
      // Weeks gone. "Vote before everyone else does" would be addressing a
      // habit that no longer exists, so the evergreen pool is out too.
      final bodies = bodiesAcross(
        50,
        votedToday: false,
        horizon: ReminderHorizon.away,
        userStats: stats(streak: 9, grace: 1),
      );
      expect(
        bodies,
        everyElement(isIn(<String>{l10n.notifAwayBody1, l10n.notifAwayBody2})),
      );
    });

    test('a voted-today stamp cannot leak into a later slot', () {
      // `votedToday` describes today only; a slot days out must ignore it
      // rather than tease the outcome of a vote that is long stale.
      for (final horizon in const [
        ReminderHorizon.tomorrow,
        ReminderHorizon.drifting,
        ReminderHorizon.away,
      ]) {
        final bodies = bodiesAcross(
          50,
          votedToday: true,
          horizon: horizon,
          userStats: stats(streak: 4),
          disagreePct: 63,
        );
        expect(
          bodies,
          isNot(contains(l10n.notifMinorityBody(63))),
          reason: '$horizon',
        );
        expect(
          bodies,
          isNot(contains(l10n.notifResultBody)),
          reason: '$horizon',
        );
      }
    });
  });

  group('the teaser', () {
    const teaser = 'Czy zdrada myslami to';

    test('reaches every horizon that still asks for a vote', () {
      // The one hook that is about the product rather than the user's
      // mechanics — it has to survive all the way out to win-back.
      for (final horizon in ReminderHorizon.values) {
        final titles = titlesAcross(
          60,
          votedToday: false,
          horizon: horizon,
          userStats: stats(streak: 4),
          teaser: teaser,
        );
        expect(
          titles,
          contains(l10n.notifTeaserTitle(teaser)),
          reason: '$horizon',
        );
      }
    });

    test('win-back gets its own body under the same question', () {
      final away = bodiesAcross(
        60,
        votedToday: false,
        horizon: ReminderHorizon.away,
        teaser: teaser,
      );
      final today = bodiesAcross(
        60,
        votedToday: false,
        horizon: ReminderHorizon.today,
        teaser: teaser,
      );
      expect(away, contains(l10n.notifTeaserBodyAway));
      expect(today, contains(l10n.notifTeaserBody));
      expect(today, isNot(contains(l10n.notifTeaserBodyAway)));
    });

    test('never names the question the user just answered', () {
      // Post-vote the teaser would be the daily they've already voted on.
      final titles = titlesAcross(
        60,
        votedToday: true,
        horizon: ReminderHorizon.today,
        userStats: stats(streak: 4),
        disagreePct: 61,
        teaser: teaser,
      );
      expect(titles, isNot(contains(l10n.notifTeaserTitle(teaser))));
    });

    test('a blank teaser is dropped rather than titled as an empty quote', () {
      // A gap date, a deactivated pick or a cache miss all arrive as nothing.
      for (final blank in <String?>[null, '', '   ']) {
        final titles = titlesAcross(
          40,
          votedToday: false,
          horizon: ReminderHorizon.today,
          userStats: stats(),
          teaser: blank,
        );
        expect(
          titles,
          isNot(contains(l10n.notifTeaserTitle(''))),
          reason: blank == null ? 'null' : '"$blank"',
        );
        expect(titles, isNotEmpty);
      }
    });

    test('does not crowd out the rest of the pool', () {
      // Weighted, not certain: a single line every single fire would go stale
      // as a habit just like the mechanics did.
      final titles = titlesAcross(
        60,
        votedToday: false,
        horizon: ReminderHorizon.today,
        userStats: stats(),
        teaser: teaser,
      );
      expect(titles.length, greaterThan(1));
    });
  });

  group('horizon mapping', () {
    test('offsets map onto the honesty budget the cadence assumes', () {
      expect(ReminderHorizon.fromDayOffset(0), ReminderHorizon.today);
      expect(ReminderHorizon.fromDayOffset(1), ReminderHorizon.tomorrow);
      expect(ReminderHorizon.fromDayOffset(2), ReminderHorizon.drifting);
      expect(ReminderHorizon.fromDayOffset(8), ReminderHorizon.drifting);
      expect(ReminderHorizon.fromDayOffset(12), ReminderHorizon.away);
      expect(ReminderHorizon.fromDayOffset(30), ReminderHorizon.away);
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
        horizon: ReminderHorizon.today,
        userStats: stats(streak: 9, grace: 1),
        disagreePct: 71,
      );
      expect(bodies.intersection(goVote), isEmpty);
    });

    test('with a known split → the "X% disagreed" line is reachable', () {
      final bodies = bodiesAcross(
        50,
        votedToday: true,
        horizon: ReminderHorizon.today,
        userStats: stats(streak: 3),
        disagreePct: 71,
      );
      expect(bodies, contains(l10n.notifMinorityBody(71)));
    });

    test('a unanimous split (0% disagreed) drops the minority line', () {
      final bodies = bodiesAcross(
        50,
        votedToday: true,
        horizon: ReminderHorizon.today,
        userStats: stats(streak: 3),
        disagreePct: 0,
      );
      expect(bodies, isNot(contains(l10n.notifMinorityBody(0))));
    });
  });
}
