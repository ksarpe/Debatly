import 'dart:io' show Platform;

import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// On-device daily reminder for the question of the day.
///
/// Deliberately **local** notifications — no Firebase, no APNs key, no server
/// cron. The daily nudge is scheduled on the device with a repeating wall-clock
/// trigger, so there is nothing to configure in any console and nothing to keep
/// running server-side. It works offline and survives reboots (the schedule is
/// also refreshed on every launch, see `main()`).
///
/// Every call is guarded so the app still runs where the native plugin isn't
/// available (desktop/web dev, tests): it simply no-ops.
class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialised = false;
  static bool get isInitialised => _initialised;

  /// Legacy id of the old single repeating reminder. Kept only so we can cancel
  /// any lingering schedule left by a previous app version when we re-arm.
  static const int _legacyDailyReminderId = 1001;

  /// The daily-reminder loop is a run of one-shot notifications, scheduled at
  /// [_loopBaseId], [_loopBaseId] + 1, … — one per entry in the caller's cadence,
  /// indexed by POSITION, not by day offset (the cadence thins out, so the two
  /// stopped matching once it went past consecutive days). Each carries its own
  /// freshly-picked message (see [scheduleReminderLoop]) instead of one repeating
  /// line. We cancel a generous range on every re-arm so shrinking the loop never
  /// strands an old entry — the range also covers the ids an older app version
  /// wrote when it indexed by day offset across a 14-day window.
  static const int _loopBaseId = 2001;
  static const int _maxLoopSlots = 16;

  static const String _channelId = 'daily_reminder';
  static const String _channelName = 'Questions';
  static const String _channelDescription =
      'A daily nudge to vote on new questions.';

  /// Initialises the plugin and the timezone database. Safe to call once at
  /// startup; subsequent calls no-op.
  static Future<void> initialise() async {
    if (_initialised) return;
    try {
      // Timezone DB + the device's local zone, so a daily wall-clock time fires
      // at the right local moment regardless of where the user is.
      tzdata.initializeTimeZones();
      try {
        final info = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(info.identifier));
      } catch (e) {
        // Falls back to UTC (the timezone package default) — the reminder still
        // fires daily, just anchored to UTC rather than the device zone.
        debugPrint('NotificationService: timezone detect failed — $e');
      }

      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      // Don't ask for permission at init — we request it contextually when the
      // user turns the reminder on (see [requestPermission]).
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: android,
          iOS: darwin,
          macOS: darwin,
        ),
      );
      _initialised = true;
    } catch (e) {
      debugPrint('NotificationService: init failed — $e');
    }
  }

  /// Whether the OS currently permits this app to post notifications.
  ///
  /// Unlike [requestPermission] this never prompts — it just reads the current
  /// grant, so the UI can keep its in-app switch honest (the user may revoke the
  /// permission in system settings at any time) and decide whether asking is
  /// even still needed. On Android < 13 there's no runtime gate, so it resolves
  /// true.
  static Future<bool> areNotificationsEnabled() async {
    if (!_initialised) return false;
    try {
      if (Platform.isAndroid) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        // Null = pre-Android-13: no runtime gate to revoke, so treat as enabled.
        return (await android?.areNotificationsEnabled()) ?? true;
      }
      if (Platform.isIOS || Platform.isMacOS) {
        final darwin = _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        final options = await darwin?.checkPermissions();
        return options?.isEnabled ?? false;
      }
      return false;
    } catch (e) {
      debugPrint('NotificationService: enabled-check failed — $e');
      return false;
    }
  }

  /// Opens this app's notification settings in the OS, so a user who denied the
  /// permission (or whose system no longer shows the prompt) can grant it in one
  /// tap instead of hunting through Settings. Best-effort — no-ops on failure.
  static Future<void> openNotificationSettings() async {
    try {
      await AppSettings.openAppSettings(type: AppSettingsType.notification);
    } catch (e) {
      debugPrint('NotificationService: open settings failed — $e');
    }
  }

  /// Requests OS permission to post notifications, returning whether it's
  /// granted. On Android < 13 no runtime permission exists, so this resolves
  /// true. Call right before enabling the reminder.
  static Future<bool> requestPermission() async {
    if (!_initialised) return false;
    try {
      if (Platform.isIOS || Platform.isMacOS) {
        final ios = _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        final granted = await ios?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return granted ?? false;
      }
      if (Platform.isAndroid) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        final granted = await android?.requestNotificationsPermission();
        // Null = pre-Android-13, where notifications need no runtime grant.
        return granted ?? true;
      }
      return false;
    } catch (e) {
      debugPrint('NotificationService: permission request failed — $e');
      return false;
    }
  }

  /// (Re)schedules the daily-reminder loop: one one-shot notification at
  /// [hour]:[minute] local time for each day offset in [dayOffsets] (0 = today).
  /// The offsets need not be consecutive — a thinning cadence is what keeps a
  /// month of coverage from costing a month of daily pings. The text for each is
  /// produced on demand by [build], given that day's offset, so every fire
  /// carries its own independently-picked message instead of one repeating line.
  ///
  /// [build] returns null to drop that slot entirely: the caller owns the "is
  /// there anything worth saying?" policy (see `rescheduleReminderLoop`) and a
  /// day with nothing to offer must stay silent rather than fall back to a
  /// filler line.
  ///
  /// Today's slot is only scheduled when [hour]:[minute] is still ahead of now;
  /// an already-passed time simply isn't scheduled for today. The whole managed
  /// range (plus the legacy single reminder) is cancelled first, so re-arming is
  /// idempotent and never stacks duplicates.
  static Future<void> scheduleReminderLoop({
    required int hour,
    required int minute,
    required List<int> dayOffsets,
    required ({String title, String body})? Function(int dayOffset) build,
  }) async {
    if (!_initialised) return;
    try {
      await _cancelManaged();
      final now = tz.TZDateTime.now(tz.local);
      final offsets = dayOffsets.take(_maxLoopSlots).toList(growable: false);
      for (var slot = 0; slot < offsets.length; slot++) {
        final offset = offsets[slot];
        // Constructing the date with `now.day + offset` lets TZDateTime normalise
        // month/year rollover and land on the right wall-clock time even across a
        // DST change (unlike adding a fixed 24h Duration).
        final when = tz.TZDateTime(
          tz.local,
          now.year,
          now.month,
          now.day + offset,
          hour,
          minute,
        );
        if (!when.isAfter(now)) continue; // today's slot already passed
        final message = build(offset);
        if (message == null) continue; // the caller's policy silenced this day
        await _plugin.zonedSchedule(
          id: _loopBaseId + slot,
          title: message.title,
          body: message.body,
          scheduledDate: when,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              _channelName,
              channelDescription: _channelDescription,
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(),
            macOS: DarwinNotificationDetails(),
          ),
          // Inexact alarms avoid the SCHEDULE_EXACT_ALARM permission and its Play
          // Store declaration — a daily reminder doesn't need to-the-second
          // timing. No matchDateTimeComponents: each entry is a one-shot, so the
          // day's freshly-picked text isn't frozen into a repeating notification.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (e) {
      debugPrint('NotificationService: loop schedule failed — $e');
    }
  }

  /// Cancels the daily reminder, e.g. when the user turns it off.
  static Future<void> cancelDailyReminder() async {
    if (!_initialised) return;
    await _cancelManaged();
  }

  /// Clears every notification this service owns: the legacy single reminder and
  /// the whole one-shot loop range. Best-effort.
  static Future<void> _cancelManaged() async {
    try {
      await _plugin.cancel(id: _legacyDailyReminderId);
      for (var i = 0; i < _maxLoopSlots; i++) {
        await _plugin.cancel(id: _loopBaseId + i);
      }
    } catch (e) {
      debugPrint('NotificationService: cancel failed — $e');
    }
  }
}
