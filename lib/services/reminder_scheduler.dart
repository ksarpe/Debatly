import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/repositories/question_repository.dart' show dateOnlyKey;
import '../features/settings/providers/reminder_providers.dart';
import '../l10n/gen/app_localizations.dart';
import 'analytics.dart';
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

/// The everyday reminder the user picked a time for.
const String kDailyReminderChannelId = 'daily_question';

/// The sparse nudges that only fire once they've stopped showing up.
const String kComebackReminderChannelId = 'comeback';

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
    id: kDailyReminderChannelId,
    name: l10n.notifChannelDailyName,
    description: l10n.notifChannelDailyDescription,
    heightened: true,
  ),
  ReminderHorizon.drifting || ReminderHorizon.away => ReminderChannel(
    id: kComebackReminderChannelId,
    name: l10n.notifChannelComebackName,
    description: l10n.notifChannelComebackDescription,
    // Nobody asked to be chased. It waits in the shade instead of interrupting.
    heightened: false,
  ),
};

/// The teaser for the daily a slot at [dayOffset] fires ON, from a map keyed by
/// `yyyy-mm-dd` publish date.
///
/// Worth its own name because the off-by-one is invisible: a slot that reached
/// for today's teaser instead of its own would ship a loop where every reminder
/// names a question the user has already answered, and nothing would fail —
/// the copy would just be quietly wrong for a month. Null for a gap date, a
/// deactivated pick, or a horizon the cache hasn't reached.
String? teaserForOffset(
  Map<String, String> teasers,
  DateTime from,
  int dayOffset,
) {
  // Date arithmetic on the calendar day, not on 24h spans: adding a Duration
  // across a DST boundary can land on the wrong date.
  final day = DateTime(from.year, from.month, from.day + dayOffset);
  final teaser = teasers[dateOnlyKey(day)]?.trim();
  return (teaser == null || teaser.isEmpty) ? null : teaser;
}

/// Why today's slot stayed silent — null when it fires.
///
/// A reason rather than a bool because this is the one decision that can make
/// the whole feature disappear: if it starts returning a value it shouldn't,
/// nobody gets a reminder and nothing errors. Reported on `reminder_scheduled`,
/// so a silence spike is visible instead of being mistaken for good behaviour.
enum ReminderSilence {
  /// A FREE user who already voted has an empty deck — the daily is the whole
  /// free tier, so every remaining nudge would point at the day wall.
  votedFree,

  /// The slot lands inside [kReminderQuietWindow] of this very session: the
  /// user was just here and either voted or chose not to.
  quietWindow,
}

/// Whether today's slot should stay silent rather than carry a message, and why.
///
/// PRO keeps its post-vote nudge — the catalog is still there to open — so the
/// [ReminderSilence.votedFree] rule deliberately doesn't apply to it.
///
/// Pure and [now]-injected so the policy is testable without a clock. A slot
/// that already passed needs no decision here — the scheduler never arms it.
ReminderSilence? todaysReminderSilence({
  required bool votedToday,
  required bool isPremium,
  required int hour,
  required int minute,
  required DateTime now,
}) {
  if (votedToday && !isPremium) return ReminderSilence.votedFree;
  final slot = DateTime(now.year, now.month, now.day, hour, minute);
  if (slot.isAfter(now) && slot.difference(now) < kReminderQuietWindow) {
    return ReminderSilence.quietWindow;
  }
  return null;
}

/// What a scheduled reminder carries about itself, so a tap can be attributed
/// to the slot that produced it.
///
/// Deliberately tiny and schema-less: it is written into the OS days before it
/// is read back, possibly by a LATER app version, so it must survive being
/// parsed by code that doesn't recognise it. Anything unreadable decodes to an
/// empty map rather than throwing — a mis-parsed payload must never cost the
/// user the tap they just made.
String encodeReminderPayload({
  required ReminderHorizon horizon,
  required int dayOffset,
  required bool hasTeaser,
}) => jsonEncode({'h': horizon.name, 'o': dayOffset, 't': hasTeaser});

/// The analytics properties for a tapped reminder, from [encodeReminderPayload].
/// Empty for a null, malformed or foreign payload.
Map<String, Object?> decodeReminderPayload(String? payload) {
  if (payload == null || payload.isEmpty) return const {};
  try {
    final decoded = jsonDecode(payload);
    if (decoded is! Map) return const {};
    return {
      if (decoded['h'] case final String horizon) 'horizon': horizon,
      if (decoded['o'] case final int offset) 'day_offset': offset,
      if (decoded['t'] case final bool teaser) 'has_teaser': teaser,
    };
  } catch (_) {
    return const {};
  }
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

  final cache = QuestionCache(prefs);
  final stats = cache.readStats();
  // Teasers for the coming dailies, keyed by local date. Cache-only on purpose:
  // this runs from `main()` before the provider graph and must work offline, so
  // keeping the map fresh is the repository's job (see the caching decorator).
  // An empty map is a normal state — every horizon falls back to its own pool.
  final teasers = cache.readDailyTeasers(l10n.localeName);
  final today = DateTime.now();
  final votedToday = hasVotedTodayLocal(prefs);
  final disagreePct = lastDisagreePctToday(prefs);
  // An unknown entitlement (never synced) counts as free: the cost of being
  // wrong is one PRO user missing one post-vote nudge, against spamming the far
  // larger free population on a day they've already spent.
  final silence = todaysReminderSilence(
    votedToday: votedToday,
    isPremium: stats?.isPremium ?? false,
    hour: reminder.hour,
    minute: reminder.minute,
    // Device-local, matching the loop's wall-clock slots (and the local-midnight
    // rollover the daily itself runs on).
    now: today,
  );
  final random = Random();
  var withTeaser = 0;

  final armed = await NotificationService.scheduleReminderLoop(
    hour: reminder.hour,
    minute: reminder.minute,
    dayOffsets: kReminderLoopOffsets,
    build: (dayOffset) {
      final horizon = ReminderHorizon.fromDayOffset(dayOffset);
      // Only today's slot can be silenced — a later one is a fresh daily that
      // nobody has spent yet.
      if (horizon == ReminderHorizon.today && silence != null) return null;
      // The daily this slot actually fires ON, not today's — offset N lands on
      // day N, where day N's pick is the question in the feed.
      final teaser = teaserForOffset(teasers, today, dayOffset);
      if (teaser != null) withTeaser++;
      final message = buildReminderMessage(
        l10n: l10n,
        stats: stats,
        // The vote state and the split are only known for today; the builder
        // gates both on the horizon, so passing them raw is safe.
        votedToday: votedToday,
        horizon: horizon,
        disagreePct: disagreePct,
        teaser: teaser,
        random: random,
      );
      return (
        title: message.title,
        body: message.body,
        channel: reminderChannelFor(horizon, l10n),
        payload: encodeReminderPayload(
          horizon: horizon,
          dayOffset: dayOffset,
          hasTeaser: teaser != null,
        ),
      );
    },
  );

  await _reportSchedule(
    prefs: prefs,
    armed: armed,
    withTeaser: withTeaser,
    silence: silence,
    reminder: reminder,
  );
}

/// SharedPreferences key holding the local date of the last `reminder_scheduled`
/// report, so a chatty session doesn't insert one per resume.
const String _kLastScheduleReportKey = 'reminder_last_schedule_report';

/// Reports the SHAPE of the loop we just armed — at most once per local day.
///
/// Throttled because the loop is re-armed on every launch, resume and vote; one
/// row per re-arm would drown `app_events` in a signal that changes maybe once
/// a day. Once a day is enough to answer the questions that matter: is anyone
/// getting reminders at all, how often is the silence rule firing, how much of
/// the loop actually carries a question, and did they mute a channel.
Future<void> _reportSchedule({
  required SharedPreferences prefs,
  required int armed,
  required int withTeaser,
  required ReminderSilence? silence,
  required ReminderPrefs reminder,
}) async {
  final now = DateTime.now();
  final month = now.month.toString().padLeft(2, '0');
  final day = now.day.toString().padLeft(2, '0');
  final stamp = '${now.year}-$month-$day';
  if (prefs.getString(_kLastScheduleReportKey) == stamp) return;
  await prefs.setString(_kLastScheduleReportKey, stamp);

  final muted = await NotificationService.mutedChannelIds();
  Analytics.log('reminder_scheduled', {
    'armed': armed,
    'planned': kReminderLoopOffsets.length,
    'with_teaser': withTeaser,
    'silenced': silence?.name,
    'hour': reminder.hour,
    // Android only; both false on iOS, which has no per-channel control.
    'daily_muted': muted.contains(kDailyReminderChannelId),
    'comeback_muted': muted.contains(kComebackReminderChannelId),
  });
}
