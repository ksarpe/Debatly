import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/app_locale.dart' show sharedPreferencesProvider;
import '../../../data/models/rank.dart';
import '../../../data/models/user_stats.dart';

/// SharedPreferences key: the highest rank tier we have already *celebrated* on
/// this device. Absent until the first stats sync seeds it. Kept locally (the
/// server owns the rank itself) so the one-shot promotion moment fires once per
/// climb instead of every time stats refresh.
const String _kCelebratedTierKey = 'rank_celebrated_tier';

/// Pure decision: should reaching [currentTier] trigger the rank-up celebration,
/// given the tier we last celebrated ([lastCelebratedTier], null if we've never
/// recorded one on this device)?
///
/// Kept free of prefs/UI so it can be unit-tested exhaustively:
///   * tier 0 is the free entry rank — never a "promotion", so never celebrated;
///   * first observation (null) → seed only, never celebrate. This stops a
///     fresh install / a user who already passed ranks before this shipped from
///     getting a retroactive barrage;
///   * a tier *above* the last celebrated one → yes, a genuine promotion;
///   * same tier → no;
///   * a *lower* tier (the streak "freeze" decayed a rank) → no, but the caller
///     drops the baseline so re-climbing the rank celebrates again — rewarding
///     the recovery the freeze mechanic sets up.
bool shouldCelebrateRank({
  required int currentTier,
  required int? lastCelebratedTier,
}) {
  if (currentTier <= 0) return false;
  if (lastCelebratedTier == null) return false;
  return currentTier > lastCelebratedTier;
}

/// Decides — and records — the one-shot rank-up celebration off the back of a
/// freshly-synced [UserStats].
///
/// Orchestration only: the *when* lives in the pure [shouldCelebrateRank], the
/// *how* (confetti + share card) lives in the UI. The single fact it holds — the
/// last celebrated tier — lives in SharedPreferences so a promotion is celebrated
/// exactly once across restarts.
class RankCelebrationController extends Notifier<void> {
  @override
  void build() {}

  /// Returns the [Rank] to celebrate for [stats], or null when no promotion just
  /// happened. Advances the stored baseline to the current tier as a side effect
  /// FIRST, so the decision is idempotent: a repeat sync of the same tier (every
  /// `invalidate(userStatsProvider)` re-fetch) can't re-fire the moment.
  ///
  /// [ladder] supplies the rank's name/icon for the celebration; pass the loaded
  /// ranks (falling back to [kDefaultRanks]).
  Future<Rank?> evaluate(UserStats stats, List<Rank> ladder) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final last = prefs.getInt(_kCelebratedTierKey);
    final current = stats.rankTier;

    final celebrate = shouldCelebrateRank(
      currentTier: current,
      lastCelebratedTier: last,
    );

    final rank = celebrate ? _rankForTier(ladder, current) : null;

    // Move the baseline to the current tier: seeding on the first observation,
    // advancing on a promotion, and lowering it after a freeze drop so the
    // re-climb fires again. Done before returning so the celebration is
    // consumed even if showing it later fails. ONE exception: a promotion whose
    // tier the ladder can't name yet (stale/partial ranks fetch) keeps the old
    // baseline — otherwise the promotion would be consumed invisibly and lost
    // for good; holding it lets the next sync celebrate once the ladder loads.
    final holdForMissingRank = celebrate && rank == null;
    if (last != current && !holdForMissingRank) {
      await prefs.setInt(_kCelebratedTierKey, current);
    }

    return rank;
  }

  Rank? _rankForTier(List<Rank> ladder, int tier) {
    for (final r in ladder) {
      if (r.tier == tier) return r;
    }
    return null;
  }
}

final rankCelebrationControllerProvider =
    NotifierProvider<RankCelebrationController, void>(
      RankCelebrationController.new,
    );
