import 'package:flutter/material.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/fit_or_scroll.dart';
import '../../../services/analytics.dart';
import '../../monetization/widgets/pro_paywall_screen.dart';
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
              color: AppTheme.spark,
              child: _CatalogFanGlyph(),
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
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _unlockAll(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.colors.ink,
                  side: BorderSide(
                    color: AppTheme.spark.withValues(alpha: 0.45),
                  ),
                  shape: const RoundedRectangleBorder(
                    borderRadius: AppTheme.ctaRadius,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.bridgeCtaSecondary,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.bridgeCtaSecondaryHint,
                      style: TextStyle(
                        color: context.colors.subtle,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A fanned stack of question cards with a sparkle — the "hundreds more are
/// waiting" promise drawn out, where the old lone sun said nothing about the
/// catalog.
class _CatalogFanGlyph extends StatelessWidget {
  const _CatalogFanGlyph();

  Widget _card(
    BuildContext context, {
    required double angle,
    required double dx,
    required double borderAlpha,
    double width = 34,
    double height = 48,
    Widget? child,
  }) {
    return Transform.translate(
      offset: Offset(dx, 0),
      child: Transform.rotate(
        angle: angle,
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: context.colors.cardSurface,
            borderRadius: const BorderRadius.all(Radius.circular(9)),
            border: Border.all(
              color: AppTheme.spark.withValues(alpha: borderAlpha),
              width: 1.5,
            ),
          ),
          child: child == null ? null : Center(child: child),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 112,
      height: 112,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _card(context, angle: -0.28, dx: -19, borderAlpha: 0.35),
          _card(context, angle: 0.28, dx: 19, borderAlpha: 0.35),
          _card(
            context,
            angle: 0,
            dx: 0,
            borderAlpha: 0.9,
            width: 38,
            height: 52,
            child: const Text(
              '?',
              style: TextStyle(
                color: AppTheme.spark,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
          Positioned(
            top: 15,
            right: 17,
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 20,
              color: AppTheme.spark,
              shadows: [
                Shadow(
                  color: AppTheme.sparkGlow.withValues(alpha: 0.6),
                  blurRadius: 12,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
