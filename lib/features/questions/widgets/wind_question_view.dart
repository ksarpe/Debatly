import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/question.dart';
import '../../account/providers/session_providers.dart';
import '../providers/question_providers.dart';
import '../providers/swipe_hint_providers.dart';
import 'falling_words_text.dart';

/// Displays the current question and runs the signature "wind" transition.
///
/// On a horizontal swipe the current text accelerates off in the direction of
/// the swipe — as if blown away — then, after a short beat, the *next* question
/// assembles itself word by word, each word dropping in from above (see
/// [FallingWordsText]). No cards, no flips: just text in motion.
///
/// Swiping LEFT goes forward through the catalog, wrapping around — except at
/// the end of a FREE user's deck (the daily), where the forward swipe lands on
/// the day wall instead of wrapping. Swiping RIGHT steps back through what was
/// already on screen, stopping at the daily (index 0) with a small bounce.
class WindQuestionView extends ConsumerStatefulWidget {
  const WindQuestionView({super.key});

  @override
  ConsumerState<WindQuestionView> createState() => WindQuestionViewState();
}

/// The one live instance sits on the home screen under this key, so
/// [QuestionBody]'s full-screen gesture layer can forward swipes made anywhere
/// on the feed (not just over the question text) into [WindQuestionViewState].
final GlobalKey<WindQuestionViewState> windQuestionViewKey =
    GlobalKey<WindQuestionViewState>(debugLabel: 'wind_question_view');

/// A slow, deliberate drag ends with ~zero velocity and would never pass the
/// velocity gate, so total finger travel past this many logical pixels commits
/// the swipe too. Tablet users in particular drag slowly (App Review swiped on
/// an iPad and "the app did not react").
const double _kSwipeCommitDistance = 64;

class WindQuestionViewState extends ConsumerState<WindQuestionView>
    with TickerProviderStateMixin {
  /// Accumulated horizontal finger travel of the drag in progress, in logical
  /// pixels — the distance fallback used when the release velocity is ~zero.
  double _dragDx = 0;
  late final AnimationController _controller;

  // Offsets are expressed as a fraction of screen width and converted to pixels
  // at paint time, so the text fully clears the screen regardless of its size.
  Animation<Offset> _offset = const AlwaysStoppedAnimation(Offset.zero);
  Animation<double> _opacity = const AlwaysStoppedAnimation(1);

  /// The question currently painted. While idle it tracks the provider; during
  /// a transition it is frozen so the OUT phase keeps showing the old question.
  Question? _displayed;
  bool _animating = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Entry points for the horizontal swipe, public so [QuestionBody]'s
  /// full-screen gesture layer can drive them through [windQuestionViewKey].
  /// A swipe commits on release velocity (a flick) OR on total travel (a slow
  /// drag, see [_kSwipeCommitDistance]) — velocity wins when both are present.
  void handleDragStart(DragStartDetails details) {
    _dragDx = 0;
  }

  void handleDragUpdate(DragUpdateDetails details) {
    _dragDx += details.delta.dx;
  }

  void handleDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() > 100) {
      _advance(velocity > 0 ? 1 : -1);
    } else if (_dragDx.abs() > _kSwipeCommitDistance) {
      _advance(_dragDx > 0 ? 1 : -1);
    }
  }

  /// [direction] is the sign of the swipe: -1 leftward, +1 rightward.
  Future<void> _advance(int direction) async {
    if (_animating) return;

    // A leftward (forward) swipe is the gesture we teach: the moment the user
    // makes one — committed or not — they've discovered the feed extends past
    // the daily, so retire the right-edge swipe affordance (persisted once).
    if (direction < 0) {
      ref.read(swipeDiscoveredControllerProvider.notifier).markDiscovered();
    }

    // RIGHT swipe — step back through what was already on screen, retracing
    // the stable per-launch deck order. At the daily there is nothing behind:
    // a small bounce says "this is the edge" instead of the swipe silently
    // doing nothing — or worse, skipping forward, which is what it used to do
    // and what made "go back" overshoot.
    if (direction > 0) {
      final notifier = ref.read(questionIndexProvider.notifier);
      if (ref.read(questionIndexProvider) == 0) {
        await _bounce(direction);
        return;
      }
      _animating = true;
      await _animateOut(direction);
      if (!mounted) {
        _animating = false;
        return;
      }
      notifier.backLinear();
      _settleIn(ref.read(currentQuestionProvider));
      _animating = false;
      return;
    }

    // LEFT swipe past the end of a FREE user's deck — the day wall takes over
    // instead of the catalog wrapping (a free deck is just the daily, so a
    // wrap would replay the same question and read as a dead swipe). The wall
    // replaces this widget entirely; it comes back fresh on the back swipe.
    final deckLength = ref.read(questionDeckProvider).length;
    final atDeckEnd = ref.read(questionIndexProvider) >= deckLength - 1;
    if (atDeckEnd && !ref.read(isPremiumProvider)) {
      _animating = true;
      await _animateOut(direction);
      _animating = false;
      if (!mounted) return;
      ref.read(dayWallVisibleProvider.notifier).show();
      return;
    }

    // LEFT swipe — forward through the wrapped catalog.
    _animating = true;
    await _animateOut(direction);
    if (!mounted) {
      _animating = false;
      return;
    }
    ref.read(questionIndexProvider.notifier).next();
    _settleIn(ref.read(currentQuestionProvider));
    _animating = false;
  }

  /// A short "there's nothing that way" nudge: the text leans a little toward
  /// the swiped edge and springs back. Played instead of a transition when a
  /// back swipe hits the daily (index 0) — feedback that the gesture registered
  /// but the feed ends here, without silently ignoring it or moving anywhere.
  Future<void> _bounce(int direction) async {
    _animating = true;
    _offset = Tween(
      begin: Offset.zero,
      end: Offset(0.06 * direction, 0),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _opacity = const AlwaysStoppedAnimation(1);
    await _controller.animateTo(1, duration: const Duration(milliseconds: 110));
    await _controller.animateBack(
      0,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
    );
    if (mounted) _settleIn(null);
    _animating = false;
  }

  /// Accelerates the current text off the swiped edge, fading as it goes, then
  /// holds an empty canvas for a beat before the next content assembles.
  Future<void> _animateOut(int direction) async {
    final exitEnd = Offset(1.5 * direction, 0);
    _offset = Tween(
      begin: Offset.zero,
      end: exitEnd,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInCubic));
    _opacity = Tween(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));
    await _controller.forward(from: 0);
    await Future.delayed(const Duration(milliseconds: 80));
  }

  /// Snaps the outer transform back to centre and (when given) paints [q].
  void _settleIn(Question? q) {
    setState(() {
      _offset = const AlwaysStoppedAnimation(Offset.zero);
      _opacity = const AlwaysStoppedAnimation(1);
      if (q != null) _displayed = q;
    });
  }

  /// Fires as each word of the new question lands. The hook is intentionally
  /// empty for now — this is where a per-word haptic tick will go.
  void _onWordLanded() {
    // TODO(vibration): add a short haptic here, e.g.
    // HapticFeedback.selectionClick(), so each landing word can be felt.
  }

  @override
  Widget build(BuildContext context) {
    // Keep the painted question in sync with the provider while idle. Assigning
    // the field here (rather than setState) is safe — we are already building.
    final current = ref.watch(currentQuestionProvider);
    if (!_animating && current != null) _displayed = current;

    final width = MediaQuery.of(context).size.width;

    // This detector only spans the question text's own bounds — the rest of
    // the screen is covered by [QuestionBody]'s full-screen gesture layer,
    // which forwards into the same handlers via [windQuestionViewKey]. Kept
    // here as well so a drag that starts on the text (and the widget tests
    // that fling this widget directly) work without the outer layer.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: handleDragStart,
      onHorizontalDragUpdate: handleDragUpdate,
      onHorizontalDragEnd: handleDragEnd,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(_offset.value.dx * width, 0),
            child: Opacity(
              opacity: _opacity.value.clamp(0.0, 1.0),
              child: child,
            ),
          );
        },
        child: FallingWordsText(
          _displayed?.questionText ?? '',
          onWordLanded: _onWordLanded,
        ),
      ),
    );
  }
}
