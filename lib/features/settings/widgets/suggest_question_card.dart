import 'package:flutter/material.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';

/// The "Suggest a question" entry on the Settings hub — deliberately its own
/// spark-bordered card rather than a row inside Preferences, so the one action
/// that feeds the catalog back stays visible at a glance.
///
/// Opens the suggestion sheet (see `showSuggestQuestionSheet`).
class SuggestQuestionCard extends StatelessWidget {
  const SuggestQuestionCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.cardSurface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.spark.withValues(alpha: 0.45)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.spark.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lightbulb_outline_rounded,
                    color: AppTheme.spark,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.suggestQuestionTitle,
                        style: AppTypography.body(
                          fontSize: 15,
                        ).copyWith(color: colors.ink),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.l10n.suggestQuestionSettingsSubtitle,
                        style: AppTypography.support(
                          fontSize: 13,
                        ).copyWith(color: colors.subtle),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: colors.subtle, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
