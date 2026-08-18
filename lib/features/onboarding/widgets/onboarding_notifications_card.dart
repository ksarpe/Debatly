import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/app_locale.dart' show sharedPreferencesProvider;
import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/fit_or_scroll.dart';
import '../../../services/analytics.dart';
import '../../../services/notification_service.dart';
import '../../../services/reminder_scheduler.dart';
import '../../settings/providers/reminder_providers.dart';
import 'onboarding_primary_button.dart';

/// A reminder opt-in slide placed right after the taste vote — the moment the
/// user has just felt the app — so the ask lands when it's most welcome. The
/// prominent CTA fires the real OS permission prompt and, when granted, turns the
/// daily reminder on and arms its loop; a quiet "Not now" lets the user move on.
///
/// This is the "priming" pattern: the system prompt only fires after a tap on the
/// in-app card, so a user who isn't interested skips here instead of spending the
/// platform's one-shot prompt on a denial.
class OnboardingNotificationsCard extends ConsumerStatefulWidget {
  const OnboardingNotificationsCard({super.key, required this.onContinue});

  /// Advances the deck to the account-choice card — called after either button,
  /// whatever the permission outcome (onboarding never blocks on it).
  final VoidCallback onContinue;

  @override
  ConsumerState<OnboardingNotificationsCard> createState() =>
      _OnboardingNotificationsCardState();
}

class _OnboardingNotificationsCardState
    extends ConsumerState<OnboardingNotificationsCard> {
  bool _busy = false;

  /// Requests the OS notification permission and, if granted, enables the daily
  /// reminder + schedules its loop — mirroring the Settings toggle's enable path.
  /// Either way (granted or denied) the deck advances; we don't trap the user on
  /// this page over a permission answer.
  Future<void> _enable() async {
    if (_busy) return;
    setState(() => _busy = true);
    // Capture l10n before the awaits — `context` is unsafe to read across them.
    //
    // The provider reads below deliberately stay inside the granted branch
    // rather than being hoisted above the awaits (the usual guard against a
    // disposed `ref`): reading them unconditionally would touch providers on the
    // denied path too, and nothing here may throw — the finally is what
    // guarantees the user is never trapped on this card. The card can't be
    // dismissed while `_busy`, so there is no unmount to race here anyway.
    final l10n = context.l10n;
    try {
      var granted = await NotificationService.areNotificationsEnabled();
      if (!granted) granted = await NotificationService.requestPermission();
      // The tap is the opt-in intent; `granted` records what the OS prompt did
      // with it — the gap between the two is the funnel number that matters.
      Analytics.log('onboarding_notify_enabled', {'granted': granted});
      if (granted) {
        await ref.read(reminderControllerProvider.notifier).setEnabled(true);
        await rescheduleReminderLoop(
          prefs: ref.read(sharedPreferencesProvider),
          l10n: l10n,
        );
      }
    } finally {
      if (mounted) widget.onContinue();
    }
  }

  void _decline() {
    Analytics.log('onboarding_notify_declined');
    widget.onContinue();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Both buttons out of this card must stay tappable on short viewports —
    // an overflowed Column still paints its spilled children but they stop
    // receiving taps, which would trap the user here.
    return FitOrScroll(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A bare glowing bell — no bubble behind it; this slide is a
            // personal aside, not another feature card.
            Icon(
              Icons.notifications_active_rounded,
              size: 84,
              color: AppTheme.spark,
              shadows: [
                Shadow(
                  color: AppTheme.sparkGlow.withValues(alpha: 0.6),
                  blurRadius: 24,
                ),
              ],
            ),
            const SizedBox(height: 36),
            Text(
              l10n.onboardingNotifyTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.ink,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.onboardingNotifyBody,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.subtle,
                fontSize: 16,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 36),
            _busy
                ? const SizedBox(
                    height: 56,
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                    ),
                  )
                : OnboardingPrimaryButton(
                    label: l10n.onboardingNotifyEnable,
                    onPressed: _enable,
                  ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : _decline,
              style: TextButton.styleFrom(
                foregroundColor: context.colors.subtle,
              ),
              child: Text(l10n.onboardingNotifySkip),
            ),
          ],
        ),
      ),
    );
  }
}
