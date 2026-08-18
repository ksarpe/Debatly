import 'package:debatly/core/locale/app_locale.dart'
    show sharedPreferencesProvider;
import 'package:debatly/core/time/epoch_day.dart';
import 'package:debatly/features/settings/providers/review_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The in-app review ask is gated by a single pure decision so its timing is
/// fully testable without the OS sheet: ask on the vote milestones (3rd and
/// 7th vote), each at most once, at most one ask per local day, and never
/// again past the last milestone.
///
/// The controller group then pins the SIDE EFFECTS the pure function can't:
/// every vote ticks the odometer, a due ask retires its milestone and stamps
/// the day in SharedPreferences (so the OS dropping the sheet — which it
/// usually does — can't make us re-fire on the next vote), and a not-due ask
/// writes nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('dueReviewMilestone', () {
    test('below the first milestone never asks', () {
      expect(
        dueReviewMilestone(
          voteCount: 2,
          lastMilestone: 0,
          lastPromptedDay: null,
          todayDay: 100,
        ),
        isNull,
      );
    });

    test('the 3rd vote asks with milestone 3', () {
      expect(
        dueReviewMilestone(
          voteCount: 3,
          lastMilestone: 0,
          lastPromptedDay: null,
          todayDay: 100,
        ),
        3,
      );
    });

    test('votes 4–6 stay quiet once milestone 3 is spent', () {
      for (final votes in [4, 5, 6]) {
        expect(
          dueReviewMilestone(
            voteCount: votes,
            lastMilestone: 3,
            lastPromptedDay: 90,
            todayDay: 100,
          ),
          isNull,
        );
      }
    });

    test('the 7th vote asks again with milestone 7', () {
      expect(
        dueReviewMilestone(
          voteCount: 7,
          lastMilestone: 3,
          lastPromptedDay: 90,
          todayDay: 100,
        ),
        7,
      );
    });

    test('past the last milestone it never asks again', () {
      expect(
        dueReviewMilestone(
          voteCount: 250,
          lastMilestone: 7,
          lastPromptedDay: 10,
          todayDay: 100,
        ),
        isNull,
      );
    });

    test('a backlog crossing both milestones asks once, with the higher one '
        '(consuming 7 retires 3 too)', () {
      expect(
        dueReviewMilestone(
          voteCount: 9,
          lastMilestone: 0,
          lastPromptedDay: null,
          todayDay: 100,
        ),
        7,
      );
    });

    test('at most one ask per local day — a same-day milestone is deferred, '
        'not consumed', () {
      // Asked this morning (milestone 3); a PRO binge reaches 7 the same day.
      expect(
        dueReviewMilestone(
          voteCount: 7,
          lastMilestone: 3,
          lastPromptedDay: 100,
          todayDay: 100,
        ),
        isNull,
      );
      // The very next day the deferred milestone comes due on the next vote.
      expect(
        dueReviewMilestone(
          voteCount: 8,
          lastMilestone: 3,
          lastPromptedDay: 100,
          todayDay: 101,
        ),
        7,
      );
    });
  });

  group('ReviewPromptController', () {
    // The private SharedPreferences keys the controller writes.
    const voteCountKey = 'review_vote_count';
    const lastMilestoneKey = 'review_last_milestone';
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

    test('recordVote ticks the odometer', () async {
      final c = await containerWith({});
      final ctrl = c.read(reviewPromptControllerProvider.notifier);
      expect(await ctrl.recordVote(), 1);
      expect(await ctrl.recordVote(), 2);

      // Read through the SAME injected instance the controller wrote to — a
      // second getInstance() wouldn't reflect the write (shared_preferences
      // 2.5.5 quirk; see locale_controller_test).
      final sp = c.read(sharedPreferencesProvider);
      expect(sp.getInt(voteCountKey), 2);
    });

    test('a due ask retires the milestone and stamps today', () async {
      final c = await containerWith({voteCountKey: 3});
      final asked = await c
          .read(reviewPromptControllerProvider.notifier)
          .maybePromptForReview();

      expect(asked, isTrue);
      final sp = c.read(sharedPreferencesProvider);
      expect(
        sp.getInt(lastMilestoneKey),
        3,
        reason: 'a due ask spends its milestone so it cannot re-fire',
      );
      expect(
        sp.getInt(lastPromptedKey),
        todayEpochDay(),
        reason: 'a due ask records today so the daily cap starts',
      );
    });

    test(
      'below the milestone it asks for nothing and records nothing',
      () async {
        final c = await containerWith({voteCountKey: 2});
        final asked = await c
            .read(reviewPromptControllerProvider.notifier)
            .maybePromptForReview();

        expect(asked, isFalse);
        final sp = c.read(sharedPreferencesProvider);
        expect(
          sp.getInt(lastMilestoneKey),
          isNull,
          reason: 'no ask → no spent milestone, so it can still ask when due',
        );
        expect(sp.getInt(lastPromptedKey), isNull);
      },
    );

    test('a second milestone reached on the ask day is deferred, and the '
        'existing stamps stay untouched', () async {
      final c = await containerWith({
        voteCountKey: 7,
        lastMilestoneKey: 3,
        lastPromptedKey: todayEpochDay(),
      });
      final asked = await c
          .read(reviewPromptControllerProvider.notifier)
          .maybePromptForReview();

      expect(asked, isFalse);
      final sp = c.read(sharedPreferencesProvider);
      expect(
        sp.getInt(lastMilestoneKey),
        3,
        reason: 'a deferred milestone must not be consumed',
      );
    });

    test('the deferred milestone fires on a later day', () async {
      final c = await containerWith({
        voteCountKey: 7,
        lastMilestoneKey: 3,
        lastPromptedKey: todayEpochDay() - 1,
      });
      final asked = await c
          .read(reviewPromptControllerProvider.notifier)
          .maybePromptForReview();

      expect(asked, isTrue);
      final sp = c.read(sharedPreferencesProvider);
      expect(sp.getInt(lastMilestoneKey), 7);
    });

    test('debugReset wipes the odometer', () async {
      final c = await containerWith({
        voteCountKey: 9,
        lastMilestoneKey: 7,
        lastPromptedKey: 100,
      });
      await c.read(reviewPromptControllerProvider.notifier).debugReset();

      final sp = c.read(sharedPreferencesProvider);
      expect(sp.getInt(voteCountKey), isNull);
      expect(sp.getInt(lastMilestoneKey), isNull);
      expect(sp.getInt(lastPromptedKey), isNull);
    });
  });
}
