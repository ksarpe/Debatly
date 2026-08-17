import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// A round, softly-lit icon container — the visual anchor at the top of each
/// feature card.
class OnboardingGlyphBubble extends StatelessWidget {
  const OnboardingGlyphBubble({
    super.key,
    required this.icon,
    required this.color,
  });

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 112,
      height: 112,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.30)),
        // The halo is painted in the brand glow hue regardless of the glyph
        // colour, so every orange glow in the app reads as one light.
        boxShadow: [
          BoxShadow(
            color: AppTheme.sparkGlow.withValues(alpha: 0.28),
            blurRadius: 28,
            spreadRadius: -6,
          ),
        ],
      ),
      child: Center(
        child: Icon(
          icon,
          size: 52,
          color: color,
          shadows: [
            Shadow(
              color: AppTheme.sparkGlow.withValues(alpha: 0.6),
              blurRadius: 16,
            ),
          ],
        ),
      ),
    );
  }
}
