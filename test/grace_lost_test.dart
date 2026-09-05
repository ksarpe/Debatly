import 'package:debatly/features/account/providers/grace_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shouldShowGraceLost', () {
    test('an intact streak never mourns', () {
      // grace_days_left is null while the user voted today / yesterday, or
      // once the rank has bottomed out — nothing to announce either way.
      expect(
        shouldShowGraceLost(currentLeft: null, lastSeenLeft: null),
        isFalse,
      );
      expect(shouldShowGraceLost(currentLeft: null, lastSeenLeft: 2), isFalse);
    });

    test('the first dented window fires on first sight', () {
      // First launch after a missed day: the server says 2 of 3 graces remain
      // and this device has no baseline yet — that IS the lost grace.
      expect(shouldShowGraceLost(currentLeft: 2, lastSeenLeft: null), isTrue);
      expect(shouldShowGraceLost(currentLeft: 1, lastSeenLeft: null), isTrue);
    });

    test(
      'a full window seen for the first time is a tier drop, not a grace',
      () {
        // Right after a drop the countdown resets to 3 — the rank fell, but no
        // grace was "lost" today relative to a full window.
        expect(
          shouldShowGraceLost(currentLeft: kGraceDays, lastSeenLeft: null),
          isFalse,
        );
      },
    );

    test('the countdown falling fires once per day', () {
      expect(shouldShowGraceLost(currentLeft: 1, lastSeenLeft: 2), isTrue);
      expect(shouldShowGraceLost(currentLeft: 2, lastSeenLeft: 3), isTrue);
    });

    test('the same countdown does not re-fire', () {
      // Every invalidate(userStatsProvider) re-fetch lands here.
      expect(shouldShowGraceLost(currentLeft: 2, lastSeenLeft: 2), isFalse);
    });

    test(
      'a reset window (tier just dropped) does not fire as a lost grace',
      () {
        // 1 → 3: the drop landed and the window restarted; the caller re-seeds
        // the baseline so tomorrow's 3 → 2 fires again.
        expect(shouldShowGraceLost(currentLeft: 3, lastSeenLeft: 1), isFalse);
      },
    );
  });
}
