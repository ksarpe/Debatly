import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/models/conformity_stats.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../services/analytics.dart';
import '../providers/question_providers.dart';
import 'debate_profile_section.dart';

/// The "oś zgodności" (conformity axis): a slide-down panel showing how often
/// the user votes with the community majority vs the minority, as a marker on
/// a five-step horizontal axis (Zawsze pod prąd → Zawsze z tłumem).
///
/// Opened from [ConformityAxisButton] in the question screen's top bar. Slides
/// in from the top over a dimmed barrier and covers roughly the top third of
/// the screen; tapping outside (or system back) closes it — a read-only stat,
/// so there is nothing to confirm.

/// The rung's localized display name (sentence case; callers uppercase where
/// the design wants it).
///
/// NAMING RULE, load-bearing: **the axis gets positional PHRASES, the 2×2
/// grid gets nouns.** A phrase describes a spot on a scale; a noun claims an
/// identity. The old noun rungs collided head-on with the grid ("Samotny
/// wilk" lived on both, meaning different things), and phrases can't collide
/// with future nouns by construction — keep any new rung a phrase.
String conformityTierName(AppLocalizations l10n, ConformityTier tier) {
  return switch (tier) {
    ConformityTier.loneWolf => l10n.axisRungAgainst2,
    ConformityTier.rebel => l10n.axisRungAgainst1,
    ConformityTier.independent => l10n.axisRungMiddle,
    ConformityTier.inTheCurrent => l10n.axisRungWith1,
    ConformityTier.crowdVoice => l10n.axisRungWith2,
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
  // Both of them: the panel renders the axis AND the debate profile below it,
  // and a profile that errored renders as nothing at all, so leaving it out
  // made the retry gesture fix half the panel and silently skip the half the
  // user came for.
  final container = ProviderScope.containerOf(context, listen: false);
  if (container.read(conformityStatsProvider).hasError) {
    container.invalidate(conformityStatsProvider);
  }
  if (container.read(debateProfileProvider).hasError) {
    container.invalidate(debateProfileProvider);
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
            child: ConstrainedBox(
              // The profile section under the axis can outgrow the top third
              // on small phones — the panel then scrolls instead of clipping
              // the retention hook off the bottom.
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      stats.when(
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
                      // The 2×2 debate profile — an EXTENSION of this axis,
                      // deliberately not a screen of its own. Renders its own
                      // locked/provisional/full states and nothing at all
                      // while its data is missing.
                      const DebateProfileSection(),
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
        // Wrap, not Row: at a large system font the title and the percentage
        // together outrun the panel, and a Row would clip the percentage —
        // the one number in this header — off the right edge. Wrapped, it
        // simply drops to a second line.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 2,
          children: [
            Text(
              l10n.conformityTitle.toUpperCase(),
              style: AppTypography.eyebrow(
                fontSize: 11,
                tracking: 0.18,
              ).copyWith(color: context.colors.subtle),
            ),
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
///
/// The badge is set at full size and merely *positioned* over its fifth — it
/// is NOT boxed into it. A rung phrase ("Częściej pod prąd") is roughly half
/// the panel wide, so squeezing it into a fifth (the old `Expanded` +
/// `FittedBox`) scaled it down to an unreadable smudge. Instead the offset is
/// computed from the measured badge width and clamped to the panel, so an end
/// rung's badge hugs the edge rather than hanging off it.
class _TierBadgeRow extends StatelessWidget {
  const _TierBadgeRow({required this.activeIndex, required this.l10n});

  final int activeIndex;
  final AppLocalizations l10n;

  static const double _hPad = 7;

  @override
  Widget build(BuildContext context) {
    final label = conformityTierName(
      l10n,
      ConformityTier.values[activeIndex],
    ).toUpperCase();
    // One style object for both the measurement and the Text, so the two can
    // never drift apart.
    final style = AppTypography.eyebrow(
      fontSize: 11,
      tracking: 0.12,
    ).copyWith(color: AppTheme.ctaForeground);

    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final badgeWidth = painter.width + _hPad * 2;
    painter.dispose();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final centre =
            width * (activeIndex + 0.5) / ConformityTier.values.length;
        final left = clampDouble(
          centre - badgeWidth / 2,
          0,
          math.max(0, width - badgeWidth),
        );
        return Padding(
          padding: EdgeInsets.only(left: left),
          child: Align(
            alignment: Alignment.centerLeft,
            // Bounded width + scaleDown: the last resort for a badge that
            // outgrows the whole panel (huge system font), never the norm.
            child: SizedBox(
              width: math.min(badgeWidth, width),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: _hPad,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.spark,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(label, maxLines: 1, style: style),
                ),
              ),
            ),
          ),
        );
      },
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
///
/// The rungs are positional PHRASES ("Częściej pod prąd"), never one word, so
/// they must WRAP inside their fifth of the axis. A plain `FittedBox` here
/// laid each phrase out on one unconstrained line and scaled it to ~4px —
/// five illegible smudges running into each other. Instead every label wraps
/// at the full label size, and the size is only reduced when the longest
/// WORD ("CZĘŚCIEJ", 51.5px at 10px) would not fit its cell — on a 320dp
/// screen, or under a large system font. The reduction is measured once and
/// applied to all five, because five labels at four different sizes look
/// broken; a per-cell shrink is what mid-word breaks are made of.
class _TierLabelRow extends StatelessWidget {
  const _TierLabelRow({required this.activeIndex, required this.l10n});

  final int activeIndex;
  final AppLocalizations l10n;

  /// Nominal label size, and the ceiling a large system font may lift it to.
  /// Past ~1.2x the axis would be all label and no axis.
  static const double _size = 10;
  static const double _maxSize = 12;

  /// Breathing room between neighbouring labels. Deliberately small: at 320dp
  /// each cell is only 56px wide and the longest word needs 51.5 of them.
  static const double _gap = 2;

  /// Words break on spaces and on the hyphen in "Fifty-fifty".
  static final RegExp _wordBreak = RegExp('[ -]');

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cell =
            constraints.maxWidth / ConformityTier.values.length - _gap * 2;
        final fontSize = _fittingSize(context, cell);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final tier in ConformityTier.values)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _gap),
                  child: Text(
                    conformityTierName(l10n, tier).toUpperCase(),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    // The system font is already baked into [fontSize] by
                    // [_fittingSize] — scaling it again would undo the fit.
                    textScaler: TextScaler.noScaling,
                    style: _style(fontSize).copyWith(
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
      },
    );
  }

  static TextStyle _style(double fontSize) =>
      AppTypography.eyebrow(fontSize: fontSize, tracking: 0.04);

  /// The size at which the longest WORD of any rung still fits one cell.
  ///
  /// Starts from the system-font size (capped at [_maxSize]) and shrinks only
  /// when it has to — a 320dp screen, or a large accessibility font. Because
  /// [AppTypography.eyebrow] derives its tracking from the font size, a label's
  /// width is exactly linear in that size, so one division lands on the fit;
  /// scaling via [TextScaler] would not, as letter spacing does not scale with
  /// it. The size is measured once and shared by all five labels — five labels
  /// at five sizes look broken, and a per-cell shrink is what mid-word breaks
  /// are made of.
  double _fittingSize(BuildContext context, double cell) {
    final scaled = MediaQuery.textScalerOf(
      context,
    ).scale(_size).clamp(_size, _maxSize);
    if (cell <= 0) return scaled;

    final direction = Directionality.of(context);
    final style = _style(scaled);
    var widest = 0.0;
    for (final tier in ConformityTier.values) {
      for (final word in conformityTierName(
        l10n,
        tier,
      ).toUpperCase().split(_wordBreak)) {
        final painter = TextPainter(
          text: TextSpan(text: word, style: style),
          textDirection: direction,
          textScaler: TextScaler.noScaling,
        )..layout();
        widest = math.max(widest, painter.width);
        painter.dispose();
      }
    }
    return widest <= cell ? scaled : scaled * cell / widest;
  }
}
