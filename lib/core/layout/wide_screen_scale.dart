import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Virtual width the layout is scaled to behave like — roughly a large phone.
///
/// A tablet is handed a viewport this wide in LOGICAL terms and the result is
/// magnified to the real screen, so the app fills the display at a comfortable
/// size instead of drawing a phone-sized island in the middle of it.
const double _kVirtualWidth = 560;

/// Upper bound on the magnification. Past this the chrome starts to look like a
/// zoomed-in phone rather than a tablet app, and a 12.9" display would reach 2.4×.
const double _kMaxScale = 1.75;

/// Below this shortest side nothing scales: every phone, and the 600pt default
/// surface the widget tests render on, must keep 1.0 exactly.
const double _kScaleFloorShortestSide = 600;

/// How much to magnify the whole UI on [size].
///
/// Keyed on the SHORTEST side, not the width, so rotating a tablet does not
/// change the type size — only how much room the (capped) column has beside it.
@visibleForTesting
double wideScreenScaleFor(Size size) {
  final shortestSide = math.min(size.width, size.height);
  if (shortestSide <= _kScaleFloorShortestSide) return 1;
  return math.min(shortestSide / _kVirtualWidth, _kMaxScale);
}

/// Magnifies the entire app on tablet-sized screens.
///
/// The design is a single phone-shaped column, and the question's own type size
/// is chosen from the text's LENGTH and only ever shrinks to fit
/// (`AppTheme.fitFontSize`) — it never grows into a bigger box. So on a tablet,
/// widening the column alone changes nothing: the content just sits small in the
/// middle of a large dark screen. Stretching it instead is worse, turning one
/// line of a question into a ribbon over a thousand points wide.
///
/// The remaining option is the one that actually works for a single-column
/// design: render it into a smaller VIRTUAL viewport and magnify the result. Type,
/// spacing, radii, strokes and touch targets all grow by the same factor, so the
/// proportions stay exactly as designed and only the scale changes.
///
/// Installed as `MaterialApp.builder`, i.e. ABOVE the Navigator — otherwise
/// pushed routes and modal sheets (the paywall, the smaczki panel) would render
/// unscaled and the app would be magnified in some places and not others.
///
/// [MediaQuery] is restated in virtual units, so anything measuring itself
/// against the screen — sheet heights, keyboard insets, safe areas — keeps
/// working in the same coordinate space it is laid out in.
class WideScreenScale extends StatelessWidget {
  const WideScreenScale({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scale = wideScreenScaleFor(media.size);
    // Phones take the untouched tree — no transform layer, nothing to go wrong.
    if (scale == 1) return child;

    final virtualSize = media.size / scale;
    return MediaQuery(
      data: media.copyWith(
        size: virtualSize,
        padding: media.padding / scale,
        viewPadding: media.viewPadding / scale,
        viewInsets: media.viewInsets / scale,
        systemGestureInsets: media.systemGestureInsets / scale,
      ),
      // The real size is stated explicitly. `MaterialApp.builder` hands its
      // child LOOSE constraints, and a bare FittedBox under those just sizes
      // itself to its child — which rendered the whole app at virtual size in
      // the top-left corner instead of magnifying it.
      child: SizedBox(
        width: media.size.width,
        height: media.size.height,
        // The virtual viewport keeps the real aspect ratio, so `fill` scales
        // both axes by the same factor — it cannot distort.
        child: FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(
            width: virtualSize.width,
            height: virtualSize.height,
            child: child,
          ),
        ),
      ),
    );
  }
}
