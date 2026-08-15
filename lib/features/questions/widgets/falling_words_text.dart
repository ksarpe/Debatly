import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'styled_question_text.dart';

/// Builds a question one word at a time: each word drops in from above and
/// settles into place with a small bounce, so the sentence assembles itself
/// left-to-right, top-to-bottom.
///
/// Whenever [text] changes the build replays from scratch. [onWordLanded] fires
/// once for each word the moment it settles — the natural seam for adding a
/// haptic tick per landing later on.
///
/// Pass `animate: false` where the sentence is already familiar — a stage that
/// re-shows a question the user has just read — and it renders fully assembled
/// with identical layout, so nothing shifts.
class FallingWordsText extends StatefulWidget {
  const FallingWordsText(
    this.text, {
    super.key,
    this.onWordLanded,
    this.animate = true,
  });

  final String text;

  /// Called once per word as it lands. Intended for haptic feedback.
  final VoidCallback? onWordLanded;

  /// Whether the words fall in. When false the text appears whole and
  /// [onWordLanded] never fires — no word ever was in flight.
  final bool animate;

  @override
  State<FallingWordsText> createState() => _FallingWordsTextState();
}

class _FallingWordsTextState extends State<FallingWordsText>
    with SingleTickerProviderStateMixin {
  // How far each word travels (logical px) and how it lands.
  static const double _dropDistance = 180;
  static const Duration _wordDuration = Duration(milliseconds: 380);
  static const Duration _stagger = Duration(milliseconds: 90);

  late final AnimationController _controller;
  List<String> _words = const [];

  /// Words whose landing callback has already fired this run.
  int _landed = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _controller.addListener(_emitLandings);
    _play(widget.text);
  }

  @override
  void didUpdateWidget(FallingWordsText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.animate != widget.animate) {
      _play(widget.text);
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_emitLandings)
      ..dispose();
    super.dispose();
  }

  /// (Re)start the staggered build for [text] — or, with `animate: false`, jump
  /// straight to the assembled sentence.
  void _play(String text) {
    _words = text.trim().split(RegExp(r'\s+'));
    final count = _words.length;
    // Total span covers every word's stagger offset plus one full word fall.
    _controller.duration = _stagger * (count - 1) + _wordDuration;
    if (!widget.animate) {
      // Marked landed *before* the jump: setting the value notifies listeners,
      // and nothing should read as having "just landed" when it never fell.
      _landed = count;
      _controller.value = 1;
      return;
    }
    _landed = 0;
    _controller.forward(from: 0);
  }

  /// Fraction of the whole timeline at which word [i] starts and finishes.
  ({double start, double end}) _window(int i) {
    final total = _controller.duration!.inMilliseconds;
    final start = (_stagger.inMilliseconds * i) / total;
    final end =
        (_stagger.inMilliseconds * i + _wordDuration.inMilliseconds) / total;
    return (start: start, end: end);
  }

  /// Fire [onWordLanded] for any word that has just reached the end of its
  /// window since the last tick.
  void _emitLandings() {
    if (widget.onWordLanded == null) return;
    final t = _controller.value;
    var landed = _landed;
    while (landed < _words.length && t >= _window(landed).end) {
      widget.onWordLanded!.call();
      landed++;
    }
    _landed = landed;
  }

  @override
  Widget build(BuildContext context) {
    // One size for the whole question. The length-based size is the intended
    // look; when the box it's given can't hold it — short screen, big system
    // font, long question — it shrinks further so the text never grows into the
    // vote panel and the share / history pills sitting below it.
    // Read outside the builder: it runs during layout, where depending on an
    // inherited widget is best avoided.
    final textScaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final fontSize = QuestionTextStyles.fitFontSize(
          widget.text,
          maxWidth: constraints.maxWidth,
          maxHeight: constraints.maxHeight,
          textScaler: textScaler,
        );
        return Wrap(
          alignment: WrapAlignment.center,
          runAlignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: QuestionTextStyles.wordSpacingFor(fontSize),
          runSpacing: QuestionTextStyles.lineSpacing,
          children: [
            for (var i = 0; i < _words.length; i++)
              _FallingWord(
                word: _words[i],
                fontSize: fontSize,
                controller: _controller,
                window: _window(i),
                dropDistance: _dropDistance,
              ),
          ],
        );
      },
    );
  }
}

/// One word, translated down from above and faded in across its slice of the
/// shared timeline.
class _FallingWord extends StatelessWidget {
  const _FallingWord({
    required this.word,
    required this.fontSize,
    required this.controller,
    required this.window,
    required this.dropDistance,
  });

  final String word;
  final double fontSize;
  final AnimationController controller;
  final ({double start, double end}) window;
  final double dropDistance;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final span = window.end - window.start;
        final raw = span <= 0
            ? 1.0
            : ((controller.value - window.start) / span).clamp(0.0, 1.0);
        // easeOutBack overshoots past 1, which reads as a tiny landing bounce.
        final eased = Curves.easeOutBack.transform(raw);
        // Starts [dropDistance] above its resting spot, falls to 0 (and a hair
        // below, then up, thanks to the overshoot).
        final dy = -(1 - eased) * dropDistance;
        // Fade in a little faster than the fall so the word is solid as it lands.
        final opacity = (raw * 1.4).clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, dy),
          child: Opacity(opacity: opacity, child: child),
        );
      },
      child: StyledWord(word, fontSize: fontSize),
    );
  }
}
