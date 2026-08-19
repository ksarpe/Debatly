import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';

/// The single primary CTA — a glowing spark-gradient pill.
///
/// A null [onTap] renders it disabled (dimmed, no glow): on the paywall this
/// only happens when the offering has no monthly plan to preselect, so the
/// button waits visibly until one is tapped.
class PaywallCtaButton extends StatelessWidget {
  const PaywallCtaButton({
    super.key,
    required this.label,
    required this.busy,
    required this.onTap,
    this.caption,
  });

  final String label;

  /// Optional second line rendered inside the pill, under [label], in a
  /// smaller muted type — e.g. the day wall's "(new sets every week!)".
  final String? caption;

  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : 0.45,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppTheme.ctaGradient,
          borderRadius: AppTheme.ctaRadius,
          boxShadow: enabled ? AppTheme.ctaGlow : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: AppTheme.ctaRadius,
            onTap: busy ? null : onTap,
            // A MINIMUM height, not a fixed one. The pill used to be a hard 54 /
            // 62 around an unbounded Column, so at a large system text size the
            // Polish copy ("ODBLOKUJ PONAD 500 PYTAŃ" over "(co tydzień nowe
            // zestawy!)") wrapped, outgrew the box and overflowed. Now the pill
            // grows with its label; padding, not a magic number, sets the height
            // a phone actually sees.
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: caption == null ? 54 : 62),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Center(
                  child: busy
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppTheme.ctaForeground,
                          ),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              label.toUpperCase(),
                              textAlign: TextAlign.center,
                              style: AppTypography.action(
                                fontSize: 14,
                              ).copyWith(color: AppTheme.ctaForeground),
                            ),
                            if (caption != null)
                              Text(
                                caption!,
                                textAlign: TextAlign.center,
                                style: AppTypography.support().copyWith(
                                  color: AppTheme.ctaForeground.withValues(
                                    alpha: 0.85,
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
