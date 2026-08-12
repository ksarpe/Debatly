import 'package:debatly/core/locale/app_locale.dart'
    show sharedPreferencesProvider;
import 'package:debatly/core/time/epoch_day.dart';
import 'package:debatly/features/settings/providers/review_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The in-app review ask is gated by a single pure decision so its timing is
/// fully testable without the OS sheet: ask once the user is engaged (a 3-day
/// streak), then at most about once a week, and back off again if the streak
/// decays below the milestone.
///
/// The controller group then pins the SIDE EFFECT the pure function can't: a due
/// ask arms the weekly cooldown in SharedPreferences (so the OS dropping the
/// sheet — which it usually does — can't make us re-fire on the next vote), a
/// premature ask writes nothing, and a not-due ask never slides the window.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('shouldPromptForReview', () {
    test('below the first milestone never asks', () {
      expect(
        shouldPromptForReview(streak: 2, lastPromptedDay: null, todayDay: 100),
        isFalse,
      );
    });

    test('first time reaching the milestone asks', () {
      expect(
        shouldPromptForReview(
          streak: kReviewFirstStreakMilestone,
          lastPromptedDay: null,
          todayDay: 100,
        ),
        isTrue,
      );
    });

    test('a long streak with no prior ask still asks', () {
      expect(
        shouldPromptForReview(streak: 30, lastPromptedDay: null, todayDay: 100),
        isTrue,
      );
    });

    test('within the weekly cooldown does not re-ask', () {
      // 4 days since the last ask — still inside the 7-day window.
      expect(
        shouldPromptForReview(streak: 10, lastPromptedDay: 96, todayDay: 100),
        isFalse,
      );
    });

    test('exactly at the cooldown boundary asks again', () {
      expect(
        shouldPromptForReview(
          streak: 10,
          lastPromptedDay: 100 - kReviewCooldownDays,
          todayDay: 100,
        ),
        isTrue,
      );
      // One day short of the boundary still holds.
      expect(
        shouldPromptForReview(
          streak: 10,
          lastPromptedDay: 100 - kReviewCooldownDays + 1,
          todayDay: 100,
        ),
        isFalse,
      );
    });

    test('a streak that decayed below the milestone stops asking', () {
      // Plenty of time has passed, but the user has cooled off — don't ask.
      expect(
        shouldPromptForReview(streak: 1, lastPromptedDay: 80, todayDay: 100),
        isFalse,
      );
    });
  });

  group('ReviewPromptController.maybePromptForStreak', () {
    // The private SharedPreferences key the controller stamps the ask date into.
    const lastPromptedKey = 'review_last_prompted_day';

    // Mirrors the controller's own local-date day index (the shared epochDay
    // helper), so a seeded "last ask" can be placed a known number of days
    // before today.
    int todayEpochDay() => epochDay(DateTime.now());

    Future<ProviderContainer> containerWith(Map<String, Object> prefs) async {
      SharedPreferences.setMockInitialValues(prefs);
      final sp = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('a due ask arms the weekly cooldown (stamps today)', () async {
      final c = await containerWith({});
      await c
          .read(reviewPromptControllerProvider.notifier)
          .maybePromptForStreak(kReviewFirstStreakMilestone);

      // Read through the SAME injected instance the controller wrote to — a
      // second getInstance() wouldn't reflect the write (shared_preferences
      // 2.5.5 quirk; see locale_controller_test).
      final sp = c.read(sharedPreferencesProvider);
      expect(
        sp.getInt(lastPromptedKey),
        todayEpochDay(),
        reason: 'a due ask records today so the cooldown starts',
      );
    });

    test(
      'below the milestone it asks for nothing and records nothing',
      () async {
        final c = await containerWith({});
        await c
            .read(reviewPromptControllerProvider.notifier)
            .maybePromptForStreak(kReviewFirstStreakMilestone - 1);

        final sp = c.read(sharedPreferencesProvider);
        expect(
          sp.getInt(lastPromptedKey),
          isNull,
          reason: 'no ask → no stamp, so it can still ask later when due',
        );
      },
    );

    test(
      'within the cooldown it leaves the existing stamp untouched',
      () async {
        final recent =
            todayEpochDay() - 1; // asked "yesterday" — well inside 7d
        final c = await containerWith({lastPromptedKey: recent});
        await c
            .read(reviewPromptControllerProvider.notifier)
            .maybePromptForStreak(10);

        final sp = c.read(sharedPreferencesProvider);
        expect(
          sp.getInt(lastPromptedKey),
          recent,
          reason: 'a not-due ask must not slide the cooldown window forward',
        );
      },
    );
  });
}
