import 'package:flutter/material.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import 'back_to_daily_link.dart';
import 'styled_question_text.dart';

/// The reveal-slot paywall: watch a rewarded ad to reveal the next question, or
/// go PRO for unlimited reading. [busy] disables both and shows a spinner while
/// an ad or purchase is in flight.
class RevealPaywall extends StatelessWidget {
  const RevealPaywall({
    super.key,
    required this.onWatchAd,
    required this.onGetPremium,
    required this.onBackToDaily,
    required this.onRestore,
    required this.busy,
    this.onSignIn,
    this.teaser,
    this.adCapReached = false,
  });

  final VoidCallback onWatchAd;
  final VoidCallback onGetPremium;
  final VoidCallback onBackToDaily;
  final VoidCallback onRestore;
  final bool busy;

  /// Opens the sign-in sheet. Only passed for GUESTS — signing in earns the
  /// daily free-unlock credit (auto-spent on the next swipe), so the hint under
  /// the ad line is pointless for a user who already has an account.
  final VoidCallback? onSignIn;

  /// First couple of words of the next question (from `peek_next_question`),
  /// teased above the CTAs. Falls back to a generic line when absent.
  final String? teaser;

  /// Today's ad-reveal cap (server-enforced) is exhausted: the ad button is
  /// dropped and PRO becomes the only unlock, under "come back tomorrow" copy.
  /// The teaser stays — the wall should still show what's being missed.
  final bool adCapReached;

  @override
  Widget build(BuildContext context) {
    final tease = teaser?.trim() ?? '';
    return Column(
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
        const SizedBox(height: 10),
        Text(
          adCapReached
              ? context.l10n.adLimitReachedInfo
              : context.l10n.watchAdToReveal,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.colors.subtle, fontSize: 14),
        ),
        if (onSignIn != null) ...[
          const SizedBox(height: 2),
          TextButton(
            onPressed: busy ? null : onSignIn,
            style: TextButton.styleFrom(
              foregroundColor: context.colors.subtle,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
              // Reserve room for the in-flight spinner so the buttons don't jump
              // when an ad loads or the paywall resolves.
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
        const SizedBox(height: 4),
        // Visible escape back to the free daily, so a user who doesn't want to
        // watch an ad isn't cornered on the paywall.
        BackToDailyLink(onTap: busy ? () {} : onBackToDaily),
        // Store-required restore path — reachable here because a guest can't
        // open Settings (where the other restore lives).
        TextButton(
          onPressed: busy ? null : onRestore,
          style: TextButton.styleFrom(
            foregroundColor: context.colors.subtle,
            textStyle: const TextStyle(fontSize: 13),
          ),
          child: Text(context.l10n.restorePurchase),
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
