import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_typography.dart';

/// The shared "premium" accent CTA: the spark gradient on a full stadium pill
/// with the orange glow and a black label ([AppTheme.ctaGradient] /
/// [AppTheme.ctaRadius] / [AppTheme.ctaGlow] / [AppTheme.ctaForeground]).
///
/// A null [onTap] renders it disabled — dimmed and without the glow, so a
/// dead button never reads as tappable. While [busy] the spinner replaces the
/// icon (or, without an [icon], the whole label) and taps are ignored, but the
/// button keeps its lit look: work in flight is not "disabled".
class SparkCtaButton extends StatelessWidget {
  const SparkCtaButton({
    super.key,
    required this.label,
    this.icon,
    this.busy = false,
    this.expand = false,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
    this.fontSize = 14,
  });

  final String label;

  /// Optional leading icon; the busy spinner takes its slot when set.
  final IconData? icon;

  final bool busy;

  /// Stretch to the full available width (form-style CTA) instead of hugging
  /// the content.
  final bool expand;

  final VoidCallback? onTap;

  final EdgeInsetsGeometry padding;

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final spinner = SizedBox.square(
      dimension: fontSize + 3,
      child: const CircularProgressIndicator(
        strokeWidth: 2,
        color: AppTheme.ctaForeground,
      ),
    );

    final Widget content;
    if (busy && icon == null) {
      content = spinner;
    } else {
      content = Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (busy)
            spinner
          else if (icon != null)
            Icon(icon, color: AppTheme.ctaForeground, size: fontSize + 3),
          if (busy || icon != null) const SizedBox(width: 8),
          // Flexible, or a long label next to the icon overflows the Row
          // horizontally at a large system text size (the icon cannot shrink,
          // so the text has to be the part that gives).
          Flexible(
            child: Text(
              label.toUpperCase(),
              textAlign: TextAlign.center,
              style: AppTypography.action(
                fontSize: fontSize,
              ).copyWith(color: AppTheme.ctaForeground),
            ),
          ),
        ],
      );
    }

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled || busy ? 1 : 0.45,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppTheme.ctaGradient,
          borderRadius: AppTheme.ctaRadius,
          boxShadow: enabled || busy ? AppTheme.ctaGlow : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: AppTheme.ctaRadius,
            onTap: busy ? null : onTap,
            child: Padding(
              padding: padding,
              child: expand ? Center(child: content) : content,
            ),
          ),
        ),
      ),
    );
  }
}
