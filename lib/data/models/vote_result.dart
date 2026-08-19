/// The community split for a single question's binary (TAK / NIE) vote, plus the
/// caller's own choice.
///
/// Returned by the `cast_daily_vote` and `get_daily_vote_state` RPCs. The counts
/// are aggregated server-side (a user never reads other users' vote rows). When
/// [myChoice] is null the user hasn't voted yet, so the UI shows the vote
/// buttons; otherwise it shows the result bars.
class VoteResult {
  const VoteResult({
    required this.yesCount,
    required this.noCount,
    this.myChoice,
    this.flipPct,
    this.fromCache = false,
  });

  /// 1 = TAK, 2 = NIE — matches the `choice` column / RPC contract.
  static const int yes = 1;
  static const int no = 2;

  final int yesCount;
  final int noCount;

  /// The caller's vote (1 = TAK, 2 = NIE), or null if they haven't voted.
  final int? myChoice;

  /// Share (0..100) of gate-takers this question's counter-argument flipped:
  /// `moved / (held + moved)`. The SERVER withholds it (null) until the
  /// question has at least 30 answered challenges, so a non-null value is
  /// always safe to show — the client never re-checks the threshold.
  final int? flipPct;

  /// True when this result was served from the on-device cache after a failed
  /// fetch (offline) rather than freshly from the server. It's a serve-time flag
  /// (never persisted): the daily panel reads it to withhold the possibly-stale
  /// community split and only confirm the user's own vote. See
  /// [CachingQuestionRepository.getDailyVoteState].
  final bool fromCache;

  int get total => yesCount + noCount;

  bool get hasVoted => myChoice != null;

  /// Share of TAK votes in 0..1 (0 when there are no votes yet).
  double get yesFraction => total == 0 ? 0 : yesCount / total;

  /// Share of NIE votes in 0..1 (0 when there are no votes yet).
  double get noFraction => total == 0 ? 0 : noCount / total;

  /// TAK percentage as a rounded whole number (0..100).
  int get yesPct => (yesFraction * 100).round();

  /// NIE percentage; derived from [yesPct] so the two always sum to 100.
  int get noPct => total == 0 ? 0 : 100 - yesPct;

  factory VoteResult.fromJson(Map<String, dynamic> json) {
    int asInt(Object? v) => v is int ? v : int.tryParse('$v') ?? 0;
    return VoteResult(
      yesCount: asInt(json['yes_count']),
      noCount: asInt(json['no_count']),
      myChoice: json['my_choice'] == null ? null : asInt(json['my_choice']),
      flipPct: json['flip_pct'] == null ? null : asInt(json['flip_pct']),
    );
  }

  /// The counts + the caller's own choice, ready to persist in the on-device
  /// cache. [fromCache] is deliberately NOT serialised — it's a serve-time tag.
  /// [flipPct] isn't either: offline the panel already withholds the (possibly
  /// stale) community split, and the flip line follows the same rule.
  Map<String, dynamic> toJson() => {
    'yes_count': yesCount,
    'no_count': noCount,
    'my_choice': myChoice,
  };

  /// A copy tagged as served from the offline cache (see [fromCache]).
  VoteResult asCached() => VoteResult(
    yesCount: yesCount,
    noCount: noCount,
    myChoice: myChoice,
    fromCache: true,
  );

  static const VoteResult empty = VoteResult(yesCount: 0, noCount: 0);
}
