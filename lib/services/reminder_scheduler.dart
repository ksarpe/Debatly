import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../features/settings/providers/reminder_providers.dart';
import '../l10n/gen/app_localizations.dart';
import 'notification_service.dart';
import 'question_cache.dart';
import 'reminder_messages.dart';

/// How many days ahead the reminder loop is pre-scheduled. A week gives the
/// "loop" real day-to-day variety even for a user who doesn't open the app for a
/// few days; it's recomputed on every launch / vote anyway, so the far days
/// rarely fire as baked.
const int kReminderLoopDays = 7;

/// How soon after a session today's reminder is considered redundant.
///
/// Every caller of [rescheduleReminderLoop] is an active session — a launch, a
/// vote, a settings change — so "now" IS the moment the user was last in the
/// app. A reminder landing inside this window would ping someone who put the
/// phone down an hour ago and already decided what to do with today's question.
const Duration kReminderQuietWindow = Duration(hours: 4);

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
    days: kReminderLoopDays,
    build: (dayOffset, isToday) {
      // Only today's slot can be silenced — a future day is a fresh daily that
      // nobody has spent yet.
      if (isToday && silenceToday) return null;
      return buildReminderMessage(
        l10n: l10n,
        stats: stats,
        // The vote state / split are only known for today; future days assume an
        // unvoted day and fall back to the "come and vote" pool.
        votedToday: isToday && votedToday,
        isToday: isToday,
        disagreePct: isToday ? disagreePct : null,
        random: random,
      );
    },
  );
}
