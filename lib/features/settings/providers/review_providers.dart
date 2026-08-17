import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/app_locale.dart' show sharedPreferencesProvider;
import '../../../core/time/epoch_day.dart';
import '../../../services/analytics.dart';
import '../../../services/review_service.dart';

/// SharedPreferences key: the local "epoch day" (days since 1970) we last *asked*
/// for a store review — set whether or not the OS actually showed its sheet.
/// Absent until the first ask. Stored as a day index so the cooldown is
/// plain integer subtraction.
const String _kLastPromptedDayKey = 'review_last_prompted_day';

/// THE review moment: the day the streak completes 3 days — the user has come
/// back three days running and just watched the rank animation, so the ask
/// lands on satisfaction. Exactly this milestone and nowhere else (never at
/// first launch, in onboarding, on the wall, or after a dismissed paywall);
/// the OS keeps its own hard cap (~3 asks per user per year) on top.
const int kReviewStreakMilestone = 3;

/// Minimum days between asks, so a streak that decays and re-climbs through
/// the milestone doesn't re-ask within the same week.
const int kReviewCooldownDays = 7;

/// The device-local date as a day index (days since the Unix epoch). The streak
/// milestone is an engagement moment the user feels in local time, and the
/// cooldown is intentionally coarse, so local midnight is the right boundary.
int _todayEpochDay() => epochDay(DateTime.now());

/// Pure decision: should we ask for a store review right now?
///
/// Kept free of platform/prefs/clock so it can be unit-tested exhaustively:
///   * anywhere but the exact 3-day milestone → never;
///   * at it and never asked before → yes (the one good moment);
///   * asked before (a decayed streak re-climbing through 3) → only once the
///     cooldown has elapsed.
bool shouldPromptForReview({
  required int streak,
  required int? lastPromptedDay,
  required int todayDay,
}) {
  if (streak != kReviewStreakMilestone) return false;
  if (lastPromptedDay == null) return true;
  return todayDay - lastPromptedDay >= kReviewCooldownDays;
}

/// Decides — and, when due, fires — the in-app review ask.
///
/// Orchestration only: the *when* lives in the pure [shouldPromptForReview], the
/// *how* in [ReviewService]. It holds no state of its own; the single fact it
/// needs (the last ask date) lives in SharedPreferences so it survives restarts.
class ReviewPromptController extends Notifier<void> {
  @override
  void build() {}

  /// Considers asking for a review off the back of [streak] — called after
  /// the rank-up celebration closes on a promotion day (streak 3 is the
  /// "Zadziora" promotion, so the ask rides right behind that animation).
  /// No-ops unless [shouldPromptForReview] says it's due.
  ///
  /// Records the attempt BEFORE requesting, so a request the OS silently drops
  /// (it usually does — the sheet is quota-limited) still arms the cooldown
  /// instead of re-firing on the very next vote.
  Future<void> maybePromptForStreak(int streak) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final lastDay = prefs.getInt(_kLastPromptedDayKey);
    final today = _todayEpochDay();

    if (!shouldPromptForReview(
      streak: streak,
      lastPromptedDay: lastDay,
      todayDay: today,
    )) {
      return;
    }

    await prefs.setInt(_kLastPromptedDayKey, today);
    Analytics.log('review_prompt_requested', {'streak': streak});
    await ReviewService.requestReview();
  }
}

final reviewPromptControllerProvider =
    NotifierProvider<ReviewPromptController, void>(ReviewPromptController.new);
