import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/monitoring/monitoring.dart';
import '../../services/supabase_service.dart';
import '../mock/mock_questions.dart';
import '../models/question.dart';
import '../models/rank.dart';
import '../models/smaczek.dart';
import '../models/user_stats.dart';
import '../models/vote_history_entry.dart';
import '../models/vote_result.dart';

/// Abstraction over the source of questions.
///
/// The app talks to this interface only, so the underlying source can move from
/// the local mock list to Supabase without touching the UI or providers.
abstract class QuestionRepository {
  Future<List<Question>> fetchQuestions();

  Future<Question?> fetchDailyQuestion(DateTime date);

  /// The discussion prompts ("smaczki") for a single question.
  ///
  /// The source applies the premium gate: a free user gets the first smaczek
  /// readable plus the rest as locked placeholders (no text), premium users get
  /// them all. See [Smaczek].
  Future<List<Smaczek>> fetchSmaczki(String questionId);

  /// Peeks the next UNVOTED question's teaser WITHOUT revealing it — the paywall
  /// bait. Returns its id (echo back to [revealAdQuestion] so the ad reveals the
  /// teased question) and the first two words of its text. No text, not marked
  /// seen. Null when nothing eligible is left.
  ///
  /// [excludeIds] are this session's already-revealed ids: the pool is "not
  /// voted", so a shown-but-unvoted question is still eligible — passing the
  /// session's ids keeps the teaser off a question already on screen this session.
  Future<({String id, String teaser})?> peekNextQuestion({
    List<String> excludeIds = const [],
  });

  /// Reveals the next UNSEEN question after a rewarded ad.
  ///
  /// Pass [questionId] (from [peekNextQuestion]) to reveal exactly the teased
  /// question; the server validates it is still eligible (active, not today's
  /// daily, NOT YET VOTED) and otherwise picks a random unvoted one so the watched
  /// ad is never wasted. Records the reveal in `question_seen` (the "shown" signal
  /// the smaczki + vote gates read) and returns it WITH text. The reveal is
  /// ephemeral: the gate no longer grants this text later, so the caller must keep
  /// the returned question in session memory. [excludeIds] skip this session's
  /// already-revealed ids on the random pick. Returns null when the user has voted
  /// on everything eligible. Available to guests too.
  Future<Question?> revealAdQuestion({
    String? questionId,
    List<String> excludeIds = const [],
  });

  /// Syncs and returns the user's engagement state (streak, free-unlock
  /// credits, rank).
  ///
  /// Calls `sync_user_state`, which ALSO tops up the daily free-unlock credit
  /// (once per server-UTC day, capped at 1, never for premium) as a side
  /// effect. Returns null when there is no signed-in user / no backend.
  Future<UserStats?> syncUserState();

  /// The current community split + the caller's own vote for [questionId].
  ///
  /// Returns [VoteResult] with TAK/NIE counts and `myChoice` (null when the user
  /// hasn't voted), so the UI can show the buttons or the result bars.
  Future<VoteResult> getDailyVoteState(String questionId);

  /// Casts the user's binary vote ([choice] = 1 TAK / 2 NIE) on [questionId].
  ///
  /// ANY vote advances the user's streak server-side (at most once per UTC
  /// day) — "vote on anything today" is the streak rule since the
  /// personal-daily migration. Returns the updated split.
  Future<VoteResult> castDailyVote(String questionId, int choice);

  /// Reveals the next UNSEEN question paid with the daily free credit instead of
  /// an ad (real accounts only, once per day).
  ///
  /// Same server-side pick (unvoted pool) + seen record as [revealAdQuestion], but
  /// charges one credit — only on a successful reveal. [excludeIds] skip this
  /// session's already-revealed ids. Returns the revealed question, or null when
  /// nothing eligible is left (no charge). Throws when there is no credit, the
  /// user is premium, or the user is a guest.
  Future<Question?> revealFreeQuestion({List<String> excludeIds = const []});

  /// The full rank ladder (ordered by tier), for the rank sheet.
  Future<List<Rank>> fetchRanks();

  /// Records that the caller has viewed [questionId] (premium catalog browsing).
  ///
  /// Best-effort and idempotent: it appends to the per-user seen-memory so the
  /// next launch surfaces UNSEEN questions first. A free user never reaches the
  /// arbitrary catalog (their daily + reveals are recorded elsewhere), so the
  /// caller only invokes this for premium. Never throws to the caller — a failed
  /// marker just means the question may reappear as "new" later, which is benign.
  Future<void> markQuestionSeen(String questionId);

  /// The ids of the questions the caller has favorited.
  ///
  /// Drives the star's filled/outline state on the question screen. Small per
  /// user, so the client loads it once and updates it optimistically on toggle.
  /// Empty for a user who has never favorited anything (incl. every free user,
  /// who can't add favorites).
  Future<Set<String>> fetchFavoriteIds();

  /// Adds or removes [questionId] from the caller's favorites, returning the NEW
  /// state (true = now favorited, false = now removed).
  ///
  /// Adding is premium-only and throws when the caller isn't premium — the
  /// free-tier star is a paywall hook, not a write. Removing is always allowed
  /// (curating a list you own), so a lapsed-premium user can still prune theirs.
  Future<bool> toggleFavorite(String questionId);

  /// The caller's favorited questions WITH text, newest first.
  ///
  /// Favorites are readable forever — once saved, the text comes back even after
  /// premium lapses (the favorite is the grant), so unlike the catalog these are
  /// never locked placeholders. For the favorites screen in Settings.
  Future<List<Question>> fetchFavoriteQuestions();

  /// Every question the caller VOTED on with its community TAK/NIE split,
  /// newest vote first — the PRO "question history" (the user's voting record).
  ///
  /// Premium-only: a free user / guest gets an EMPTY list (the server returns no
  /// rows; the client shows a PRO upsell instead of an error). Votes are the
  /// gate — a question the user merely saw but never voted on has no row. See
  /// the `get_vote_history` RPC.
  Future<List<VoteHistoryEntry>> fetchVoteHistory();

  /// The ids of active questions added to the catalog at or after [since].
  ///
  /// Drives the small "Nowe" badge on the feed: a question younger than the
  /// freshness window gets flagged so a thin vote count reads as "just added",
  /// not "nobody cares". Ids only (no text), so it's one cheap indexed read of
  /// the public `questions` table — the RPC return shapes stay untouched.
  Future<Set<String>> fetchRecentQuestionIds({required DateTime since});
}

/// Default implementation backed by the in-memory mock list.
///
/// Replace with a `SupabaseQuestionRepository` (querying the `questions` table)
/// when the backend is ready — the [QuestionRepository] contract stays the same.
class MockQuestionRepository implements QuestionRepository {
  /// [random] drives the "random pool question" picks (peek / ad reveal); tests
  /// pass a seeded [Random] for reproducible picks. Defaults to a fresh one.
  MockQuestionRepository({Random? random}) : _random = random ?? Random();

  final Random _random;

  /// Instance-local favorites for the offline/dev preview.
  ///
  /// The real store is the `question_favorites` table; in mock mode there's no
  /// backend, so a simple mutable set lets the star + favorites screen
  /// round-trip during development without persistence. Per-INSTANCE on
  /// purpose: a process-global set leaked favorites between the many tests
  /// (and dev locale switches) that each build their own repository.
  final Set<String> _favorites = <String>{};

  @override
  Future<List<Question>> fetchQuestions() async {
    // Simulate a small network delay so loading states are exercised in the UI.
    await Future.delayed(const Duration(milliseconds: 300));
    // Mirror the free-tier shape the get_questions RPC returns: the catalog
    // comes back in full but every question is locked, each carrying a short
    // teaser (the first two words) so the locked-card "Czy miliarderzy…" tease
    // is exercised offline. Only the daily is free, and the deck shows that
    // separately (fetchDailyQuestion, always unlocked) at position 0.
    return [
      for (final q in kMockQuestions)
        q.copyWith(isLocked: true, teaser: _teaserOf(q.questionText)),
    ];
  }

  @override
  Future<Question?> fetchDailyQuestion(DateTime date) async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (kMockQuestions.isEmpty) return null;

    // The daily is always free to read, regardless of its position in the pool.
    return kMockQuestions[date.day % kMockQuestions.length].copyWith(
      isLocked: false,
    );
  }

  @override
  Future<List<Smaczek>> fetchSmaczki(String questionId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    // Dev/offline preview mirrors the free-tier shape the RPC returns: the
    // first smaczek is readable, the rest come back locked (no text). Premium
    // can't be exercised without real RevenueCat config, so mock mode is always
    // the free view.
    return const [
      Smaczek(
        position: 1,
        isLocked: false,
        text:
            'Zapytaj o konkretny przykład z ostatniego tygodnia — konkret '
            'otwiera rozmowę szybciej niż ogólniki.',
      ),
      Smaczek(position: 2, isLocked: true),
      Smaczek(position: 3, isLocked: true),
    ];
  }

  @override
  Future<({String id, String teaser})?> peekNextQuestion({
    List<String> excludeIds = const [],
  }) async {
    await Future.delayed(const Duration(milliseconds: 150));
    if (kMockQuestions.length < 2) return null;
    final pick = kMockQuestions[1 + _random.nextInt(kMockQuestions.length - 1)];
    final teaser = pick.questionText
        .trim()
        .split(RegExp(r'\s+'))
        .take(2)
        .join(' ');
    return (id: pick.id, teaser: teaser);
  }

  @override
  Future<Question?> revealAdQuestion({
    String? questionId,
    List<String> excludeIds = const [],
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
    // Offline preview: reveal the requested mock question (or a random pool one).
    // No real seen-memory in mock mode, so this can repeat — fine for a dev
    // preview; tests use a custom fake repository.
    if (kMockQuestions.isEmpty) return null;
    final pick = questionId != null
        ? kMockQuestions.firstWhere(
            (q) => q.id == questionId,
            orElse: () => kMockQuestions.first,
          )
        : kMockQuestions[kMockQuestions.length < 2
              ? 0
              : 1 + _random.nextInt(kMockQuestions.length - 1)];
    return pick.copyWith(isLocked: false);
  }

  @override
  Future<UserStats?> syncUserState() async {
    // Offline preview: a fresh free user with the daily credit available and no
    // streak yet. The real top-up / streak logic is server-side (off the server
    // clock), so mock mode just shows the entry state.
    return const UserStats(
      currentStreak: 0,
      longestStreak: 0,
      freeUnlockCredits: 1,
      rankTier: 0,
      rankName: 'Amator kontrowersji',
      nextRankStreak: 3,
    );
  }

  @override
  Future<VoteResult> getDailyVoteState(String questionId) async {
    await Future.delayed(const Duration(milliseconds: 150));
    // Not voted yet in mock mode, with a plausible community split to preview.
    return const VoteResult(yesCount: 0, noCount: 0);
  }

  @override
  Future<VoteResult> castDailyVote(String questionId, int choice) async {
    await Future.delayed(const Duration(milliseconds: 150));
    // Fake a 60/40-ish split so the result bars render in dev; the user's own
    // vote is folded into the side they picked.
    return VoteResult(
      yesCount: choice == VoteResult.yes ? 61 : 60,
      noCount: choice == VoteResult.no ? 41 : 40,
      myChoice: choice,
    );
  }

  @override
  Future<Question?> revealFreeQuestion({
    List<String> excludeIds = const [],
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
    // Offline preview: same as the ad reveal — the credit accounting is
    // server-side, so mock just hands back a readable pool question.
    return revealAdQuestion();
  }

  @override
  Future<List<Rank>> fetchRanks() async => kDefaultRanks;

  @override
  Future<void> markQuestionSeen(String questionId) async {
    // Offline preview has no real seen-memory; nothing to record.
  }

  @override
  Future<Set<String>> fetchFavoriteIds() async => Set<String>.from(_favorites);

  @override
  Future<bool> toggleFavorite(String questionId) async {
    await Future.delayed(const Duration(milliseconds: 120));
    // Dev/offline preview keeps favorites in an instance-local set so the star
    // and the favorites screen behave; the real premium gate lives server-side.
    if (_favorites.remove(questionId)) return false;
    _favorites.add(questionId);
    return true;
  }

  @override
  Future<List<Question>> fetchFavoriteQuestions() async {
    await Future.delayed(const Duration(milliseconds: 200));
    // Map the saved ids back to readable mock questions, mirroring the RPC's
    // "favorites are never locked" shape.
    return [
      for (final q in kMockQuestions)
        if (_favorites.contains(q.id)) q.copyWith(isLocked: false),
    ];
  }

  @override
  Future<List<VoteHistoryEntry>> fetchVoteHistory() async {
    await Future.delayed(const Duration(milliseconds: 250));
    // Offline preview: fabricate a handful of voted questions from the pool so
    // the history screen renders with plausible splits. The real premium gate +
    // tallies live server-side; mock mode always shows the "has data" view.
    final now = DateTime.now();
    final source = kMockQuestions.length > 6
        ? kMockQuestions.sublist(1, 7)
        : kMockQuestions;
    return [
      for (var i = 0; i < source.length; i++)
        VoteHistoryEntry(
          questionId: source[i].id,
          category: source[i].category,
          questionText: source[i].questionText,
          votedAt: now.subtract(Duration(hours: 3 + i * 11)),
          votes: VoteResult(
            yesCount: 40 + (i * 13) % 55,
            noCount: 20 + (i * 7) % 45,
            myChoice: i.isEven ? VoteResult.yes : VoteResult.no,
          ),
        ),
    ];
  }

  @override
  Future<Set<String>> fetchRecentQuestionIds({required DateTime since}) async {
    await Future.delayed(const Duration(milliseconds: 100));
    // Offline preview: mark the first couple of pool questions "new" so the
    // badge can be eyeballed in dev without a backend.
    return {for (final q in kMockQuestions.take(2)) q.id};
  }
}

/// Supabase-backed implementation used in production builds.
///
/// Matches the schema in `supabase/migrations/schema/20260618120000_init.sql`:
/// question text lives in `question_translations` (one row per locale) and is
/// gated by RLS, so a free user only receives the text they may read (today's
/// daily + unlocked) while a premium user receives all of it. Writes never
/// happen here — content is managed via the dashboard / service-role.
class SupabaseQuestionRepository implements QuestionRepository {
  SupabaseQuestionRepository({this.locale = 'pl', this.client});

  final String locale;

  /// The Supabase client to talk to. Null in production — the repo then falls
  /// back to the app-wide [SupabaseService.client]; a test injects one backed by
  /// a mock HTTP transport to exercise the real RPC↔model mapping and the
  /// param/function names without a live backend.
  ///
  /// The fallback is resolved lazily (only when an RPC actually fires, via [_db])
  /// rather than in the constructor, so building the repo never touches the
  /// singleton — the provider can construct it without forcing [SupabaseService]
  /// to be initialised at that exact moment.
  final SupabaseClient? client;

  SupabaseClient get _db => client ?? SupabaseService.client;

  @override
  Future<List<Question>> fetchQuestions() async {
    // The deck is the full catalog. get_questions returns every active question
    // with a `locked` flag, and frees the text of exactly ONE — the daily for
    // the device's local date (`p_date`), which the gate clamps to UTC ±1 so the
    // user's real "today" is honoured but the archive can't be harvested.
    // Everything else comes back locked (no text) and renders as a locked card.
    final data = await _db.rpc(
      'get_questions',
      params: {'p_locale': locale, 'p_date': dateOnlyKey(DateTime.now())},
    );

    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(Question.fromJson)
        .toList();
  }

  @override
  Future<Question?> fetchDailyQuestion(DateTime date) async {
    // The RPC serves the caller's PERSONAL daily for their local date: on the
    // first call of the day it draws a random not-yet-voted question (unseen
    // first) and pins it for the rest of that date, so every user opens to a
    // fresh, votable question — never a re-run they already answered.
    final data = await _db.rpc(
      'get_daily_question',
      params: {'p_locale': locale, 'p_date': dateOnlyKey(date)},
    );

    final rows = (data as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return null;

    final question = Question.fromJson(rows.first);
    return question.questionText.trim().isEmpty ? null : question;
  }

  @override
  Future<List<Smaczek>> fetchSmaczki(String questionId) async {
    // The RPC returns every smaczek for the question but withholds the text of
    // locked ones (premium-only beyond the first). RLS/grants are deliberately
    // off on the smaczki tables — this SECURITY DEFINER RPC is the only way in.
    final data = await _db.rpc(
      'get_question_smaczki',
      params: {'p_question_id': questionId, 'p_locale': locale},
    );

    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(Smaczek.fromJson)
        .toList();
  }

  @override
  Future<({String id, String teaser})?> peekNextQuestion({
    List<String> excludeIds = const [],
  }) async {
    // SECURITY DEFINER RPC: previews the next UNVOTED pick's teaser without
    // revealing it (no text, not marked seen). Empty = nothing left. p_exclude_ids
    // keeps the teaser off a question already revealed this session.
    final data = await _db.rpc(
      'peek_next_question',
      params: {
        'p_locale': locale,
        'p_date': dateOnlyKey(DateTime.now()),
        'p_exclude_ids': excludeIds,
      },
    );
    final rows = (data as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return null;
    final row = rows.first;
    return (id: row['id'].toString(), teaser: row['teaser'] as String? ?? '');
  }

  @override
  Future<Question?> revealAdQuestion({
    String? questionId,
    List<String> excludeIds = const [],
  }) async {
    // SECURITY DEFINER RPC: reveals the peeked question (when still eligible) or
    // a random UNVOTED, non-daily one, records it in question_seen, and returns it
    // WITH text. Empty result = nothing unvoted left. p_exclude_ids skips this
    // session's already-revealed ids on the random pick.
    final data = await _db.rpc(
      'reveal_ad_question',
      params: {
        'p_locale': locale,
        'p_date': dateOnlyKey(DateTime.now()),
        'p_question_id': ?questionId,
        'p_exclude_ids': excludeIds,
      },
    );
    final rows = (data as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return null;
    return Question.fromJson(rows.first).copyWith(isLocked: false);
  }

  @override
  Future<UserStats?> syncUserState() async {
    // SECURITY DEFINER RPC: returns the server's view of streak / credits / rank
    // and tops up today's free credit (once per UTC day, capped at 1) as a side
    // effect. Returns a single row.
    final data = await _db.rpc('sync_user_state', params: {'p_locale': locale});

    final rows = (data as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return null;
    return UserStats.fromJson(rows.first);
  }

  @override
  Future<VoteResult> getDailyVoteState(String questionId) async {
    final data = await _db.rpc(
      'get_daily_vote_state',
      params: {'p_question_id': questionId},
    );

    final rows = (data as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return VoteResult.empty;
    return VoteResult.fromJson(rows.first);
  }

  @override
  Future<VoteResult> castDailyVote(String questionId, int choice) async {
    // The RPC records the vote, advances the streak when this is the daily, and
    // returns the fresh community split. Pass the device's local date so the
    // streak's "is this the daily" check honours the user's timezone (clamped to
    // UTC ±1 server-side).
    final data = await _db.rpc(
      'cast_daily_vote',
      params: {
        'p_question_id': questionId,
        'p_choice': choice,
        'p_date': dateOnlyKey(DateTime.now()),
        'p_locale': locale,
      },
    );

    final rows = (data as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return VoteResult.empty;
    return VoteResult.fromJson(rows.first);
  }

  @override
  Future<Question?> revealFreeQuestion({
    List<String> excludeIds = const [],
  }) async {
    // SECURITY DEFINER RPC: same pick as reveal_ad_question (unvoted pool) but
    // charges one daily credit (real accounts only). Empty result = nothing left
    // (no charge). Throws on no-credit / premium / guest — the caller surfaces it.
    final data = await _db.rpc(
      'reveal_free_question',
      params: {
        'p_locale': locale,
        'p_date': dateOnlyKey(DateTime.now()),
        'p_exclude_ids': excludeIds,
      },
    );
    final rows = (data as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return null;
    return Question.fromJson(rows.first).copyWith(isLocked: false);
  }

  @override
  Future<List<Rank>> fetchRanks() async {
    // The ranks table is public-readable; order by tier for the ladder.
    final data = await _db.from('ranks').select().order('tier');

    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(Rank.fromJson)
        .toList();
  }

  @override
  Future<void> markQuestionSeen(String questionId) async {
    // SECURITY DEFINER RPC: appends a `source='view'` row to question_seen for
    // the caller (idempotent). Best-effort — a failed marker only means the
    // question might be surfaced as "new" again, so swallow errors rather than
    // bubbling them into a fire-and-forget call site.
    try {
      await _db.rpc(
        'mark_question_seen',
        params: {'p_question_id': questionId},
      );
    } catch (e) {
      // Non-fatal: the deck still works, just without this view recorded. Keep a
      // breadcrumb only — a failed marker is benign and routinely offline.
      Monitoring.addBreadcrumb(
        'mark_question_seen failed',
        category: 'questions',
        data: {'questionId': questionId},
      );
    }
  }

  @override
  Future<Set<String>> fetchFavoriteIds() async {
    // SECURITY DEFINER RPC: the caller's favorite ids (own rows only).
    final data = await _db.rpc('get_favorite_ids');
    return (data as List).map((e) => e.toString()).toSet();
  }

  @override
  Future<bool> toggleFavorite(String questionId) async {
    // SECURITY DEFINER RPC: pins the row to auth.uid(), enforces the premium
    // gate on ADD server-side, and returns the new state. Throws on a non-premium
    // add ('premium required') — the caller surfaces the paywall instead.
    final data = await _db.rpc(
      'toggle_question_favorite',
      params: {'p_question_id': questionId},
    );
    return data as bool;
  }

  @override
  Future<List<Question>> fetchFavoriteQuestions() async {
    // SECURITY DEFINER RPC: returns favorites WITH text (readable forever), so —
    // unlike get_questions — nothing comes back locked. fromJson sees no `locked`
    // key, defaulting isLocked to false.
    final data = await _db.rpc(
      'get_favorite_questions',
      params: {'p_locale': locale},
    );
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(Question.fromJson)
        .toList();
  }

  @override
  Future<List<VoteHistoryEntry>> fetchVoteHistory() async {
    // SECURITY DEFINER RPC: returns every question the caller voted on (newest
    // vote first) with the live community split, gating on premium server-side
    // — a non-premium caller simply gets zero rows. No date param: the row's
    // date is the vote's own timestamp, rendered locally by the client.
    final data = await _db.rpc(
      'get_vote_history',
      params: {'p_locale': locale},
    );
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(VoteHistoryEntry.fromJson)
        .toList();
  }

  @override
  Future<Set<String>> fetchRecentQuestionIds({required DateTime since}) async {
    // A plain table read, not an RPC: `questions` is granted to anon +
    // authenticated with RLS limiting rows to active questions, and ids carry
    // no gated content — the text stays behind the SECURITY DEFINER RPCs.
    final data = await _db
        .from('questions')
        .select('id')
        .gte('created_at', since.toUtc().toIso8601String());

    return (data as List)
        .cast<Map<String, dynamic>>()
        .map((row) => row['id'].toString())
        .toSet();
  }
}

/// The device-local calendar date as the `yyyy-MM-dd` string sent as the
/// `p_date` RPC param AND used as the daily-question cache key (see
/// `CachingQuestionRepository`). ONE definition on purpose: if the repo and the
/// cache ever format this differently, the cached daily can no longer be found
/// under the date the repo asks for and the offline daily silently breaks.
String dateOnlyKey(DateTime date) {
  final local = date.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}

/// The first two words of [text], used as the locked-card teaser in mock mode.
///
/// Mirrors what the `get_questions` RPC computes server-side, so the offline
/// preview shows the same "two words + ellipsis" tease as production.
String _teaserOf(String text) =>
    text.trim().split(RegExp(r'\s+')).take(2).join(' ');
