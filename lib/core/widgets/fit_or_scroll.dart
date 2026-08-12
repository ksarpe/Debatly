import 'package:flutter/material.dart';

/// Centres [child] in the space it is given, and lets it scroll the moment that
/// space is too small.
///
/// This exists because of one specific Flutter failure mode. When a [Column]
/// overflows, the framework still *paints* the spilled children — but
/// `RenderBox.hitTest` only descends into a box whose own `size` contains the
/// pointer, so an overflowed button ends up visible and completely dead to
/// touch. It is the same class of bug as a gesture surface that only spans the
/// text it wraps: the pixels are there, the finger just never reaches them.
///
/// Reach for this on any surface whose height is content-driven and whose
/// viewport isn't (a phone in landscape, an iPad Slide Over column, a large
/// accessibility text scale). When the content fits, the layout is exactly a
/// [Center] and no scrolling machinery is involved.
class FitOrScroll extends StatelessWidget {
  const FitOrScroll({super.key, required this.child, this.minContentHeight});

  final Widget child;

  /// The height to hand [child] when the viewport is shorter than this.
  ///
  /// Leave it null when [child] sizes itself — a column of CTAs, a card of copy.
  /// It then gets the viewport as a *minimum* and starts scrolling as soon as it
  /// wants more room.
  ///
  /// Pass a value when [child] contains a [Flexible] that has to flex against a
  /// bounded box: the feed's question shrinks its font to whatever height it is
  /// given, so handing it an unbounded box (which is what a scroll view does)
  /// would stop it shrinking at all. The child then always gets a bounded box —
  /// the viewport while that is big enough, this floor once it isn't.
  final double? minContentHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // An unbounded box can neither overflow nor host a scroll view.
        if (!constraints.hasBoundedHeight) return Center(child: child);

        final floor = minContentHeight;
        if (floor == null) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(child: child),
            ),
          );
        }
        if (constraints.maxHeight >= floor) return Center(child: child);
        return SingleChildScrollView(
          child: SizedBox(
            height: floor,
            child: Center(child: child),
          ),
        );
      },
    );
  }
}
