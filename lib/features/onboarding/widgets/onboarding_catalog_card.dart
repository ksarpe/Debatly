import 'package:flutter/material.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/fit_or_scroll.dart';
import 'onboarding_glyph_bubble.dart';

/// The card right after the taste vote's second question: the moment the user
/// has felt the loop twice is the moment to say how much more of it there is —
/// 500+ questions of the same kind — and where it's meant to be used (a date,
/// a party, an evening for two, the family table).
///
/// It is pure pitch, so it carries no buttons of its own: the deck's shared
/// dots + "Next" underneath move it along, like the intro cards.
class OnboardingCatalogCard extends StatelessWidget {
  const OnboardingCatalogCard({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Title, body and four use-cases stack taller than the intro cards, so a
    // short viewport or a large system font has to scroll rather than clip.
    return FitOrScroll(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const OnboardingGlyphBubble(
              icon: Icons.forum_rounded,
              color: AppTheme.spark,
            ),
            const SizedBox(height: 36),
            Text(
              l10n.onboardingCatalogTitle,
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
              l10n.onboardingCatalogBody,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.subtle,
                fontSize: 16,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              l10n.onboardingCatalogPerfectFor,
              style: const TextStyle(
                color: AppTheme.spark,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            // Left-aligned as a block (so the icons line up) but the block
            // itself sits centred under the copy above it.
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _UseCase(
                  icon: Icons.favorite_rounded,
                  label: l10n.onboardingCatalogUse1,
                ),
                _UseCase(
                  icon: Icons.groups_rounded,
                  label: l10n.onboardingCatalogUse2,
                ),
                _UseCase(
                  icon: Icons.wine_bar_rounded,
                  label: l10n.onboardingCatalogUse3,
                ),
                _UseCase(
                  icon: Icons.restaurant_rounded,
                  label: l10n.onboardingCatalogUse4,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One "perfect for" line: a small spark-coloured icon and the occasion.
class _UseCase extends StatelessWidget {
  const _UseCase({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: AppTheme.spark),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: context.colors.ink,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
