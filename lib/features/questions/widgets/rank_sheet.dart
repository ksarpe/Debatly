import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/content_width.dart';
import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/models/rank.dart';
import '../../account/providers/stats_providers.dart';
import 'animated_flame_icon.dart';

/// Opens the rank sheet: the user's current rank, streak, progress to the next
/// rank, and the full controversy ladder. Styled to match [showSmaczkiSheet].
Future<void> showRankSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.colors.background,
    showDragHandle: true,
    isScrollControlled: true,
    // Tablets: keep the sheet a centred column instead of letting one line
    // of text run the full width of an iPad.
    constraints: const BoxConstraints(maxWidth: kReadingMaxWidth),
    // Without this the sheet (and its drag handle) can grow up behind the
    // status bar when the ladder is tall, leaving the handle in the notch /
    // safe area. `useSafeArea: true` keeps the top edge below it — the inner
    // SafeArea below then only has the bottom inset left to handle.
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _RankSheet(),
  );
}

/// Maps a rank's icon key (from the `ranks` table) to a Material glyph.
IconData rankIcon(String? key) {
  switch (key) {
    case 'seedling':
      return Icons.eco_rounded;
    case 'spark':
      return Icons.auto_awesome_rounded;
    case 'flame':
      return Icons.local_fire_department_rounded;
    case 'megaphone':
      return Icons.campaign_rounded;
    case 'mask':
      return Icons.theater_comedy_rounded;
    case 'storm':
      return Icons.cyclone_rounded;
    case 'bolt':
      return Icons.bolt_rounded;
    case 'whatshot':
      return Icons.whatshot_rounded;
    case 'wind':
      return Icons.air_rounded;
    case 'shield':
      return Icons.shield_rounded;
    case 'medal':
      return Icons.military_tech_rounded;
    case 'star':
      return Icons.stars_rounded;
    case 'diamond':
      return Icons.diamond_rounded;
    case 'crown':
      return Icons.workspace_premium_rounded;
    case 'trophy':
      return Icons.emoji_events_rounded;
    case 'rocket':
      return Icons.rocket_launch_rounded;
    default:
      return Icons.military_tech_rounded;
  }
}

class _RankSheet extends ConsumerWidget {
  const _RankSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(userStatsValueProvider);
    final ranksAsync = ref.watch(ranksProvider);
    final lang = Localizations.localeOf(context).languageCode;
    final streak = stats.currentStreak;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
        child: ranksAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              context.l10n.ranksLoadError,
              style: AppTypography.body(
                fontSize: 14,
              ).copyWith(color: context.colors.subtle),
            ),
          ),
          data: (ranks) {
            final ladder = [...ranks]..sort((a, b) => a.tier.compareTo(b.tier));
            final current = _currentRank(ladder, streak);
            final next = _nextRank(ladder, streak);

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Header(rank: current, streak: streak, lang: lang),
                if (stats.graceDaysLeft != null) ...[
                  const SizedBox(height: 12),
                  _GraceWarning(daysLeft: stats.graceDaysLeft!),
                ],
                const SizedBox(height: 20),
                _Progress(streak: streak, current: current, next: next),
                const SizedBox(height: 16),
                _LongestLine(longest: stats.longestStreak),
                const SizedBox(height: 20),
                Divider(color: context.colors.accent, height: 1),
                const SizedBox(height: 16),
                Text(
                  context.l10n.rankLadder.toUpperCase(),
                  style: AppTypography.eyebrow(
                    fontSize: 11,
                  ).copyWith(color: context.colors.subtle),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final r in ladder)
                          _LadderRow(
                            rank: r,
                            lang: lang,
                            unlocked: streak >= r.minStreak,
                            isCurrent: r.tier == current.tier,
                            // Every locked rank — including the very next one —
                            // is kept a blurred mystery, so a promotion is a
                            // full surprise. Only the streak threshold and the
                            // lock badge stay sharp, so the goal is still clear.
                            // Purely a local visual effect — the row data is
                            // still loaded, just obscured client-side.
                            obscured: streak < r.minStreak,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Rank _currentRank(List<Rank> ladder, int streak) {
    var result = ladder.first;
    for (final r in ladder) {
      if (streak >= r.minStreak) result = r;
    }
    return result;
  }

  Rank? _nextRank(List<Rank> ladder, int streak) {
    for (final r in ladder) {
      if (r.minStreak > streak) return r;
    }
    return null;
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.rank, required this.streak, required this.lang});

  final Rank rank;
  final int streak;
  final String lang;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.spark.withValues(alpha: 0.14),
            border: Border.all(color: AppTheme.spark.withValues(alpha: 0.45)),
          ),
          child: Icon(rankIcon(rank.icon), color: AppTheme.spark, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.yourRankUpper.toUpperCase(),
                style: AppTypography.eyebrow(
                  fontSize: 10.5,
                ).copyWith(color: context.colors.subtle),
              ),
              const SizedBox(height: 2),
              Text(
                rank.nameFor(lang).toUpperCase(),
                style: AppTypography.title(
                  fontSize: 30,
                ).copyWith(color: context.colors.ink),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(
                    Icons.local_fire_department_rounded,
                    color: Color(0xFFF59E0B),
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    context.l10n.streakDays(streak),
                    style: AppTypography.body(
                      fontSize: 14,
                    ).copyWith(color: context.colors.ink),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shown while the streak's "graces" are counting down: the user has missed a
/// day but hasn't lost a rank yet — this warns how many graces remain (one is
/// spent per missed day) before the next tier drop.
class _GraceWarning extends StatelessWidget {
  const _GraceWarning({required this.daysLeft});

  final int daysLeft;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: kGrace.withValues(alpha: 0.12),
        border: Border.all(color: kGrace.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.favorite_rounded, color: kGrace, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.l10n.streakGraceWarning(daysLeft),
              style: AppTypography.body(
                fontSize: 14,
              ).copyWith(color: context.colors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({
    required this.streak,
    required this.current,
    required this.next,
  });

  final int streak;
  final Rank current;
  final Rank? next;

  @override
  Widget build(BuildContext context) {
    if (next == null) {
      return Text(
        context.l10n.topRankRespect,
        style: AppTypography.body(fontSize: 14).copyWith(color: AppTheme.spark),
      );
    }

    final span = (next!.minStreak - current.minStreak).clamp(1, 1 << 30);
    final done = (streak - current.minStreak).clamp(0, span);
    final fraction = done / span;
    final remaining = next!.minStreak - streak;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 8,
            backgroundColor: context.colors.accent,
            valueColor: const AlwaysStoppedAnimation(AppTheme.spark),
          ),
        ),
        const SizedBox(height: 8),
        // The next rank is deliberately not named here — it stays blurred in
        // the ladder below until the streak actually unlocks it.
        Text(
          context.l10n.daysToNextRank(remaining),
          style: AppTypography.support(
            fontSize: 13,
          ).copyWith(color: context.colors.subtle),
        ),
      ],
    );
  }
}

class _LongestLine extends StatelessWidget {
  const _LongestLine({required this.longest});

  final int longest;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.emoji_events_outlined,
          color: context.colors.subtle,
          size: 16,
        ),
        const SizedBox(width: 6),
        Text(
          context.l10n.longestStreakDays(longest),
          style: AppTypography.support(
            fontSize: 13,
          ).copyWith(color: context.colors.subtle),
        ),
      ],
    );
  }
}

class _LadderRow extends StatelessWidget {
  const _LadderRow({
    required this.rank,
    required this.lang,
    required this.unlocked,
    required this.isCurrent,
    this.obscured = false,
  });

  final Rank rank;
  final String lang;
  final bool unlocked;
  final bool isCurrent;

  /// Blur this row's icon + name to keep a far-off rank a teaser (see the call
  /// site). The unlock threshold and lock badge stay sharp so the goal is clear.
  final bool obscured;

  @override
  Widget build(BuildContext context) {
    final fg = unlocked ? context.colors.ink : context.colors.subtle;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: isCurrent
            ? AppTheme.spark.withValues(alpha: 0.12)
            : context.colors.accent,
        border: isCurrent
            ? Border.all(color: AppTheme.spark.withValues(alpha: 0.5))
            : null,
      ),
      child: Row(
        children: [
          _blur(
            Icon(
              rankIcon(rank.icon),
              color: unlocked ? AppTheme.spark : context.colors.subtle,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _blur(
              // One weight per role: the current row is already lit by its
              // border + fill, so the name stays at BODY's single weight.
              Text(
                rank.nameFor(lang),
                style: AppTypography.body(fontSize: 15).copyWith(color: fg),
              ),
            ),
          ),
          Text(
            context.l10n.rankFrom(rank.minStreak),
            style: AppTypography.support().copyWith(
              color: context.colors.subtle,
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            unlocked ? Icons.check_circle_rounded : Icons.lock_outline_rounded,
            color: unlocked ? AppTheme.spark : context.colors.subtle,
            size: 16,
          ),
        ],
      ),
    );
  }

  /// Wraps [child] in a blur when this row is [obscured]; otherwise passes it
  /// through untouched.
  Widget _blur(Widget child) {
    if (!obscured) return child;
    return ImageFiltered(
      imageFilter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
      child: child,
    );
  }
}
