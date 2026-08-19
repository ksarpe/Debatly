import 'dart:async';

import 'package:debatly/core/locale/app_locale.dart';
import 'package:debatly/data/models/conformity_stats.dart';
import 'package:debatly/data/models/question.dart';
import 'package:debatly/data/models/rank.dart';
import 'package:debatly/data/models/smaczek.dart';
import 'package:debatly/data/models/user_stats.dart';
import 'package:debatly/data/models/vote_history_entry.dart';
import 'package:debatly/data/models/vote_result.dart';
import 'package:debatly/data/repositories/question_repository.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:debatly/features/settings/providers/offline_download_providers.dart';
import 'package:debatly/features/settings/widgets/offline_download_row.dart';
import 'package:debatly/services/question_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/localized_test_app.dart';

/// The download controller must walk the whole catalog (one smaczki fetch per
/// question), stamp the sync time, and end in `done` — or surface `error` when a
/// fetch throws — without caching anything itself.
///
/// It must also hand its terminal state back to the caller: the walk takes
/// minutes and deliberately outlives the row that started it, so the caller can
/// no longer read the result through its own (disposed) `ref`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeRepo repo;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    repo = _FakeRepo();
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        questionRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Question q(String id) =>
      Question(id: id, category: id, questionText: 'Q $id?');

  test(
    'downloads every question, fetching smaczki per question, then done',
    () async {
      repo.catalog = [q('a'), q('b'), q('c')];
      final container = makeContainer();

      final result = await container
          .read(offlineDownloadControllerProvider.notifier)
          .download();

      // What download() returns is what a caller reports from, so it has to
      // carry the same outcome as the controller's own state.
      expect(result.status, OfflineDownloadStatus.done);
      expect(result.done, 3);

      final state = container.read(offlineDownloadControllerProvider);
      expect(state.status, OfflineDownloadStatus.done);
      expect(state.done, 3);
      expect(state.total, 3);
      expect(state.lastSyncAt, isNotNull);
      // One smaczki fetch per catalog question.
      expect(repo.smaczkiCallIds, ['a', 'b', 'c']);
      // The cache's sync stamp was written.
      expect(container.read(questionCacheProvider).lastSyncAt, isNotNull);
    },
  );

  test('surfaces an error status when a fetch fails', () async {
    repo.failQuestions = true;
    final container = makeContainer();

    final result = await container
        .read(offlineDownloadControllerProvider.notifier)
        .download();

    expect(result.status, OfflineDownloadStatus.error);
    expect(
      container.read(offlineDownloadControllerProvider).status,
      OfflineDownloadStatus.error,
    );
  });

  testWidgets('a download that outlives its row still finishes and reports', (
    tester,
  ) async {
    // The production crash: the walk runs for minutes, so the user starts it and
    // leaves Settings while it works. The row is disposed by the time it lands,
    // and reaching back through its `ref` for the outcome threw a fatal
    // StateError (Riverpod's ref is tied to the element's BuildContext).
    repo.catalog = [q('a')];
    final gate = Completer<void>();
    repo.gate = gate;

    final container = makeContainer();
    final showRow = ValueNotifier(true);
    addTearDown(showRow.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LocalizedTestApp(
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: showRow,
              builder: (_, show, _) => show
                  ? const OfflineDownloadRow(localeCode: 'pl')
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(OfflineDownloadRow));
    await tester.pump();

    // Leave Settings mid-download.
    showRow.value = false;
    await tester.pump();
    expect(find.byType(OfflineDownloadRow), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      container.read(offlineDownloadControllerProvider).status,
      OfflineDownloadStatus.done,
      reason: 'the download must run to completion after the row is gone',
    );
  });
}

class _FakeRepo implements QuestionRepository {
  List<Question> catalog = const [];
  bool failQuestions = false;
  final List<String> smaczkiCallIds = [];

  /// When set, the catalog fetch parks here until the test completes it —
  /// standing in for the minutes-long real walk.
  Completer<void>? gate;

  @override
  Future<List<Question>> fetchQuestions() async {
    if (failQuestions) throw Exception('boom');
    final pending = gate;
    if (pending != null) await pending.future;
    return catalog;
  }

  @override
  Future<List<Smaczek>> fetchSmaczki(String questionId) async {
    smaczkiCallIds.add(questionId);
    return const [];
  }

  @override
  Future<Question?> fetchDailyQuestion(DateTime date) async => null;

  @override
  Future<String?> peekNextQuestion({
    List<String> excludeIds = const [],
  }) async => null;

  @override
  Future<List<Rank>> fetchRanks() async => const [];

  @override
  Future<Set<String>> fetchFavoriteIds() async => const {};

  @override
  Future<List<Question>> fetchFavoriteQuestions() async => const [];

  @override
  Future<UserStats?> syncUserState() async => null;

  @override
  Future<VoteResult> getDailyVoteState(String questionId) async =>
      VoteResult.empty;

  @override
  Future<VoteResult> castDailyVote(String questionId, int choice) async =>
      VoteResult.empty;

  @override
  Future<VoteResult> recordSmaczekChallenge({
    required String questionId,
    required int position,
    required ChallengeOutcome outcome,
    int? dwellMs,
  }) async => VoteResult.empty;

  @override
  Future<void> markQuestionSeen(String questionId) async {}

  @override
  Future<bool> toggleFavorite(String questionId) async => false;

  @override
  Future<List<VoteHistoryEntry>> fetchVoteHistory() async => const [];

  @override
  Future<ConformityStats> fetchConformityStats() async => ConformityStats.empty;

  @override
  Future<Set<String>> fetchRecentQuestionIds({required DateTime since}) async =>
      const {};

  @override
  Future<void> submitQuestionSuggestion(String text) async {}

  @override
  Future<void> submitSmaczekSuggestion({
    required String questionId,
    required String text,
  }) async {}
}
