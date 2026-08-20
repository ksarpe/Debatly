import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';

/// How far the feed's question pills (this one and `NewQuestionBadge`) follow
/// the system font — the same 1.6 ceiling as the bottom overlay and the vote
/// tiles. A status pill is the least important text on the screen; letting it
/// track a 3x accessibility font just steals height from the question the
/// pill is labelling.
const double kQuestionBadgeMaxTextScale = 1.6;

/// The tallest a question pill can render: one 11px eyebrow line (rounded up
/// to 16 to cover the line height) grown as far as the pills scale, plus the
/// vertical padding (8) and the border (2).
///
/// [QuestionBody]'s `_minGroupHeight` adds this to the group's floor whenever
/// a pill is shown — a height the floor doesn't know about is exactly how the
/// question ends up painted over the TAK/NIE row on a small viewport (see the
/// flip-line incident documented on `votePanelExtrasMaxHeight`).
double questionBadgeMaxHeight(BuildContext context) {
  final scale = MediaQuery.textScalerOf(context).scale(1);
  return 16 * math.min(kQuestionBadgeMaxTextScale, math.max(1, scale)) + 10;
}

/// The quiet "PYTANIE DNIA" pill worn by the shared daily question — the one
/// question the whole community debates on a given date (see `daily_picks`
/// server-side).
///
/// Its job is framing: the daily used to be indistinguishable from any other
/// card, so nothing told a PRO user swiping the catalog which question the
/// world is arguing about today, and nothing told a free user their one
/// question is a shared moment rather than a random draw. Tapping the pill
/// spells that out in a tooltip.
///
/// Deliberately NOT the spark orange of [NewQuestionBadge]: that pill is a
/// highlight ("you're early"), this one is an identity label, so it sits on
/// the neutral raised-surface tint with the plain ink.
class DailyQuestionBadge extends StatelessWidget {
  const DailyQuestionBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: kQuestionBadgeMaxTextScale,
      child: Tooltip(
        message: context.l10n.dailyQuestionTooltip,
        // The explanation is the point — surface it on a plain tap, not only
        // the long-press nobody discovers.
        triggerMode: TooltipTriggerMode.tap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: context.colors.accent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: context.colors.hairline),
          ),
          child: Text(
            context.l10n.dailyQuestionBadge.toUpperCase(),
            style: AppTypography.eyebrow(
              fontSize: 11,
              tracking: 0.14,
            ).copyWith(color: context.colors.ink),
          ),
        ),
      ),
    );
  }
}
