import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/feedback/haptics.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/models/smaczek.dart';
import '../../../data/models/vote_result.dart';
import 'falling_words_text.dart';
import 'vote_visuals.dart';

/// How the user answered the argument thrown at them between their vote and the
/// community split.
enum ChallengeOutcome {
  /// They stood by the answer they gave.
  held,

  /// They changed their mind — the vote is re-cast for the other side.
  flipped,
}

/// Drops one smaczek between the vote and the result.
///
/// The user has just answered; before the percentages appear, the argument
/// aimed at THEIR side falls in word by word — the same falling-words motion
/// the feed uses for a question — and lands on their own answer, which visibly
/// shakes. Then, and only then, they say whether they are holding.
///
/// Returns [ChallengeOutcome.held] or [ChallengeOutcome.flipped]. It is never a
/// trap: system back resolves as "held" and the result appears, so the worst a
/// confused user can do is keep the answer they already gave.
Future<ChallengeOutcome> showSmaczekChallenge(
  BuildContext context, {
  required Smaczek smaczek,
  required int choice,
}) async {
  final outcome = await Navigator.of(context).push<ChallengeOutcome>(
    PageRouteBuilder<ChallengeOutcome>(
      opaque: true,
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, _, _) =>
          SmaczekChallengeScreen(smaczek: smaczek, choice: choice),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
  return outcome ?? ChallengeOutcome.held;
}

/// The challenge itself. Public for the widget tests, which drive it directly
/// rather than through the whole vote flow.
class SmaczekChallengeScreen extends StatefulWidget {
  const SmaczekChallengeScreen({
    super.key,
    required this.smaczek,
    required this.choice,
  });

  final Smaczek smaczek;

  /// The side the user just voted ([VoteResult.yes] / [VoteResult.no]).
  final int choice;

  @override
  State<SmaczekChallengeScreen> createState() => _SmaczekChallengeScreenState();
}

class _SmaczekChallengeScreenState extends State<SmaczekChallengeScreen>
    with TickerProviderStateMixin {
  /// The hit: a damped side-to-side shake of the tile the argument landed on.
  static const Duration _impactDuration = Duration(milliseconds: 520);

  /// The answer: the tile flashes (held) or tips over and goes out (flipped).
  static const Duration _verdictDuration = Duration(milliseconds: 420);

  late final AnimationController _impact = AnimationController(
    vsync: this,
    duration: _impactDuration,
  );
  late final AnimationController _verdict = AnimationController(
    vsync: this,
    duration: _verdictDuration,
  );

  /// True once the last word has landed — the buttons only appear after the
  /// argument has actually hit.
  bool _landed = false;

  /// Set once the user answers; drives which way [_verdict] plays and stops a
  /// second tap from resolving the route twice.
  ChallengeOutcome? _outcome;

  bool get _mineIsYes => widget.choice == VoteResult.yes;

  @override
  void dispose() {
    _impact.dispose();
    _verdict.dispose();
    super.dispose();
  }

  /// Fired by [FallingWordsText] as the last word settles: the argument has
  /// arrived, so it hits.
  void _onArgumentLanded() {
    if (!mounted || _landed) return;
    setState(() => _landed = true);
    if (MediaQuery.disableAnimationsOf(context)) return;
    Haptics.impact();
    _impact.forward(from: 0);
  }

  Future<void> _resolve(ChallengeOutcome outcome) async {
    if (_outcome != null) return;
    setState(() => _outcome = outcome);
    Haptics.confirm();
    if (!MediaQuery.disableAnimationsOf(context)) {
      await _verdict.forward(from: 0);
    }
    if (!mounted) return;
    Navigator.of(context).pop(outcome);
  }

  /// Damped side-to-side wiggle of the struck tile — sharp at the moment of
  /// impact, gone within half a second.
  double _shakeDx(double t) => math.sin(t * math.pi * 7) * 7 * (1 - t);

  /// A short brightening as the user holds their ground, back to normal by the
  /// end. Reads as "you took it".
  double _flashOpacity(double t) => math.sin(t * math.pi) * 0.5;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final flipping = _outcome == ChallengeOutcome.flipped;

    return PopScope(
      // System back is a legitimate way out and means "I'm keeping my answer" —
      // the result appears either way, so the gate is never a dead end.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _resolve(ChallengeOutcome.held);
      },
      child: Scaffold(
        backgroundColor: colors.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
            child: Align(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: kReadingMaxWidth),
                child: Column(
                  children: [
                    Text(
                      context.l10n.smaczekChallengeEyebrow,
                      textAlign: TextAlign.center,
                      style: AppTypography.eyebrow().copyWith(
                        color: colors.subtle,
                      ),
                    ),
                    // The argument owns the middle of the screen, exactly as a
                    // question does on the feed — same falling words, same
                    // stroke-and-fill type, same per-word haptic tick.
                    Expanded(
                      child: Center(
                        child: FallingWordsText(
                          widget.smaczek.text ?? '',
                          animate: !MediaQuery.disableAnimationsOf(context),
                          onWordLanded: Haptics.tick,
                          onFinished: _onArgumentLanded,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _AnswerTiles(
                      mineIsYes: _mineIsYes,
                      impact: _impact,
                      verdict: _verdict,
                      outcome: _outcome,
                      shakeDx: _shakeDx,
                      flashOpacity: _flashOpacity,
                    ),
                    const SizedBox(height: 24),
                    // Held back until the argument has landed: answering before
                    // it arrives would make the whole beat pointless.
                    AnimatedOpacity(
                      opacity: _landed ? 1 : 0,
                      duration: const Duration(milliseconds: 260),
                      child: IgnorePointer(
                        ignoring: !_landed || _outcome != null,
                        child: Row(
                          children: [
                            Expanded(
                              child: _ChallengeButton(
                                label: context.l10n.smaczekChallengeHold,
                                primary: true,
                                onTap: () => _resolve(ChallengeOutcome.held),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _ChallengeButton(
                                label: context.l10n.smaczekChallengeFlip,
                                primary: false,
                                dimmed: flipping,
                                onTap: () => _resolve(ChallengeOutcome.flipped),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The two slanted vote tiles, laid out on the same grid as the result bars.
///
/// The side the user picked is lit and is the one the argument hits; the other
/// sits faded beside it. On a flip the lit tile tips over and goes out while
/// the other one comes up — the swap is the whole message, so it is animated
/// rather than simply re-rendered.
class _AnswerTiles extends StatelessWidget {
  const _AnswerTiles({
    required this.mineIsYes,
    required this.impact,
    required this.verdict,
    required this.outcome,
    required this.shakeDx,
    required this.flashOpacity,
  });

  final bool mineIsYes;
  final AnimationController impact;
  final AnimationController verdict;
  final ChallengeOutcome? outcome;
  final double Function(double t) shakeDx;
  final double Function(double t) flashOpacity;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: voteTileHeight(context),
      child: AnimatedBuilder(
        animation: Listenable.merge([impact, verdict]),
        builder: (context, _) {
          final flipping = outcome == ChallengeOutcome.flipped;
          final v = verdict.value;
          // While the verdict plays, "mine" is losing its light and the other
          // side is taking it — on a hold nothing moves between them.
          final mineLit = flipping ? 1 - v : 1.0;
          final otherLit = flipping ? v : 0.0;
          return Row(
            children: [
              Expanded(
                child: _Tile(
                  isYes: true,
                  isMine: mineIsYes,
                  lit: mineIsYes ? mineLit : otherLit,
                  shakeDx: mineIsYes ? shakeDx(impact.value) : 0,
                  tilt: flipping && mineIsYes ? v * 0.06 : 0,
                  flash: outcome == ChallengeOutcome.held && mineIsYes
                      ? flashOpacity(v)
                      : 0,
                ),
              ),
              const SizedBox(width: kVoteSeamGap),
              Expanded(
                child: _Tile(
                  isYes: false,
                  isMine: !mineIsYes,
                  lit: !mineIsYes ? mineLit : otherLit,
                  shakeDx: !mineIsYes ? shakeDx(impact.value) : 0,
                  tilt: flipping && !mineIsYes ? v * 0.06 : 0,
                  flash: outcome == ChallengeOutcome.held && !mineIsYes
                      ? flashOpacity(v)
                      : 0,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One tile plus the transforms of the moment: the sideways knock of the
/// impact, the tip-over of a flip, and the flash of a hold.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.isYes,
    required this.isMine,
    required this.lit,
    required this.shakeDx,
    required this.tilt,
    required this.flash,
  });

  final bool isYes;
  final bool isMine;

  /// 0..1 — how lit this tile is right now. Crossfaded rather than switched, so
  /// a flip reads as the light moving from one side to the other.
  final double lit;

  final double shakeDx;
  final double tilt;
  final double flash;

  @override
  Widget build(BuildContext context) {
    Widget tile = Stack(
      children: [
        // Both states are painted and crossfaded: VoteSideTile takes a bool, so
        // the in-between of a flip has to be built out of the two ends.
        Opacity(
          opacity: 1 - lit,
          child: VoteSideTile(isYes: isYes, lit: false),
        ),
        Opacity(
          opacity: lit,
          child: VoteSideTile(isYes: isYes, lit: true),
        ),
        if (flash > 0)
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                color: (isYes ? AppTheme.yes : AppTheme.no).withValues(
                  alpha: flash,
                ),
              ),
            ),
          ),
      ],
    );
    if (tilt != 0) tile = Transform.rotate(angle: tilt, child: tile);
    if (shakeDx != 0) {
      tile = Transform.translate(offset: Offset(shakeDx, 0), child: tile);
    }
    return tile;
  }
}

/// One of the two answers to the argument. The "holding" side is the lit,
/// spark-gradient one — standing your ground is the default reading — and
/// changing your mind is the quiet outline beside it.
class _ChallengeButton extends StatelessWidget {
  const _ChallengeButton({
    required this.label,
    required this.primary,
    required this.onTap,
    this.dimmed = false,
  });

  final String label;
  final bool primary;
  final bool dimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Opacity(
      opacity: dimmed ? 0.5 : 1,
      child: Material(
        color: primary ? Colors.transparent : colors.accent,
        borderRadius: AppTheme.ctaRadius,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: AppTheme.ctaRadius,
            gradient: primary ? AppTheme.ctaGradient : null,
            boxShadow: primary ? AppTheme.ctaGlow : null,
          ),
          child: InkWell(
            borderRadius: AppTheme.ctaRadius,
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: kMinTouchTarget),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              alignment: Alignment.center,
              child: Text(
                label.toUpperCase(),
                textAlign: TextAlign.center,
                maxLines: 2,
                style: AppTypography.action(fontSize: 13).copyWith(
                  color: primary ? AppTheme.ctaForeground : colors.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
