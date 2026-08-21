import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../features/settings/providers/reminder_providers.dart';
import '../l10n/gen/app_localizations.dart';
import 'notification_service.dart';
import 'question_cache.dart';
import 'reminder_messages.dart';

/// The day offsets the reminder loop is armed on, thinning out as it goes.
///
/// It used to be seven consecutive days, which got both ends wrong: someone
/// absent for a week caught a ping every single evening, and then the loop ran
/// out — since only a launch, resume or vote re-arms it, a user who stayed away
/// past day seven left the reminder system permanently, exactly the user worth
/// reaching. This cadence spends ten fires across a month instead of seven
/// across a week: dense while a habit is still recoverable, sparse once it is a
/// win-back, and never silent-by-accident.
///
/// Because every re-arm cancels the rest, a slot only fires after that many days
/// of real absence — see [ReminderHorizon], which reads the same offsets as the
/// honesty budget for what a fire is still allowed to claim.
const List<int> kReminderLoopOffsets = [0, 1, 2, 3, 5, 8, 12, 17, 23, 30];

/// How soon after a session today's reminder is considered redundant.
///
/// Every caller of [rescheduleReminderLoop] is an active session — a launch, a
/// vote, a settings change — so "now" IS the moment the user was last in the
/// app. A reminder landing inside this window would ping someone who put the
/// phone down an hour ago and already decided what to do with today's question.
const Duration kReminderQuietWindow = Duration(hours: 4);

/// The channel a slot at [horizon] belongs to.
///
/// Two channels, split by what the user actually opted into rather than by
/// message type: the everyday reminder they chose a time for, and the sparse
/// nudges that only fire once they've stopped showing up. Android lets them mute
/// the second without losing the first — the alternative was one bucket where
/// silencing a win-back ping also silenced the daily.
///
/// The split follows [ReminderHorizon] rather than the drawn message, so the
/// evening reminder always lands in the same place: a slot must not change
/// channel depending on which line the pool happened to pick.
ReminderChannel reminderChannelFor(
  ReminderHorizon horizon,
  AppLocalizations l10n,
) => switch (horizon) {
  ReminderHorizon.today || ReminderHorizon.tomorrow => ReminderChannel(
    id: 'daily_question',
    name: l10n.notifChannelDailyName,
    description: l10n.notifChannelDailyDescription,
    heightened: true,
  ),
  ReminderHorizon.drifting || ReminderHorizon.away => ReminderChannel(
    id: 'comeback',
    name: l10n.notifChannelComebackName,
    description: l10n.notifChannelComebackDescription,
    // Nobody asked to be chased. It waits in the shade instead of interrupting.
    heightened: false,
  ),
};

/// Whether today's slot should stay silent rather than carry a message.
///
/// Two reasons, both "the ping has nothing to offer":
///   * a FREE user who already voted today has an empty deck — the daily is the
///     whole free tier, so every remaining nudge would point at the day wall.
///     PRO keeps its post-vote nudge; the catalog is still there to open.
///   * the slot lands inside [kReminderQuietWindow] of this very session, i.e.
///     the user was just here and either voted or chose not to.
///
/// Pure and [now]-injected so the policy is testable without a clock. A slot
/// that already passed needs no decision here — the scheduler never arms it.
bool shouldSilenceTodaysReminder({
  required bool votedToday,
  required bool isPremium,
  required int hour,
  required int minute,
  required DateTime now,
}) {
  if (votedToday && !isPremium) return true;
  final slot = DateTime(now.year, now.month, now.day, hour, minute);
  return slot.isAfter(now) && slot.difference(now) < kReminderQuietWindow;
}

/// Rebuilds the whole reminder loop from local state, in [l10n]'s language.
/// No-ops when reminders are off.
///
/// Reads the inputs that drive the message choice straight from [prefs] — the
/// last cached [UserStats] sync (streak / grace window / entitlement) and whether
/// today's daily is already voted (with the split the user landed on) — so it
/// works without the provider graph and is safe to call from `main()`. Call it
/// anywhere that state may have changed: launch, after a daily vote, on enable,
/// on a time change, and on a language switch.
Future<void> rescheduleReminderLoop({
  required SharedPreferences prefs,
  required AppLocalizations l10n,
}) async {
  final reminder = ReminderPrefs.fromPrefs(prefs);
  if (!reminder.enabled) return;

  final stats = QuestionCache(prefs).readStats();
  final votedToday = hasVotedTodayLocal(prefs);
  final disagreePct = lastDisagreePctToday(prefs);
  // An unknown entitlement (never synced) counts as free: the cost of being
  // wrong is one PRO user missing one post-vote nudge, against spamming the far
  // larger free population on a day they've already spent.
  final silenceToday = shouldSilenceTodaysReminder(
    votedToday: votedToday,
    isPremium: stats?.isPremium ?? false,
    hour: reminder.hour,
    minute: reminder.minute,
    // Device-local, matching the loop's wall-clock slots (and the local-midnight
    // rollover the daily itself runs on).
    now: DateTime.now(),
  );
  final random = Random();

  await NotificationService.scheduleReminderLoop(
    hour: reminder.hour,
    minute: reminder.minute,
    dayOffsets: kReminderLoopOffsets,
    build: (dayOffset) {
      final horizon = ReminderHorizon.fromDayOffset(dayOffset);
      // Only today's slot can be silenced — a later one is a fresh daily that
      // nobody has spent yet.
      if (horizon == ReminderHorizon.today && silenceToday) return null;
      final message = buildReminderMessage(
        l10n: l10n,
        stats: stats,
        // The vote state and the split are only known for today; the builder
        // gates both on the horizon, so passing them raw is safe.
        votedToday: votedToday,
        horizon: horizon,
        disagreePct: disagreePct,
        random: random,
      );
      return (
        title: message.title,
        body: message.body,
        channel: reminderChannelFor(horizon, l10n),
      );
    },
  );
}
