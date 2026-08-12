import 'package:debatly/core/graphics/svg_path.dart';
import 'package:debatly/features/account/widgets/auth_brand_glyph.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The brand glyphs are drawn from raw SVG path data, so the parser underneath
/// them is the thing that can silently turn a logo into a smear. These tests
/// pin the grammar it has to get right — relative commands, packed numbers,
/// implicit repetition, smooth-curve reflection — and then render both glyphs
/// end to end.
void main() {
  Rect boundsOf(String d) => parseSvgPath(d).getBounds();

  // Skia stores path coordinates as 32-bit floats, so a parsed 3.2 comes back
  // as 3.2000000476837158 — every comparison has to carry a tolerance. Note
  // also that `getBounds()` is the hull of the control POINTS, not of the drawn
  // curve, which is what makes it a precise probe of where each control point
  // landed.
  Matcher rectCloseTo(double left, double top, double right, double bottom) =>
      isA<Rect>()
          .having((rect) => rect.left, 'left', closeTo(left, 1e-4))
          .having((rect) => rect.top, 'top', closeTo(top, 1e-4))
          .having((rect) => rect.right, 'right', closeTo(right, 1e-4))
          .having((rect) => rect.bottom, 'bottom', closeTo(bottom, 1e-4));

  group('parseSvgPath', () {
    test('absolute move and line', () {
      expect(boundsOf('M0 0 L10 0 L10 10 Z'), rectCloseTo(0, 0, 10, 10));
    });

    test('relative commands are measured from the pen position', () {
      expect(boundsOf('m5 5l5 0l0 5z'), rectCloseTo(5, 5, 10, 10));
    });

    test('horizontal and vertical commands', () {
      expect(boundsOf('M0 0H10V10z'), rectCloseTo(0, 0, 10, 10));
      expect(boundsOf('M2 2h8v8z'), rectCloseTo(2, 2, 10, 10));
    });

    test('extra coordinate pairs after a moveto are linetos', () {
      expect(boundsOf('M0 0 10 0 10 10z'), rectCloseTo(0, 0, 10, 10));
    });

    test('closepath returns the pen to the start of the subpath', () {
      // The `l0 4` runs from (0,0) — where `z` put the pen — not from (4,0).
      expect(boundsOf('M0 0h4zl0 4'), rectCloseTo(0, 0, 4, 4));
    });

    test('numbers packed without separators', () {
      // `.5.5` is two numbers, and `3.2.6` is 3.2 followed by .6 — not `3.`
      // and `2.6`.
      expect(boundsOf('M0 0L.5.5'), rectCloseTo(0, 0, 0.5, 0.5));
      expect(boundsOf('M0 0L3.2.6'), rectCloseTo(0, 0, 3.2, 0.6));
      expect(boundsOf('M0 0L1-2'), rectCloseTo(0, -2, 1, 0));
    });

    test('cubic curves, including implicit repetition of the command', () {
      // Two groups of six numbers under a single `C`; every control point sits
      // on y = 0, so the bounds show exactly how far the run got.
      expect(boundsOf('M0 0C1 0 2 0 3 0 4 0 5 0 6 0'), rectCloseTo(0, 0, 6, 0));
    });

    test('a smooth cubic reflects the previous control point', () {
      // The previous cubic ends at (2,0) with its second control point at
      // (0,-3), so `S` must synthesise (4,3) — mirrored through the pen. Using
      // the pen itself (the no-previous-curve fallback) would leave the bounds
      // at y = 0 on the way down.
      expect(boundsOf('M0 0C0 -3 0 -3 2 0S3 0 4 0'), rectCloseTo(0, -3, 4, 3));
    });

    test('a smooth cubic with no previous curve uses the pen position', () {
      expect(boundsOf('M0 0S1 1 2 2'), rectCloseTo(0, 0, 2, 2));
    });

    test('quadratic and smooth quadratic', () {
      expect(boundsOf('M0 0Q1 1 2 0'), rectCloseTo(0, 0, 2, 1));
      // `T` mirrors (1,1) through the pen at (2,0), giving (3,-1).
      expect(boundsOf('M0 0Q1 1 2 0T4 0'), rectCloseTo(0, -1, 4, 1));
    });

    test('rejects elliptical arcs rather than approximating them', () {
      expect(
        () => parseSvgPath('M0 0A1 1 0 0 1 2 2'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects malformed data instead of looping or drawing garbage', () {
      expect(() => parseSvgPath('10 10'), throwsA(isA<FormatException>()));
      expect(() => parseSvgPath('M0 0z5 5'), throwsA(isA<FormatException>()));
      expect(() => parseSvgPath('M0 0L5'), throwsA(isA<FormatException>()));
    });
  });

  group('brand glyphs', () {
    testWidgets('the Apple mark parses and paints', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: AppleGlyph(color: Color(0xFF000000))),
        ),
      );

      expect(tester.takeException(), isNull);
      // Taller than wide, per the logo's 814 x 1000 artboard.
      expect(tester.getSize(find.byType(AppleGlyph)), const Size(20, 20));
    });

    testWidgets('the Google mark parses and paints', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: GoogleGlyph()),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(GoogleGlyph)), const Size(20, 20));
    });
  });
}
