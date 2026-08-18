import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../account/providers/stats_providers.dart';
import 'stat_card_shell.dart';

/// Warm flame colour for the (placeholder) streak card.
const Color _kFlame = Color(0xFFFF7A29);

class StreakCard extends ConsumerWidget {
  const StreakCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streak = ref.watch(currentStreakProvider);
    final record = ref.watch(
      userStatsValueProvider.select((s) => s.longestStreak),
    );
    return StatCardShell(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.local_fire_department, color: _kFlame, size: 28),
          const SizedBox(height: 8),
          Text(
            '$streak',
            // 32 → 36: Barlow Condensed is narrower than the old Manrope 800,
            // so the numeral needs a touch more size to keep its presence.
            style: AppTypography.numeric(
              36,
            ).copyWith(color: context.colors.ink),
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.daysInARow.toUpperCase(),
            style: AppTypography.eyebrow(
              fontSize: 11,
            ).copyWith(color: context.colors.subtle),
          ),
          // Personal best, kept deliberately quiet beneath the headline streak.
          if (record > 0) ...[
            const SizedBox(height: 4),
            Text(
              context.l10n.streakRecord(record),
              style: AppTypography.support(
                fontSize: 11,
              ).copyWith(color: context.colors.subtle.withValues(alpha: 0.7)),
            ),
          ],
        ],
      ),
    );
  }
}
