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
import '../../settings/providers/reminder_providers.dart';
import 'paywall_cta_button.dart';

/// SharedPreferences key: whether the day wall's reminder ask has been
/// answered on this install (enabled OR declined). Absent until the first
/// answer — the ask is made once; after that the Settings toggle is the way in.
const String kWallReminderAskedPrefKey = 'wall_reminder_asked';

/// Whether the wall should carry the reminder ask instead of the unlock CTA:
/// reminders are off and nobody has answered the ask yet. A user who turned
/// reminders on anywhere (the old onboarding card, Settings) is never asked.
bool wallReminderAskPending(SharedPreferences prefs, ReminderPrefs reminder) =>
    !reminder.enabled && !(prefs.getBool(kWallReminderAskedPrefKey) ?? false);

/// `HH:MM` for the reminder line — the same 24h rendering the Settings row
/// uses, so "o 20:00" here matches what the user later finds there.
String formatReminderTime(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

/// The reminder opt-in, on the day wall — where the onboarding deck used to
/// ask ("Hej, jeszcze jedno", 18% opt-in, asked before the user had felt
/// anything). Here the user has just voted, swiped forward and been told the
/// next question is behind local midnight: the ask names that question
/// ("Jutro: „`<teaser>`…” — przypomnę Ci o 20:00") and the reminder that fires
/// tomorrow bakes the same calendar teaser, so the promise and the
/// notification agree.
///
/// Priming pattern, as before: the OS prompt only fires after a tap on the
/// in-app CTA, so a "Nie teraz" never spends the platform's one-shot prompt on
/// a denial. Enable = permission → reminder on + loop armed (mirrors the
/// Settings toggle's enable path); a denied prompt gets the Settings toast
/// with the "open settings" action. Either answer marks the ask done for this
/// install and hands the band back to the owner ([onAnswered]) — the unlock
/// CTA takes its place in the same frame, so the wall never loses its
/// conversion surface for more than one decision.
class WallReminderAsk extends ConsumerStatefulWidget {
  const WallReminderAsk({
    super.key,
    required this.teaser,
    required this.onAnswered,
  });

  /// Tomorrow's pick, first words (the wall's own teaser). Null on a gap date
  /// or offline — the line then promises "a new question" instead of naming
  /// one.
  final String? teaser;

  /// Called once the ask has been answered either way (after the OS prompt
  /// resolved, for the enable path). The owner swaps the band.
  final VoidCallback onAnswered;

  /// The shortest the band is laid out in at this text scale: the two-line
  /// promise, the pill and the quiet decline. The wall adds it to its own
  /// minimum height so an ask never overflows into an untappable CTA.
  static double minHeight(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 3.0);
    return (15 * 1.35 * 2 + 12 + 54 + 4 + 44) * scale;
  }

  @override
  ConsumerState<WallReminderAsk> createState() => _WallReminderAskState();
}

class _WallReminderAskState extends ConsumerState<WallReminderAsk> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Analytics.log('wall_notify_shown', {'has_teaser': widget.teaser != null});
  }

  Future<void> _enable() async {
    if (_busy) return;
    setState(() => _busy = true);
    // Everything the awaits need, read up front: `context` and `ref` are
    // unsafe across them (a back swipe can unmount the wall mid-prompt), and
    // the notifier outlives this widget, so enabling through a captured
    // handle still lands even if the user has swiped away.
    final l10n = context.l10n;
    final prefs = ref.read(sharedPreferencesProvider);
    final reminders = ref.read(reminderControllerProvider.notifier);
    final time = formatReminderTime(ref.read(reminderControllerProvider).time);
    try {
      var granted = await NotificationService.areNotificationsEnabled();
      if (!granted) granted = await NotificationService.requestPermission();
      // The tap is the opt-in intent; `granted` is what the OS prompt did
      // with it — the gap between the two is the funnel number that matters.
      Analytics.log('wall_notify_enabled', {'granted': granted});
      if (granted) {
        await reminders.setEnabled(true);
        await rescheduleReminderLoop(prefs: prefs, l10n: l10n);
      }
      if (!mounted) return;
      if (granted) {
        AppToast.success(context, l10n.wallRemindConfirmed(time));
      } else {
        // Same recovery the Settings toggle offers: the prompt was denied (or
        // the OS no longer shows one), so point at the switch that is left.
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
    } finally {
      // Asked is asked, whatever the OS said — a denied prompt must not turn
      // the wall into a nag. The finally is what guarantees the band is
      // handed back even if something above throws.
      await prefs.setBool(kWallReminderAskedPrefKey, true);
      if (mounted) widget.onAnswered();
    }
  }

  Future<void> _decline() async {
    if (_busy) return;
    Analytics.log('wall_notify_declined');
    await ref
        .read(sharedPreferencesProvider)
        .setBool(kWallReminderAskedPrefKey, true);
    if (mounted) widget.onAnswered();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    final time = formatReminderTime(ref.watch(reminderControllerProvider).time);
    final teaser = widget.teaser;
    final line = teaser == null
        ? l10n.wallRemindLineNoTeaser(time)
        : l10n.wallRemindLine(teaser, time);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          line,
          textAlign: TextAlign.center,
          style: AppTypography.body(
            fontSize: 15,
            height: 1.35,
          ).copyWith(color: colors.ink),
        ),
        const SizedBox(height: 12),
        PaywallCtaButton(
          label: l10n.wallRemindCta,
          busy: _busy,
          onTap: _enable,
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: _busy ? null : _decline,
          style: TextButton.styleFrom(foregroundColor: colors.subtle),
          child: Text(
            l10n.wallRemindSkip.toUpperCase(),
            style: AppTypography.action(),
          ),
        ),
      ],
    );
  }
}
