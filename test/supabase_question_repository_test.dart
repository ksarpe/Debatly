import 'dart:convert';

import 'package:debatly/data/models/smaczek.dart';
import 'package:debatly/data/models/vote_result.dart';
import 'package:debatly/data/repositories/question_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The production data path — `SupabaseQuestionRepository` — talks to Supabase
/// RPCs and maps their rows onto models. The widget/provider suites all swap in
/// a fake repository, so until now NOTHING exercised this class: a typo in an
/// RPC name or a `p_*` param, or a drift in the gating guard, would ship green.
///
/// These tests run the REAL repository against a [SupabaseClient] backed by an
/// [MockClient] HTTP transport. That pins down both halves of the contract:
///   * the OUTBOUND request — the function name and the exact `p_*` params the
///     SQL functions expect (a rename on either side breaks a test, not prod);
///   * the INBOUND mapping — row→model wiring, the unlock/`copyWith` shaping,
///     and the empty-result fall-throughs (`VoteResult.empty` / null).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Captures the last HTTP request the client made, so a test can assert on the
  /// RPC name and the params the repo sent.
  late Uri capturedUrl;
  late String capturedMethod;
  late Map<String, dynamic> capturedBody;

  /// Builds a repository whose Supabase client returns [responseBody] (with
  /// [status]) for every request, recording what was sent. The JSON body is the
  /// shape PostgREST hands back: an array for set-returning functions, a bare
  /// scalar for the scalar ones.
  SupabaseQuestionRepository repo(
    String responseBody, {
    int status = 200,
    String locale = 'pl',
  }) {
    final mock = MockClient((request) async {
      capturedUrl = request.url;
      capturedMethod = request.method;
      // A no-param rpc (e.g. get_favorite_ids) sends a `null`/empty body; keep
      // the captured params an empty map in that case rather than crashing.
      final decoded = request.body.isEmpty ? null : jsonDecode(request.body);
      capturedBody = decoded is Map<String, dynamic> ? decoded : const {};
      return http.Response(
        responseBody,
        status,
        // postgrest reads response.request!.method/headers, so echo the request
        // back or it null-checks and throws before parsing the body.
        request: request,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final client = SupabaseClient(
      'https://test.supabase.co',
      'test-anon-key',
      httpClient: mock,
    );
    return SupabaseQuestionRepository(locale: locale, client: client);
  }

  group('fetchQuestions', () {
    test(
      'calls get_questions with p_locale/p_date and maps the gated shape',
      () async {
        final questions = await repo('''
        [
          {"id": 1, "category": "money", "question_text": "", "teaser": "Czy miliarderzy", "locked": true, "seen": false},
          {"id": 2, "category": "love", "question_text": "Czy warto?", "teaser": null, "locked": false, "seen": true}
        ]
      ''').fetchQuestions();

        expect(capturedUrl.path, endsWith('/rpc/get_questions'));
        expect(capturedBody['p_locale'], 'pl');
        expect(capturedBody['p_date'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));

        expect(questions, hasLength(2));
        // The locked catalog row keeps its teaser but withholds the text.
        expect(questions[0].id, '1');
        expect(questions[0].isLocked, isTrue);
        expect(questions[0].teaser, 'Czy miliarderzy');
        expect(questions[0].questionText, isEmpty);
        // The freed row carries text and reports `seen`.
        expect(questions[1].isLocked, isFalse);
        expect(questions[1].questionText, 'Czy warto?');
        expect(questions[1].seen, isTrue);
      },
    );
  });

  group('fetchDailyQuestion', () {
    test('maps the daily row and passes the device-local date', () async {
      final daily = await repo('''
        [{"id": "d1", "category": "general", "question_text": "Pytanie dnia?"}]
      ''').fetchDailyQuestion(DateTime(2026, 6, 15));

      expect(capturedUrl.path, endsWith('/rpc/get_daily_question'));
      expect(capturedBody['p_locale'], 'pl');
      expect(capturedBody['p_date'], '2026-06-15');
      expect(daily, isNotNull);
      expect(daily!.questionText, 'Pytanie dnia?');
      // get_daily_question omits `locked`; the daily is always readable.
      expect(daily.isLocked, isFalse);
    });

    test('returns null on an empty result set', () async {
      expect(
        await repo('[]').fetchDailyQuestion(DateTime(2026, 6, 15)),
        isNull,
      );
    });

    test(
      'returns null when the row comes back with empty text (gate withheld it)',
      () async {
        // The premium-leak guard: if a premium question ever lands on a daily
        // slot for a free user, the gate strips the text — and the repo must
        // surface "no daily", never a blank card.
        final daily = await repo('''
          [{"id": "d1", "question_text": "   "}]
        ''').fetchDailyQuestion(DateTime(2026, 6, 15));
        expect(daily, isNull);
      },
    );
  });

  group('syncUserState', () {
    test('maps the engagement row', () async {
      final stats = await repo('''
        [{
          "current_streak": 5, "longest_streak": 9, "free_unlock_credits": 1,
          "rank_tier": 2, "rank_name": "Podżegacz", "next_rank_streak": 7,
          "grace_days_left": null
        }]
      ''').syncUserState();

      expect(capturedUrl.path, endsWith('/rpc/sync_user_state'));
      expect(stats, isNotNull);
      expect(stats!.currentStreak, 5);
      expect(stats.rankName, 'Podżegacz');
    });

    test('returns null with no signed-in user (empty set)', () async {
      expect(await repo('[]').syncUserState(), isNull);
    });
  });

  group('getDailyVoteState', () {
    test('maps the split and sends p_question_id', () async {
      final v = await repo('''
        [{"yes_count": 61, "no_count": 39, "my_choice": 1}]
      ''').getDailyVoteState('q1');

      expect(capturedUrl.path, endsWith('/rpc/get_daily_vote_state'));
      expect(capturedBody['p_question_id'], 'q1');
      expect(v.yesCount, 61);
      expect(v.noCount, 39);
      expect(v.myChoice, 1);
    });

    test('falls back to VoteResult.empty on an empty set', () async {
      final v = await repo('[]').getDailyVoteState('q1');
      expect(v.yesCount, 0);
      expect(v.noCount, 0);
      expect(v.hasVoted, isFalse);
    });
  });

  group('castDailyVote', () {
    test('sends the full param set and returns the fresh split', () async {
      final v = await repo('''
        [{"yes_count": 10, "no_count": 5, "my_choice": 2}]
      ''').castDailyVote('q1', VoteResult.no);

      expect(capturedUrl.path, endsWith('/rpc/cast_daily_vote'));
      expect(capturedBody['p_question_id'], 'q1');
      expect(capturedBody['p_choice'], VoteResult.no);
      expect(capturedBody['p_locale'], 'pl');
      expect(capturedBody['p_date'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      expect(v.myChoice, 2);
    });

    test('falls back to VoteResult.empty on an empty set', () async {
      expect((await repo('[]').castDailyVote('q1', 1)).total, 0);
    });
  });

  group('recordSmaczekChallenge', () {
    test('sends the outcome wire values and maps flip_pct', () async {
      final v =
          await repo('''
        [{"yes_count": 61, "no_count": 39, "my_choice": 1, "flip_pct": 11}]
      ''').recordSmaczekChallenge(
            questionId: 'q1',
            position: 2,
            outcome: ChallengeOutcome.moved,
            dwellMs: 3200,
          );

      expect(capturedUrl.path, endsWith('/rpc/record_smaczek_challenge'));
      expect(capturedBody['p_question_id'], 'q1');
      expect(capturedBody['p_position'], 2);
      expect(capturedBody['p_outcome'], 'moved');
      expect(capturedBody['p_dwell_ms'], 3200);
      // The vote itself is untouched by the gate: my_choice comes back as the
      // side cast BEFORE it, and the flip share arrives only past the server's
      // 30-answer threshold.
      expect(v.myChoice, 1);
      expect(v.flipPct, 11);
    });

    test('flip_pct stays null below the server threshold', () async {
      final v =
          await repo('''
        [{"yes_count": 6, "no_count": 4, "my_choice": 1, "flip_pct": null}]
      ''').recordSmaczekChallenge(
            questionId: 'q1',
            position: 1,
            outcome: ChallengeOutcome.held,
          );
      expect(v.flipPct, isNull);
    });
  });

  group('fetchRanks', () {
    test(
      'queries the ranks table ordered by tier and maps the ladder',
      () async {
        final ranks = await repo('''
        [
          {"tier": 0, "min_streak": 0, "name_pl": "Amator", "name_en": "Amateur", "icon": "seed"},
          {"tier": 1, "min_streak": 3, "name_pl": "Prowokator", "name_en": "Provoker", "icon": "flame"}
        ]
      ''').fetchRanks();

        // A plain table read, not an RPC.
        expect(capturedMethod, 'GET');
        expect(capturedUrl.path, endsWith('/ranks'));
        expect(capturedUrl.query, contains('order=tier'));
        expect(ranks, hasLength(2));
        expect(ranks[1].nameFor('pl'), 'Prowokator');
      },
    );
  });

  group('markQuestionSeen', () {
    test('posts the id to mark_question_seen', () async {
      await repo('null').markQuestionSeen('q1');
      expect(capturedUrl.path, endsWith('/rpc/mark_question_seen'));
      expect(capturedBody['p_question_id'], 'q1');
    });

    test('swallows a server error — a failed marker is benign', () async {
      // The deck still works without the view recorded, so a non-2xx must not
      // bubble out of this fire-and-forget call.
      await expectLater(
        repo('{"message": "boom"}', status: 500).markQuestionSeen('q1'),
        completes,
      );
    });
  });

  group('favorites', () {
    test('fetchFavoriteIds maps a scalar id array to a Set', () async {
      final ids = await repo('["fav-1", "fav-2", "fav-1"]').fetchFavoriteIds();
      expect(capturedUrl.path, endsWith('/rpc/get_favorite_ids'));
      expect(ids, {'fav-1', 'fav-2'});
    });

    test('toggleFavorite returns the new boolean state', () async {
      expect(await repo('true').toggleFavorite('q1'), isTrue);
      expect(capturedBody['p_question_id'], 'q1');
      expect(await repo('false').toggleFavorite('q1'), isFalse);
    });

    test(
      'fetchFavoriteQuestions returns rows unlocked (no `locked` key)',
      () async {
        final favs = await repo('''
        [{"id": "q1", "category": "love", "question_text": "Zapisane?"}]
      ''').fetchFavoriteQuestions();
        expect(capturedUrl.path, endsWith('/rpc/get_favorite_questions'));
        // Favorites are readable forever: fromJson defaults isLocked to false.
        expect(favs.single.isLocked, isFalse);
        expect(favs.single.questionText, 'Zapisane?');
      },
    );
  });

  group('fetchVoteHistory', () {
    test('maps voted questions with their split and the vote time', () async {
      final history = await repo('''
        [{
          "question_id": "q1", "category": "money", "question_text": "Było?",
          "voted_at": "2026-07-10T18:42:07+00:00",
          "yes_count": 30, "no_count": 12, "my_choice": 1
        }]
      ''').fetchVoteHistory();

      expect(capturedUrl.path, endsWith('/rpc/get_vote_history'));
      expect(capturedBody['p_locale'], 'pl');
      final entry = history.single;
      expect(entry.questionId, 'q1');
      expect(entry.votedAt, DateTime.utc(2026, 7, 10, 18, 42, 7));
      expect(entry.votes.yesCount, 30);
      expect(entry.votes.myChoice, 1);
    });

    test(
      'returns an empty list for a non-premium caller (zero rows)',
      () async {
        expect(await repo('[]').fetchVoteHistory(), isEmpty);
      },
    );
  });
}
