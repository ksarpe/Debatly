import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/locale/app_locale.dart';
import '../data/models/question.dart';
import '../data/models/rank.dart';
import '../data/models/smaczek.dart';
import '../data/models/user_stats.dart';
import '../data/models/vote_result.dart';

/// On-device cache of the content the app can legitimately show offline.
///
/// Backed by [SharedPreferences] (JSON blobs) rather than a real database: the
/// catalog is at most a few hundred small rows, so the extra build weight of a
/// SQLite/Isar layer isn't justified. Everything is keyed by locale because the
/// text differs per language; the daily is additionally tagged with the date it
/// was scheduled for so a stale day can be detected.
///
/// SECURITY: question text is server-gated (a free user only ever receives the
/// daily + their reveals; premium receives the whole catalog). The cache only
/// ever stores what the server actually returned, so a free user's cache holds
/// nothing premium. The [cachedAsPremium] flag records whether the stored
/// catalog/smaczki contain full premium text; the caller (the caching
/// repository) refuses to serve a premium cache to a now-free identity and calls
/// [clearContent] when premium lapses, so a downgrade can't leak the full pool.
class QuestionCache {
  QuestionCache(this._prefs);

  final SharedPreferences _prefs;

  static const String _prefix = 'qcache_';
  static const String _catalogPrefix = '${_prefix}catalog_'; // + locale
  static const String _dailyPrefix = '${_prefix}daily_'; // + locale
  static const String _smaczkiPrefix = '${_prefix}smaczki_'; // + locale + _id
  static const String _favIdsPrefix = '${_prefix}fav_ids_'; // + locale
  static const String _favQuestionsPrefix = '${_prefix}fav_qs_'; // + locale
  static const String _votePrefix = '${_prefix}vote_'; // + questionId
  static const String _statsKey = '${_prefix}stats';
  static const String _ranksKey = '${_prefix}ranks';
  static const String _cachedAsPremiumKey = '${_prefix}cached_as_premium';
  static const String _lastSyncKey = '${_prefix}last_sync_at';

  // ---- Catalog ---------------------------------------------------------------

  List<Question>? readCatalog(String locale) =>
      _readList(_catalogPrefix + locale, Question.fromJson);

  Future<void> writeCatalog(String locale, List<Question> questions) =>
      _writeList(_catalogPrefix + locale, questions, (q) => q.toJson());

  // ---- Daily -----------------------------------------------------------------

  /// The cached daily for [locale] IFF it was the one scheduled for [date].
  /// Returns null when the cached daily is for a different day, so a new-day
  /// offline launch doesn't masquerade yesterday's question as today's through
  /// the exact-date path.
  Question? readDaily(String locale, String date) {
    final entry = _readMap(_dailyPrefix + locale);
    if (entry == null || entry['date'] != date) return null;
    return _questionFrom(entry['question']);
  }

  /// The most recently cached daily for [locale] regardless of its date, plus
  /// the date it was scheduled for. The graceful fallback when the exact-date
  /// cache misses (e.g. offline on a fresh day) — better a stale daily than a
  /// blank error screen. Null when nothing was ever cached.
  ({Question question, String date})? readLatestDaily(String locale) {
    final entry = _readMap(_dailyPrefix + locale);
    if (entry == null) return null;
    final question = _questionFrom(entry['question']);
    final date = entry['date'];
    if (question == null || date is! String) return null;
    return (question: question, date: date);
  }

  /// The best cached daily stored under a DIFFERENT language than [locale],
  /// preferring the one scheduled for [date]. Null when no other locale has one.
  ///
  /// The last rung of the offline ladder, and the one that keeps the app from
  /// emptying out entirely: switching language offline points every read at a
  /// key prefix nothing was ever written to, so the daily — which for a free
  /// user IS the whole deck — had nothing to fall back on and threw, leaving a
  /// retry screen where the app used to be. The question is the same question
  /// in either language (the daily is global), so serving the copy the user
  /// was reading a minute ago costs them the translation and nothing else.
  Question? readDailyFromOtherLocale(String locale, String date) {
    final others = [
      for (final l in kSupportedLocales)
        if (l.languageCode != locale) l.languageCode,
    ];
    // Today's question in the wrong language beats yesterday's in a third one,
    // so every locale is tried for the exact date before any is asked for its
    // latest.
    for (final other in others) {
      final exact = readDaily(other, date);
      if (exact != null) return exact;
    }
    for (final other in others) {
      final latest = readLatestDaily(other);
      if (latest != null) return latest.question;
    }
    return null;
  }

  Future<void> writeDaily(String locale, String date, Question question) =>
      _writeMap(_dailyPrefix + locale, {
        'date': date,
        'question': question.toJson(),
      });

  // ---- Smaczki ---------------------------------------------------------------

  List<Smaczek>? readSmaczki(String locale, String questionId) =>
      _readList('$_smaczkiPrefix${locale}_$questionId', Smaczek.fromJson);

  Future<void> writeSmaczki(
    String locale,
    String questionId,
    List<Smaczek> smaczki,
  ) => _writeList(
    '$_smaczkiPrefix${locale}_$questionId',
    smaczki,
    (s) => s.toJson(),
  );

  // ---- Favorites -------------------------------------------------------------

  Set<String>? readFavoriteIds(String locale) {
    final raw = _prefs.getStringList(_favIdsPrefix + locale);
    return raw?.toSet();
  }

  Future<void> writeFavoriteIds(String locale, Set<String> ids) =>
      _prefs.setStringList(_favIdsPrefix + locale, ids.toList());

  List<Question>? readFavoriteQuestions(String locale) =>
      _readList(_favQuestionsPrefix + locale, Question.fromJson);

  Future<void> writeFavoriteQuestions(
    String locale,
    List<Question> questions,
  ) => _writeList(_favQuestionsPrefix + locale, questions, (q) => q.toJson());

  // ---- Daily vote state ------------------------------------------------------
  // Not locale-keyed: a vote is on the canonical question id and the community
  // tally aggregates across every language. Stamped with the voter's id so a
  // different identity never reads someone else's cached vote.
  //
  // One entry per question the user votes on or opens — NOT just the daily, as
  // this comment used to claim. A PRO reader who works through the catalog
  // accumulates one `qcache_vote_<uuid>` key per question, and nothing prunes
  // them short of [clearContent]. Worth capping if the count ever matters.

  /// The last-known vote state for [questionId] IFF it was cached for [userId].
  /// Returns null when nothing is cached, the blob is malformed, or it belongs
  /// to a different identity.
  VoteResult? readVoteState(String questionId, String? userId) {
    final map = _readMap(_votePrefix + questionId);
    if (map == null || map['user_id'] != userId) return null;
    try {
      return VoteResult.fromJson(map.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  /// Remembers [result] for [questionId] under [userId] so a later offline open
  /// can confirm the user's own vote.
  Future<void> writeVoteState(
    String questionId,
    String? userId,
    VoteResult result,
  ) {
    final map = <String, Object?>{...result.toJson(), 'user_id': userId};
    return _writeMap(_votePrefix + questionId, map);
  }

  // ---- Stats -----------------------------------------------------------------

  UserStats? readStats() {
    final map = _readMap(_statsKey);
    if (map == null) return null;
    try {
      return UserStats.fromJson(map.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  Future<void> writeStats(UserStats stats) =>
      _writeMap(_statsKey, stats.toJson());

  // ---- Ranks -----------------------------------------------------------------

  List<Rank>? readRanks() => _readList(_ranksKey, Rank.fromJson);

  Future<void> writeRanks(List<Rank> ranks) =>
      _writeList(_ranksKey, ranks, (r) => r.toJson());

  // ---- Meta ------------------------------------------------------------------

  /// Whether the stored catalog/smaczki contain full premium text. Read by the
  /// caching repository to refuse serving a premium cache to a free identity.
  bool get cachedAsPremium => _prefs.getBool(_cachedAsPremiumKey) ?? false;

  Future<void> setCachedAsPremium(bool value) =>
      _prefs.setBool(_cachedAsPremiumKey, value);

  /// When the catalog was last refreshed from the server — drives the
  /// "last synced" line under the offline-download action.
  DateTime? get lastSyncAt {
    final raw = _prefs.getString(_lastSyncKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> markSynced([DateTime? at]) =>
      _prefs.setString(_lastSyncKey, (at ?? DateTime.now()).toIso8601String());

  /// Wipes every cached content entry (catalog, daily, smaczki, favorites,
  /// stats, ranks) and the premium tag. Called when premium lapses so a former
  /// subscriber can't keep reading the full pool offline, and as the reset when
  /// a downgrade is detected on read.
  Future<void> clearContent() async {
    final keys = _prefs
        .getKeys()
        .where((k) => k.startsWith(_prefix))
        .toList(growable: false);
    for (final key in keys) {
      await _prefs.remove(key);
    }
  }

  // ---- JSON helpers ----------------------------------------------------------

  Question? _questionFrom(Object? value) {
    if (value is! Map) return null;
    try {
      return Question.fromJson(value.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  List<T>? _readList<T>(String key, T Function(Map<String, dynamic>) fromJson) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return [
        for (final item in decoded)
          if (item is Map) fromJson(item.cast<String, dynamic>()),
      ];
    } catch (e) {
      debugPrint('QuestionCache: failed to decode list at $key: $e');
      return null;
    }
  }

  Future<void> _writeList<T>(
    String key,
    List<T> items,
    Map<String, dynamic> Function(T) toJson,
  ) async {
    final encoded = jsonEncode([for (final item in items) toJson(item)]);
    await _prefs.setString(key, encoded);
  }

  Map<String, Object?>? _readMap(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return decoded.cast<String, Object?>();
    } catch (e) {
      debugPrint('QuestionCache: failed to decode map at $key: $e');
    }
    return null;
  }

  Future<void> _writeMap(String key, Map<String, Object?> value) =>
      _prefs.setString(key, jsonEncode(value));
}

/// The single [QuestionCache], built over the same [SharedPreferences] handle
/// the rest of the app shares (injected in `main`).
final questionCacheProvider = Provider<QuestionCache>(
  (ref) => QuestionCache(ref.watch(sharedPreferencesProvider)),
);
