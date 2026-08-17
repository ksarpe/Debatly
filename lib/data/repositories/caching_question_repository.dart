import '../../core/network/network_error.dart';
import '../../services/question_cache.dart';
import '../models/question.dart';
import '../models/rank.dart';
import '../models/smaczek.dart';
import '../models/user_stats.dart';
import '../models/vote_history_entry.dart';
import '../models/vote_result.dart';
import 'question_repository.dart';

/// Wraps another [QuestionRepository] with an on-device cache so the catalog,
/// daily, smaczki, favorites, stats and ranks stay readable when the network
/// drops — and so premium users get their whole (legitimately-accessible)
/// catalog offline.
///
/// Strategy: every READ is "network-first, cache-fallback". On a successful
/// fetch we refresh the cache and return the fresh data; on a TRANSPORT error
/// (see [isOfflineError]) we serve the cache when present, otherwise rethrow so
/// the existing "you're offline, retry" screen still shows. A real server error
/// (4xx/5xx) is never masked by cache — it rethrows.
///
/// WRITES (vote, favorite toggle, mark-seen) are pass-through: they
/// inherently need the server, so offline they throw and the UI surfaces a
/// "you're offline" message rather than queueing.
///
/// SECURITY: question text is server-gated, so the cache only ever holds what
/// the server returned for THIS identity. The catalog is tagged with
/// [QuestionCache.cachedAsPremium]; if premium lapses we refuse to serve that
/// premium-text cache and wipe it (defence-in-depth on top of the explicit clear
/// the session does on a lapse), so a downgrade can never read the full pool.
class CachingQuestionRepository implements QuestionRepository {
  CachingQuestionRepository({
    required this.inner,
    required this.cache,
    required this.locale,
    required this.isPremium,
    this.userId,
  });

  final QuestionRepository inner;
  final QuestionCache cache;
  final String locale;
  final bool isPremium;

  /// The signed-in identity, used to scope the cached daily-vote state so one
  /// account never reads another's vote. Null for a guest (who can't vote).
  final String? userId;

  @override
  Future<List<Question>> fetchQuestions() async {
    try {
      final fresh = await inner.fetchQuestions();
      await cache.writeCatalog(locale, fresh);
      await cache.setCachedAsPremium(isPremium);
      await cache.markSynced();
      return fresh;
    } catch (e) {
      if (!isOfflineError(e)) rethrow;
      final cached = await _readPremiumSafe(() => cache.readCatalog(locale));
      if (cached != null) return cached;
      rethrow;
    }
  }

  @override
  Future<Question?> fetchDailyQuestion(DateTime date) async {
    final dateKey = dateOnlyKey(date);
    try {
      final fresh = await inner.fetchDailyQuestion(date);
      if (fresh != null) await cache.writeDaily(locale, dateKey, fresh);
      return fresh;
    } catch (e) {
      if (!isOfflineError(e)) rethrow;
      // Prefer today's cached daily; fall back to the last one we ever cached so
      // a fresh-day offline launch shows a (stale) daily instead of an error.
      final exact = cache.readDaily(locale, dateKey);
      if (exact != null) return exact;
      final latest = cache.readLatestDaily(locale);
      if (latest != null) return latest.question;
      rethrow;
    }
  }

  @override
  Future<List<Smaczek>> fetchSmaczki(String questionId) async {
    try {
      final fresh = await inner.fetchSmaczki(questionId);
      await cache.writeSmaczki(locale, questionId, fresh);
      return fresh;
    } catch (e) {
      if (!isOfflineError(e)) rethrow;
      final cached = await _readPremiumSafe(
        () => cache.readSmaczki(locale, questionId),
      );
      if (cached != null) return cached;
      rethrow;
    }
  }

  @override
  Future<UserStats?> syncUserState() async {
    try {
      final fresh = await inner.syncUserState();
      if (fresh != null) await cache.writeStats(fresh);
      return fresh;
    } catch (e) {
      if (!isOfflineError(e)) rethrow;
      // Stats are not gated content (just the user's own streak/rank), so no
      // premium guard — serve the last sync so the chip doesn't reset offline.
      return cache.readStats();
    }
  }

  @override
  Future<List<Rank>> fetchRanks() async {
    try {
      final fresh = await inner.fetchRanks();
      await cache.writeRanks(fresh);
      return fresh;
    } catch (e) {
      if (!isOfflineError(e)) rethrow;
      // Ranks are public + small, with a compiled-in default — never error here.
      return cache.readRanks() ?? kDefaultRanks;
    }
  }

  @override
  Future<Set<String>> fetchFavoriteIds() async {
    try {
      final fresh = await inner.fetchFavoriteIds();
      await cache.writeFavoriteIds(locale, fresh);
      return fresh;
    } catch (e) {
      if (!isOfflineError(e)) rethrow;
      return cache.readFavoriteIds(locale) ?? const <String>{};
    }
  }

  @override
  Future<List<Question>> fetchFavoriteQuestions() async {
    try {
      final fresh = await inner.fetchFavoriteQuestions();
      await cache.writeFavoriteQuestions(locale, fresh);
      return fresh;
    } catch (e) {
      if (!isOfflineError(e)) rethrow;
      final cached = cache.readFavoriteQuestions(locale);
      if (cached != null) return cached;
      rethrow;
    }
  }

  // ---- Pass-through writes / live reads --------------------------------------
  // These need the server every time (entitlement, server clock, fresh tallies),
  // so they go straight to the inner repo. Offline they throw and the caller
  // surfaces a "you're offline" message — we deliberately do NOT queue.

  // The history's vote tallies are live (they keep changing) and premium-gated,
  // so it goes straight to the server every open rather than serving a stale
  // cache; offline it throws and the sheet shows its retry state.
  @override
  Future<List<VoteHistoryEntry>> fetchVoteHistory() => inner.fetchVoteHistory();

  // The "Nowe" badge is decoration, never worth an offline error screen: with
  // no network the badge simply doesn't show, so a transport failure degrades
  // to an empty set instead of being cached or rethrown.
  @override
  Future<Set<String>> fetchRecentQuestionIds({required DateTime since}) async {
    try {
      return await inner.fetchRecentQuestionIds(since: since);
    } catch (e) {
      if (!isOfflineError(e)) rethrow;
      return const <String>{};
    }
  }

  // ---- Daily vote state (cache-fallback for the user's OWN vote) -------------

  /// Network-first with a cache fallback, but only for the user's own vote —
  /// NOT the live community split. On a successful fetch we remember a cast vote
  /// (identity-scoped) and return it fresh. Offline we serve that snapshot
  /// tagged [VoteResult.fromCache] so the panel confirms "you voted X" without
  /// showing a possibly-stale percentage; with nothing cached we rethrow so the
  /// buttons stay (a guest / not-yet-voted user simply can't vote offline).
  @override
  Future<VoteResult> getDailyVoteState(String questionId) async {
    try {
      final fresh = await inner.getDailyVoteState(questionId);
      if (fresh.hasVoted) {
        await cache.writeVoteState(questionId, userId, fresh);
      }
      return fresh;
    } catch (e) {
      if (!isOfflineError(e)) rethrow;
      final cached = cache.readVoteState(questionId, userId);
      if (cached != null && cached.hasVoted) return cached.asCached();
      rethrow;
    }
  }

  /// A write — it needs the server, so offline it throws and the caller surfaces
  /// the "no connection" toast (we deliberately do NOT queue). On success we
  /// write through so a vote cast right before losing signal is still confirmed
  /// on the next open.
  @override
  Future<VoteResult> castDailyVote(String questionId, int choice) async {
    final result = await inner.castDailyVote(questionId, choice);
    if (result.hasVoted) {
      await cache.writeVoteState(questionId, userId, result);
    }
    return result;
  }

  @override
  Future<void> markQuestionSeen(String questionId) =>
      inner.markQuestionSeen(questionId);

  @override
  Future<bool> toggleFavorite(String questionId) =>
      inner.toggleFavorite(questionId);

  /// A write — offline it throws and the sheet shows "no connection"; nothing
  /// to cache either way (the inbox lives server-side only).
  @override
  Future<void> submitQuestionSuggestion(String text) =>
      inner.submitQuestionSuggestion(text);

  // ---- Helpers ---------------------------------------------------------------

  /// Reads from [read], but treats a premium-tagged cache as empty when the
  /// current identity is NOT premium — and wipes it — so a lapsed subscriber
  /// can't keep reading the full pool offline. Returns null when there's nothing
  /// safe to serve.
  Future<T?> _readPremiumSafe<T>(T? Function() read) async {
    if (cache.cachedAsPremium && !isPremium) {
      await cache.clearContent();
      return null;
    }
    return read();
  }
}
