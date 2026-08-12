import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import 'styled_question_text.dart';

/// The reveal-slot paywall: watch a rewarded ad to reveal the next question, or
/// go PRO for unlimited reading. [busy] disables both and shows a spinner while
/// an ad or purchase is in flight.
class RevealPaywall extends StatelessWidget {
  const RevealPaywall({
    super.key,
    required this.onWatchAd,
    required this.onGetPremium,
    required this.onRestore,
    required this.busy,
    this.onSignIn,
    this.teaser,
    this.adCapReached = false,
    this.onAdCapExpired,
  });

  final VoidCallback onWatchAd;
  final VoidCallback onGetPremium;
  final VoidCallback onRestore;
  final bool busy;

  /// Opens the sign-in sheet. Only passed for GUESTS — signing in earns the
  /// daily free-unlock credit (auto-spent on the next swipe), so the hint under
  /// the PRO button is pointless for a user who already has an account.
  final VoidCallback? onSignIn;

  /// First couple of words of the next question (from `peek_next_question`),
  /// teased above the CTAs. Falls back to a generic line when absent.
  final String? teaser;

  /// Today's ad-reveal cap (server-enforced) is exhausted: the ad button is
  /// dropped and PRO becomes the only unlock, under "come back tomorrow" copy
  /// plus a live countdown to the UTC-midnight reset.
  /// The teaser stays — the wall should still show what's being missed.
  final bool adCapReached;

  /// Fired once when the countdown crosses the UTC-midnight reset while the
  /// capped wall is on screen — the caller re-syncs the server state so the ad
  /// button comes back without the user restarting the app.
  final VoidCallback? onAdCapExpired;

  @override
  Widget build(BuildContext context) {
    final tease = teaser?.trim() ?? '';
    // SafeArea (bottom) keeps the CTAs and the restore link clear of the
    // system gesture bar — the feed body extends behind it.
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tease.isNotEmpty)
            StyledQuestionText('$tease…')
          else
            Text(
              context.l10n.nextQuestionWaiting,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.ink,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
          // No "watch an ad" subtitle here — the ad button says it already.
          if (adCapReached) ...[
            const SizedBox(height: 10),
            Text(
              context.l10n.adLimitReachedInfo,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.subtle, fontSize: 14),
            ),
            const SizedBox(height: 8),
            _AdCapCountdown(onExpired: onAdCapExpired),
          ],
          const SizedBox(height: 32),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!adCapReached) ...[
                  _UnlockButton(
                    icon: Icons.play_circle_outline,
                    label: context.l10n.unlockWithAd,
                    onTap: busy ? null : onWatchAd,
                  ),
                  const SizedBox(height: 12),
                ],
                _UnlockButton(
                  icon: Icons.workspace_premium_outlined,
                  label: context.l10n.goPro,
                  onTap: busy ? null : onGetPremium,
                  primary: true,
                ),
                if (onSignIn != null) ...[
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: busy ? null : onSignIn,
                    style: TextButton.styleFrom(
                      foregroundColor: context.colors.subtle,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(
                        fontSize: 14,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                    child: Text(
                      context.l10n.orSignInFreeQuestion,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
                // Reserve room for the in-flight spinner so the buttons don't
                // jump when an ad loads or the paywall resolves.
                SizedBox(
                  height: 30,
                  child: Center(
                    child: busy
                        ? SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: context.colors.subtle,
                            ),
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // No explicit "back" link: a rightward swipe steps back off the
          // paywall, same as everywhere else in the feed.
          // Store-required restore path — reachable here because a guest can't
          // open Settings (where the other restore lives). Last in the column,
          // so it sits at the very bottom of the wall.
          TextButton(
            onPressed: busy ? null : onRestore,
            style: TextButton.styleFrom(
              foregroundColor: context.colors.subtle,
              textStyle: const TextStyle(fontSize: 15),
            ),
            child: Text(context.l10n.restorePurchase),
          ),
        ],
      ),
    );
  }
}

/// "Nowe odblokowania za X godz. Y min" — counts down to the next UTC midnight,
/// the moment the server's daily ad-reveal cap lazily resets (the cap counts
/// the SERVER's UTC day, so local midnight would show the wrong time). Ticks
/// once a minute; display is hours+minutes so that's plenty. When the boundary
/// passes it fires [onExpired] (once) and stops — the owner re-syncs the stats,
/// which flips the paywall back to its ad-button variant and disposes this.
class _AdCapCountdown extends StatefulWidget {
  const _AdCapCountdown({this.onExpired});

  final VoidCallback? onExpired;

  @override
  State<_AdCapCountdown> createState() => _AdCapCountdownState();
}

class _AdCapCountdownState extends State<_AdCapCountdown> {
  Timer? _timer;
  Duration _remaining = _untilUtcMidnight();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static Duration _untilUtcMidnight() {
    final now = DateTime.now().toUtc();
    // DateTime.utc normalises day+1 across month/year ends.
    return DateTime.utc(now.year, now.month, now.day + 1).difference(now);
  }

  void _tick() {
    if (!mounted) return;
    final left = _untilUtcMidnight();
    if (left > _remaining) {
      // Remaining only ever shrinks — a jump UP (back to ~24h) means the
      // midnight reset just passed. Fire once and stop; the owner's re-sync
      // swaps the paywall back to its ad variant, which disposes this widget.
      _timer?.cancel();
      widget.onExpired?.call();
      return;
    }
    setState(() => _remaining = left);
  }

  @override
  Widget build(BuildContext context) {
    final left = _remaining;
    final hours = left.inHours;
    // Under an hour, never show "0 min" — the reset is at most a minute away.
    final minutes = hours > 0
        ? left.inMinutes % 60
        : left.inMinutes.clamp(1, 59);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.schedule, size: 14, color: context.colors.subtle),
        const SizedBox(width: 5),
        // Flexible so the line wraps instead of overflowing on narrow screens
        // or large accessibility text scales.
        Flexible(
          child: Text(
            hours > 0
                ? context.l10n.adLimitResetInHM(hours, minutes)
                : context.l10n.adLimitResetInM(minutes),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.colors.subtle,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// One of the two paywall CTAs, styled to the app's language: a rounded pill
/// with an icon + uppercase label. [primary] paints it in the signature orange
/// "spark" with a soft glow (the recommended PRO path); otherwise it sits on the
/// muted accent surface. A null [onTap] dims it.
class _UnlockButton extends StatelessWidget {
  const _UnlockButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;

  static final BorderRadius _radius = BorderRadius.circular(30);

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: _radius,
          boxShadow: primary
              ? const [
                  BoxShadow(
                    color: Color(0x55F97316),
                    blurRadius: 20,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Material(
          color: primary ? AppTheme.spark : context.colors.accent,
          borderRadius: _radius,
          child: InkWell(
            borderRadius: _radius,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: context.colors.ink, size: 20),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      label.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.colors.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
