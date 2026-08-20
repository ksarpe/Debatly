import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/fit_or_scroll.dart';
import '../../../services/analytics.dart';
import '../../account/widgets/save_pro_prompt.dart';
import '../../monetization/widgets/pro_paywall_screen.dart';
import '../../monetization/widgets/purchase_settlement.dart';

/// The bridge card right after the taste votes — the screen that replaced the
/// hard paywall. It explains the freemium model ("one free question a day,
/// forever") and hands the user FORWARD.
///
/// The FREE path is the dominant CTA: gradient, glow, top of the stack. That is
/// the product's own rule (one free question a day is the whole growth engine,
/// and this is the last screen before a first-run user ever reaches the feed),
/// and it is also what the strings say — `bridgeCtaPrimary` is the free path,
/// `bridgeCtaSecondary` opens the paywall. The visuals used to be the other way
/// round while the analytics kept the string names, so `bridge_cta_primary` was
/// logged by the quiet outlined button and `bridge_cta_secondary` by the loud
/// one — every funnel built on those two events read backwards. Spec, strings,
/// visuals and event names now all agree; keep them that way.
///
/// The paywall sheet is always dismissible back here, so neither path is a trap.
class OnboardingBridgeCard extends ConsumerWidget {
  const OnboardingBridgeCard({super.key, required this.onContinue});

  /// Moves the deck along (to the notifications ask). Both the free path and
  /// a completed purchase end up here.
  final VoidCallback onContinue;

  void _getToday() {
    Analytics.log('bridge_cta_primary');
    onContinue();
  }

  Future<void> _unlockAll(BuildContext context, WidgetRef ref) async {
    Analytics.log('bridge_cta_secondary');
    final purchased = await showProPaywall(
      context,
      source: PaywallSource.bridge,
    );
    // Dismissed → stay on the bridge, with the free path still one tap away.
    if (!purchased || !context.mounted) return;

    // Settle and pitch the account HERE, which every other purchase site gets
    // for free from `HomeGate`. It cannot cover this one: during the bridge the
    // app is still in the onboarding phase, so the gate isn't mounted and its
    // `ref.listen` never registers — by the time it does mount, the free→premium
    // flip has already happened and nothing fires. Left alone, the highest-intent
    // cohort there is — people who pay before they have even seen the feed —
    // ended up holding PRO on an anonymous UUID with no prompt to save it, and
    // lost it on the next reinstall.
    await settleProPurchase(context, ref);
    if (!context.mounted) return;
    await promptSaveProAccount(context, ref);
    onContinue();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return FitOrScroll(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _CatalogFanGlyph(),
            const SizedBox(height: 36),
            Text(
              l10n.bridgeTitle.toUpperCase(),
              textAlign: TextAlign.center,
              style: AppTypography.display(
                40,
              ).copyWith(color: context.colors.ink),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.bridgeBody,
              textAlign: TextAlign.center,
              style: AppTypography.body(
                fontSize: 15,
                height: 1.4,
              ).copyWith(color: context.colors.subtle),
            ),
            const SizedBox(height: 36),
            // The free path: gradient, glow, first in the stack.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppTheme.ctaGradient,
                borderRadius: AppTheme.ctaRadius,
                boxShadow: AppTheme.ctaGlow,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _getToday,
                  borderRadius: AppTheme.ctaRadius,
                  child: SizedBox(
                    width: double.infinity,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      child: Text(
                        l10n.bridgeCtaPrimary.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: AppTypography.action(
                          fontSize: 14,
                        ).copyWith(color: AppTheme.ctaForeground),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // The paywall, kept plainly available underneath — the label and its
            // hint line are unchanged, only the weight is.
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _unlockAll(context, ref),
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
                      l10n.bridgeCtaSecondary.toUpperCase(),
                      style: AppTypography.action(fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.bridgeCtaSecondaryHint,
                      style: AppTypography.support(
                        fontSize: 12.5,
                      ).copyWith(color: context.colors.subtle),
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
            child: Text(
              '?',
              // The mini-card is a miniature question card, so its glyph is set
              // in the question's own DISPLAY face.
              style: AppTypography.display(
                24,
              ).copyWith(color: AppTheme.spark, height: 1),
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
