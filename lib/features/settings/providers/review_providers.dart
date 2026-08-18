import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/app_locale.dart' show sharedPreferencesProvider;
import '../../../core/time/epoch_day.dart';
import '../../../services/analytics.dart';
import '../../../services/review_service.dart';

/// SharedPreferences key: lifetime count of successfully cast votes on this
/// device — the engagement odometer the review milestones ride on. Counted
/// client-side (not from server stats) so it also ticks offline-queued votes
/// and needs no extra fetch on the hot vote path.
const String _kVoteCountKey = 'review_vote_count';

/// SharedPreferences key: the highest vote milestone already spent on an ask.
/// Consuming the higher milestone implies the lower one, so a single int is
/// enough. Absent (→ 0) until the first ask.
const String _kLastMilestoneKey = 'review_last_milestone';

/// SharedPreferences key: the local "epoch day" (days since 1970) we last
/// *asked* for a store review — set whether or not the OS actually showed its
/// sheet. Caps the ask at one per local day, so a PRO binge that crosses both
/// milestones in one session doesn't ask twice in a row.
const String _kLastPromptedDayKey = 'review_last_prompted_day';

/// The vote counts at which we ask for a store review: once the loop has been
/// felt (3rd vote), and one reminder later (7th vote). The OS gives no "did
/// they review?" signal, so the second ask is unconditional — but the native
/// sheet is quota-limited and Android/iOS won't re-show it to someone who
/// already rated. After the last milestone we never ask again.
const List<int> kReviewVoteMilestones = [3, 7];

/// The device-local date as a day index (days since the Unix epoch). Votes are
/// a moment the user feels in local time and the one-per-day cap is
/// intentionally coarse, so local midnight is the right boundary.
int _todayEpochDay() => epochDay(DateTime.now());

/// Pure decision: which milestone (if any) earns an ask right now?
///
/// Kept free of platform/prefs/clock so it can be unit-tested exhaustively:
///   * at most one ask per local day — a milestone reached on an
///     already-asked day is NOT consumed, it simply comes due again on the
///     next vote on a later day;
///   * each milestone fires at most once, and consuming a higher one retires
///     every lower one (no double-ask when a backlog crosses both at once);
///   * past the last milestone → never again.
int? dueReviewMilestone({
  required int voteCount,
  required int lastMilestone,
  required int? lastPromptedDay,
  required int todayDay,
}) {
  if (lastPromptedDay != null && lastPromptedDay >= todayDay) return null;
  for (final milestone in kReviewVoteMilestones.reversed) {
    if (milestone > lastMilestone && voteCount >= milestone) return milestone;
  }
  return null;
}

/// Decides — and, when due, fires — the in-app review ask.
///
/// Orchestration only: the *when* lives in the pure [dueReviewMilestone], the
/// *how* in [ReviewService]. It holds no state of its own; the three facts it
/// needs (vote count, spent milestone, last ask date) live in
/// SharedPreferences so they survive restarts.
///
/// Two call sites share it:
///   * DailyVotePanel counts every successful vote ([recordVote]) and, on a
///     non-promotion day, immediately considers the ask;
///   * RankCelebrationListener considers it right after the rank-up
///     celebration closes, so on a promotion day the ask rides the moment of
///     satisfaction instead of colliding with the confetti.
class ReviewPromptController extends Notifier<void> {
  @override
  void build() {}

  /// Ticks the lifetime vote counter. Call once per successfully cast vote,
  /// before [maybePromptForReview]. Returns the new count.
  Future<int> recordVote() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final count = (prefs.getInt(_kVoteCountKey) ?? 0) + 1;
    await prefs.setInt(_kVoteCountKey, count);
    return count;
  }

  /// Fires the OS review sheet if a vote milestone is due; no-ops otherwise.
  /// Returns whether an ask was spent, so the caller can keep the
  /// one-dialog-per-vote rule.
  ///
  /// Records the attempt BEFORE requesting, so a request the OS silently drops
  /// (it usually does — the sheet is quota-limited) still retires the
  /// milestone instead of re-firing on the very next vote.
  Future<bool> maybePromptForReview() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final votes = prefs.getInt(_kVoteCountKey) ?? 0;
    final milestone = dueReviewMilestone(
      voteCount: votes,
      lastMilestone: prefs.getInt(_kLastMilestoneKey) ?? 0,
      lastPromptedDay: prefs.getInt(_kLastPromptedDayKey),
      todayDay: _todayEpochDay(),
    );
    if (milestone == null) return false;

    await prefs.setInt(_kLastMilestoneKey, milestone);
    await prefs.setInt(_kLastPromptedDayKey, _todayEpochDay());
    Analytics.log('review_prompt_requested', {
      'milestone': milestone,
      'votes': votes,
    });
    await ReviewService.requestReview();
    return true;
  }

  /// DEV tools: the current odometer, for display in the DEV screen.
  ({int votes, int lastMilestone, int? lastPromptedDay}) debugState() {
    final prefs = ref.read(sharedPreferencesProvider);
    return (
      votes: prefs.getInt(_kVoteCountKey) ?? 0,
      lastMilestone: prefs.getInt(_kLastMilestoneKey) ?? 0,
      lastPromptedDay: prefs.getInt(_kLastPromptedDayKey),
    );
  }

  /// DEV tools: wipes the odometer so the milestone flow can be replayed.
  Future<void> debugReset() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.remove(_kVoteCountKey);
    await prefs.remove(_kLastMilestoneKey);
    await prefs.remove(_kLastPromptedDayKey);
  }
}

final reviewPromptControllerProvider =
    NotifierProvider<ReviewPromptController, void>(ReviewPromptController.new);
