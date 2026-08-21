import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../../core/feedback/haptics.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/models/smaczek.dart';
import '../../../data/models/vote_result.dart';
import 'falling_words_text.dart';

/// What the gate reports back: how the user answered and how long they sat
/// with the argument on screen (null when they left before it landed).
typedef SmaczekChallengeResult = ({ChallengeOutcome outcome, int? dwellMs});

/// Drops one smaczek between the vote and the result.
///
/// The user has just answered; before the percentages appear, the argument
/// aimed at THEIR side falls in word by word — the same falling-words motion
/// the feed uses for a question — and lands on the quiet reminder of their own
/// vote, which visibly shakes. Then, and only then, they say whether it moved
/// them.
///
/// The VOTE IS FINAL either way: "to mnie ruszyło" admits the argument landed,
/// it does not re-cast anything. It is never a trap: system back resolves as
/// [ChallengeOutcome.dismissed] and the result appears regardless.
///
/// [compact] is the shortened beat for every gate after the first in a session:
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

  /// The shortened every-gate-after-the-first beat: text appears
  /// whole, buttons right after the hit. See [showSmaczekChallenge].
  final bool compact;

  @override
  State<SmaczekChallengeScreen> createState() => _SmaczekChallengeScreenState();
}

class _SmaczekChallengeScreenState extends State<SmaczekChallengeScreen>
    with TickerProviderStateMixin {
  /// The hit: a damped side-to-side shake of the stance line the argument
  /// landed on.
  static const Duration _impactDuration = Duration(milliseconds: 520);

  /// The answer: the stance line pulses brighter (held) or dims and sinks
  /// (moved).
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

  /// When the gate opened. The dwell clock starts HERE, not at the landing:
  /// the words falling in ARE the reading — roughly a second of it on a median
  /// argument — and a reader who follows the fall and answers promptly must not
  /// be scored as if they never read a word. Starting the clock at the landing
  /// measured hesitation AFTER the sentence was assembled, which quietly filed
  /// honest fast readers as `skipped_fast` and kept their profile locked
  /// forever, with nothing on screen to tell them why.
  ///
  /// The head start can't be gamed the other way: the answers are inert until
  /// the last word lands, so nobody banks fall time without sitting through it.
  ///
  /// [clock] rather than [DateTime.now] so widget tests, which run on fake
  /// time, can assert the measurement instead of just its sign.
  final DateTime _openedAt = clock.now();

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
    // No landing, no measurement: leaving mid-fall is an exit, not a reading.
    final dwellMs = _landed
        ? clock.now().difference(_openedAt).inMilliseconds
        : null;
    setState(() => _outcome = outcome);
    Haptics.confirm();
    if (outcome != ChallengeOutcome.dismissed &&
        !MediaQuery.disableAnimationsOf(context)) {
      await _verdict.forward(from: 0);
    }
    if (!mounted) return;
    Navigator.of(context).pop((outcome: outcome, dwellMs: dwellMs));
  }

  /// Damped side-to-side wiggle of the struck stance line — sharp at the
  /// moment of impact, gone within half a second.
  double _shakeDx(double t) => math.sin(t * math.pi * 7) * 7 * (1 - t);

  /// A short brightening as the user holds their ground, back to normal by the
  /// end. Reads as "you took it".
  double _heldPulse(double t) => math.sin(t * math.pi);

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
                    _StanceLine(
                      mineIsYes: _mineIsYes,
                      impact: _impact,
                      verdict: _verdict,
                      outcome: _outcome,
                      shakeDx: _shakeDx,
                      heldPulse: _heldPulse,
                    ),
                    const SizedBox(height: 16),
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

/// The muted reminder of the vote the argument just hit.
///
/// This used to be a pair of slanted TAK/NIE vote tiles — but two vote-shaped
/// tiles under an argument read as "vote again", and people tried to tap them.
/// A quiet line of text now states the recorded side and asks the question the
/// buttons below answer. The impact shake and the "moved" sink land on this
/// line, so the argument still visibly strikes the user's own stance; on
/// "held" it pulses briefly brighter instead — "you took it". Either way the
/// line dims, it never disappears: the vote stands.
class _StanceLine extends StatelessWidget {
  const _StanceLine({
    required this.mineIsYes,
    required this.impact,
    required this.verdict,
    required this.outcome,
    required this.shakeDx,
    required this.heldPulse,
  });

  final bool mineIsYes;
  final AnimationController impact;
  final AnimationController verdict;
  final ChallengeOutcome? outcome;
  final double Function(double t) shakeDx;
  final double Function(double t) heldPulse;

  /// How far the line sinks on "moved", in logical px.
  static const double _sinkDy = 4;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final side = (mineIsYes ? context.l10n.voteYes : context.l10n.voteNo)
        .toUpperCase();
    return AnimatedBuilder(
      animation: Listenable.merge([impact, verdict]),
      builder: (context, _) {
        final v = verdict.value;
        final moved = outcome == ChallengeOutcome.moved;
        // "Held" brightens the line toward full ink for a beat; "moved" lets
        // it lose some presence and sink a little.
        final color = outcome == ChallengeOutcome.held
            ? Color.lerp(colors.subtle, colors.ink, heldPulse(v))!
            : colors.subtle;
        Widget line = Opacity(
          opacity: moved ? 1 - 0.45 * v : 1,
          child: Text(
            context.l10n.challengeStanceLine(side),
            textAlign: TextAlign.center,
            style: AppTypography.support(fontSize: 13).copyWith(color: color),
          ),
        );
        final dx = shakeDx(impact.value);
        final dy = moved ? v * _sinkDy : 0.0;
        if (dx != 0 || dy != 0) {
          line = Transform.translate(offset: Offset(dx, dy), child: line);
        }
        return line;
      },
    );
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
