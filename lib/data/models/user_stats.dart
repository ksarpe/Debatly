/// The user's engagement state shown by the two top icons (streak + free
/// unlocks) and the rank sheet.
///
/// Produced server-side by the `sync_user_state` RPC, which also performs the
/// once-per-day free-credit top-up as a side effect. Everything here is the
/// SERVER's view — the client never computes streak or credits itself, so the
/// phone clock can't be used to game them.
class UserStats {
  const UserStats({
    required this.currentStreak,
    required this.longestStreak,
    required this.freeUnlockCredits,
    required this.rankTier,
    required this.rankName,
    this.nextRankStreak,
    this.graceDaysLeft,
    this.isPremium = false,
    this.adRevealsLeftToday,
  });

  /// Consecutive days the user voted on the daily. The server applies the streak
  /// "freeze" decay (one rank per 3 missed days) before returning this, so a
  /// missed day no longer snaps it to 0 — it only steps down once the grace
  /// window elapses.
  final int currentStreak;

  /// Best streak ever reached — shown as a secondary stat in the rank sheet.
  final int longestStreak;

  /// Free unlock credits in the bank (0 or 1). Always 0 for premium users, who
  /// don't use the credit system at all (everything is already readable).
  final int freeUnlockCredits;

  /// Index of the current rank in the ladder (0 = the entry rank).
  final int rankTier;

  /// Localised name of the current rank (e.g. "Prowokator").
  final String rankName;

  /// Streak needed to reach the next rank, or null when already at the top.
  final int? nextRankStreak;

  /// Days left before the streak "freeze" drops the user one more rank, or null
  /// when the streak is intact (voted today/yesterday) or already at the bottom.
  /// Non-null means the user is mid-grace and about to lose a tier.
  final int? graceDaysLeft;

  final bool isPremium;

  /// Ad reveals left before today's daily cap (server-enforced, UTC day).
  /// Null = unknown: premium (never hits the ad wall), an old server without
  /// the field, or a pre-sync/offline snapshot — the paywall then keeps the ad
  /// button and lets the server be the judge.
  final int? adRevealsLeftToday;

  factory UserStats.fromJson(Map<String, dynamic> json) {
    int asInt(Object? v) => v is int ? v : int.tryParse('$v') ?? 0;
    return UserStats(
      currentStreak: asInt(json['current_streak']),
      longestStreak: asInt(json['longest_streak']),
      freeUnlockCredits: asInt(json['free_unlock_credits']),
      rankTier: asInt(json['rank_tier']),
      rankName: json['rank_name'] as String? ?? '',
      nextRankStreak: json['next_rank_streak'] == null
          ? null
          : asInt(json['next_rank_streak']),
      graceDaysLeft: json['grace_days_left'] == null
          ? null
          : asInt(json['grace_days_left']),
      isPremium: json['is_premium'] as bool? ?? false,
      adRevealsLeftToday: json['ad_reveals_left_today'] == null
          ? null
          : asInt(json['ad_reveals_left_today']),
    );
  }

  /// Mirrors the `sync_user_state` row shape so a cached snapshot round-trips
  /// back through [UserStats.fromJson] — lets the streak / credit chips render
  /// from the last sync while offline instead of resetting to [empty].
  Map<String, dynamic> toJson() => {
    'current_streak': currentStreak,
    'longest_streak': longestStreak,
    'free_unlock_credits': freeUnlockCredits,
    'rank_tier': rankTier,
    'rank_name': rankName,
    'next_rank_streak': nextRankStreak,
    'grace_days_left': graceDaysLeft,
    'is_premium': isPremium,
    'ad_reveals_left_today': adRevealsLeftToday,
  };

  /// A zeroed state used as the offline/mock baseline and before the first sync.
  static const UserStats empty = UserStats(
    currentStreak: 0,
    longestStreak: 0,
    freeUnlockCredits: 0,
    rankTier: 0,
    rankName: '',
    nextRankStreak: null,
  );
}
