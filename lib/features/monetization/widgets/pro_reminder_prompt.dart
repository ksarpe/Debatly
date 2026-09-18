import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/feedback/app_toast.dart';
import '../../../core/locale/app_locale.dart' show sharedPreferencesProvider;
import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../services/analytics.dart';
import '../../../services/notification_service.dart';
import '../../../services/reminder_scheduler.dart';
import '../../account/providers/session_providers.dart';
import '../../settings/providers/reminder_providers.dart';
import 'wall_reminder_ask.dart' show formatReminderTime;

/// SharedPreferences key: whether the post-purchase reminder ask has been made
/// on this install (answered either way). Deliberately SEPARATE from
/// [kWallReminderAskedPrefKey]: the wall's ask and this one are different
/// moments, and a buyer has usually just skipped the wall's one minutes
/// earlier — the purchase is what earns the second (and last) ask.
const String kProReminderAskedPrefKey = 'pro_reminder_asked';

/// True while the dialog is on screen — guards against a second entitlement
/// flip (a restore landing on top of a purchase) stacking a duplicate.
bool _prompting = false;

/// Asks a fresh PRO buyer to turn the daily reminder on, once per install.
///
/// Why this exists: the reminder opt-in lives on the DAY WALL, and a PRO user
/// never sees the day wall again — so before this, the one group that had paid
/// was also the one group the app never asked for a notification permission,
/// and the local reminder is the only channel that can bring anyone back.
/// It showed: of the first 15 payers, 10 were active on at most two days after
/// buying, and the whole history holds one production renewal.
///
/// Sequenced AFTER `promptSaveProAccount` by both callers, so a guest answers
/// "secure the purchase" first — that one is about not LOSING what they just
/// paid for, this one is about coming back tomorrow.
///
/// Priming pattern, same as the wall: the OS prompt only fires after a tap on
/// the in-app CTA, so "Later" never spends the platform's one-shot prompt on a
/// denial. A denied prompt gets the Settings toast with the "open settings"
/// action. Either answer marks the ask done for this install; Settings keep the
/// toggle afterwards.
///
/// No-ops unless the session is premium, reminders are off, and the ask has not
/// been made on this install.
Future<void> promptProReminder(BuildContext context, WidgetRef ref) async {
  if (_prompting) return;
  final session = ref.read(sessionProvider).value;
  if (session == null || !session.isPremium) return;
  if (ref.read(reminderControllerProvider).enabled) return;
  final prefs = ref.read(sharedPreferencesProvider);
  if (prefs.getBool(kProReminderAskedPrefKey) ?? false) return;

  _prompting = true;
  try {
    await _ask(context, ref, prefs);
  } finally {
    _prompting = false;
  }
}

Future<void> _ask(
  BuildContext context,
  WidgetRef ref,
  SharedPreferences prefs,
) async {
  final time = formatReminderTime(ref.read(reminderControllerProvider).time);
  Analytics.log('pro_notify_shown');

  final wantsReminder = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.62),
    builder: (dialogContext) => AlertDialog(
      backgroundColor: context.colors.cardSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 10),
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.spark.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_active_outlined,
              color: AppTheme.spark,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              context.l10n.proRemindTitle.toUpperCase(),
              style: AppTypography.title(
                fontSize: 30,
              ).copyWith(color: context.colors.ink),
            ),
          ),
        ],
      ),
      content: Text(
        context.l10n.proRemindBody(time),
        style: AppTypography.body(
          height: 1.4,
        ).copyWith(color: context.colors.subtle),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          style: TextButton.styleFrom(
            foregroundColor: context.colors.subtle,
            textStyle: AppTypography.action(),
          ),
          child: Text(context.l10n.later.toUpperCase()),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.spark,
            textStyle: AppTypography.action(),
          ),
          child: Text(context.l10n.proRemindCta.toUpperCase()),
        ),
      ],
    ),
  );

  // Asked is asked, whatever the answer or the OS said — this must not become
  // a nag on every relaunch.
  await prefs.setBool(kProReminderAskedPrefKey, true);

  if (wantsReminder != true) {
    Analytics.log('pro_notify_declined');
    return;
  }
  if (!context.mounted) return;

  // Read everything the awaits need up front: `context` and `ref` are unsafe
  // across them, while the notifier outlives this call.
  final l10n = context.l10n;
  final reminders = ref.read(reminderControllerProvider.notifier);

  var granted = await NotificationService.areNotificationsEnabled();
  if (!granted) granted = await NotificationService.requestPermission();
  // The tap is the opt-in intent; `granted` is what the OS prompt did with it —
  // the gap between the two is the funnel number that matters.
  Analytics.log('pro_notify_enabled', {'granted': granted});
  if (granted) {
    await reminders.setEnabled(true);
    await rescheduleReminderLoop(prefs: prefs, l10n: l10n);
  }
  if (!context.mounted) return;
  if (granted) {
    AppToast.success(context, l10n.wallRemindConfirmed(time));
  } else {
    // Same recovery the wall and the Settings toggle offer: the prompt was
    // denied (or the OS no longer shows one), so point at the switch that is
    // left.
    AppToast.show(
      context,
      l10n.remindersPermissionDenied,
      type: ToastType.error,
      duration: const Duration(seconds: 6),
      action: (
        label: l10n.remindersOpenSettings,
        onPressed: NotificationService.openNotificationSettings,
      ),
    );
  }
}
