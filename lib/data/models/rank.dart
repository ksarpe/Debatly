/// One tier in the controversy-rank ladder.
///
/// The ladder is data-driven (the `ranks` table), so tiers can be added or
/// renamed without code changes. Names ship in both locales as plain columns
/// (a small fixed list, not a translations split); [nameFor] picks one.
class Rank {
  const Rank({
    required this.tier,
    required this.minStreak,
    required this.namePl,
    required this.nameEn,
    this.icon,
  });

  /// Order in the ladder (0 = the entry rank).
  final int tier;

  /// Current streak at which this rank unlocks.
  final int minStreak;

  final String namePl;
  final String nameEn;

  /// Optional icon key (e.g. 'flame', 'crown') for the client to map to a glyph.
  final String? icon;

  String nameFor(String languageCode) => languageCode == 'pl' ? namePl : nameEn;

  factory Rank.fromJson(Map<String, dynamic> json) {
    int asInt(Object? v) => v is int ? v : int.tryParse('$v') ?? 0;
    return Rank(
      tier: asInt(json['tier']),
      minStreak: asInt(json['min_streak']),
      namePl: json['name_pl'] as String? ?? '',
      nameEn: json['name_en'] as String? ?? '',
      icon: json['icon'] as String?,
    );
  }

  /// Mirrors the `ranks` row shape so a cached rank round-trips back through
  /// [Rank.fromJson] (used by the offline cache).
  Map<String, dynamic> toJson() => {
    'tier': tier,
    'min_streak': minStreak,
    'name_pl': namePl,
    'name_en': nameEn,
    'icon': icon,
  };
}

/// The default ladder, mirroring the `ranks` table seed. Used as the offline /
/// mock source so the rank sheet renders without a backend.
///
/// Keep in lockstep with the latest `ranks` re-seed migration
/// (20260812130000_reseed_rank_ladder_v3.sql): a dense, front-loaded 16-tier
/// ladder — first promotion after the very first vote, 4 promotions in week
/// one, longest wait 30 days.
const List<Rank> kDefaultRanks = [
  Rank(
    tier: 0,
    minStreak: 0,
    namePl: 'Niewiniątko',
    nameEn: 'The Innocent',
    icon: 'seedling',
  ),
  Rank(
    tier: 1,
    minStreak: 1,
    namePl: 'Pierwsza iskra',
    nameEn: 'First Spark',
    icon: 'spark',
  ),
  Rank(
    tier: 2,
    minStreak: 3,
    namePl: 'Zadziora',
    nameEn: 'Firebrand',
    icon: 'flame',
  ),
  Rank(
    tier: 3,
    minStreak: 5,
    namePl: 'Prowokator',
    nameEn: 'Provocateur',
    icon: 'megaphone',
  ),
  Rank(
    tier: 4,
    minStreak: 7,
    namePl: 'Adwokat diabła',
    nameEn: "Devil's Advocate",
    icon: 'mask',
  ),
  Rank(
    tier: 5,
    minStreak: 10,
    namePl: 'Mąciciel',
    nameEn: 'Troublemaker',
    icon: 'storm',
  ),
  Rank(
    tier: 6,
    minStreak: 14,
    namePl: 'Burzyciel spokoju',
    nameEn: 'Peacebreaker',
    icon: 'bolt',
  ),
  Rank(
    tier: 7,
    minStreak: 18,
    namePl: 'Podpalacz debaty',
    nameEn: 'Debate Arsonist',
    icon: 'whatshot',
  ),
  Rank(
    tier: 8,
    minStreak: 23,
    namePl: 'Wichrzyciel',
    nameEn: 'Agitator',
    icon: 'wind',
  ),
  Rank(
    tier: 9,
    minStreak: 30,
    namePl: 'Nieugięty',
    nameEn: 'The Unshaken',
    icon: 'shield',
  ),
  Rank(
    tier: 10,
    minStreak: 40,
    namePl: 'Mistrz prowokacji',
    nameEn: 'Master Provocateur',
    icon: 'medal',
  ),
  Rank(
    tier: 11,
    minStreak: 50,
    namePl: 'Wirtuoz skandalu',
    nameEn: 'Scandal Virtuoso',
    icon: 'star',
  ),
  Rank(
    tier: 12,
    minStreak: 65,
    namePl: 'Ikona kontrowersji',
    nameEn: 'Controversy Icon',
    icon: 'diamond',
  ),
  Rank(
    tier: 13,
    minStreak: 80,
    namePl: 'Legenda kontrowersji',
    nameEn: 'Controversy Legend',
    icon: 'crown',
  ),
  Rank(
    tier: 14,
    minStreak: 100,
    namePl: 'Mit kontrowersji',
    nameEn: 'Controversy Myth',
    icon: 'trophy',
  ),
  Rank(
    tier: 15,
    minStreak: 130,
    namePl: 'Nieśmiertelny',
    nameEn: 'The Immortal',
    icon: 'rocket',
  ),
];
