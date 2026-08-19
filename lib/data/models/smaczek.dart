import 'vote_result.dart';

/// Which answer a smaczek argues against.
///
/// The server serves the smaczki ordered by how relevant they are to the
/// caller's OWN vote — the one attacking their actual choice comes first (see
/// the `get_question_smaczki` RPC) — so the client rarely has to re-decide
/// anything from this. It carries the tag anyway because the post-vote
/// challenge needs to know whether the argument it just dropped on the user is
/// actually aimed at them ([Smaczek.attacks]).
enum SmaczekSide {
  /// Aimed at someone who voted TAK.
  attacksYes('attacks_yes'),

  /// Aimed at someone who voted NIE.
  attacksNo('attacks_no'),

  /// Personal / practical — works against either side.
  neutral('neutral');

  const SmaczekSide(this.wire);

  /// The value stored in `question_smaczki.side`.
  final String wire;

  /// Parses a server value. Anything unknown — including the NULL that every
  /// smaczek carries until it is tagged in the admin panel — reads as
  /// [neutral], which is how the server orders it too.
  static SmaczekSide fromWire(Object? value) {
    for (final side in SmaczekSide.values) {
      if (side.wire == value) return side;
    }
    return SmaczekSide.neutral;
  }
}

/// A single "smaczek" — an argument against the answer the reader just gave.
///
/// Whether a smaczek is unlocked is decided on the SERVER by the
/// `get_question_smaczki` RPC: a free user gets the most relevant one readable
/// plus the rest flagged [isLocked], premium users get them all. Locked smaczki
/// arrive with a null [text] — the real wording never leaves the database — so
/// the UI only ever blurs a client-side placeholder, never hidden content. The
/// client is intentionally "dumb": it renders purely from [isLocked], it does
/// not re-decide entitlement.
class Smaczek {
  final int position;
  final bool isLocked;
  final String? text;

  /// Which answer this argument attacks. Untagged rows arrive as
  /// [SmaczekSide.neutral].
  final SmaczekSide side;

  const Smaczek({
    required this.position,
    required this.isLocked,
    this.text,
    this.side = SmaczekSide.neutral,
  });

  /// Builds a [Smaczek] from a `get_question_smaczki` row. Locked rows come
  /// back without text, so [text] stays null.
  factory Smaczek.fromJson(Map<String, dynamic> json) => Smaczek(
    position: (json['position'] as num?)?.toInt() ?? 0,
    isLocked: json['is_locked'] as bool? ?? true,
    text: json['text'] as String?,
    side: SmaczekSide.fromWire(json['side']),
  );

  /// Whether this argument is aimed at [choice] ([VoteResult.yes] /
  /// [VoteResult.no]). A neutral smaczek counts as aimed at everyone — it is
  /// written to work against either side.
  bool attacks(int choice) => switch (side) {
    SmaczekSide.neutral => true,
    SmaczekSide.attacksYes => choice == VoteResult.yes,
    SmaczekSide.attacksNo => choice == VoteResult.no,
  };

  /// Mirrors the `get_question_smaczki` row shape so a cached smaczek round-trips
  /// back through [Smaczek.fromJson] (used by the offline cache). A locked
  /// smaczek serialises its null [text] — no hidden content is ever stored.
  Map<String, dynamic> toJson() => {
    'position': position,
    'is_locked': isLocked,
    'text': text,
    'side': side.wire,
  };
}
