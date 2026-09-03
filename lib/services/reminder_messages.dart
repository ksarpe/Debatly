import 'dart:math';

import '../data/models/user_stats.dart';
import '../l10n/gen/app_localizations.dart';

/// A single reminder's text — what [NotificationService] bakes into one fire.
typedef ReminderMessage = ({String title, String body});

/// One drawn reminder plus whether the draw actually PICKED the teaser line.
///
/// The distinction is the whole point: the teaser is one weighted candidate in
/// the pool, so "a teaser was available" and "this fire carries the question"
/// are different claims — and the tap payload's `has_teaser` must make the
/// second one, or the teaser-vs-evergreen comparison it exists for is noise.
typedef ReminderDraw = ({String title, String body, bool usedTeaser});

/// The day-offset from which a slot is addressing someone who has drifted away
/// for good, rather than someone who missed a couple of days.
const int kReminderAwayDays = 12;

/// How many missed days cost one rank (mirrors the server's decay rule). A slot
/// firing before this many days of absence must not claim the rank is already
/// sliding — the threat isn't fact yet.
const int kRankDecayMissedDays = 3;

/// How far into the future a scheduled slot sits — and therefore how long the
/// user will have been absent by the time it fires.
///
/// Any launch, resume or vote re-arms the entire loop, cancelling every pending
/// slot. So a slot at day-offset N can only ever fire if the app has not been
/// opened for N days: **the horizon IS the absence**. That is what lets the far
/// slots stop pretending a streak is alive and start talking to someone who
/// left.
enum ReminderHorizon {
  /// Tonight. Everything is known: the vote, the split, the grace countdown.
  today,

  /// One missed day. The cached streak may well still stand — minus its exact
  /// number, which is already a day stale.
  tomorrow,

  /// Two to [kReminderAwayDays] missed days. The rank decay (one tier per three
  /// missed days) has started, and no claim about the streak is safe any more.
  drifting,

  /// Weeks gone. "Vote before everyone else does" reads absurd here — this is
  /// win-back, and it talks about the debate rather than the mechanics.
  away;

  static ReminderHorizon fromDayOffset(int dayOffset) => switch (dayOffset) {
    <= 0 => today,
    1 => tomorrow,
    < kReminderAwayDays => drifting,
    _ => away,
  };
}

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
/// [horizon] is the honesty budget. Only [ReminderHorizon.today] may use the
/// time-sensitive hooks (grace countdown, exact streak day) and the post-vote
/// branch; every step further out drops another claim the fire could no longer
/// stand behind, until [ReminderHorizon.away] talks only about the debate.
///
/// [teaser] is the first few words of the daily this slot fires ON — the only
/// hook here that is about the product rather than about the user's mechanics,
/// and the reason the whole calendar-read exists. It survives every horizon (a
/// question is a question whether you left yesterday or a month ago) but never
/// appears post-vote, where it would name the question just answered.
ReminderDraw buildReminderMessage({
  required AppLocalizations l10n,
  required UserStats? stats,
  required bool votedToday,
  required ReminderHorizon horizon,
  required Random random,
  int? disagreePct,
  String? teaser,
  // Whether, by the day this slot FIRES, the rank decay (one rank per
  // [kRankDecayMissedDays] missed days) has actually begun. The scheduler
  // derives it from the slot's day offset; defaults to false so the claim can
  // only be made when a caller vouches for it.
  bool rankDecayUnderway = false,
}) {
  final candidates = <ReminderMessage>[];
  ReminderMessage? teaserLine;

  /// The evergreen controversy nudges — always honest, so they backstop every
  /// horizon that still asks for a vote.
  void addEvergreen() {
    candidates
      ..add((title: l10n.notifNudgeTitle1, body: l10n.notifNudgeBody1))
      ..add((title: l10n.notifNudgeTitle2, body: l10n.notifNudgeBody2))
      ..add((title: l10n.notifNudgeTitle3, body: l10n.notifNudgeBody3));
  }

  /// The real question, in the user's hand before they open anything. Weighted
  /// but not certain: it's the strongest line we have, and it would still go
  /// stale as a habit if it were the only one they ever saw.
  void addTeaser() {
    final text = teaser?.trim();
    if (text == null || text.isEmpty) return;
    final line = (
      title: l10n.notifTeaserTitle(text),
      body: horizon == ReminderHorizon.away
          ? l10n.notifTeaserBodyAway
          : l10n.notifTeaserBody,
    );
    teaserLine = line;
    candidates
      ..add(line)
      ..add(line);
  }

  final streak = stats?.currentStreak ?? 0;

  if (horizon == ReminderHorizon.today && votedToday) {
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
    candidates
      ..add((title: l10n.notifResultTitle, body: l10n.notifResultBody))
      ..add((title: l10n.notifNextTitle, body: l10n.notifNextBody));
    if (streak > 0) {
      candidates.add((title: l10n.notifSafeTitle, body: l10n.notifSafeBody));
    }
  } else {
    switch (horizon) {
      case ReminderHorizon.today:
        // Full state known — sharpen the nudge with the highest-value hook.
        final grace = stats?.graceDaysLeft;
        if (grace != null && grace > 0) {
          final body = grace == 1
              ? l10n.notifGraceBodyTomorrow
              : l10n.notifGraceBodyDays(grace);
          final dropping = (title: l10n.notifGraceTitle, body: body);
          // Losing a rank is the most motivating hook — weight it heavily (but
          // not to certainty, so it stays unpredictable).
          candidates
            ..add(dropping)
            ..add(dropping)
            ..add(dropping);
        }
        if (streak > 0) {
          // The exact streak day is only honest here, where the cached number
          // still describes now — weight it, it's a strong hook.
          final keepAlive = (
            title: l10n.notifStreakTitle,
            body: l10n.notifStreakBody(streak),
          );
          candidates
            ..add(keepAlive)
            ..add(keepAlive);
        }
        addTeaser();
        addEvergreen();

      case ReminderHorizon.tomorrow:
        // One day out the streak habit is still the right lever, but the number
        // is not: baking today's count into a later fire is how someone whose
        // streak already broke gets told they're on "day 12".
        if (streak > 0) {
          candidates.add((
            title: l10n.notifStreakSoftTitle,
            body: l10n.notifStreakSoftBody,
          ));
        }
        addTeaser();
        addEvergreen();

      case ReminderHorizon.drifting:
        // Days of silence. The streak is past saving, so name the absence —
        // and only make the rank-slide claim once it is FACT: decay starts
        // after [kRankDecayMissedDays] missed days, and someone whose cached
        // streak was already zero had no rank progress to lose. Without both
        // gates a rank-less user gets told their rank is sliding on day two.
        candidates.add((
          title: l10n.notifDriftTitle1,
          body: l10n.notifDriftBody1,
        ));
        if (rankDecayUnderway && streak > 0) {
          candidates.add((
            title: l10n.notifDriftTitle2,
            body: l10n.notifDriftBody2,
          ));
        }
        addTeaser();
        addEvergreen();

      case ReminderHorizon.away:
        // Weeks gone: no mechanics left worth invoking, and "vote before
        // everyone else does" would be talking to a habit that no longer
        // exists. Only the debate itself is still a reason to come back.
        candidates
          ..add((title: l10n.notifAwayTitle1, body: l10n.notifAwayBody1))
          ..add((title: l10n.notifAwayTitle2, body: l10n.notifAwayBody2));
        addTeaser();
    }
  }

  // Safety net — should never be empty, but never schedule a blank notification.
  if (candidates.isEmpty) {
    return (
      title: l10n.notificationDailyTitle,
      body: l10n.notificationDailyBody,
      usedTeaser: false,
    );
  }
  final picked = candidates[random.nextInt(candidates.length)];
  // Record equality is by value, and the teaser line is unique by construction
  // (its title carries the question text) — so this is "did the draw land on
  // the teaser", not "was one available".
  return (
    title: picked.title,
    body: picked.body,
    usedTeaser: picked == teaserLine,
  );
}
