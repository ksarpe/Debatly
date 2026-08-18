import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/models/conformity_stats.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../services/analytics.dart';
import '../providers/question_providers.dart';

/// The "oś zgodności" (conformity axis): a slide-down panel showing how often
/// the user votes with the community majority vs the minority, as a marker on
/// a five-step horizontal axis (Samotny wilk → Głos tłumu).
///
/// Opened from [ConformityAxisButton] in the question screen's top bar. Slides
/// in from the top over a dimmed barrier and covers roughly the top third of
/// the screen; tapping outside (or system back) closes it — a read-only stat,
/// so there is nothing to confirm.

/// The tier's localized display name (title case; callers uppercase where the
/// design wants it).
String conformityTierName(AppLocalizations l10n, ConformityTier tier) {
  return switch (tier) {
    ConformityTier.loneWolf => l10n.conformityTierLoneWolf,
    ConformityTier.rebel => l10n.conformityTierRebel,
    ConformityTier.independent => l10n.conformityTierIndependent,
    ConformityTier.inTheCurrent => l10n.conformityTierInTheCurrent,
    ConformityTier.crowdVoice => l10n.conformityTierCrowdVoice,
  };
}

/// Top-bar icon that opens the conformity panel. Lives in the app bar's
/// top-LEFT corner (`leading`) — a balance-scales glyph: the axis weighs the
/// user's votes against the majority, "which side do you tip toward?".
class ConformityAxisButton extends StatelessWidget {
  const ConformityAxisButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.balance),
      tooltip: context.l10n.conformityTooltip,
      onPressed: () => showConformityPanel(context),
    );
  }
}

/// Slides the conformity panel down from the top edge. Dismissible via the
/// barrier and system back; honours reduced motion by skipping the slide.
Future<void> showConformityPanel(BuildContext context) {
  Analytics.log('conformity_panel_opened');
  // The provider is kept alive (and refreshed) by QuestionScreen, so a failed
  // fetch would otherwise stick as "try again in a moment" for the whole
  // session — opening the panel is the user's retry gesture.
  final container = ProviderScope.containerOf(context, listen: false);
  if (container.read(conformityStatsProvider).hasError) {
    container.invalidate(conformityStatsProvider);
  }
  final reduceMotion = MediaQuery.of(context).disableAnimations;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'conformity',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 280),
    pageBuilder: (_, _, _) => const ConformityPanel(),
    transitionBuilder: (_, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -1),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

/// The panel body: fetches the caller's conformity stats fresh on every open
/// (the aggregate moves with every vote — the user's and everyone else's).
class ConformityPanel extends ConsumerWidget {
  const ConformityPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final stats = ref.watch(conformityStatsProvider);

    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: double.infinity,
        child: Material(
          color: context.colors.cardSurface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
          ),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              child: stats.when(
                loading: () => const SizedBox(
                  height: 140,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, _) => SizedBox(
                  height: 140,
                  child: Center(
                    child: Text(
                      l10n.conformityLoadError,
                      textAlign: TextAlign.center,
                      style: AppTypography.body(
                        fontSize: 14,
                      ).copyWith(color: context.colors.subtle),
                    ),
                  ),
                ),
                data: (value) => _ConformityView(stats: value),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConformityView extends StatelessWidget {
  const _ConformityView({required this.stats});

  final ConformityStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tier = stats.tier;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              l10n.conformityTitle.toUpperCase(),
              style: AppTypography.eyebrow(
                fontSize: 11,
                tracking: 0.18,
              ).copyWith(color: context.colors.subtle),
            ),
            const Spacer(),
            if (stats.hasData)
              Text(
                l10n.conformityPctLine(stats.majorityPct),
                style: AppTypography.support(
                  fontSize: 12.5,
                ).copyWith(color: context.colors.subtle),
              ),
          ],
        ),
        const SizedBox(height: 18),
        if (!stats.hasData)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              l10n.conformityEmpty,
              style: AppTypography.body(
                fontSize: 14,
                height: 1.4,
              ).copyWith(color: context.colors.subtle),
            ),
          )
        else ...[
          _TierBadgeRow(activeIndex: tier.index, l10n: l10n),
          const SizedBox(height: 6),
          _AxisBar(activeIndex: tier.index, fraction: stats.majorityFraction),
          const SizedBox(height: 8),
          _TierLabelRow(activeIndex: tier.index, l10n: l10n),
          ..._nextTierFooter(context, l10n),
        ],
      ],
    );
  }

  /// The "Do stopnia X — N głosów z większością / +Y%" progress card, present
  /// only when there IS a next tier up the axis and real progress to show.
  List<Widget> _nextTierFooter(BuildContext context, AppLocalizations l10n) {
    final next = stats.nextTier;
    final votesNeeded = stats.votesWithMajorityToNextTier;
    if (next == null || votesNeeded == null) return const [];
    final deltaPct = next.lowerBoundFifths * 20 - stats.majorityPct;

    return [
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: context.colors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.colors.hairline),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.conformityNextTierLabel(
                      conformityTierName(l10n, next),
                    ),
                    style: AppTypography.body(
                      fontSize: 14,
                    ).copyWith(color: context.colors.ink),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    l10n.conformityVotesNeeded(votesNeeded),
                    style: AppTypography.support().copyWith(
                      color: context.colors.subtle,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '+$deltaPct%',
              style: AppTypography.numeric(20).copyWith(color: AppTheme.spark),
            ),
          ],
        ),
      ),
    ];
  }
}

/// The current tier's name as an orange badge sitting over its axis segment.
class _TierBadgeRow extends StatelessWidget {
  const _TierBadgeRow({required this.activeIndex, required this.l10n});

  final int activeIndex;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final tier in ConformityTier.values)
          Expanded(
            child: tier.index == activeIndex
                ? Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.spark,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          conformityTierName(l10n, tier).toUpperCase(),
                          maxLines: 1,
                          style: AppTypography.eyebrow(
                            fontSize: 11,
                            tracking: 0.12,
                          ).copyWith(color: AppTheme.ctaForeground),
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
      ],
    );
  }
}

/// The five-segment axis with a thin marker at the user's exact position.
class _AxisBar extends StatelessWidget {
  const _AxisBar({required this.activeIndex, required this.fraction});

  final int activeIndex;

  /// Marker position along the whole axis, 0..1 (= share of votes with the
  /// majority).
  final double fraction;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            children: [
              for (final tier in ConformityTier.values)
                Expanded(
                  child: Container(
                    height: 12,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: tier.index == activeIndex
                          ? AppTheme.spark
                          : AppTheme.spark.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
            ],
          ),
          // The exact-position notch: Alignment maps -1..1, the fraction 0..1.
          Positioned.fill(
            child: Align(
              alignment: Alignment(fraction * 2 - 1, 0),
              child: Container(
                width: 3,
                height: 20,
                decoration: BoxDecoration(
                  color: context.colors.ink,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The five tier names under the axis, the active one lit in spark orange.
class _TierLabelRow extends StatelessWidget {
  const _TierLabelRow({required this.activeIndex, required this.l10n});

  final int activeIndex;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final tier in ConformityTier.values)
          Expanded(
            // FittedBox: the widest names ("NIEZALEŻNY") would overrun their
            // fifth of the axis at the eyebrow's tracked 10px — shrink-to-fit
            // beats a mid-word break.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                conformityTierName(l10n, tier).toUpperCase(),
                textAlign: TextAlign.center,
                maxLines: 2,
                style: AppTypography.eyebrow(fontSize: 10, tracking: 0.12)
                    .copyWith(
                      height: 1.25,
                      color: tier.index == activeIndex
                          ? AppTheme.spark
                          : context.colors.subtle,
                    ),
              ),
            ),
          ),
      ],
    );
  }
}
