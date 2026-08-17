import 'package:flutter/material.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/fit_or_scroll.dart';
import '../../../services/analytics.dart';
import '../../monetization/widgets/pro_paywall_sheet.dart';
import 'onboarding_glyph_bubble.dart';
import 'onboarding_primary_button.dart';

/// The bridge card right after the taste votes — the screen that replaced the
/// hard paywall. It explains the freemium model ("one free question a day,
/// forever") and hands the user FORWARD: the dominant CTA continues for free
/// to today's question, the quiet one opens the paywall sheet. We want the
/// user to walk in and get hooked, not bounce off a wall — so the free path
/// is deliberately the louder button.
class OnboardingBridgeCard extends StatelessWidget {
  const OnboardingBridgeCard({super.key, required this.onContinue});

  /// Moves the deck along (to the notifications ask). Both the free path and
  /// a completed purchase end up here.
  final VoidCallback onContinue;

  void _getToday() {
    Analytics.log('bridge_cta_primary');
    onContinue();
  }

  Future<void> _unlockAll(BuildContext context) async {
    Analytics.log('bridge_cta_secondary');
    final purchased = await showProPaywall(
      context,
      source: PaywallSource.bridge,
    );
    // Dismissed → stay on the bridge, with the free path still one tap away.
    if (purchased) onContinue();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FitOrScroll(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const OnboardingGlyphBubble(
              icon: Icons.wb_sunny_rounded,
              color: AppTheme.spark,
            ),
            const SizedBox(height: 36),
            Text(
              l10n.bridgeTitle,
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
              l10n.bridgeBody,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.subtle,
                fontSize: 16,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 36),
            OnboardingPrimaryButton(
              label: l10n.bridgeCtaPrimary,
              onPressed: _getToday,
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => _unlockAll(context),
              style: TextButton.styleFrom(
                foregroundColor: context.colors.subtle,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              child: Text(
                l10n.bridgeCtaSecondary,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
