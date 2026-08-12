import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/fit_or_scroll.dart';

/// One intro slide: a glyph up top, a bold title, and a paragraph of copy —
/// vertically centred so every card has the same rhythm.
class OnboardingIntroCard extends StatelessWidget {
  const OnboardingIntroCard({
    super.key,
    required this.glyph,
    required this.title,
    required this.body,
  });

  final Widget glyph;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    // The very first screen of the app, so it has to survive a large system
    // font and a short window (an iPad Slide Over column) rather than clipping
    // its own body copy — which it did, silently, past ~1.4x text.
    return FitOrScroll(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            glyph,
            const SizedBox(height: 40),
            Text(
              title,
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
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.subtle,
                fontSize: 16,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
