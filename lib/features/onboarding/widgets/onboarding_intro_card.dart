import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/fit_or_scroll.dart';

/// One intro slide: a glyph up top, a bold title, and a paragraph of copy —
/// vertically centred so every card has the same rhythm.
///
/// The title plays a staged entrance on mount: [title] rises in first, then —
/// after a beat — [titlePunch] lands as the punchline, and finally [body]
/// quietly fades in. The stagger is the emphasis; nothing moves after the
/// last line settles. All three widgets are in the tree from the first frame
/// (only their opacity/offset animate), so tests and screen readers see the
/// full copy immediately.
class OnboardingIntroCard extends StatefulWidget {
  const OnboardingIntroCard({
    super.key,
    required this.glyph,
    required this.title,
    this.titlePunch,
    required this.body,
  });

  /// The full entrance timeline: 0.8s of just the glyph, the hook at 0.8s,
  /// the punchline at 2.3s, and the body from 3.5s. The screen's bottom CTA
  /// runs its own controller with this same duration and [ctaRevealInterval],
  /// so the button lands together with the body copy.
  static const Duration entranceDuration = Duration(milliseconds: 4000);

  /// The tail of [entranceDuration] (3.5s → 4.0s) in which the body copy —
  /// and, on the screen side, the CTA — fade in.
  static const Interval ctaRevealInterval = Interval(
    0.875,
    1.0,
    curve: Curves.easeOut,
  );

  final Widget glyph;
  final String title;

  /// Optional second title line, revealed after [title] as a punchline.
  final String? titlePunch;

  final String body;

  @override
  State<OnboardingIntroCard> createState() => _OnboardingIntroCardState();
}

class _OnboardingIntroCardState extends State<OnboardingIntroCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;

  // The stagger, in ms on the 4s controller: the glyph alone for 0.8s (its
  // own entrance plays and settles), the hook rises at 0.8s, the punchline
  // 1.5s after it at 2.3s, and 1.2s later — at 3.5s — the body copy fades in
  // without theatrics, together with the screen's CTA.
  late final CurvedAnimation _hookIn = CurvedAnimation(
    parent: _entrance,
    curve: const Interval(0.20, 0.3125, curve: Curves.easeOutCubic),
  );
  late final CurvedAnimation _punchIn = CurvedAnimation(
    parent: _entrance,
    curve: const Interval(0.575, 0.6875, curve: Curves.easeOutCubic),
  );
  late final CurvedAnimation _bodyIn = CurvedAnimation(
    parent: _entrance,
    curve: OnboardingIntroCard.ctaRevealInterval,
  );

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: OnboardingIntroCard.entranceDuration,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion: settle straight to the resting frame.
    if (MediaQuery.of(context).disableAnimations) {
      _entrance.value = 1;
    } else if (!_entrance.isCompleted) {
      _entrance.forward();
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  /// Fade + a short upward drift, driven by [t]. Used for the title lines.
  Widget _rise(Animation<double> t, Widget child) {
    return AnimatedBuilder(
      animation: t,
      builder: (context, child) => Opacity(
        opacity: t.value,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - t.value)),
          child: child,
        ),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final punch = widget.titlePunch;
    final titleStyle = TextStyle(
      color: context.colors.ink,
      fontSize: 26,
      fontWeight: FontWeight.w800,
      height: 1.15,
    );

    // The very first screen of the app, so it has to survive a large system
    // font and a short window (an iPad Slide Over column) rather than clipping
    // its own body copy — which it did, silently, past ~1.4x text.
    return FitOrScroll(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            widget.glyph,
            const SizedBox(height: 40),
            _rise(
              _hookIn,
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: titleStyle,
              ),
            ),
            if (punch != null) ...[
              const SizedBox(height: 4),
              _rise(
                _punchIn,
                Text(punch, textAlign: TextAlign.center, style: titleStyle),
              ),
            ],
            const SizedBox(height: 16),
            FadeTransition(
              opacity: _bodyIn,
              child: Text(
                widget.body,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.colors.subtle,
                  fontSize: 16,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
