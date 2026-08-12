import 'package:debatly/data/models/vote_history_entry.dart';
import 'package:debatly/data/models/vote_result.dart';
import 'package:debatly/data/repositories/question_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VoteHistoryEntry.fromJson', () {
    test('maps the get_vote_history row shape, folding in the vote split', () {
      final entry = VoteHistoryEntry.fromJson({
        'question_id': 'q-1',
        'category': 'Ethics',
        'question_text': 'Czy kara śmierci powinna istnieć?',
        'voted_at': '2026-07-10T18:42:07+00:00',
        'yes_count': 7,
        'no_count': 3,
        'my_choice': 1,
      });

      expect(entry.questionId, 'q-1');
      expect(entry.category, 'Ethics');
      expect(entry.questionText, 'Czy kara śmierci powinna istnieć?');
      expect(entry.votedAt, DateTime.utc(2026, 7, 10, 18, 42, 7));
      expect(entry.votes.yesCount, 7);
      expect(entry.votes.noCount, 3);
      expect(entry.votes.total, 10);
      expect(entry.votes.yesPct, 70);
      expect(entry.votes.myChoice, VoteResult.yes);
    });

    test('treats a null my_choice as "not voted"', () {
      final entry = VoteHistoryEntry.fromJson({
        'question_id': 'q-2',
        'category': 'Society',
        'question_text': 'Pytanie?',
        'voted_at': '2026-07-09T08:00:00+00:00',
        'yes_count': 0,
        'no_count': 0,
        'my_choice': null,
      });

      expect(entry.votes.hasVoted, isFalse);
      expect(entry.votes.total, 0);
    });
  });

  group('MockQuestionRepository.fetchVoteHistory', () {
    test('returns past-dated entries, newest vote first', () async {
      final repo = MockQuestionRepository();
      final history = await repo.fetchVoteHistory();

      expect(history, isNotEmpty);

      // Every entry was voted in the past …
      final now = DateTime.now();
      for (final e in history) {
        expect(e.votedAt.isBefore(now), isTrue);
      }
      // … and they descend by vote time (newest first).
      for (var i = 1; i < history.length; i++) {
        expect(history[i].votedAt.isBefore(history[i - 1].votedAt), isTrue);
      }
    });
  });
}
