import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/app_locale.dart';
import '../../../data/models/question.dart';
import '../../../data/models/smaczek.dart';
import '../../../data/models/vote_history_entry.dart';
import '../../../data/models/vote_result.dart';
import '../../../data/repositories/caching_question_repository.dart';
import '../../../data/repositories/question_repository.dart';
import '../../../services/question_cache.dart';
import '../../../services/supabase_service.dart';
import '../../account/providers/session_providers.dart';

/// The active question source.
///
/// In production builds, providing SUPABASE_URL and SUPABASE_ANON_KEY makes the
/// app read questions from Supabase. Without credentials, local mock data keeps
/// development and tests simple.
///
/// The Supabase source is built with the active app language (see
/// [localeControllerProvider]) so its `p_locale` matches the UI. Watching the
/// locale means switching language rebuilds this provider, which in turn
/// invalidates every downstream question/smaczki fetch — they re-load in the
/// newly chosen language.
///
/// In production the Supabase source is wrapped in a [CachingQuestionRepository]
/// so reads survive a dropped network (cache-fallback) and premium users get
/// their whole catalog offline. The wrapper also watches [isPremiumProvider]:
/// when premium flips, the repo (and every downstream fetch) rebuilds, which
/// both refreshes the now-unlocked catalog AND lets the wrapper wipe a stale
/// premium cache on a lapse. The mock source stays unwrapped — it's already
/// fully offline.
final questionRepositoryProvider = Provider<QuestionRepository>((ref) {
  if (!SupabaseService.isInitialised) return const MockQuestionRepository();
  final locale = ref.watch(localeControllerProvider).languageCode;
  return CachingQuestionRepository(
    inner: SupabaseQuestionRepository(locale: locale),
    cache: ref.watch(questionCacheProvider),
    locale: locale,
    isPremium: ref.watch(isPremiumProvider),
    // Scopes the cached daily-vote snapshot to this identity so a re-logged /
    // switched account never reads the previous user's vote offline.
    userId: ref.watch(sessionProvider.select((s) => s.value?.userId)),
  );
});

/// Loads the full question catalog once — for PREMIUM users only. Free users
/// get an empty list without any fetch: their deck never reads the catalog.
final questionsProvider = FutureProvider<List<Question>>((ref) async {
  // Hold the first fetch until the session's initial load has resolved, so the
  // catalog is fetched ONCE with the final identity + premium tier — not once on
  // the loading placeholder (userId=null, free) and again when the session lands.
  // That placeholder→final refetch is the launch/login "double reload"; the deck
  // shows its spinner while we wait. `isLoading` is only ever true during that
  // first build (refresh() never flips to loading), so this never re-holds —
  // later identity/premium changes refetch through the repository's own watch.
  if (ref.watch(sessionProvider.select((s) => s.isLoading))) {
    return const <Question>[];
  }
  // A free user's deck is only the daily + this session's reveals (see
  // [questionDeckProvider]) — the locked catalog is never rendered for them, so
  // don't ship ~1000 locked rows (and jsonEncode them into the cache on the UI
  // thread) on every launch. Watching the flag here (not just via the repo)
  // makes the pool load the moment premium flips true.
  if (!ref.watch(isPremiumProvider)) return const <Question>[];
  final repo = ref.watch(questionRepositoryProvider);
  return repo.fetchQuestions();
});

/// Loads the scheduled daily question for a concrete local date.
final dailyQuestionProvider = FutureProvider.family<Question?, DateTime>((
  ref,
  date,
) async {
  final repo = ref.watch(questionRepositoryProvider);
  return repo.fetchDailyQuestion(date);
});

/// Loads the discussion prompts ("smaczki") for a given question id.
///
/// The repository calls the `get_question_smaczki` RPC, which applies the
/// premium gate server-side: a free user gets the first smaczek plus the others
/// as locked placeholders, premium users get them all. Keyed by question id so
/// each question caches its own set; invalidate it after a purchase to re-fetch
/// the now-unlocked text.
final smaczkiProvider = FutureProvider.family<List<Smaczek>, String>((
  ref,
  questionId,
) async {
  final repo = ref.watch(questionRepositoryProvider);
  return repo.fetchSmaczki(questionId);
});

/// Tracks which question in the loaded list is currently shown.
///
/// The "wind" swipe simply advances this index; the view animates the text
/// transition in response to the change. Wraps around at both ends.
class QuestionDeckNotifier extends Notifier<int> {
  @override
  int build() => 0;

  // read, NOT watch: this is a one-off length lookup inside an action. Watching
  // here would subscribe the index notifier to the deck, so a pool refetch
  // (e.g. when an ad unlock invalidates questionsProvider) would rebuild this
  // notifier and reset the index to 0 — snapping the user back to the daily
  // instead of leaving them on the question they just unlocked.
  int get _length => ref.read(questionDeckProvider).length;

  /// Premium-only wrap-around forward (the full catalog is a loop).
  void next() {
    final length = _length;
    if (length == 0) return;
    state = (state + 1) % length;
  }

  /// Premium-only wrap-around backward.
  void previous() {
    final length = _length;
    if (length == 0) return;
    state = (state - 1 + length) % length;
  }

  /// Free-feed forward: advance by one WITHOUT wrapping, allowing exactly one
  /// step past the last item onto the "reveal slot" (index == length), where the
  /// paywall / auto-credit reveal kicks in. A no-op once already at the slot.
  void forwardLinear() {
    final length = _length;
    if (state < length) state = state + 1;
  }

  /// Free-feed backward: step back through this session's revealed questions,
  /// clamped at the daily (index 0). Also the way back off the reveal slot.
  void backLinear() {
    if (state > 0) state = state - 1;
  }

  /// Jumps straight back to the daily, which the deck always keeps at index 0
  /// (see [questionDeckProvider]). This is the escape hatch for a free user who
  /// swiped onto the reveal slot and doesn't want to watch an ad: instead of
  /// being stuck on the paywall, they can return to the free daily in one tap.
  void toDaily() => state = 0;
}

/// Index of the currently displayed question.
final questionIndexProvider = NotifierProvider<QuestionDeckNotifier, int>(
  QuestionDeckNotifier.new,
);

/// Today's PERSONAL daily question (drawn server-side for the user's local
/// date from the questions they haven't voted on yet, stable for the day).
///
/// Captures "now" once when first read, so it does not refetch on every rebuild
/// the way `dailyQuestionProvider(DateTime.now())` would (a fresh DateTime is a
/// fresh family key). This is the free, no-paywall question every user opens to.
final todaysDailyQuestionProvider = FutureProvider<Question?>((ref) async {
  // See questionsProvider: wait out the session's first load so the daily is
  // fetched once with the final identity/premium instead of flashing the
  // placeholder-identity fetch and reloading the moment the session resolves.
  if (ref.watch(sessionProvider.select((s) => s.isLoading))) return null;
  final repo = ref.watch(questionRepositoryProvider);
  return repo.fetchDailyQuestion(DateTime.now());
});

/// The community vote split (TAK/NIE) plus the caller's own vote for a question.
///
/// Keyed by question id so each question caches its own state. The daily vote
/// panel watches this to decide between showing the vote buttons (`myChoice`
/// null) or the result bars. After casting, the panel holds the fresh result
/// returned by the RPC, so it does not need to invalidate this to update — but
/// invalidating it forces a re-read when desired.
final dailyVoteStateProvider = FutureProvider.family<VoteResult, String>((
  ref,
  questionId,
) async {
  final repo = ref.watch(questionRepositoryProvider);
  return repo.getDailyVoteState(questionId);
});

/// The PRO "question history": every question the user voted on with its
/// community vote split, newest vote first. Empty for non-premium (the RPC
/// returns no rows; the screen shows a PRO upsell).
///
/// autoDispose so each open of the history screen pulls a fresh snapshot — the
/// tallies keep moving — and nothing lingers in memory after it closes. The repo
/// it watches already carries the active locale, so switching language refetches.
final voteHistoryProvider = FutureProvider.autoDispose<List<VoteHistoryEntry>>((
  ref,
) async {
  final repo = ref.watch(questionRepositoryProvider);
  return repo.fetchVoteHistory();
});

/// A shuffle seed fixed once per app launch.
///
/// A [Provider] is computed lazily and then cached for the life of its
/// container, so this picks a fresh random seed exactly once each time the app
/// starts (a new [ProviderContainer]) and keeps returning it for the rest of
/// the session. That gives the deck order two properties at once:
///
///   * fresh on every relaunch — reopening the app reshuffles the tail, so the
///     non-daily questions appear in a different order each visit;
///   * stable within a session — an unlock invalidates [questionsProvider] to
///     pick up the now-readable text, and because the seed is unchanged the
///     deck does NOT reshuffle, so the user stays on the question they unlocked.
///
/// Override it in tests to make the order deterministic.
final deckShuffleSeedProvider = Provider<int>(
  (ref) => Random().nextInt(1 << 32),
);

/// The questions a free user has revealed THIS session, in the order they were
/// revealed. Held only in memory: revealed text is no longer re-readable through
/// the gate, so it lives here until the app closes (then it is gone — not
/// re-readable, not re-served). Each reveal RPC appends one question.
class RevealedFeedNotifier extends Notifier<List<Question>> {
  @override
  List<Question> build() => const [];

  void append(Question q) => state = [...state, q];

  void clear() => state = const [];
}

final revealedFeedProvider =
    NotifierProvider<RevealedFeedNotifier, List<Question>>(
      RevealedFeedNotifier.new,
    );

/// The ordered deck the home screen walks through.
///
/// Position 0 is always today's daily. PREMIUM gets the whole catalog after it,
/// ordered UNSEEN-FIRST so fresh questions surface before the archive (each is
/// recorded as seen the moment they land on it — see `markQuestionSeen`). A FREE
/// user instead gets a forward "feed": the daily plus the questions they've
/// revealed this session (one ad / credit at a time), and nothing else — the
/// locked catalog is never shipped to them.
///
/// While the daily is still loading the deck stays empty on purpose, so the
/// screen shows its spinner rather than flashing a non-daily question first.
final questionDeckProvider = Provider<List<Question>>((ref) {
  final dailyAsync = ref.watch(todaysDailyQuestionProvider);
  if (dailyAsync.isLoading) return const [];
  final daily = dailyAsync.asData?.value;

  if (ref.watch(isPremiumProvider)) {
    final pool =
        ref.watch(questionsProvider).asData?.value ?? const <Question>[];
    final seed = ref.watch(deckShuffleSeedProvider);

    // Order unseen-before-seen, shuffling each group with the per-launch seed:
    // random each open, STABLE across refetches within the session so the user
    // isn't jumped around. The `seen` flags are read once at fetch time and we do
    // NOT refetch the pool when marking a question seen mid-session, so walking
    // forward keeps the unseen run intact (newly-marked questions only move to the
    // archive on the NEXT launch). Done even when the daily fails to resolve —
    // otherwise the deck would fall back to the raw catalog order (created_at),
    // the "questions feel sequential" symptom.
    List<Question> orderedUnseenFirst(Iterable<Question> qs) {
      final list = qs.toList();
      final unseen = list.where((q) => !q.seen).toList()..shuffle(Random(seed));
      final seen = list.where((q) => q.seen).toList()..shuffle(Random(seed));
      return [...unseen, ...seen];
    }

    if (daily == null) return orderedUnseenFirst(pool);
    return [daily, ...orderedUnseenFirst(pool.where((q) => q.id != daily.id))];
  }

  final revealed = ref.watch(revealedFeedProvider);
  if (daily == null) return revealed;
  return [daily, ...revealed];
});

/// The single question to render, or null when there is nothing to show.
///
/// For a free user the index may sit one past the last item — the "reveal slot"
/// — where there is no question yet (the paywall / auto-reveal shows instead);
/// that returns null. Premium wraps around its catalog and never hits the slot.
final currentQuestionProvider = Provider<Question?>((ref) {
  final deck = ref.watch(questionDeckProvider);
  if (deck.isEmpty) return null;
  final index = ref.watch(questionIndexProvider);
  if (ref.watch(isPremiumProvider)) return deck[index % deck.length];
  if (index >= deck.length) return null; // the reveal slot
  return deck[index];
});

/// True when a free user has swiped one step past the last revealed question and
/// is sitting on the reveal slot (where the paywall / auto-credit reveal lives).
final isAtRevealSlotProvider = Provider<bool>((ref) {
  if (ref.watch(isPremiumProvider)) return false;
  final deck = ref.watch(questionDeckProvider);
  if (deck.isEmpty) return false;
  return ref.watch(questionIndexProvider) >= deck.length;
});

/// Whether the question currently on screen is today's free (personal) daily.
///
/// True only when the visible question's id matches the served daily. The
/// daily shares its id with its deck entry (both the mock list and the
/// `get_daily_question` RPC return the same id), so an id comparison is enough
/// and stays correct even if the deck wraps around.
final isShowingDailyProvider = Provider<bool>((ref) {
  final current = ref.watch(currentQuestionProvider);
  final daily = ref.watch(todaysDailyQuestionProvider).asData?.value;
  if (current == null || daily == null) return false;
  return current.id == daily.id;
});
