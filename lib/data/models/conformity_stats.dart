/// How often the caller votes with the community majority — the data behind
/// the top-bar "oś zgodności" (conformity axis) panel.
///
/// Returned by the `get_conformity_stats` RPC as one aggregate row over the
/// caller's own votes. The majority side is computed server-side from the SAME
/// seed-inclusive totals the app renders as the community split, so the axis
/// can never disagree with the result bars the user actually saw. Votes on
/// questions with a tied split carry no majority to agree with — they count
/// into [totalVotes] but into neither side.
class ConformityStats {
  const ConformityStats({
    required this.totalVotes,
    required this.majorityVotes,
    required this.minorityVotes,
  });

  /// Every vote the user ever cast (ties included).
  final int totalVotes;

  /// Votes where the user's side holds the (seed-inclusive) majority.
  final int majorityVotes;

  /// Votes where the user's side is the minority.
  final int minorityVotes;

  /// Votes that place the user on a side — the axis denominator.
  int get decidedVotes => majorityVotes + minorityVotes;

  /// False until at least one vote lands on a non-tied question; the panel
  /// shows its "vote and find out" empty state instead of a meaningless marker.
  bool get hasData => decidedVotes > 0;

  /// Share of decided votes cast with the majority, 0..1. Centered (0.5) when
  /// there is no data, purely so a marker drawn anyway sits mid-axis.
  double get majorityFraction =>
      decidedVotes == 0 ? 0.5 : majorityVotes / decidedVotes;

  /// [majorityFraction] as a rounded whole percentage (0..100).
  int get majorityPct => (majorityFraction * 100).round();

  ConformityTier get tier => ConformityTier.fromFraction(majorityFraction);

  /// The neighbouring tier toward the majority end, or null at the top.
  ConformityTier? get nextTier => tier.next;

  /// How many consecutive with-the-majority votes would lift [majorityFraction]
  /// into [nextTier] — the panel's "N głosów z większością" progress line.
  ///
  /// Exact integer math on fifths (every tier bound is a multiple of 20%):
  /// smallest k with (majority+k)/(decided+k) ≥ bound. Null when already in the
  /// top tier or there is no data yet.
  int? get votesWithMajorityToNextTier {
    final next = nextTier;
    if (next == null || !hasData) return null;
    // bound = fifths/5. (m+k)*5 ≥ fifths*(d+k)  ⇒  k ≥ (fifths*d − 5m)/(5 − fifths)
    final fifths = next.lowerBoundFifths;
    final numerator = fifths * decidedVotes - 5 * majorityVotes;
    final denominator = 5 - fifths;
    if (numerator <= 0) return null; // already at/above the bound
    return (numerator + denominator - 1) ~/ denominator; // ceil
  }

  factory ConformityStats.fromJson(Map<String, dynamic> json) {
    int asInt(Object? v) => v is int ? v : int.tryParse('$v') ?? 0;
    return ConformityStats(
      totalVotes: asInt(json['total_votes']),
      majorityVotes: asInt(json['majority_votes']),
      minorityVotes: asInt(json['minority_votes']),
    );
  }

  static const ConformityStats empty = ConformityStats(
    totalVotes: 0,
    majorityVotes: 0,
    minorityVotes: 0,
  );
}

/// The five steps of the conformity axis, ordered from "always the minority"
/// to "always the majority". Each tier spans 20 percentage points of
/// [ConformityStats.majorityFraction]; a fraction on a bound belongs to the
/// higher tier (40% is already Niezależny, not Buntownik).
enum ConformityTier {
  loneWolf(0), // 0–19% with the majority — Samotny wilk
  rebel(1), // 20–39% — Buntownik
  independent(2), // 40–59% — Niezależny
  inTheCurrent(3), // 60–79% — W nurcie
  crowdVoice(4); // 80–100% — Głos tłumu

  const ConformityTier(this.lowerBoundFifths);

  /// Lower bound of the tier's range expressed in fifths (0..4 → 0%..80%),
  /// kept integer so tier progress math stays exact.
  final int lowerBoundFifths;

  double get lowerBound => lowerBoundFifths / 5;

  ConformityTier? get next =>
      this == crowdVoice ? null : ConformityTier.values[index + 1];

  static ConformityTier fromFraction(double fraction) {
    for (final tier in ConformityTier.values.reversed) {
      if (fraction >= tier.lowerBound) return tier;
    }
    return loneWolf;
  }
}
