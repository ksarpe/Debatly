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
                      for (final mode in QuestionMode.values)
                        if (mode != active) ...[
                          _ModeRow(
                            name: questionModeName(l10n, mode),
                            description: questionModeDescription(l10n, mode),
                            locked: !premium,
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
/// card surface with the hairline border.
class _ModeRow extends StatelessWidget {
  const _ModeRow({
    required this.name,
    required this.description,
    required this.locked,
    required this.onTap,
  });

  final String name;
  final String description;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: colors.cardSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.hairline),
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
                  locked ? Icons.lock_outline : Icons.arrow_forward,
                  size: 18,
                  color: colors.subtle,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
