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

/// What the gate reports back: how the user answered and how long they sat
/// with the argument before tapping (null when they left before it landed).
typedef SmaczekChallengeResult = ({ChallengeOutcome outcome, int? dwellMs});

/// Drops one smaczek between the vote and the result.
///
/// The user has just answered; before the percentages appear, the argument
/// aimed at THEIR side falls in word by word — the same falling-words motion
/// the feed uses for a question — and lands on their own answer, which visibly
/// shakes. Then, and only then, they say whether it moved them.
///
/// The VOTE IS FINAL either way: "to mnie ruszyło" admits the argument landed,
/// it does not re-cast anything. It is never a trap: system back resolves as
/// [ChallengeOutcome.dismissed] and the result appears regardless.
///
/// [compact] is the shortened beat for the second and third gate of a session:
/// the argument appears whole (no word-by-word fall, no per-word haptics), the
/// entry is faster and the buttons are up the moment the hit lands. The impact
/// shake itself stays — it is the entire message.
Future<SmaczekChallengeResult> showSmaczekChallenge(
  BuildContext context, {
  required Smaczek smaczek,
  required int choice,
  bool compact = false,
}) async {
  final result = await Navigator.of(context).push<SmaczekChallengeResult>(
    PageRouteBuilder<SmaczekChallengeResult>(
      opaque: true,
      barrierDismissible: false,
      transitionDuration: Duration(milliseconds: compact ? 150 : 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, _, _) => SmaczekChallengeScreen(
        smaczek: smaczek,
        choice: choice,
        compact: compact,
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
  // The route resolves itself on every path (PopScope intercepts system back),
  // so a null only means it was removed from the outside — an exit, not an
  // answer.
  return result ?? (outcome: ChallengeOutcome.dismissed, dwellMs: null);
}

/// The challenge itself. Public for the widget tests, which drive it directly
/// rather than through the whole vote flow.
class SmaczekChallengeScreen extends StatefulWidget {
  const SmaczekChallengeScreen({
    super.key,
    required this.smaczek,
    required this.choice,
    this.compact = false,
  });

  final Smaczek smaczek;

  /// The side the user just voted ([VoteResult.yes] / [VoteResult.no]).
  final int choice;

  /// The shortened second-and-third-gate-of-a-session beat: text appears
  /// whole, buttons right after the hit. See [showSmaczekChallenge].
  final bool compact;

  @override
  State<SmaczekChallengeScreen> createState() => _SmaczekChallengeScreenState();
}

class _SmaczekChallengeScreenState extends State<SmaczekChallengeScreen>
    with TickerProviderStateMixin {
  /// The hit: a damped side-to-side shake of the tile the argument landed on.
  static const Duration _impactDuration = Duration(milliseconds: 520);

  /// The answer: the tile flashes (held) or dims and sinks (moved).
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

  /// When the argument finished landing (i.e. the buttons became available).
  /// The dwell measurement starts here: answers faster than reading is
  /// physically possible are how we find out the mechanic is theatre.
  DateTime? _landedAt;

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
    _landedAt = DateTime.now();
    if (MediaQuery.disableAnimationsOf(context)) return;
    Haptics.impact();
    _impact.forward(from: 0);
  }

  Future<void> _resolve(ChallengeOutcome outcome) async {
    if (_outcome != null) return;
    final dwellMs = _landedAt == null
        ? null
        : DateTime.now().difference(_landedAt!).inMilliseconds;
    setState(() => _outcome = outcome);
    Haptics.confirm();
    if (outcome != ChallengeOutcome.dismissed &&
        !MediaQuery.disableAnimationsOf(context)) {
      await _verdict.forward(from: 0);
    }
    if (!mounted) return;
    Navigator.of(context).pop((outcome: outcome, dwellMs: dwellMs));
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
    final animate = !widget.compact && !MediaQuery.disableAnimationsOf(context);

    return PopScope(
      // System back is a legitimate way out, but it is an EXIT, not an answer:
      // it resolves as "dismissed" (kept out of the flip statistic) and the
      // result appears either way, so the gate is never a dead end.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _resolve(ChallengeOutcome.dismissed);
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
                    // question does on the feed. The full beat drops it word by
                    // word with a per-word haptic tick; the compact beat shows
                    // it whole — the hit below still lands (onFinished fires
                    // next frame), which is the part that must survive.
                    Expanded(
                      child: Center(
                        child: FallingWordsText(
                          widget.smaczek.text ?? '',
                          animate: animate,
                          onWordLanded: animate ? Haptics.tick : null,
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
                    // it arrives would make the whole beat pointless. Compact
                    // gates skip the fade — buttons up right after the hit.
                    AnimatedOpacity(
                      opacity: _landed ? 1 : 0,
                      duration: widget.compact
                          ? Duration.zero
                          : const Duration(milliseconds: 260),
                      child: IgnorePointer(
                        ignoring: !_landed || _outcome != null,
                        child: Row(
                          children: [
                            Expanded(
                              child: _ChallengeButton(
                                label: context.l10n.challengeHoldCta,
                                primary: true,
                                onTap: () => _resolve(ChallengeOutcome.held),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _ChallengeButton(
                                label: context.l10n.challengeMovedCta,
                                primary: false,
                                dimmed: _outcome == ChallengeOutcome.moved,
                                onTap: () => _resolve(ChallengeOutcome.moved),
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
/// sits faded beside it. On "moved" the lit tile dims and sinks a little while
/// the other briefly brightens and settles back — "it shook me", never "I
/// changed my answer": the vote stands, so no light may change hands for good.
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

  /// How far the user's tile sinks on "moved", in logical px.
  static const double _sinkDy = 6;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: voteTileHeight(context),
      child: AnimatedBuilder(
        animation: Listenable.merge([impact, verdict]),
        builder: (context, _) {
          final moved = outcome == ChallengeOutcome.moved;
          final v = verdict.value;
          // "Moved": mine loses some of its light (never all — the vote still
          // stands) and sinks; the other side gets a brief sympathetic glow
          // that has fully faded again by the end of the beat.
          final mineLit = moved ? 1 - 0.6 * v : 1.0;
          final otherLit = moved ? math.sin(v * math.pi) * 0.35 : 0.0;
          final mineDy = moved ? v * _sinkDy : 0.0;
          return Row(
            children: [
              Expanded(
                child: _Tile(
                  isYes: true,
                  lit: mineIsYes ? mineLit : otherLit,
                  shakeDx: mineIsYes ? shakeDx(impact.value) : 0,
                  dy: mineIsYes ? mineDy : 0,
                  flash: outcome == ChallengeOutcome.held && mineIsYes
                      ? flashOpacity(v)
                      : 0,
                ),
              ),
              const SizedBox(width: kVoteSeamGap),
              Expanded(
                child: _Tile(
                  isYes: false,
                  lit: !mineIsYes ? mineLit : otherLit,
                  shakeDx: !mineIsYes ? shakeDx(impact.value) : 0,
                  dy: !mineIsYes ? mineDy : 0,
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
/// impact, the sink-and-dim of "moved", and the flash of a hold.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.isYes,
    required this.lit,
    required this.shakeDx,
    required this.dy,
    required this.flash,
  });

  final bool isYes;

  /// 0..1 — how lit this tile is right now. Crossfaded rather than switched,
  /// so the dimming and the sympathetic glow both read as light moving, not a
  /// re-render.
  final double lit;

  final double shakeDx;
  final double dy;
  final double flash;

  @override
  Widget build(BuildContext context) {
    Widget tile = Stack(
      children: [
        // Both states are painted and crossfaded: VoteSideTile takes a bool,
        // so every in-between has to be built out of the two ends.
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
    if (shakeDx != 0 || dy != 0) {
      tile = Transform.translate(offset: Offset(shakeDx, dy), child: tile);
    }
    return tile;
  }
}

/// One of the two answers to the argument. The "holding" side is the lit,
/// spark-gradient one — standing your ground is the default reading — and
/// admitting the hit is the quiet outline beside it.
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
