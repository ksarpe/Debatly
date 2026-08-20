import 'dart:async' show unawaited;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/monitoring/monitoring.dart';
import '../../core/network/network_timeout.dart';
import '../../services/supabase_service.dart';
import '../mock/mock_questions.dart';
import '../models/conformity_stats.dart';
import '../models/debate_profile.dart';
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

  /// The first words of the NEXT question waiting for the caller — the day
  /// wall's blurred teaser ("Czy osoba otyła powinna…").
  ///
  /// Calls `peek_next_question`, a pure read: the server picks a random active
  /// question the caller hasn't voted on (outside their own daily-assignment
  /// window) and returns only its first few words — never the full text, and
  /// nothing is consumed or recorded (`question_seen` stays untouched, so the
  /// wall may peek every day for free). [excludeIds] keeps the served daily
  /// out of the pick. Null when there is nothing left to tease.
  Future<String?> peekNextQuestion({List<String> excludeIds = const []});

  /// The discussion prompts ("smaczki") for a single question.
  ///
  /// The source applies the gates: premium reads everything; a free user gets
  /// readable text only AFTER voting on the question, and then exactly one row
  /// — the argument aimed at their own side (or a neutral / untagged one) —
  /// with the rest as locked placeholders (no text). Call this only once the
  /// vote exists; before it, use [fetchSmaczkiMeta]. See [Smaczek].
  Future<List<Smaczek>> fetchSmaczki(String questionId);

  /// The pre-vote smaczki prefetch: positions + rough lengths, never any text.
  ///
  /// Calls `get_question_smaczki_meta` — the only smaczki request allowed
  /// before the caller's vote, so no readable argument can sit on the device
  /// while the reflex the community split measures is still forming.
  Future<List<SmaczekMeta>> fetchSmaczkiMeta(String questionId);

  /// Syncs and returns the user's engagement state (streak, rank).
  ///
  /// Calls `sync_user_state`. Returns null when there is no signed-in user /
  /// no backend.
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

  /// Records how the user answered the post-vote gate (the smaczek challenge)
  /// on their existing vote row — the vote itself is never modified.
  ///
  /// [position] identifies the shown smaczek within the question (the server
  /// resolves the row id from it), [dwellMs] is the time the argument spent on
  /// screen — gate opened to tap, so the words falling in count as the reading
  /// they are (null when dismissed before it landed). First write
  /// wins server-side, so a retry can never double-count. Returns the fresh
  /// split including [VoteResult.flipPct].
  Future<VoteResult> recordSmaczekChallenge({
    required String questionId,
    required int position,
    required ChallengeOutcome outcome,
    int? dwellMs,
  });

  /// The full rank ladder (ordered by tier), for the rank sheet.
  Future<List<Rank>> fetchRanks();

  /// Records that the caller has viewed [questionId] (catalog browsing).
  ///
  /// Best-effort and idempotent: it appends to the per-user seen-memory so the
  /// next launch surfaces UNSEEN questions first. Never throws to the caller —
  /// a failed marker just means the question may reappear as "new" later,
  /// which is benign.
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
  /// newest vote first — the "question history" (the user's voting record).
  ///
  /// Premium gets the full record; a free user / guest gets only their newest
  /// votes (server-side: the last 48 hours — enough to cover the local "today"
  /// the history screen renders, with everything older shown as a locked PRO
  /// panel). Votes are the gate — a question the user merely saw but never
  /// voted on has no row. See the `get_vote_history` RPC.
  Future<List<VoteHistoryEntry>> fetchVoteHistory();

  /// The caller's debate profile: conformity + resilience raw counts plus the
  /// server's live boundaries and unlock thresholds (`get_debate_profile`).
  ///
  /// Like the conformity stats it aggregates only the caller's own votes, so
  /// it is NOT premium-gated — the 2×2 type is deliberately free (a free user
  /// who never sees their type never wants the PRO depth behind it).
  Future<DebateProfile> fetchDebateProfile();

  /// The PRO trend: the profile's counts bucketed per month, oldest first
  /// (`get_profile_trend`). Throws 'premium required' for a free caller.
  Future<List<ProfileTrendPoint>> fetchProfileTrend();

  /// PRO: what share of unlocked profiles lands in the caller's 2×2 cell
  /// (`get_type_rarity`). Null when the number would embarrass the feature
  /// (population under the server's floor, or the caller's own profile still
  /// locked) — the UI hides the block then. Throws 'premium required' for a
  /// free caller.
  ///
  /// The category breakdown (`get_profile_categories`) deliberately has NO
  /// client method: the catalog's category labels are English-only, so the
  /// section was pulled from the UI until they're localized. The RPC stays
  /// live server-side.
  Future<int?> fetchTypeRarity();

  /// The PRO "zdania, które Cię przewróciły" list: every qualifying gate the
  /// caller answered "to mnie ruszyło", newest first (`get_moved_smaczki`).
  /// Throws 'premium required' for a free caller.
  Future<List<MovedSmaczek>> fetchMovedSmaczki();

  /// How often the caller votes with the community majority — one aggregate
  /// row (total / with-majority / with-minority) behind the conformity-axis
  /// panel.
  ///
  /// Available to every signed-in identity (guests included): unlike the
  /// history it exposes only counts of the caller's own votes, so it is NOT
  /// premium-gated. The majority is decided server-side on the same
  /// seed-inclusive totals shown as the community split. See the
  /// `get_conformity_stats` RPC.
  Future<ConformityStats> fetchConformityStats();

  /// The ids of active questions added to the catalog at or after [since].
  ///
  /// Drives the small "Nowe" badge on the feed: a question younger than the
  /// freshness window gets flagged so a thin vote count reads as "just added",
  /// not "nobody cares". Ids only (no text), so it's one cheap indexed read of
  /// the public `questions` table — the RPC return shapes stay untouched.
  Future<Set<String>> fetchRecentQuestionIds({required DateTime since});

  /// Sends the user's own question idea ("Zaproponuj pytanie") to the team's
  /// review inbox — raw text, not a published question.
  ///
  /// Server-side the RPC validates length (10–500 chars) and caps submissions
  /// per day; violations and offline both throw, and the suggestion sheet turns
  /// the failure into the right toast.
  Future<void> submitQuestionSuggestion(String text);

  /// Sends the user's own smaczek idea for [questionId] ("Zaproponuj własny"
  /// in the Arguments panel) to the same review inbox as question suggestions
  /// (`question_suggestions`, kind = 'smaczek').
  ///
  /// Server-side the RPC normalises whitespace, validates length (5–80 chars),
  /// rejects control characters and unknown question ids, and shares the
  /// question-suggestion daily cap; violations and offline both throw, and the
  /// composer turns the failure into the right toast.
  Future<void> submitSmaczekSuggestion({
    required String questionId,
    required String text,
  });
}

/// Default implementation backed by the in-memory mock list.
///
/// Replace with a `SupabaseQuestionRepository` (querying the `questions` table)
/// when the backend is ready — the [QuestionRepository] contract stays the same.
class MockQuestionRepository implements QuestionRepository {
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
    // Mock sessions are premium (see SessionNotifier), so mirror the entitled
    // shape the get_questions RPC returns: the whole catalog, readable.
    return [for (final q in kMockQuestions) q.copyWith(isLocked: false)];
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
  Future<String?> peekNextQuestion({List<String> excludeIds = const []}) async {
    // No simulated latency, unlike the other mock methods: QuestionBody
    // prefetches the teaser whenever a free feed is on screen, so a delay here
    // would leave a pending fake timer failing any widget test that merely
    // shows the free feed. (Mock-mode dev sessions are premium and never meet
    // the wall, so nothing real exercised the delay anyway.)
    // First non-excluded mock question, cut to the server teaser length.
    for (final q in kMockQuestions) {
      if (excludeIds.contains(q.id)) continue;
      final words = q.questionText.trim().split(RegExp(r'\s+'));
      if (words.isEmpty) continue;
      return words.take(4).join(' ');
    }
    return null;
  }

  @override
  Future<List<Smaczek>> fetchSmaczki(String questionId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    // Mock sessions are premium (see SessionNotifier), so every smaczek comes
    // back readable — the entitled shape of the RPC. One argument per side plus
    // a neutral one, so the post-vote challenge has something aimed at whichever
    // way a keyless dev session votes.
    return const [
      Smaczek(
        position: 1,
        isLocked: false,
        side: SmaczekSide.attacksYes,
        text:
            'Zgodziłeś się w sekundę — a to samo zdanie podpisałby ktoś, '
            'kogo nie znosisz.',
      ),
      Smaczek(
        position: 2,
        isLocked: false,
        side: SmaczekSide.attacksNo,
        text:
            'Odmawiasz dzisiaj. Za pięć lat to będzie standard i nikt już '
            'Cię o to nie zapyta.',
      ),
      Smaczek(
        position: 3,
        isLocked: false,
        side: SmaczekSide.neutral,
        text:
            'Odpowiedziałeś od razu. Ile z tego było decyzją, a ile '
            'odruchem?',
      ),
    ];
  }

  @override
  Future<List<SmaczekMeta>> fetchSmaczkiMeta(String questionId) async {
    // Mirror the meta RPC's shape off the mock list: positions plus lengths
    // rounded to 10, no text — so the pre-vote path is exercisable in dev.
    // No simulated latency, same reasoning as peekNextQuestion above: the
    // feed prefetches this for every visible question, so a delay here would
    // leave a pending fake timer failing any widget test that merely shows
    // the feed. NOT routed through fetchSmaczki (and its delay) for the same
    // reason — subclass test repos overriding fetchSmaczki keep their canned
    // list, while the meta path stays instant.
    return const [
      SmaczekMeta(position: 1, approxLen: 70),
      SmaczekMeta(position: 2, approxLen: 70),
      SmaczekMeta(position: 3, approxLen: 60),
    ];
  }

  @override
  Future<UserStats?> syncUserState() async {
    // Offline preview: a fresh user with no streak yet. The real streak logic
    // is server-side (off the server clock), so mock mode shows the entry state.
    return const UserStats(
      currentStreak: 0,
      longestStreak: 0,
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

  /// The last cast choice, so the mock challenge record can echo a plausible
  /// post-gate state the way the real RPC does.
  int? _lastChoice;

  @override
  Future<VoteResult> castDailyVote(String questionId, int choice) async {
    await Future.delayed(const Duration(milliseconds: 150));
    _lastChoice = choice;
    // Fake a 60/40-ish split so the result bars render in dev; the user's own
    // vote is folded into the side they picked.
    return VoteResult(
      yesCount: choice == VoteResult.yes ? 61 : 60,
      noCount: choice == VoteResult.no ? 41 : 40,
      myChoice: choice,
    );
  }

  @override
  Future<VoteResult> recordSmaczekChallenge({
    required String questionId,
    required int position,
    required ChallengeOutcome outcome,
    int? dwellMs,
  }) async {
    await Future.delayed(const Duration(milliseconds: 120));
    final choice = _lastChoice;
    // Same fake split as the cast, plus a plausible flip share so the
    // "Kontra przewróciła X%" line can be eyeballed in keyless dev.
    return VoteResult(
      yesCount: choice == VoteResult.yes ? 61 : 60,
      noCount: choice == VoteResult.no ? 41 : 40,
      myChoice: choice,
      flipPct: 11,
    );
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
  Future<ConformityStats> fetchConformityStats() async {
    await Future.delayed(const Duration(milliseconds: 200));
    // Offline preview: a rebel-ish split (15/44 decided ≈ 34% with the
    // majority) so the axis, marker and next-tier progress all render in dev.
    return const ConformityStats(
      totalVotes: 47,
      majorityVotes: 15,
      minorityVotes: 29,
    );
  }

  @override
  Future<DebateProfile> fetchDebateProfile() async {
    await Future.delayed(const Duration(milliseconds: 200));
    // Mirrors the conformity mock (34% with the majority) plus a 3/12 moved
    // share — an unlocked, FULL "Poszukiwacz", so the whole grid renders in
    // keyless dev. Boundaries/thresholds are the server defaults.
    return const DebateProfile(
      totalVotes: 47,
      majorityVotes: 15,
      minorityVotes: 29,
      gateHeld: 9,
      gateMoved: 3,
    );
  }

  @override
  Future<List<ProfileTrendPoint>> fetchProfileTrend() async {
    await Future.delayed(const Duration(milliseconds: 200));
    // Mock sessions are premium, so serve a plausible three-month curve.
    final base = DateTime.now();
    final thisMonth = DateTime(base.year, base.month);
    DateTime monthsAgo(int n) => DateTime(thisMonth.year, thisMonth.month - n);
    return [
      ProfileTrendPoint(
        month: monthsAgo(2),
        totalVotes: 12,
        majorityVotes: 5,
        minorityVotes: 6,
        gateHeld: 2,
        gateMoved: 1,
      ),
      ProfileTrendPoint(
        month: monthsAgo(1),
        totalVotes: 18,
        majorityVotes: 6,
        minorityVotes: 11,
        gateHeld: 4,
        gateMoved: 1,
      ),
      ProfileTrendPoint(
        month: thisMonth,
        totalVotes: 17,
        majorityVotes: 4,
        minorityVotes: 12,
        gateHeld: 3,
        gateMoved: 1,
      ),
    ];
  }

  @override
  Future<int?> fetchTypeRarity() async {
    await Future.delayed(const Duration(milliseconds: 200));
    // A plausible minority share so the PRO rarity line renders in dev.
    return 9;
  }

  @override
  Future<List<MovedSmaczek>> fetchMovedSmaczki() async {
    await Future.delayed(const Duration(milliseconds: 200));
    final now = DateTime.now();
    return [
      MovedSmaczek(
        questionText: 'Czy pytanie dnia jest darmowe?',
        smaczekText:
            'Zgodziłeś się w sekundę — a to samo zdanie podpisałby ktoś, '
            'kogo nie znosisz.',
        movedAt: now.subtract(const Duration(days: 2)),
      ),
      MovedSmaczek(
        questionText: 'Czy wiek uprawnia do wszystkiego?',
        smaczekText:
            'Odpowiedziałeś od razu. Ile z tego było decyzją, a ile odruchem?',
        movedAt: now.subtract(const Duration(days: 9)),
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

  @override
  Future<void> submitQuestionSuggestion(String text) async {
    // Offline preview: accept and drop — there is no backend inbox to keep, and
    // the sheet only needs the success path to be exercisable in dev/tests.
    await Future.delayed(const Duration(milliseconds: 250));
  }

  @override
  Future<void> submitSmaczekSuggestion({
    required String questionId,
    required String text,
  }) async {
    // Offline preview: accept and drop, same as question suggestions above.
    await Future.delayed(const Duration(milliseconds: 250));
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
    final data = await _db
        .rpc(
          'get_questions',
          params: {'p_locale': locale, 'p_date': dateOnlyKey(DateTime.now())},
        )
        .withNetworkTimeout();

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
    final data = await _db
        .rpc(
          'get_daily_question',
          params: {'p_locale': locale, 'p_date': dateOnlyKey(date)},
        )
        .withNetworkTimeout();

    final rows = (data as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) {
      _reportNoDaily('no_row', date);
      return null;
    }

    final question = Question.fromJson(rows.first);
    if (question.questionText.trim().isEmpty) {
      _reportNoDaily('blank_text', date, questionId: question.id);
      return null;
    }
    return question;
  }

  /// Reports a daily that resolved to NOTHING — the only daily failure with no
  /// exception behind it, and so the only one nothing else can see.
  ///
  /// The degraded-but-working paths (a dead pick, a gap in `daily_picks`, an
  /// exhausted calendar, a cron that never ran) all fall back to the personal
  /// draw and return a real question; those are a spread problem, measured in
  /// `user_daily_questions`, not an error. This is the other end: the RPC
  /// answered 200 with nothing usable, so the caller has NO daily at all. It
  /// throws nothing, logs nothing server-side and passes `beforeSend`
  /// untouched, because there is no error object anywhere in it — which is
  /// exactly why it has to be constructed here.
  ///
  /// Every empty-feed dead end funnels through this: the deck is empty only
  /// when the daily is null (a non-null daily is always deck[0]), so the
  /// screen's "resolved but empty" retry state cannot happen without one of
  /// these two branches firing first. It also catches the case that dead end
  /// MISSES — a premium user whose catalog loaded fine, who just silently
  /// never gets a daily.
  ///
  /// [reason] separates the two in Sentry because they are different bugs:
  ///   * `no_row` — the RPC selected nothing. Leading cause is a caller with no
  ///     uid: a failed anonymous sign-in leaves `ensureSignedIn` null and
  ///     `get_daily_question` has no user to draw for (Supabase rate-limits
  ///     anonymous sign-ups per IP, which a carrier CGNAT or an office network
  ///     reaches). `has_session` is in the payload to confirm or kill that
  ///     hypothesis without guessing.
  ///   * `blank_text` — a row came back with no readable text. Two very
  ///     different bugs share this shape: the question has no translation in
  ///     either language (content), or the gate STRIPPED the text because a
  ///     premium question landed on a free user's daily slot (the leak guard —
  ///     see the repo tests). `question_id` + `locale` are what tell them
  ///     apart, so they are always in the payload here.
  void _reportNoDaily(String reason, DateTime date, {String? questionId}) {
    unawaited(
      Monitoring.captureException(
        StateError('get_daily_question returned no usable question ($reason)'),
        feature: 'daily_question',
        extra: {
          'reason': reason,
          'locale': locale,
          'date': dateOnlyKey(date),
          'has_session': SupabaseService.currentUser != null,
          'question_id': ?questionId,
        },
      ),
    );
  }

  @override
  Future<String?> peekNextQuestion({List<String> excludeIds = const []}) async {
    // SECURITY DEFINER RPC, read-only by design: {id, teaser} for one random
    // eligible question, the teaser cut server-side to the first few words —
    // the full text never reaches a non-premium client, and the peek records
    // nothing (no question_seen row, no spend).
    final data = await _db
        .rpc(
          'peek_next_question',
          params: {
            'p_locale': locale,
            'p_date': dateOnlyKey(DateTime.now()),
            'p_exclude_ids': excludeIds,
          },
        )
        .withNetworkTimeout();

    final rows = (data as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return null;
    final teaser = rows.first['teaser'] as String?;
    if (teaser == null || teaser.trim().isEmpty) return null;
    return teaser.trim();
  }

  @override
  Future<List<Smaczek>> fetchSmaczki(String questionId) async {
    // The RPC returns every smaczek for the question, ordered by how relevant
    // each one is to the caller's own vote, but withholds the text of the
    // locked ones. A free caller gets readable text only after their vote
    // exists — and then only the argument aimed at them (attacker of their
    // side, else neutral/untagged; a pure defense stays locked). RLS/grants
    // are deliberately off on the smaczki tables — this SECURITY DEFINER RPC
    // is the only way in.
    final data = await _db
        .rpc(
          'get_question_smaczki',
          params: {'p_question_id': questionId, 'p_locale': locale},
        )
        .withNetworkTimeout();

    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(Smaczek.fromJson)
        .toList();
  }

  @override
  Future<List<SmaczekMeta>> fetchSmaczkiMeta(String questionId) async {
    // SECURITY DEFINER RPC, metadata only: positions + lengths rounded to 10
    // characters. This is the whole pre-vote surface of the smaczki — no text
    // column even exists in the result.
    final data = await _db
        .rpc(
          'get_question_smaczki_meta',
          params: {'p_question_id': questionId, 'p_locale': locale},
        )
        .withNetworkTimeout();

    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(SmaczekMeta.fromJson)
        .toList();
  }

  @override
  Future<UserStats?> syncUserState() async {
    // SECURITY DEFINER RPC: returns the server's view of streak / rank as a
    // single row. (Server-side it still tops up the legacy daily credit for
    // older app versions; this client ignores those fields.)
    final data = await _db
        .rpc('sync_user_state', params: {'p_locale': locale})
        .withNetworkTimeout();

    final rows = (data as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return null;
    return UserStats.fromJson(rows.first);
  }

  @override
  Future<VoteResult> getDailyVoteState(String questionId) async {
    final data = await _db
        .rpc('get_daily_vote_state', params: {'p_question_id': questionId})
        .withNetworkTimeout();

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
    //
    // FIRST WRITE WINS server-side: a second cast on a question already voted
    // writes nothing and comes back with the STORED choice in `my_choice` (the
    // vote also decides which argument is readable, so it must not stay
    // rewritable). Callers must trust the returned `myChoice` over the one they
    // sent — see 20260820120000_vote_is_final_in_the_rpc.sql.
    final data = await _db
        .rpc(
          'cast_daily_vote',
          params: {
            'p_question_id': questionId,
            'p_choice': choice,
            'p_date': dateOnlyKey(DateTime.now()),
            'p_locale': locale,
          },
        )
        .withNetworkTimeout();

    final rows = (data as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return VoteResult.empty;
    return VoteResult.fromJson(rows.first);
  }

  @override
  Future<VoteResult> recordSmaczekChallenge({
    required String questionId,
    required int position,
    required ChallengeOutcome outcome,
    int? dwellMs,
  }) async {
    // SECURITY DEFINER RPC: stamps the outcome onto the caller's OWN vote row
    // (first write wins — a retry never double-counts) and resolves the shown
    // smaczek's id from its position server-side. The vote's `choice` is never
    // touched. Returns the same row shape as get_daily_vote_state, so the
    // panel can show the freshest split (incl. flip_pct) without a refetch.
    final data = await _db
        .rpc(
          'record_smaczek_challenge',
          params: {
            'p_question_id': questionId,
            'p_position': position,
            'p_outcome': outcome.name,
            'p_dwell_ms': dwellMs,
          },
        )
        .withNetworkTimeout();

    final rows = (data as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return VoteResult.empty;
    return VoteResult.fromJson(rows.first);
  }

  @override
  Future<List<Rank>> fetchRanks() async {
    // The ranks table is public-readable; order by tier for the ladder.
    final data = await _db
        .from('ranks')
        .select()
        .order('tier')
        .withNetworkTimeout();

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
      await _db
          .rpc('mark_question_seen', params: {'p_question_id': questionId})
          .withNetworkTimeout();
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
    final data = await _db.rpc('get_favorite_ids').withNetworkTimeout();
    return (data as List).map((e) => e.toString()).toSet();
  }

  @override
  Future<bool> toggleFavorite(String questionId) async {
    // SECURITY DEFINER RPC: pins the row to auth.uid(), enforces the premium
    // gate on ADD server-side, and returns the new state. Throws on a non-premium
    // add ('premium required') — the caller surfaces the paywall instead.
    final data = await _db
        .rpc('toggle_question_favorite', params: {'p_question_id': questionId})
        .withNetworkTimeout();
    return data as bool;
  }

  @override
  Future<List<Question>> fetchFavoriteQuestions() async {
    // SECURITY DEFINER RPC: returns favorites WITH text (readable forever), so —
    // unlike get_questions — nothing comes back locked. fromJson sees no `locked`
    // key, defaulting isLocked to false.
    final data = await _db
        .rpc('get_favorite_questions', params: {'p_locale': locale})
        .withNetworkTimeout();
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(Question.fromJson)
        .toList();
  }

  @override
  Future<List<VoteHistoryEntry>> fetchVoteHistory() async {
    // SECURITY DEFINER RPC: returns every question the caller voted on (newest
    // vote first) with the live community split, gating on premium server-side
    // — a non-premium caller gets only their last 48 hours of votes (the
    // always-free daily), which the screen trims to the local today. No date
    // param: the row's date is the vote's own timestamp, rendered locally.
    final data = await _db
        .rpc('get_vote_history', params: {'p_locale': locale})
        .withNetworkTimeout();
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(VoteHistoryEntry.fromJson)
        .toList();
  }

  @override
  Future<ConformityStats> fetchConformityStats() async {
    // SECURITY DEFINER RPC: one aggregate row over the caller's own votes,
    // majority decided on the seed-inclusive totals (so the axis matches the
    // result bars the user saw). Always exactly one row; zeros for a fresh
    // user, but guard the empty shape anyway.
    final data = await _db.rpc('get_conformity_stats').withNetworkTimeout();
    final rows = (data as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return ConformityStats.empty;
    return ConformityStats.fromJson(rows.first);
  }

  @override
  Future<DebateProfile> fetchDebateProfile() async {
    // SECURITY DEFINER RPC: the caller's own counts on both axes PLUS the
    // live boundaries/thresholds from profile_config — the client never
    // hard-codes a boundary, so the server can retune them without a release.
    final data = await _db.rpc('get_debate_profile').withNetworkTimeout();
    final rows = (data as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return DebateProfile.empty;
    return DebateProfile.fromJson(rows.first);
  }

  @override
  Future<List<ProfileTrendPoint>> fetchProfileTrend() async {
    // SECURITY DEFINER RPC, premium-gated server-side ('premium required').
    final data = await _db.rpc('get_profile_trend').withNetworkTimeout();
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(ProfileTrendPoint.fromJson)
        .toList();
  }

  @override
  Future<int?> fetchTypeRarity() async {
    // SECURITY DEFINER RPC, premium-gated server-side ('premium required').
    // One row; rarity_pct is NULL below the server's population floor.
    final data = await _db.rpc('get_type_rarity').withNetworkTimeout();
    final rows = (data as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return null;
    return (rows.first['rarity_pct'] as num?)?.toInt();
  }

  @override
  Future<List<MovedSmaczek>> fetchMovedSmaczki() async {
    // SECURITY DEFINER RPC, premium-gated server-side ('premium required').
    // Localized: the smaczek/question text follows the app locale with an
    // English fallback, same as every other content RPC.
    final data = await _db
        .rpc('get_moved_smaczki', params: {'p_locale': locale})
        .withNetworkTimeout();
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(MovedSmaczek.fromJson)
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

  @override
  Future<void> submitQuestionSuggestion(String text) async {
    // SECURITY DEFINER RPC: inserts into the admin-reviewed suggestions inbox,
    // pinning the row to auth.uid() and enforcing length + a per-day cap
    // server-side (TOO_SHORT / TOO_LONG / RATE_LIMITED).
    await _db
        .rpc(
          'submit_question_suggestion',
          params: {'p_text': text, 'p_locale': locale},
        )
        .withNetworkTimeout();
  }

  @override
  Future<void> submitSmaczekSuggestion({
    required String questionId,
    required String text,
  }) async {
    // SECURITY DEFINER RPC into the same admin inbox as question suggestions
    // (kind = 'smaczek'). The server normalises whitespace and enforces length
    // (5–80), control-character and question-id checks plus the shared per-day
    // cap (BAD_TEXT / TOO_SHORT / TOO_LONG / BAD_QUESTION / RATE_LIMITED).
    await _db
        .rpc(
          'submit_smaczek_suggestion',
          params: {
            'p_question_id': questionId,
            'p_text': text,
            'p_locale': locale,
          },
        )
        .withNetworkTimeout();
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
