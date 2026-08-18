import 'package:debatly/data/models/conformity_stats.dart';
import 'package:flutter_test/flutter_test.dart';

/// The conformity-axis math. Release guarantees:
///   * tier bounds are inclusive at the bottom (40% is already Niezależny);
///   * the "votes with the majority to the next tier" projection is exact
///     integer math, never off by one on the bound;
///   * ties and empty data never produce a marker or a progress line.
void main() {
  ConformityStats stats(int majority, int minority, {int? total}) =>
      ConformityStats(
        totalVotes: total ?? (majority + minority),
        majorityVotes: majority,
        minorityVotes: minority,
      );

  group('tier from fraction', () {
    test('bounds fall upward: a fraction on a bound is the higher tier', () {
      expect(ConformityTier.fromFraction(0.0), ConformityTier.loneWolf);
      expect(ConformityTier.fromFraction(0.19), ConformityTier.loneWolf);
      expect(ConformityTier.fromFraction(0.2), ConformityTier.rebel);
      expect(ConformityTier.fromFraction(0.39), ConformityTier.rebel);
      expect(ConformityTier.fromFraction(0.4), ConformityTier.independent);
      expect(ConformityTier.fromFraction(0.6), ConformityTier.inTheCurrent);
      expect(ConformityTier.fromFraction(0.8), ConformityTier.crowdVoice);
      expect(ConformityTier.fromFraction(1.0), ConformityTier.crowdVoice);
    });

    test('next walks up the axis and stops at the top', () {
      expect(ConformityTier.loneWolf.next, ConformityTier.rebel);
      expect(ConformityTier.inTheCurrent.next, ConformityTier.crowdVoice);
      expect(ConformityTier.crowdVoice.next, isNull);
    });
  });

  group('progress to the next tier', () {
    test('the 34% rebel needs exactly 5 majority votes to reach 40%', () {
      // 15/44 decided ≈ 34%: (15+5)/(44+5) = 20/49 ≈ 40.8% ≥ 40%,
      // while (15+4)/(44+4) = 19/48 ≈ 39.6% still falls short.
      final s = stats(15, 29);
      expect(s.majorityPct, 34);
      expect(s.tier, ConformityTier.rebel);
      expect(s.nextTier, ConformityTier.independent);
      expect(s.votesWithMajorityToNextTier, 5);
    });

    test('a single minority vote needs one majority vote to leave 0%', () {
      final s = stats(0, 1);
      expect(s.tier, ConformityTier.loneWolf);
      // (0+1)/(1+1) = 50%… but the target is only 20%; one vote suffices.
      expect(s.votesWithMajorityToNextTier, 1);
    });

    test('the top tier has no next step', () {
      final s = stats(9, 1); // 90%
      expect(s.tier, ConformityTier.crowdVoice);
      expect(s.nextTier, isNull);
      expect(s.votesWithMajorityToNextTier, isNull);
    });
  });

  group('ties and empty data', () {
    test('ties count into total but decide nothing', () {
      final s = stats(2, 3, total: 7); // 2 tie votes
      expect(s.decidedVotes, 5);
      expect(s.majorityPct, 40);
    });

    test('no decided votes → no data, centered marker, no progress', () {
      final s = stats(0, 0, total: 2); // only tie votes
      expect(s.hasData, isFalse);
      expect(s.majorityFraction, 0.5);
      expect(s.votesWithMajorityToNextTier, isNull);
    });
  });

  test('fromJson reads the RPC row shape (and tolerates strings)', () {
    final s = ConformityStats.fromJson({
      'total_votes': 47,
      'majority_votes': '15',
      'minority_votes': 29,
    });
    expect(s.totalVotes, 47);
    expect(s.majorityVotes, 15);
    expect(s.minorityVotes, 29);
  });
}
