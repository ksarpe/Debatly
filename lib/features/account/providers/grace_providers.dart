import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/app_locale.dart' show sharedPreferencesProvider;
import '../../../data/models/user_stats.dart';
import '../../settings/providers/reminder_providers.dart'
    show votedTodayLocalProvider;
import 'stats_providers.dart';

/// Missed days that cost one rank tier — mirrors `decayed_streak`'s GRACE
/// constant server-side. A fresh grace window therefore holds this many
/// "graces", and `grace_days_left` counts down from it.
const int kGraceDays = 3;

/// SharedPreferences key: the `grace_days_left` value this device last saw (or
/// absent while the streak was intact). Kept locally so the "you lost a grace"
/// moment fires once per lost grace instead of on every stats refresh.
const String _kSeenGraceLeftKey = 'grace_seen_left';

/// Pure decision: did the user just LOSE a grace, given the countdown the
/// server reports now ([currentLeft], null while intact) and the one this
/// device last saw ([lastSeenLeft], null when intact / never observed)?
///
/// Kept free of prefs/UI so it can be unit-tested exhaustively:
///   * intact now (null) → no; nothing to mourn;
///   * a countdown LOWER than the last seen one → yes, a day slipped by;
///   * never seen a countdown (null) → yes if the window is already dented
///     (below [kGraceDays]) — the first launch after a missed day is exactly
///     the moment to say so; a full window (3) right after a tier drop is a
///     different event (the rank fell) and is not a lost grace;
///   * the same value → no (every `invalidate(userStatsProvider)` re-fetch
///     lands here);
///   * a HIGHER value → no: the window reset because a tier just dropped; the
///     caller re-seeds so the next lost day fires again.
bool shouldShowGraceLost({
  required int? currentLeft,
  required int? lastSeenLeft,
}) {
  if (currentLeft == null) return false;
  return currentLeft < (lastSeenLeft ?? kGraceDays);
}

/// Decides — and records — the one-shot "a grace is gone" moment off the back
/// of a freshly-synced [UserStats]. Orchestration only: the *when* lives in
/// the pure [shouldShowGraceLost], the *how* (the cracking heart) in the UI.
class GraceLostController extends Notifier<void> {
  @override
  void build() {}

  /// Returns the graces still left to announce for [stats], or null when no
  /// grace was just lost. Moves the stored baseline to the current countdown
  /// FIRST (clearing it while intact), so a repeat sync can't re-fire.
  Future<int?> evaluate(UserStats stats) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final last = prefs.containsKey(_kSeenGraceLeftKey)
        ? prefs.getInt(_kSeenGraceLeftKey)
        : null;
    final current = stats.graceDaysLeft;

    final show = shouldShowGraceLost(currentLeft: current, lastSeenLeft: last);

    if (last != current) {
      if (current == null) {
        await prefs.remove(_kSeenGraceLeftKey);
      } else {
        await prefs.setInt(_kSeenGraceLeftKey, current);
      }
    }

    return show ? current : null;
  }

  /// DEV: forget the baseline so the next sync re-evaluates from scratch.
  Future<void> debugReset() async {
    await ref.read(sharedPreferencesProvider).remove(_kSeenGraceLeftKey);
  }

  /// DEV: the baseline currently stored, for the tools screen's subtitle.
  int? debugLastSeen() {
    final prefs = ref.read(sharedPreferencesProvider);
    return prefs.containsKey(_kSeenGraceLeftKey)
        ? prefs.getInt(_kSeenGraceLeftKey)
        : null;
  }
}

final graceLostControllerProvider = NotifierProvider<GraceLostController, void>(
  GraceLostController.new,
);

/// Whether the streak is "cooling": there IS a streak to lose and today's
/// vote hasn't been cast yet (per the local stamp, which flips back at local
/// midnight). Drives the blue flame in the streak chip. A vote turns it off in
/// the same frame the stamp lands; a signed-out / zero streak is never at
/// risk — there is nothing to protect.
final streakAtRiskProvider = Provider<bool>((ref) {
  final streak = ref.watch(currentStreakProvider);
  if (streak <= 0) return false;
  return !ref.watch(votedTodayLocalProvider);
});
