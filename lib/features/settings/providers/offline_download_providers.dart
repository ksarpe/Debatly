import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/question_cache.dart';
import '../../questions/providers/question_providers.dart';

/// Phase of the explicit "download for offline" action.
enum OfflineDownloadStatus { idle, running, done, error }

/// Snapshot of the offline-download tile: where we are, how far through, and when
/// the cache was last refreshed.
@immutable
class OfflineDownloadState {
  const OfflineDownloadState({
    required this.status,
    this.done = 0,
    this.total = 0,
    this.lastSyncAt,
  });

  final OfflineDownloadStatus status;
  final int done;
  final int total;
  final DateTime? lastSyncAt;

  bool get isRunning => status == OfflineDownloadStatus.running;

  OfflineDownloadState copyWith({
    OfflineDownloadStatus? status,
    int? done,
    int? total,
    DateTime? lastSyncAt,
  }) => OfflineDownloadState(
    status: status ?? this.status,
    done: done ?? this.done,
    total: total ?? this.total,
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
  );
}

/// Drives the premium "download everything for offline" action.
///
/// It doesn't cache anything itself — it simply walks the repository's read
/// methods, and the [CachingQuestionRepository] underneath persists each result
/// as a side effect. So one pass over the catalog + every question's smaczki (+
/// the daily, favorites and ranks) leaves the whole premium-accessible set on
/// device, with [QuestionCache.markSynced] stamping the "last downloaded" time.
class OfflineDownloadController extends Notifier<OfflineDownloadState> {
  @override
  OfflineDownloadState build() => OfflineDownloadState(
    status: OfflineDownloadStatus.idle,
    lastSyncAt: ref.read(questionCacheProvider).lastSyncAt,
  );

  /// Fetches and caches the entire premium-accessible content set. Smaczki are
  /// per-question RPCs, so this is the slow part — we surface progress as
  /// done/total over the catalog. Safe to call again to refresh.
  ///
  /// Returns the terminal state so the caller can report the outcome without
  /// reading it back through `ref`: this runs for minutes and the user is
  /// expected to leave Settings while it works, by which point the widget that
  /// started it is gone and its `ref` would throw (see [OfflineDownloadRow]).
  Future<OfflineDownloadState> download() async {
    if (state.isRunning) return state;
    final repo = ref.read(questionRepositoryProvider);
    final cache = ref.read(questionCacheProvider);

    state = const OfflineDownloadState(
      status: OfflineDownloadStatus.running,
      done: 0,
      total: 0,
    );

    try {
      // Catalog + daily + favorites + ranks are each cached by the decorator.
      final catalog = await repo.fetchQuestions();
      await repo.fetchDailyQuestion(DateTime.now());
      await repo.fetchRanks();
      await repo.fetchFavoriteIds();
      await repo.fetchFavoriteQuestions();

      final total = catalog.length;
      state = state.copyWith(total: total);

      // Warm every question's smaczki so "go deeper" works offline too.
      var done = 0;
      for (final question in catalog) {
        await repo.fetchSmaczki(question.id);
        done++;
        state = state.copyWith(done: done);
      }

      await cache.markSynced();
      state = OfflineDownloadState(
        status: OfflineDownloadStatus.done,
        done: total,
        total: total,
        lastSyncAt: cache.lastSyncAt,
      );
    } catch (e) {
      debugPrint('OfflineDownloadController.download failed: $e');
      state = OfflineDownloadState(
        status: OfflineDownloadStatus.error,
        lastSyncAt: cache.lastSyncAt,
      );
    }
    return state;
  }
}

final offlineDownloadControllerProvider =
    NotifierProvider<OfflineDownloadController, OfflineDownloadState>(
      OfflineDownloadController.new,
    );
