import 'dart:io' show Platform;

import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// One Android notification channel, as the OS surfaces it in the app's own
/// settings. The caller supplies the user-visible strings, so channel names are
/// localized like every other piece of copy rather than frozen in English here.
///
/// iOS and macOS have no equivalent concept — everything lands in one bucket
/// there and only [id] is ignored.
class ReminderChannel {
  const ReminderChannel({
    required this.id,
    required this.name,
    required this.description,
    required this.heightened,
  });

  final String id;
  final String name;
  final String description;

  /// High importance — a heads-up banner with sound. False leaves the fire
  /// sitting quietly in the shade, which is what an unprompted come-back nudge
  /// deserves next to the reminder the user actually asked for.
  final bool heightened;
}

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

  /// The zone identifier `tz.local` currently points at, so re-detection can
  /// skip the (string-keyed) location lookup when nothing changed.
  static String? _tzIdentifier;

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

  /// The single English-only channel every reminder used to share. Split into
  /// per-purpose channels (see [ReminderChannel]) so muting the come-back nudges
  /// doesn't also mute the daily one the user opted into; deleted on init so it
  /// stops sitting in the OS settings as an orphan.
  static const String _legacyChannelId = 'daily_reminder';

  /// Initialises the plugin and the timezone database. Safe to call once at
  /// startup; subsequent calls no-op.
  ///
  /// [onOpened] receives the payload of a reminder the user TAPPED, from both
  /// paths that exist: the live callback (app running or backgrounded) and the
  /// launch details (app was killed, so the tap is the reason we're starting and
  /// there was no listener alive to catch it). Local notifications can't report
  /// delivery, so a tap is the only signal the loop ever gets back — without
  /// this, every claim about which copy works is unfalsifiable.
  static Future<void> initialise({
    void Function(String? payload)? onOpened,
  }) async {
    if (_initialised) return;
    try {
      // Timezone DB + the device's local zone, so a daily wall-clock time fires
      // at the right local moment regardless of where the user is.
      tzdata.initializeTimeZones();
      await _syncLocalTimezone();

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
        onDidReceiveNotificationResponse: (response) =>
            onOpened?.call(response.payload),
      );
      // The cold-start path: a tap that launched the process happened before
      // any callback existed. Guarded by _initialised above, so it can't
      // double-report on a second call.
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        onOpened?.call(launch?.notificationResponse?.payload);
      }
      if (Platform.isAndroid) {
        // Best-effort tidy-up: no-op once it's gone, and on the platforms that
        // never had it.
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.deleteNotificationChannel(channelId: _legacyChannelId);
      }
      _initialised = true;
    } catch (e) {
      debugPrint('NotificationService: init failed — $e');
    }
  }

  /// Points `tz.local` at the device's CURRENT zone. Runs at init and again on
  /// every re-arm: the process can outlive a flight across timezones, and a
  /// loop scheduled against a stale `tz.local` fires at the wrong local hour
  /// (and hands `teaserForOffset` dates one day off from the real fire day).
  ///
  /// Best-effort — on failure `tz.local` keeps whatever it had (UTC on a
  /// never-succeeded detect), which still fires daily, just not anchored to
  /// the device zone.
  static Future<void> _syncLocalTimezone() async {
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      if (info.identifier == _tzIdentifier) return;
      tz.setLocalLocation(tz.getLocation(info.identifier));
      _tzIdentifier = info.identifier;
    } catch (e) {
      debugPrint('NotificationService: timezone detect failed — $e');
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

  /// The ids of this app's notification channels the user has muted (importance
  /// "none"). Android only — iOS has no per-channel control, so it resolves
  /// empty there and the app-level [areNotificationsEnabled] is the whole story.
  ///
  /// The point of splitting the channels was to let someone silence the chasing
  /// without silencing the reminder they asked for; this is how we find out
  /// whether they actually do, instead of assuming.
  static Future<Set<String>> mutedChannelIds() async {
    if (!_initialised || !Platform.isAndroid) return const {};
    try {
      final channels = await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.getNotificationChannels();
      return {
        for (final channel in channels ?? const <AndroidNotificationChannel>[])
          if (channel.importance == Importance.none) channel.id,
      };
    } catch (e) {
      debugPrint('NotificationService: channel read failed — $e');
      return const {};
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
  /// Returns how many slots were actually armed — fewer than [dayOffsets] when
  /// today's time has passed or the caller silenced a day.
  static Future<int> scheduleReminderLoop({
    required int hour,
    required int minute,
    required List<int> dayOffsets,
    required ({
      String title,
      String body,
      ReminderChannel channel,
      String payload,
    })?
    Function(int dayOffset)
    build,
  }) async {
    if (!_initialised) return 0;
    // The device zone may have changed since init (travel with the app
    // resident) — every re-arm re-anchors the loop to the current one.
    await _syncLocalTimezone();
    var armed = 0;
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
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              message.channel.id,
              message.channel.name,
              channelDescription: message.channel.description,
              importance: message.channel.heightened
                  ? Importance.high
                  : Importance.defaultImportance,
              priority: message.channel.heightened
                  ? Priority.high
                  : Priority.defaultPriority,
            ),
            iOS: const DarwinNotificationDetails(),
            macOS: const DarwinNotificationDetails(),
          ),
          // Inexact alarms avoid the SCHEDULE_EXACT_ALARM permission and its Play
          // Store declaration — a daily reminder doesn't need to-the-second
          // timing. No matchDateTimeComponents: each entry is a one-shot, so the
          // day's freshly-picked text isn't frozen into a repeating notification.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: message.payload,
        );
        armed++;
      }
    } catch (e) {
      debugPrint('NotificationService: loop schedule failed — $e');
    }
    return armed;
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
