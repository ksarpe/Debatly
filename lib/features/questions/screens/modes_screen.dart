import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/sub_screen_chrome.dart';
import '../../../data/models/question_mode.dart';
import '../../../services/analytics.dart';
import '../../account/providers/session_providers.dart';
import '../../monetization/widgets/pro_paywall_screen.dart';
import '../../monetization/widgets/purchase_settlement.dart';
import '../providers/mode_providers.dart';
import '../providers/question_providers.dart';
import '../widgets/animated_flame_icon.dart' show flameColor, kFlame;

/// Opens the modes screen — pushed as a sub-screen (title + X) like history
/// and favorites, never a sheet. Safe to open for any tier: the screen gates
/// itself.
Future<void> openModes(BuildContext context) {
  Analytics.log('modes_opened');
  return Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const ModesScreen()));
}

/// The modes screen, top to bottom: the header, one line of explanation, the
/// "Teraz grasz" card (the current scope, ticked), then one full-width row
/// per OTHER choice — the topic's name as a big heading over a three-word
/// description, an arrow on the right — a dashed "next mode / in the works"
/// row, and a footer line reassuring that switching keeps the history. No
/// counts, no rings, no save button: a tap IS the choice.
///
/// PRO: the current scope is the pinned mode or "all topics"; the rows list
/// everything else, so "all topics" becomes a row (the way back) once a mode
/// is pinned, and the pinned mode leaves the list. A tap pins and closes —
/// the feed reopens on the mode's first question, the daily one back swipe
/// away. FREE: the scope is the daily (what they actually play), every row
/// is locked (padlock instead of the arrow) and a tap opens the paywall; a
/// purchase then pins the tapped mode, so the person who paid for "Związki"
/// lands in "Związki".
class ModesScreen extends ConsumerWidget {
  const ModesScreen({super.key});

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref,
    QuestionMode? mode, {
    required bool premium,
  }) async {
    Analytics.log('mode_tile_tapped', {
      'mode': mode?.name ?? 'all',
      'premium': premium,
    });
    if (!premium) {
      final purchased = await showProPaywall(
        context,
        source: PaywallSource.modes,
      );
      if (!purchased || !context.mounted) return;
      final settled = await settleProPurchase(context, ref);
      if (!settled || !context.mounted) return;
    }
    final deck = ref.read(questionIndexProvider.notifier);
    if (mode == null) {
      Analytics.log('mode_cleared', {'from': 'modes'});
      deck.leaveMode();
    } else {
      deck.enterMode(mode);
      Analytics.log('mode_selected', {'mode': mode.name});
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final colors = context.colors;
    final premium = ref.watch(isPremiumProvider);
    final active = ref.watch(activeModeProvider);

    // The current scope: the pinned mode (PRO), else the whole catalog — for
    // a free user that is "the question of the day", which is what they are
    // actually playing.
    final String scopeName;
    final String scopeDescription;
    if (active != null) {
      scopeName = questionModeName(l10n, active);
      scopeDescription = questionModeDescription(l10n, active);
    } else if (premium) {
      scopeName = l10n.modesAllTopics;
      scopeDescription = l10n.modesAllTopicsDescription;
    } else {
      scopeName = l10n.dailyQuestionBadge;
      scopeDescription = l10n.modesDailyScopeDescription;
    }

    return Scaffold(
      backgroundColor: colors.background,
      body: Stack(
        children: [
          const TopGlow(),
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                24 + MediaQuery.paddingOf(context).bottom,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SubScreenHeader(
                        title: l10n.modesTitle,
                        onClose: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        premium
                            ? l10n.modesSubtitlePro
                            : l10n.modesSubtitleFree,
                        style: AppTypography.body(
                          fontSize: 14.5,
                        ).copyWith(color: colors.subtle),
                      ),
                      const SizedBox(height: 22),
                      _NowPlayingCard(
                        name: scopeName,
                        description: scopeDescription,
                      ),
                      const SizedBox(height: 12),
                      // "All topics" is a choice only while a mode is pinned
                      // (it is the way back); with nothing pinned it is the
                      // scope above. Free sees it too — locked, like the
                      // rest, because the whole catalog is the PRO thing.
                      if (active != null || !premium) ...[
                        _ModeRow(
                          name: l10n.modesAllTopics,
                          description: l10n.modesAllTopicsDescription,
                          locked: !premium,
                          onTap: () =>
                              _pick(context, ref, null, premium: premium),
                        ),
                        const SizedBox(height: 12),
                      ],
                      // Declaration order is screen order: the adult-themes
                      // mode is declared first and wears the flame.
                      for (final mode in QuestionMode.values)
                        if (mode != active) ...[
                          _ModeRow(
                            name: questionModeName(l10n, mode),
                            description: questionModeDescription(l10n, mode),
                            locked: !premium,
                            flame: mode == QuestionMode.intimacy,
                            onTap: () =>
                                _pick(context, ref, mode, premium: premium),
                          ),
                          const SizedBox(height: 12),
                        ],
                      const _ComingSoonRow(),
                      const SizedBox(height: 36),
                      Text(
                        l10n.modesFooter,
                        textAlign: TextAlign.center,
                        style: AppTypography.support(
                          fontSize: 12,
                        ).copyWith(color: colors.subtle),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The card above the list: "TERAZ GRASZ" over the current scope's name and
/// description, a filled spark tick on the right. Spark-bordered — it is the
/// one element on the screen that is about NOW rather than a choice, and it
/// is not tappable: the choices are the rows below it.
class _NowPlayingCard extends StatelessWidget {
  const _NowPlayingCard({required this.name, required this.description});

  final String name;
  final String description;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 16, 14),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.spark, width: 1.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.modesNowPlaying.toUpperCase(),
                  style: AppTypography.eyebrow(
                    fontSize: 10.5,
                  ).copyWith(color: AppTheme.spark),
                ),
                const SizedBox(height: 6),
                Text(
                  name.toUpperCase(),
                  style: AppTypography.display(
                    _kHeadingSize,
                  ).copyWith(color: colors.ink),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: AppTypography.support(
                    fontSize: 12.5,
                  ).copyWith(color: colors.subtle),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              color: AppTheme.spark,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 18,
              color: AppTheme.ctaForeground,
            ),
          ),
        ],
      ),
    );
  }
}

/// The heading size shared by the scope card and every row, so the list
/// reads as one column of equals.
const double _kHeadingSize = 24;

/// One choice: the topic's name as a big heading over its three-word
/// description, an arrow on the right (a padlock for free) — on the raised
/// card surface with the hairline border. The [flame] row (the adult-themes
/// mode) swaps the hairline for a slowly shimmering ember border with a
/// breathing glow, and a flame glyph in place of the arrow — see
/// [_FlameFrame].
class _ModeRow extends StatelessWidget {
  const _ModeRow({
    required this.name,
    required this.description,
    required this.locked,
    required this.onTap,
    this.flame = false,
  });

  final String name;
  final String description;
  final bool locked;
  final VoidCallback onTap;
  final bool flame;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final IconData trailing;
    final Color trailingColor;
    if (locked) {
      trailing = Icons.lock_outline;
      trailingColor = colors.subtle;
    } else if (flame) {
      trailing = Icons.local_fire_department_rounded;
      trailingColor = flameColor(context);
    } else {
      trailing = Icons.arrow_forward;
      trailingColor = colors.subtle;
    }
    final card = Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: colors.cardSurface,
          borderRadius: BorderRadius.circular(14),
          // The flame frame paints its own border on top.
          border: flame ? null : Border.all(color: colors.hairline),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.toUpperCase(),
                        style: AppTypography.display(
                          _kHeadingSize,
                        ).copyWith(color: colors.ink),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: AppTypography.support(
                          fontSize: 12.5,
                        ).copyWith(color: colors.subtle),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  trailing,
                  size: flame && !locked ? 20 : 18,
                  color: trailingColor,
                  shadows: flame && !locked
                      ? [
                          Shadow(
                            color: trailingColor.withValues(alpha: 0.6),
                            blurRadius: 12,
                          ),
                        ]
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return flame ? _FlameFrame(child: card) : card;
  }
}

/// The ember frame around the adult-themes row: a 1.5 px border whose
/// spark → amber → glow sweep turns slowly around the card, over a halo that
/// breathes in step — "lekko się mieni, jak płomień". One 4-second loop
/// drives both; every effect is an integer number of cycles over it, so the
/// wrap is seamless. Under reduced motion it is a still spark border with a
/// fixed soft glow, and the loop never starts.
class _FlameFrame extends StatefulWidget {
  const _FlameFrame({required this.child});

  final Widget child;

  @override
  State<_FlameFrame> createState() => _FlameFrameState();
}

class _FlameFrameState extends State<_FlameFrame>
    with SingleTickerProviderStateMixin {
  static const Duration _period = Duration(milliseconds: 4000);

  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: _period,
  );

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion can flip at runtime; re-evaluate whether the loop runs.
    if (!_reduceMotion && !_loop.isAnimating) {
      _loop.repeat();
    } else if (_reduceMotion && _loop.isAnimating) {
      _loop.stop();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduceMotion) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppTheme.sparkGlow.withValues(alpha: 0.16),
              blurRadius: 16,
              spreadRadius: 0.5,
            ),
          ],
        ),
        child: CustomPaint(
          foregroundPainter: const _FlameBorderPainter(phase: null),
          child: widget.child,
        ),
      );
    }
    return AnimatedBuilder(
      animation: _loop,
      child: widget.child,
      builder: (context, child) {
        final p = _loop.value;
        // One slow breath per loop.
        final breath = 0.5 + 0.5 * math.sin(2 * math.pi * p);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppTheme.sparkGlow.withValues(
                  alpha: 0.10 + 0.14 * breath,
                ),
                blurRadius: 14 + 10 * breath,
                spreadRadius: 0.5,
              ),
            ],
          ),
          child: CustomPaint(
            foregroundPainter: _FlameBorderPainter(phase: p),
            child: child,
          ),
        );
      },
    );
  }
}

/// Paints the frame's border. With a [phase] the stroke is a sweep gradient
/// (spark → amber → glow → spark) rotated by that fraction of a turn, so the
/// bright band travels once around the card per loop; a null phase is the
/// still, plain-spark border for reduced motion.
class _FlameBorderPainter extends CustomPainter {
  const _FlameBorderPainter({required this.phase});

  final double? phase;

  static const double _stroke = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(_stroke / 2);
    final rrect = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(14 - _stroke / 2),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke;
    final phase = this.phase;
    if (phase == null) {
      paint.color = AppTheme.spark;
    } else {
      paint.shader = SweepGradient(
        colors: const [
          AppTheme.spark,
          kFlame,
          AppTheme.sparkGlow,
          AppTheme.spark,
          AppTheme.spark,
        ],
        stops: const [0, 0.18, 0.36, 0.55, 1],
        transform: GradientRotation(2 * math.pi * phase),
      ).createShader(rect);
    }
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_FlameBorderPainter old) => old.phase != phase;
}

/// The dashed placeholder at the foot of the list: the next mode, "in the
/// works". Dimmed and inert.
class _ComingSoonRow extends StatelessWidget {
  const _ComingSoonRow();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    return Opacity(
      opacity: 0.55,
      child: CustomPaint(
        painter: _DashedBorderPainter(color: colors.hairline),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.modesComingSoonTitle.toUpperCase(),
                      style: AppTypography.display(
                        _kHeadingSize,
                      ).copyWith(color: colors.subtle),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.modesComingSoonBody,
                      style: AppTypography.support(
                        fontSize: 12.5,
                      ).copyWith(color: colors.subtle),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(Icons.hourglass_top_rounded, size: 16, color: colors.subtle),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color});

  final Color color;

  static const double _dash = 6;
  static const double _gap = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.6),
          const Radius.circular(14),
        ),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + _dash), paint);
        distance += _dash + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color;
}
