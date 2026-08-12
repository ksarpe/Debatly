import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/graphics/svg_path.dart';

/// Brand marks for the social sign-in buttons, drawn from the providers' own
/// vector artwork.
///
/// Both platforms require their real logo on their sign-in button — Apple's
/// Human Interface Guidelines for Sign in with Apple, Google's Sign-In branding
/// guidelines — and neither is shipped in Material Icons (`Icons.apple` is a
/// generic apple shape, not Apple's mark). Drawing the path data keeps them
/// crisp at any density and any button height without adding an SVG dependency
/// or a set of raster assets.

// The Apple logo, viewBox 0 0 814 1000.
const String _applePathData =
    'M788.1 340.9c-5.8 4.5-108.2 62.2-108.2 190.5 0 148.4 130.3 200.9 134.2 '
    '202.2-.6 3.2-20.7 71.9-68.7 141.9-42.8 61.6-87.5 123.1-155.5 123.1s-85.5'
    '-39.5-164-39.5c-76.5 0-103.7 40.8-165.9 40.8s-105.6-57-155.5-127C46.7 '
    '790.7 0 663 0 541.8c0-194.4 126.4-297.5 250.8-297.5 66.1 0 121.2 43.4 '
    '162.7 43.4 39.5 0 101.1-46 176.3-46 28.5 0 130.9 2.6 198.3 99.2zm-234'
    '-145.3c31.1-36.9 53.1-88.1 53.1-139.3 0-7.1-.6-14.3-1.9-20.1-50.6 1.9'
    '-110.8 33.7-147.1 75.8-28.5 32.4-55.1 83.6-55.1 135.5 0 7.8 1.3 15.6 1.9 '
    '18.1 3.2.6 8.4 1.3 13.6 1.3 45.4 0 102.5-30.4 135.5-71.3z';

// The Google "G", viewBox 0 0 48 48 — one path per brand colour.
const String _googleBluePathData =
    'M45.12 24.5c0-1.56-.14-3.06-.4-4.5H24v8.51h11.84c-.51 2.75-2.06 5.08'
    '-4.39 6.64v5.52h7.11c4.16-3.83 6.56-9.47 6.56-16.17z';
const String _googleGreenPathData =
    'M24 46c5.94 0 10.92-1.97 14.56-5.33l-7.11-5.52c-1.97 1.32-4.49 2.1-7.45 '
    '2.1-5.73 0-10.58-3.87-12.31-9.07H4.34v5.7C7.96 41.07 15.4 46 24 46z';
const String _googleYellowPathData =
    'M11.69 28.18C11.25 26.86 11 25.45 11 24s.25-2.86.69-4.18v-5.7H4.34C2.85 '
    '17.09 2 20.45 2 24s.85 6.91 2.34 9.88l7.35-5.7z';
const String _googleRedPathData =
    'M24 10.75c3.23 0 6.13 1.11 8.41 3.29l6.31-6.31C34.91 4.18 29.93 2 24 2 '
    '15.4 2 7.96 6.93 4.34 14.12l7.35 5.7c1.73-5.2 6.58-9.07 12.31-9.07z';

// Parsed once, on first paint — top-level finals are lazily initialised.
final Path _applePath = parseSvgPath(_applePathData);
final List<_GlyphShape> _googleShapes = List.unmodifiable([
  _GlyphShape(parseSvgPath(_googleBluePathData), const Color(0xFF4285F4)),
  _GlyphShape(parseSvgPath(_googleGreenPathData), const Color(0xFF34A853)),
  _GlyphShape(parseSvgPath(_googleYellowPathData), const Color(0xFFFBBC05)),
  _GlyphShape(parseSvgPath(_googleRedPathData), const Color(0xFFEA4335)),
]);

/// The Apple logo, tinted to sit on the app's own button (Apple allows the mark
/// in the button's foreground colour, so it follows the light/dark theme).
class AppleGlyph extends StatelessWidget {
  const AppleGlyph({super.key, required this.color, this.size = 20});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // The mark is taller than it is wide and its stem sits low, so a square
      // box centred on the glyph reads as if it has slipped below the label.
      // Nudging it up a hair puts it back on the text's optical centre.
      width: size,
      height: size,
      child: Transform.translate(
        offset: const Offset(0, -1),
        child: CustomPaint(
          painter: _GlyphPainter([_GlyphShape(_applePath, color)]),
        ),
      ),
    );
  }
}

/// The Google "G", in Google's four brand colours on every theme — its branding
/// guidelines don't allow recolouring the mark.
class GoogleGlyph extends StatelessWidget {
  const GoogleGlyph({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GlyphPainter(_googleShapes)),
    );
  }
}

@immutable
class _GlyphShape {
  const _GlyphShape(this.path, this.color);

  final Path path;
  final Color color;

  @override
  bool operator ==(Object other) =>
      other is _GlyphShape &&
      identical(other.path, path) &&
      other.color == color;

  @override
  int get hashCode => Object.hash(identityHashCode(path), color);
}

/// Scales a set of filled paths to fit the widget, preserving their aspect
/// ratio. Fitting the paths' own bounds rather than the source viewBox means
/// marks authored with different amounts of built-in padding (Apple's has none,
/// Google's has 2 units) still come out optically the same size next to each
/// other.
class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.shapes);

  final List<_GlyphShape> shapes;

  @override
  void paint(Canvas canvas, Size size) {
    if (shapes.isEmpty) return;

    var bounds = shapes.first.path.getBounds();
    for (final shape in shapes.skip(1)) {
      bounds = bounds.expandToInclude(shape.path.getBounds());
    }
    if (bounds.isEmpty) return;

    final scale = math.min(
      size.width / bounds.width,
      size.height / bounds.height,
    );

    canvas.save();
    canvas.translate(
      (size.width - bounds.width * scale) / 2,
      (size.height - bounds.height * scale) / 2,
    );
    canvas.scale(scale);
    canvas.translate(-bounds.left, -bounds.top);
    for (final shape in shapes) {
      canvas.drawPath(shape.path, Paint()..color = shape.color);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlyphPainter oldDelegate) =>
      !listEquals(oldDelegate.shapes, shapes);
}
