import 'package:debatly/data/models/debate_profile.dart';
import 'package:flutter_test/flutter_test.dart';

/// The 2×2 profile's arithmetic — the release guarantees:
///   * unlock needs BOTH counters (votes AND qualifying gate answers) at the
///     threshold; progress follows whichever is further behind;
///   * 6–11 on the limiting counter = provisional, 12+ = full;
///   * the boundaries come from the server payload, not client constants —
///     and the conformity boundary is NOT 50%;
///   * type mapping: crowd × resilience → pillar / flow / wolf / seeker.
void main() {
  DebateProfile profile({
    int votes = 20,
    int maj = 10,
    int min = 8,
    int held = 10,
    int moved = 2,
    double cb = 0.65,
    double rb = 0.15,
  }) => DebateProfile(
    totalVotes: votes,
    majorityVotes: maj,
    minorityVotes: min,
    gateHeld: held,
    gateMoved: moved,
    conformityBoundary: cb,
    resilienceBoundary: rb,
  );

  group('unlock — both counters must clear the threshold', () {
    test('20 votes but only 3 gate answers stays locked', () {
      final p = profile(votes: 20, held: 2, moved: 1);
      expect(p.stage, DebateProfileStage.locked);
      // The limiting counter is the gates (3), so 3 answers are missing.
      expect(p.limitingCounter, 3);
      expect(p.answersToUnlock, 3);
    });

    test('6 gate answers but only 4 votes stays locked', () {
      final p = profile(votes: 4, maj: 2, min: 2, held: 4, moved: 2);
      expect(p.stage, DebateProfileStage.locked);
      expect(p.answersToUnlock, 2);
    });

    test('6 and 6 unlocks as provisional', () {
      final p = profile(votes: 6, maj: 3, min: 3, held: 5, moved: 1);
      expect(p.stage, DebateProfileStage.provisional);
      expect(p.answersToUnlock, 0);
    });

    test('11 on the limiting counter is still provisional, 12 is full', () {
      expect(
        profile(votes: 30, held: 9, moved: 2).stage,
        DebateProfileStage.provisional,
      );
      expect(
        profile(votes: 30, held: 9, moved: 3).stage,
        DebateProfileStage.full,
      );
    });

    test(
      'all-ties corner: enough counters but zero decided votes → locked',
      () {
        final p = profile(votes: 12, maj: 0, min: 0, held: 8, moved: 4);
        expect(p.stage, DebateProfileStage.locked);
      },
    );
  });

  group('boundaries — server-fed, 65/15 defaults', () {
    test('64% with the majority is AGAINST the crowd at the 65% boundary', () {
      final p = profile(maj: 16, min: 9); // 16/25 = 64%
      expect(p.withCrowd, isFalse);
    });

    test('65% exactly is WITH the crowd (boundary belongs to the top)', () {
      final p = profile(maj: 13, min: 7); // 13/20 = 65%
      expect(p.withCrowd, isTrue);
    });

    test('a re-tuned server boundary moves the cut without a release', () {
      // Same 64% user, boundary re-derived down to 0.60 → now with the crowd.
      final p = profile(maj: 16, min: 9, cb: 0.60);
      expect(p.withCrowd, isTrue);
    });

    test('moved share at 15% is movable; below is resistant', () {
      expect(profile(held: 17, moved: 3).movable, isTrue); // 15%
      expect(profile(held: 18, moved: 2).movable, isFalse); // 10%
    });
  });

  group('type mapping', () {
    test('with the crowd + resistant = pillar', () {
      final p = profile(maj: 14, min: 6, held: 11, moved: 1); // 70%, 8%
      expect(p.type, DebateProfileType.pillar);
    });

    test('with the crowd + movable = flow', () {
      final p = profile(maj: 14, min: 6, held: 9, moved: 3); // 70%, 25%
      expect(p.type, DebateProfileType.flow);
    });

    test('against the crowd + resistant = wolf', () {
      final p = profile(maj: 6, min: 14, held: 11, moved: 1); // 30%, 8%
      expect(p.type, DebateProfileType.wolf);
    });

    test('against the crowd + movable = seeker', () {
      final p = profile(maj: 6, min: 14, held: 9, moved: 3); // 30%, 25%
      expect(p.type, DebateProfileType.seeker);
    });
  });

  test('fromJson maps the RPC row incl. numeric boundaries', () {
    final p = DebateProfile.fromJson(const {
      'total_votes': 47,
      'majority_votes': 15,
      'minority_votes': 29,
      'gate_held': 9,
      'gate_moved': 3,
      'conformity_boundary': 0.7,
      'resilience_boundary': 0.2,
      'unlock_min': 5,
      'full_min': 10,
    });
    expect(p.totalVotes, 47);
    expect(p.conformityBoundary, 0.7);
    expect(p.resilienceBoundary, 0.2);
    expect(p.unlockMin, 5);
    expect(p.fullMin, 10);
    expect(p.stage, DebateProfileStage.full);
    expect(p.type, DebateProfileType.seeker);
  });
}
