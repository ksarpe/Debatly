import 'package:flutter/material.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';

/// The small "NOWE" pill worn by a question added within the freshness window
/// (see `newQuestionIdsProvider`).
///
/// Its job is expectation-setting, not decoration: a just-added question has
/// had little time to collect votes, so without the badge a thin community
/// split reads as "nobody cares" instead of "you're early". Tapping the pill
/// spells that out in a tooltip.
///
/// Painted in the spark orange so it reads as a highlight, not a warning, on
/// both the black and the light canvas — the tint from the shared accent, the
/// label from the canvas-resolved [AppColors.sparkInk] (the accent itself on a
/// 16%-spark tint measured 2.5:1 on the light canvas).
class NewQuestionBadge extends StatelessWidget {
  const NewQuestionBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: context.l10n.newQuestionTooltip,
      // The explanation is the point — surface it on a plain tap, not only the
      // long-press nobody discovers.
      triggerMode: TooltipTriggerMode.tap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.spark.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppTheme.spark.withValues(alpha: 0.45)),
        ),
        child: Text(
          context.l10n.newQuestionBadge.toUpperCase(),
          style: AppTypography.eyebrow(
            fontSize: 11,
            tracking: 0.14,
          ).copyWith(color: context.colors.sparkInk),
        ),
      ),
    );
  }
}
