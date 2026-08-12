import 'package:debatly/data/models/vote_result.dart';
import 'package:debatly/data/repositories/question_repository.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the daily-vote layer: the [VoteResult] percentage math and the
/// client contract for casting / reading a vote. The streak side effect of a
/// daily vote lives in the SQL RPC and is verified there.
void main() {
  group('VoteResult math', () {
    test('even-ish split rounds and always sums to 100', () {
      const r = VoteResult(yesCount: 60, noCount: 40, myChoice: VoteResult.yes);
      expect(r.total, 100);
      expect(r.yesPct, 60);
      expect(r.noPct, 40);
      expect(r.yesPct + r.noPct, 100);
      expect(r.hasVoted, true);
    });

    test('noPct is derived so the two never drift apart on rounding', () {
      // 1 / 3 ≈ 33.3 → yes 33, no must be 67 (not an independently-rounded 67).
      const r = VoteResult(yesCount: 1, noCount: 2);
      expect(r.yesPct, 33);
      expect(r.noPct, 67);
      expect(r.yesPct + r.noPct, 100);
    });

    test('a unanimous side is 100 / 0', () {
      const r = VoteResult(yesCount: 5, noCount: 0, myChoice: VoteResult.yes);
      expect(r.yesPct, 100);
      expect(r.noPct, 0);
    });

    test('no votes yet is 0 / 0 and not voted', () {
      const r = VoteResult.empty;
      expect(r.total, 0);
      expect(r.yesPct, 0);
      expect(r.noPct, 0);
      expect(r.hasVoted, false);
    });

    test('fromJson maps the RPC row incl. a null my_choice', () {
      final r = VoteResult.fromJson(const {
        'yes_count': 7,
        'no_count': 3,
        'my_choice': null,
      });
      expect(r.yesCount, 7);
      expect(r.noCount, 3);
      expect(r.myChoice, isNull);
      expect(r.hasVoted, false);
    });
  });

  group('vote providers', () {
    ProviderContainer container() {
      final c = ProviderContainer(
        overrides: [
          questionRepositoryProvider.overrideWithValue(
            MockQuestionRepository(),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('dailyVoteStateProvider resolves a question to a result', () async {
      final c = container();
      final result = await c.read(dailyVoteStateProvider('q1').future);
      expect(result, isA<VoteResult>());
      expect(result.hasVoted, false); // mock starts unvoted
    });

    test('castDailyVote returns a split folding in the chosen side', () async {
      final c = container();
      final repo = c.read(questionRepositoryProvider);

      final result = await repo.castDailyVote('q1', VoteResult.no);
      expect(result.myChoice, VoteResult.no);
      expect(result.hasVoted, true);
      expect(result.total, greaterThan(0));
    });
  });
}
