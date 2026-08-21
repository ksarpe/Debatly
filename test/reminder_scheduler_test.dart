import 'package:debatly/services/reminder_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

/// The reminder's anti-spam contract: a nudge only fires when it still has
/// something to offer. Everything here pins [shouldSilenceTodaysReminder], the
/// one decision that stands between the user and a pointless ping.
void main() {
  /// Today at [hour]:[minute], relative to a fixed reference day so the tests
  /// never depend on the wall clock.
  DateTime at(int hour, int minute) => DateTime(2026, 8, 21, hour, minute);

  bool silence({
    bool votedToday = false,
    bool isPremium = false,
    int hour = 20,
    int minute = 0,
    required DateTime now,
  }) => shouldSilenceTodaysReminder(
    votedToday: votedToday,
    isPremium: isPremium,
    hour: hour,
    minute: minute,
    now: now,
  );

  group('already voted', () {
    test('free + voted → silent: the daily was their whole deck', () {
      expect(silence(votedToday: true, now: at(9, 0)), isTrue);
    });

    test('free + voted → silent even far from the slot', () {
      // Nothing about the hour rescues it — there is no second question to open.
      expect(silence(votedToday: true, now: at(0, 5)), isTrue);
    });

    test('PRO + voted → still nudged: the catalog is open to them', () {
      expect(
        silence(votedToday: true, isPremium: true, now: at(9, 0)),
        isFalse,
      );
    });
  });

  group('quiet window', () {
    test('a session hours before the slot leaves it armed', () {
      expect(silence(now: at(9, 0)), isFalse);
    });

    test('a session just inside the window silences the slot', () {
      expect(silence(now: at(17, 30)), isTrue);
    });

    test('the window boundary itself still fires', () {
      expect(silence(now: at(16, 0)), isFalse);
    });

    test('PRO gets no exemption from the quiet window', () {
      // The rule is "you were just here", which has nothing to do with tier.
      expect(silence(isPremium: true, now: at(19, 0)), isTrue);
    });

    test('a slot already past is left to the scheduler, not silenced here', () {
      // `scheduleReminderLoop` never arms a passed slot; this must not claim
      // one is "within the window" just because it is close behind.
      expect(silence(now: at(21, 0)), isFalse);
    });

    test('an early-morning slot is unaffected by an evening session', () {
      expect(silence(hour: 8, now: at(20, 0)), isFalse);
    });
  });

  group('cadence', () {
    test('starts today and thins out across a month', () {
      // The shape is the whole point: dense while the habit is recoverable,
      // sparse once it is a win-back — and never a week of nightly pings.
      expect(kReminderLoopOffsets.first, 0);
      expect(kReminderLoopOffsets.last, greaterThanOrEqualTo(28));
      expect(
        kReminderLoopOffsets,
        orderedEquals(kReminderLoopOffsets.toList()..sort()),
      );
      expect(
        kReminderLoopOffsets.toSet(),
        hasLength(kReminderLoopOffsets.length),
      );
    });

    test('gaps never shrink as the loop reaches further out', () {
      final gaps = [
        for (var i = 1; i < kReminderLoopOffsets.length; i++)
          kReminderLoopOffsets[i] - kReminderLoopOffsets[i - 1],
      ];
      for (var i = 1; i < gaps.length; i++) {
        expect(gaps[i], greaterThanOrEqualTo(gaps[i - 1]), reason: 'gap $i');
      }
    });

    test('a month of coverage costs fewer fires than the old flat week', () {
      // The regression this replaces: 7 consecutive days, then permanent
      // silence for anyone still away on day 8.
      expect(kReminderLoopOffsets, hasLength(lessThanOrEqualTo(12)));
      expect(kReminderLoopOffsets.where((o) => o <= 7), hasLength(lessThan(7)));
    });
  });
}
