import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/locale/app_locale.dart' show sharedPreferencesProvider;

const String _kEnabledKey = 'reminders_enabled';
const String _kHourKey = 'reminder_hour';
const String _kMinuteKey = 'reminder_minute';

/// Local date (`yyyy-mm-dd`) of the user's most recent daily vote. Stamped at
/// vote time so the reminder can tell a day already answered from a quiet one —
/// including across a same-day relaunch, before any network sync.
const String _kLastVoteDateKey = 'reminder_last_vote_date';

/// Share (0..100) of voters who landed on the OTHER side from the user, for the
/// daily they most recently voted on. Stamped alongside [_kLastVoteDateKey] so a
/// post-vote nudge can say "X% disagreed with you today"; only trusted when that
/// stamp is today's (see [lastDisagreePctToday]).
const String _kLastDisagreePctKey = 'reminder_last_disagree_pct';

/// The device-local date as `yyyy-mm-dd`. The reminder runs on wall-clock local
/// time, and the daily question is fetched for the local date too, so "today" is
/// measured locally here as well (not UTC).
String _todayStamp() {
  final now = DateTime.now();
  final month = now.month.toString().padLeft(2, '0');
  final day = now.day.toString().padLeft(2, '0');
  return '${now.year}-$month-$day';
}

/// Whether the user has already cast today's daily vote, per the locally-cached
/// stamp. Read directly from [prefs] (before the provider graph exists, e.g. in
/// `main()`) by the reminder scheduler: it silences tonight's slot for a free
/// user who already spent their daily, and switches PRO's to a post-vote line.
bool hasVotedTodayLocal(SharedPreferences prefs) =>
    prefs.getString(_kLastVoteDateKey) == _todayStamp();

/// The share (0..100) of voters who disagreed with the user on today's daily, or
/// null when they haven't voted today (so a stale yesterday value never leaks
/// into a "X% disagreed with you today" nudge). Read straight from [prefs] by the
/// reminder scheduler.
int? lastDisagreePctToday(SharedPreferences prefs) {
  if (prefs.getString(_kLastVoteDateKey) != _todayStamp()) return null;
  return prefs.getInt(_kLastDisagreePctKey);
}

/// Default daily-reminder time: 20:00 — a quiet evening slot with good open
/// rates, used until the user picks their own.
const int kDefaultReminderHour = 20;
const int kDefaultReminderMinute = 0;

/// The user's daily-reminder preference: whether it's on and at what local time.
/// Persisted in SharedPreferences so it survives restarts; the actual OS-level
/// scheduling is done by [NotificationService], orchestrated from the Settings
/// screen (which has the localized strings) and refreshed on launch in `main()`.
class ReminderPrefs {
  const ReminderPrefs({
    required this.enabled,
    required this.hour,
    required this.minute,
  });

  final bool enabled;
  final int hour;
  final int minute;

  /// Reads the persisted preference straight from [prefs] — used in `main()` to
  /// re-arm the reminder on launch before the provider graph exists.
  factory ReminderPrefs.fromPrefs(SharedPreferences prefs) => ReminderPrefs(
    enabled: prefs.getBool(_kEnabledKey) ?? false,
    hour: prefs.getInt(_kHourKey) ?? kDefaultReminderHour,
    minute: prefs.getInt(_kMinuteKey) ?? kDefaultReminderMinute,
  );

  TimeOfDay get time => TimeOfDay(hour: hour, minute: minute);

  ReminderPrefs copyWith({bool? enabled, int? hour, int? minute}) =>
      ReminderPrefs(
        enabled: enabled ?? this.enabled,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
      );
}

/// Reads and persists [ReminderPrefs]. Mutating it does NOT touch the OS
/// schedule — the caller pairs a state change with [NotificationService] calls,
/// keeping this provider free of platform/l10n concerns.
class ReminderController extends Notifier<ReminderPrefs> {
  @override
  ReminderPrefs build() =>
      ReminderPrefs.fromPrefs(ref.watch(sharedPreferencesProvider));

  Future<void> setEnabled(bool enabled) async {
    state = state.copyWith(enabled: enabled);
    await ref.read(sharedPreferencesProvider).setBool(_kEnabledKey, enabled);
  }

  Future<void> setTime(TimeOfDay time) async {
    state = state.copyWith(hour: time.hour, minute: time.minute);
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setInt(_kHourKey, time.hour);
    await prefs.setInt(_kMinuteKey, time.minute);
  }

  /// Stamps today's local date as "voted" — so the reminder switches from a
  /// "go vote" nudge to a post-vote one — and, when known, the share of voters
  /// who disagreed with the user ([disagreePct], 0..100) for the "X% disagreed
  /// with you today" line. Local-only: rescheduling the OS notification is the
  /// caller's job (it holds the localized strings); see the daily vote panel.
  Future<void> markVotedToday({int? disagreePct}) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_kLastVoteDateKey, _todayStamp());
    if (disagreePct != null) {
      await prefs.setInt(_kLastDisagreePctKey, disagreePct);
    }
  }
}

final reminderControllerProvider =
    NotifierProvider<ReminderController, ReminderPrefs>(ReminderController.new);
