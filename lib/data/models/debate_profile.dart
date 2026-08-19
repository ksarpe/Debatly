import 'dart:math' as math;

/// The four cells of the 2×2 debate-profile grid: conformity (does the user
/// vote with the crowd?) × resilience (do good arguments move them?).
///
/// All four names carry equal dignity ON PURPOSE. The moment one reads as a
/// punishment, the gamification teaches people to stop reading smaczki — the
/// exact opposite of what the product wants.
enum DebateProfileType {
  /// With the crowd, rarely moved — "myślisz jak większość i nic Tobą nie
  /// ruszy".
  pillar,

  /// With the crowd AND with every good argument.
  flow,

  /// Against the crowd, rarely moved — own mind, end of discussion.
  wolf,

  /// Against the crowd, but moved by better arguments — doesn't buy opinions,
  /// hunts for better ones.
  seeker,
}

/// How much of the profile may be shown.
enum DebateProfileStage {
  /// Under the unlock threshold on either counter — show progress, not a type.
  locked,

  /// Both counters cleared the unlock minimum but not the full one. The type
  /// shows with a "profil wstępny" tag: at n=6 the error bars reach ±40 pp,
  /// enough to name a side of the boundary, not enough to certify it.
  provisional,

  /// Both counters at or past the full threshold.
  full,
}

/// The caller's debate profile: both axes' raw counts plus the LIVE boundaries
/// and thresholds, all served by the `get_debate_profile` RPC.
///
/// The boundaries arrive from the server (`profile_config`) instead of being
/// client constants, so they can be re-derived from real population medians
/// without an app release. The defaults mirror the server's seeds: a 65%
/// conformity boundary (NOT 50% — the expected conformity of a random voter
/// at typical 55–75% splits is ~65%, so a 50% cut would collapse the grid)
/// and a 15% moved-share boundary.
class DebateProfile {
  const DebateProfile({
    required this.totalVotes,
    required this.majorityVotes,
    required this.minorityVotes,
    required this.gateHeld,
    required this.gateMoved,
    this.conformityBoundary = 0.65,
    this.resilienceBoundary = 0.15,
    this.unlockMin = 6,
    this.fullMin = 12,
  });

  /// Every vote the user ever cast (ties included) — unlock counter #1.
  final int totalVotes;

  final int majorityVotes;
  final int minorityVotes;

  /// Qualifying gate answers only: outcome held/moved with dwell at or above
  /// the server's minimum (default 1500 ms). Fast taps, dismissals and
  /// skipped gates never reach these numbers.
  final int gateHeld;
  final int gateMoved;

  /// Conformity boundary, 0..1: at/above = "with the crowd".
  final double conformityBoundary;

  /// Resilience boundary, 0..1 of the moved share: at/above = "movable".
  final double resilienceBoundary;

  /// Both counters must reach this for any type to show.
  final int unlockMin;

  /// Both counters at/past this drop the "provisional" tag.
  final int fullMin;

  int get decidedVotes => majorityVotes + minorityVotes;

  /// Qualifying gate answers — unlock counter #2.
  int get gateAnswered => gateHeld + gateMoved;

  /// The limiting counter: BOTH thresholds are per-counter, so progress and
  /// stage follow whichever of the two is further behind.
  int get limitingCounter => math.min(totalVotes, gateAnswered);

  /// Answers still missing before the type unlocks (0 once unlocked).
  int get answersToUnlock => math.max(0, unlockMin - limitingCounter);

  DebateProfileStage get stage {
    // decidedVotes guards the absurd all-ties corner: a fraction computed
    // over zero decided votes would be noise wearing a name.
    if (limitingCounter < unlockMin || decidedVotes == 0) {
      return DebateProfileStage.locked;
    }
    return limitingCounter >= fullMin
        ? DebateProfileStage.full
        : DebateProfileStage.provisional;
  }

  /// Share of decided votes cast with the majority, 0..1.
  double get conformityFraction =>
      decidedVotes == 0 ? 0.5 : majorityVotes / decidedVotes;

  /// Share of qualifying gates answered "to mnie ruszyło", 0..1.
  double get movedFraction => gateAnswered == 0 ? 0 : gateMoved / gateAnswered;

  int get conformityPct => (conformityFraction * 100).round();
  int get movedPct => (movedFraction * 100).round();

  bool get withCrowd => conformityFraction >= conformityBoundary;
  bool get movable => movedFraction >= resilienceBoundary;

  DebateProfileType get type => switch ((withCrowd, movable)) {
    (true, false) => DebateProfileType.pillar,
    (true, true) => DebateProfileType.flow,
    (false, false) => DebateProfileType.wolf,
    (false, true) => DebateProfileType.seeker,
  };

  factory DebateProfile.fromJson(Map<String, dynamic> json) {
    int asInt(Object? v) => v is int ? v : int.tryParse('$v') ?? 0;
    double asDouble(Object? v, double fallback) =>
        v is num ? v.toDouble() : double.tryParse('$v') ?? fallback;
    return DebateProfile(
      totalVotes: asInt(json['total_votes']),
      majorityVotes: asInt(json['majority_votes']),
      minorityVotes: asInt(json['minority_votes']),
      gateHeld: asInt(json['gate_held']),
      gateMoved: asInt(json['gate_moved']),
      conformityBoundary: asDouble(json['conformity_boundary'], 0.65),
      resilienceBoundary: asDouble(json['resilience_boundary'], 0.15),
      unlockMin: asInt(json['unlock_min']) == 0 ? 6 : asInt(json['unlock_min']),
      fullMin: asInt(json['full_min']) == 0 ? 12 : asInt(json['full_min']),
    );
  }

  static const DebateProfile empty = DebateProfile(
    totalVotes: 0,
    majorityVotes: 0,
    minorityVotes: 0,
    gateHeld: 0,
    gateMoved: 0,
  );
}

/// One month of the PRO trend (`get_profile_trend`): the same counts as the
/// profile itself, bucketed by the vote's month.
class ProfileTrendPoint {
  const ProfileTrendPoint({
    required this.month,
    required this.totalVotes,
    required this.majorityVotes,
    required this.minorityVotes,
    required this.gateHeld,
    required this.gateMoved,
  });

  final DateTime month;
  final int totalVotes;
  final int majorityVotes;
  final int minorityVotes;
  final int gateHeld;
  final int gateMoved;

  int get decidedVotes => majorityVotes + minorityVotes;
  int get conformityPct =>
      decidedVotes == 0 ? 0 : (majorityVotes * 100 / decidedVotes).round();

  factory ProfileTrendPoint.fromJson(Map<String, dynamic> json) {
    int asInt(Object? v) => v is int ? v : int.tryParse('$v') ?? 0;
    return ProfileTrendPoint(
      month: DateTime.tryParse('${json['month']}') ?? DateTime(2000),
      totalVotes: asInt(json['total_votes']),
      majorityVotes: asInt(json['majority_votes']),
      minorityVotes: asInt(json['minority_votes']),
      gateHeld: asInt(json['gate_held']),
      gateMoved: asInt(json['gate_moved']),
    );
  }
}

// NOTE: the per-category breakdown (`get_profile_categories`) has no client
// model on purpose — the catalog's category labels are English-only, so the
// section was pulled from the UI until they're localized. The RPC stays live.

/// One argument that flipped the caller (`get_moved_smaczki`, PRO): the
/// smaczek's text with the question it belonged to.
class MovedSmaczek {
  const MovedSmaczek({
    required this.questionText,
    required this.smaczekText,
    required this.movedAt,
  });

  final String questionText;
  final String smaczekText;
  final DateTime movedAt;

  factory MovedSmaczek.fromJson(Map<String, dynamic> json) => MovedSmaczek(
    questionText: '${json['question_text'] ?? ''}',
    smaczekText: '${json['smaczek_text'] ?? ''}',
    movedAt: DateTime.tryParse('${json['moved_at']}') ?? DateTime(2000),
  );
}
