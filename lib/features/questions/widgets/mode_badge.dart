import 'package:flutter/material.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import 'daily_question_badge.dart' show kQuestionBadgeMaxTextScale;

/// The quiet pill worn by every non-daily card while a mode is active —
/// "ZWIĄZKI", "RODZINA" … — so a PRO user always knows the feed is pinned to
/// a topic. Same neutral chrome as the "PYTANIE DNIA" pill (an identity
/// label, not a highlight); the daily keeps its own pill and never wears this
/// one. Tapping it explains the mode and where the way out is.
class ModeBadge extends StatelessWidget {
  const ModeBadge({super.key, required this.label});

  /// The localized mode name (see `questionModeName`).
  final String label;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: kQuestionBadgeMaxTextScale,
      child: Tooltip(
        message: context.l10n.modeBadgeTooltip,
        triggerMode: TooltipTriggerMode.tap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: context.colors.accent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: context.colors.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.grid_view_rounded, size: 11, color: AppTheme.spark),
              const SizedBox(width: 6),
              Text(
                label.toUpperCase(),
                style: AppTypography.eyebrow(
                  fontSize: 11,
                  tracking: 0.14,
                ).copyWith(color: context.colors.ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
