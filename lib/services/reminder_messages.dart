import 'dart:math';

import '../data/models/user_stats.dart';
import '../l10n/gen/app_localizations.dart';

/// A single reminder's text — what [NotificationService] bakes into one fire.
typedef ReminderMessage = ({String title, String body});

/// Picks the text for one daily-reminder fire from a pool, so the user can't
/// predict which nudge they'll get, and switches on local state so someone who
/// already voted today is teased about the outcome instead of told to "go vote".
///
/// Pure + synchronous by design: everything it needs — the streak / grace window
/// from the last cached [UserStats] sync, whether today's daily is already
/// voted, and the split the user landed on — is read by the caller straight from
/// SharedPreferences and passed in. That keeps selection unit-testable and the
/// scheduler free of l10n concerns, and matches the local-only model (the body
/// is baked at schedule time; nothing runs when the notification actually fires).
///
/// [isToday] marks the nearest fire (today's slot). Only it may use the
/// time-sensitive hooks (grace countdown, exact streak day) and the post-vote
/// branch — for future days in the loop we can't know the state yet, so they
/// fall back to the evergreen "come and vote" pool.
ReminderMessage buildReminderMessage({
  required AppLocalizations l10n,
  required UserStats? stats,
  required bool votedToday,
  required bool isToday,
  required Random random,
  int? disagreePct,
}) {
  final candidates = <ReminderMessage>[];

  if (votedToday) {
    // Already voted today — never nudge to vote. Tease the live outcome and the
    // next drop instead. In practice this branch only ever reaches PRO: a free
    // user who voted has an empty deck, so `rescheduleReminderLoop` drops their
    // slot outright rather than picking a message here.
    if (disagreePct != null && disagreePct > 0) {
      // The personalised "you were in the minority" hook is the strongest, so
      // weight it by adding it twice into the draw.
      final minority = (
        title: l10n.notifMinorityTitle,
        body: l10n.notifMinorityBody(disagreePct),
      );
      candidates
        ..add(minority)
        ..add(minority);
    }
    candidates.add((title: l10n.notifResultTitle, body: l10n.notifResultBody));
    candidates.add((title: l10n.notifNextTitle, body: l10n.notifNextBody));
    if ((stats?.currentStreak ?? 0) > 0) {
      candidates.add((title: l10n.notifSafeTitle, body: l10n.notifSafeBody));
    }
  } else {
    // Not voted (today's slot, or any future day) — nudge, sharpened by the
    // highest-value hook available.
    final grace = isToday ? stats?.graceDaysLeft : null;
    if (grace != null && grace > 0) {
      final body = grace == 1
          ? l10n.notifGraceBodyTomorrow
          : l10n.notifGraceBodyDays(grace);
      final dropping = (title: l10n.notifGraceTitle, body: body);
      // Losing a rank is the most motivating hook — weight it heavily (but not
      // to certainty, so it stays unpredictable).
      candidates
        ..add(dropping)
        ..add(dropping)
        ..add(dropping);
    }
    final streak = stats?.currentStreak ?? 0;
    if (streak > 0) {
      if (isToday) {
        // The exact streak day is only honest for the nearest fire, where the
        // cached number still describes now — weight it, it's a strong hook.
        final keepAlive = (
          title: l10n.notifStreakTitle,
          body: l10n.notifStreakBody(streak),
        );
        candidates
          ..add(keepAlive)
          ..add(keepAlive);
      } else {
        // A future day cannot know the streak survived. Baking today's number
        // into a fire three days out is how someone whose streak already broke
        // gets told they're on "day 12" — so the far slots keep the hook but
        // drop every claim about the streak's current state.
        candidates.add((
          title: l10n.notifStreakSoftTitle,
          body: l10n.notifStreakSoftBody,
        ));
      }
    }
    // Evergreen controversy nudges — always eligible, so there's always variety
    // even at streak 0 with an intact rank.
    candidates.add((title: l10n.notifNudgeTitle1, body: l10n.notifNudgeBody1));
    candidates.add((title: l10n.notifNudgeTitle2, body: l10n.notifNudgeBody2));
    candidates.add((title: l10n.notifNudgeTitle3, body: l10n.notifNudgeBody3));
  }

  // Safety net — should never be empty, but never schedule a blank notification.
  if (candidates.isEmpty) {
    return (
      title: l10n.notificationDailyTitle,
      body: l10n.notificationDailyBody,
    );
  }
  return candidates[random.nextInt(candidates.length)];
}
