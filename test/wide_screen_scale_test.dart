import 'package:debatly/core/layout/wide_screen_scale.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The magnification applied to tablets.
///
/// The floor is the part that matters most: it must be EXACTLY 1.0 for phones,
/// so no transform layer is inserted on the devices almost every session runs
/// on — and so the 800x600 surface the widget tests render on keeps measuring
/// what it has always measured.
void main() {
  group('wideScreenScaleFor', () {
    test('phones are untouched', () {
      expect(wideScreenScaleFor(const Size(393, 852)), 1.0); // Pixel-ish
      expect(wideScreenScaleFor(const Size(320, 568)), 1.0); // smallest
      expect(wideScreenScaleFor(const Size(430, 932)), 1.0); // largest phone
    });

    test('the default widget-test surface stays at 1.0', () {
      // 800x600 -> shortest side exactly 600, which must NOT scale, or every
      // layout assertion in the suite would silently shift.
      expect(wideScreenScaleFor(const Size(800, 600)), 1.0);
    });

    test('tablets are magnified, and identically in both orientations', () {
      final portrait = wideScreenScaleFor(const Size(1067, 1707));
      final landscape = wideScreenScaleFor(const Size(1707, 1067));
      expect(portrait, greaterThan(1.0));
      // Keyed on the shortest side, so rotating must not resize the type.
      expect(portrait, landscape);
    });

    test(
      'magnification is capped so a large display is not a zoomed phone',
      () {
        // 12.9" iPad — uncapped this would reach ~2.4x.
        expect(
          wideScreenScaleFor(const Size(1024, 1366)),
          lessThanOrEqualTo(1.75),
        );
      },
    );

    test(
      'scaling down the screen by the factor lands near the design width',
      () {
        const size = Size(834, 1194); // 11" iPad
        final scale = wideScreenScaleFor(size);
        // The point of the exercise: the tree lays out as if on a phone-sized
        // viewport, which is what keeps the column full rather than an island.
        expect(size.width / scale, closeTo(560, 1));
      },
    );
  });
}
