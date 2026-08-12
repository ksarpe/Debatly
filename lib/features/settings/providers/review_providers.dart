import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/app_locale.dart' show sharedPreferencesProvider;
import '../../../core/time/epoch_day.dart';
import '../../../services/review_service.dart';

/// SharedPreferences key: the local "epoch day" (days since 1970) we last *asked*
/// for a store review — set whether or not the OS actually showed its sheet.
/// Absent until the first ask. Stored as a day index so the weekly cooldown is
/// plain integer subtraction.
const String _kLastPromptedDayKey = 'review_last_prompted_day';

/// The streak that first makes a user worth asking: they've come back three days
/// running, so they're engaged enough that a rating ask feels earned rather than
/// premature. Lines up with the entry milestones in the engagement ladder.
const int kReviewFirstStreakMilestone = 3;

/// Minimum days between asks. The OS throttles far harder than this (iOS roughly
/// three asks a year), but we keep our own cooldown so we only spend an ask at a
/// fresh high — "then about once a week" per the product brief.
const int kReviewCooldownDays = 7;

/// The device-local date as a day index (days since the Unix epoch). The streak
/// milestone is an engagement moment the user feels in local time, and the
/// cooldown is intentionally coarse, so local midnight is the right boundary.
int _todayEpochDay() => epochDay(DateTime.now());

/// Pure decision: should we ask for a store review right now?
///
/// Kept free of platform/prefs/clock so it can be unit-tested exhaustively:
///   * below the first milestone → never (too early to ask);
///   * at/above it and never asked before → yes (the first good moment);
///   * asked before → only once the weekly cooldown has elapsed.
///
/// A streak that later decays back below the milestone naturally stops the asks
/// again — exactly what we want, since that user has cooled off.
bool shouldPromptForReview({
  required int streak,
  required int? lastPromptedDay,
  required int todayDay,
}) {
  if (streak < kReviewFirstStreakMilestone) return false;
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

  /// Considers asking for a review off the back of [streak] — the freshly-synced
  /// current streak right after a daily vote, a genuine high point. No-ops unless
  /// the milestone + cooldown rules in [shouldPromptForReview] say it's due.
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
    await ReviewService.requestReview();
  }
}

final reviewPromptControllerProvider =
    NotifierProvider<ReviewPromptController, void>(ReviewPromptController.new);
