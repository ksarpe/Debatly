import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

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
            child: SizedBox(
              height: caption == null ? 54 : 62,
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
                            label,
                            style: const TextStyle(
                              color: AppTheme.ctaForeground,
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                            ),
                          ),
                          if (caption != null)
                            Text(
                              caption!,
                              style: TextStyle(
                                color: AppTheme.ctaForeground.withValues(
                                  alpha: 0.85,
                                ),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
