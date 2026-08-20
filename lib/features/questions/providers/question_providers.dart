import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/app_locale.dart';
import '../../../core/startup/supabase_init_provider.dart';
import '../../../data/models/conformity_stats.dart';
import '../../../data/models/debate_profile.dart';
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
/// The branch is on [SupabaseInitStatus], NOT on `SupabaseService.isInitialised`.
/// Those look interchangeable and are not: a build WITH credentials whose init
/// failed also reads as "not initialised", and answering that with mock data
/// gave real users a fake app — invented questions, a fabricated split, a
/// frozen streak, and every vote thrown away without a word. Mock data is only
/// ever correct when there is no backend configured at all; a backend that is
/// configured but down is an error to surface (see [HomeGate]), so this throws
/// rather than substituting fiction for it.
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
  final status = ref.watch(supabaseInitProvider);
  if (status == SupabaseInitStatus.notConfigured) {
    return MockQuestionRepository();
  }
  if (status == SupabaseInitStatus.failed) {
    throw const SupabaseUnavailableException();
  }
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

/// Loads the full question catalog once — for PREMIUM users only. The free
/// tier's whole deck is the personal daily (the day wall stands where the
/// catalog would continue), so a non-premium read gets an empty list without
/// any fetch (defense in depth: the server withholds the text anyway).
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
  // Watching the flag here (not just via the repo) makes the pool load the
  // moment premium flips true — right as the home gate swaps the paywall out
  // for the feed.
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
/// gates server-side: premium reads everything; a free user gets readable text
/// only AFTER voting, and then exactly the argument aimed at them. Instantiate
/// this family only post-vote (pre-vote, warm [smaczkiMetaProvider] instead) —
/// that discipline is what keeps a free device at one readable argument.
/// Keyed by question id so each question caches its own set; invalidate it
/// after a purchase to re-fetch the now-unlocked text.
final smaczkiProvider = FutureProvider.family<List<Smaczek>, String>((
  ref,
  questionId,
) async {
  // The DEV custom pin has no server row and the RPC's uuid param would choke
  // on its synthetic id — an empty list renders the "no smaczki" sheet.
  if (questionId == kDevCustomQuestionId) return const <Smaczek>[];
  final repo = ref.watch(questionRepositoryProvider);
  return repo.fetchSmaczki(questionId);
});

/// The pre-vote smaczki prefetch: positions + rough lengths via
/// `get_question_smaczki_meta` — no text column even exists in the response,
/// so warming this while the user reads the question can't leak an argument.
final smaczkiMetaProvider = FutureProvider.family<List<SmaczekMeta>, String>((
  ref,
  questionId,
) async {
  if (questionId == kDevCustomQuestionId) return const <SmaczekMeta>[];
  final repo = ref.watch(questionRepositoryProvider);
  return repo.fetchSmaczkiMeta(questionId);
});

/// The highest deck index reached this session — how far forward the user has
/// ever been, regardless of where they've since swiped back to. Drives the
/// "back to the latest" jump (see [canJumpToLatestProvider] and
/// [QuestionDeckNotifier.toLatest]), so someone who stepped back five questions
/// returns in one tap instead of five forward swipes. Only [QuestionDeckNotifier]
/// bumps it; reset alongside the index on an identity switch.
class FurthestIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump(int index) {
    if (index > state) state = index;
  }

  void reset() => state = 0;
}

final furthestIndexProvider = NotifierProvider<FurthestIndexNotifier, int>(
  FurthestIndexNotifier.new,
);

/// Tracks which question in the loaded list is currently shown.
///
/// The "wind" swipe simply advances this index; the view animates the text
/// transition in response to the change. Forward wraps (the catalog is a
/// loop); backward is clamped at the daily, so a right swipe steps back
/// through what was already on screen and stops at index 0.
class QuestionDeckNotifier extends Notifier<int> {
  @override
  int build() => 0;

  // read, NOT watch: this is a one-off length lookup inside an action. Watching
  // here would subscribe the index notifier to the deck, so a pool refetch
  // would rebuild this notifier and reset the index to 0 — snapping the user
  // back to the daily instead of leaving them on the question they were reading.
  int get _length => ref.read(questionDeckProvider).length;

  void _bumpFurthest() => ref.read(furthestIndexProvider.notifier).bump(state);

  /// Wrap-around forward (the full catalog is a loop).
  void next() {
    final length = _length;
    if (length == 0) return;
    state = (state + 1) % length;
    _bumpFurthest();
  }

  /// Step back by one, clamped at the daily (index 0) — retraces the stable
  /// per-launch deck order, which IS the order the user just read.
  void backLinear() {
    if (state > 0) state = state - 1;
  }

  /// Jumps straight back to the daily, which the deck always keeps at index 0
  /// (see [questionDeckProvider]) — used on an identity switch so a fresh user
  /// starts at their own daily.
  void toDaily() => state = 0;

  /// Jumps forward to the furthest question reached this session — the "undo"
  /// for a run of back swipes.
  void toLatest() {
    final length = _length;
    if (length == 0) return;
    final furthest = ref.read(furthestIndexProvider);
    state = min(furthest, length - 1);
  }

  /// DEV tools only: shows the question at [index], clamped to the deck.
  void jumpTo(int index) {
    final length = _length;
    if (length == 0) return;
    state = index.clamp(0, length - 1);
    _bumpFurthest();
  }
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

/// How long a question counts as "new" after being added to the catalog.
///
/// Two weeks: long enough for the community split to firm up, after which a
/// thin vote count no longer needs the "it's just new" explanation.
const Duration kNewQuestionWindow = Duration(days: 14);

/// Ids of active questions added within [kNewQuestionWindow] — the questions
/// that wear the small "Nowe" badge over the feed.
///
/// One cheap ids-only read per session (per repo rebuild). Best-effort by
/// design: the badge is decoration, so any failure degrades to an empty set
/// rather than surfacing an error anywhere.
final newQuestionIdsProvider = FutureProvider<Set<String>>((ref) async {
  final repo = ref.watch(questionRepositoryProvider);
  try {
    return await repo.fetchRecentQuestionIds(
      since: DateTime.now().subtract(kNewQuestionWindow),
    );
  } catch (_) {
    return const <String>{};
  }
});

/// Whether the question currently on screen is fresh enough to wear the
/// "Nowe" badge. False for locked teasers (the badge would date the paywalled
/// text) and while the id set is still loading.
final currentQuestionIsNewProvider = Provider<bool>((ref) {
  final current = ref.watch(currentQuestionProvider);
  if (current == null || current.isLocked == true) return false;
  final ids = ref.watch(newQuestionIdsProvider).asData?.value;
  return ids != null && ids.contains(current.id);
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
  // The DEV custom pin has no server row and the RPC's uuid param would choke
  // on its synthetic id — "not voted" shows the vote buttons for the preview.
  if (questionId == kDevCustomQuestionId) return VoteResult.empty;
  final repo = ref.watch(questionRepositoryProvider);
  return repo.getDailyVoteState(questionId);
});

/// The "question history": every question the user voted on with its
/// community vote split, newest vote first. Non-premium gets only the last 48
/// hours from the RPC (the always-free daily); the screen trims that to the
/// local today and shows the older record as a locked PRO panel.
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

/// The caller's conformity stats (votes with the majority vs the minority) —
/// the data behind the top-bar axis panel.
///
/// PREFETCHED: the question screen watches this for its whole lifetime, so
/// the value is already resolved when the panel opens — no spinner. Freshness
/// is by invalidation, not refetch-per-open: after every cast vote, on an
/// identity switch and on the offline→online edge (all in QuestionScreen /
/// DailyVotePanel). Still autoDispose so nothing lingers once the screen
/// itself is gone. Not premium-gated: the server counts only the caller's
/// own votes.
final conformityStatsProvider = FutureProvider.autoDispose<ConformityStats>((
  ref,
) async {
  final repo = ref.watch(questionRepositoryProvider);
  return repo.fetchConformityStats();
});

/// The caller's debate profile (both axes + live boundaries) — the 2×2 grid
/// rendered UNDER the conformity axis in the same panel.
///
/// Prefetched and refreshed exactly like [conformityStatsProvider] (the
/// question screen holds the subscription; votes / identity switches /
/// reconnects invalidate). Not premium-gated: the TYPE is free by design —
/// only the depth behind it (trend, categories, moved list) is PRO.
final debateProfileProvider = FutureProvider.autoDispose<DebateProfile>((
  ref,
) async {
  final repo = ref.watch(questionRepositoryProvider);
  return repo.fetchDebateProfile();
});

/// PRO: the profile's per-month trend. Fetched only when the panel's PRO
/// section actually renders (premium caller) — the server throws
/// 'premium required' otherwise.
final profileTrendProvider =
    FutureProvider.autoDispose<List<ProfileTrendPoint>>((ref) async {
      final repo = ref.watch(questionRepositoryProvider);
      return repo.fetchProfileTrend();
    });

/// PRO: what share of unlocked profiles lands in the caller's 2×2 cell.
/// Null (block hidden) below the server's population floor.
final typeRarityProvider = FutureProvider.autoDispose<int?>((ref) async {
  final repo = ref.watch(questionRepositoryProvider);
  return repo.fetchTypeRarity();
});

/// PRO: the arguments that flipped the caller, newest first.
final movedSmaczkiProvider = FutureProvider.autoDispose<List<MovedSmaczek>>((
  ref,
) async {
  final repo = ref.watch(questionRepositoryProvider);
  return repo.fetchMovedSmaczki();
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

/// Id of the synthetic "własne pytanie" pin from the DEV tools screen. Never a
/// real catalog row: the vote/smaczki RPCs take `uuid` params, so this id must
/// be short-circuited client-side (see [dailyVoteStateProvider],
/// [smaczkiProvider] and the vote cast in DailyVotePanel) rather than sent to
/// the server, where it fails the uuid cast outright instead of returning
/// "no rows".
const String kDevCustomQuestionId = 'dev-custom';

/// DEV tools only: a question pinned from the settings DEV screen so a tester
/// can put any question on the home screen. Null in normal use — the deck is
/// untouched then. In-memory only; gone on restart.
class DevPinnedQuestionNotifier extends Notifier<Question?> {
  @override
  Question? build() => null;

  void pin(Question q) => state = q;

  void unpin() => state = null;
}

final devPinnedQuestionProvider =
    NotifierProvider<DevPinnedQuestionNotifier, Question?>(
      DevPinnedQuestionNotifier.new,
    );

/// The ordered deck the home screen walks through.
///
/// Position 0 is always today's daily; for PREMIUM users the whole catalog
/// follows, ordered UNSEEN-FIRST so fresh questions surface before the archive
/// (each is recorded as seen the moment the user lands on it — see
/// `markQuestionSeen`). For a FREE user the pool is empty, so the deck is just
/// the daily — swiping forward off it lands on the day wall (see
/// [dayWallVisibleProvider]), which is a visual state over the feed, not a
/// deck entry.
///
/// While the daily is still loading the deck stays empty on purpose, so the
/// screen shows its spinner rather than flashing a non-daily question first.
final questionDeckProvider = Provider<List<Question>>((ref) {
  final dailyAsync = ref.watch(todaysDailyQuestionProvider);
  if (dailyAsync.isLoading) return const [];
  final daily = dailyAsync.asData?.value;

  // DEV tools only: a pinned question slots in right after the daily, so index
  // 0 stays the daily and toDaily()/isShowingDaily keep their meaning. Null in
  // normal use, leaving the deck exactly as built below.
  List<Question> withDevPin(List<Question> deck) {
    final pinned = ref.watch(devPinnedQuestionProvider);
    if (pinned == null) return deck;
    final rest = deck.where((q) => q.id != pinned.id).toList();
    final at = rest.isEmpty ? 0 : 1;
    return [...rest.take(at), pinned, ...rest.skip(at)];
  }

  final pool = ref.watch(questionsProvider).asData?.value ?? const <Question>[];
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

  if (daily == null) return withDevPin(orderedUnseenFirst(pool));
  return withDevPin([
    daily,
    ...orderedUnseenFirst(pool.where((q) => q.id != daily.id)),
  ]);
});

/// The single question to render, or null while the deck is still empty. The
/// index wraps around the catalog (the deck is a loop).
final currentQuestionProvider = Provider<Question?>((ref) {
  final deck = ref.watch(questionDeckProvider);
  if (deck.isEmpty) return null;
  final index = ref.watch(questionIndexProvider);
  return deck[index % deck.length];
});

/// True when the user has swiped back from the furthest question they reached
/// this session — i.e. a one-tap "back to the latest" jump would move them
/// forward.
final canJumpToLatestProvider = Provider<bool>((ref) {
  final deck = ref.watch(questionDeckProvider);
  if (deck.isEmpty) return false;
  final index = ref.watch(questionIndexProvider);
  final furthest = min(ref.watch(furthestIndexProvider), deck.length - 1);
  return index < furthest;
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

/// Whether the free tier's day wall currently covers the feed.
///
/// The wall is a VISUAL STATE over the feed, not a deck entry: a free user's
/// forward swipe off the daily shows it, a back swipe (or "come back
/// tomorrow") hides it. Anything that reshapes the feed resets it to hidden —
/// a premium flip (the wall is a free-tier surface) and every re-resolve of
/// the daily (midnight rollover, identity switch, offline→online refetch) —
/// by watching those providers in [build].
class DayWallVisibleNotifier extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(isPremiumProvider);
    ref.watch(todaysDailyQuestionProvider);
    return false;
  }

  void show() => state = true;

  void hide() => state = false;
}

final dayWallVisibleProvider = NotifierProvider<DayWallVisibleNotifier, bool>(
  DayWallVisibleNotifier.new,
);

/// Teaser of the next question waiting behind the wall — the first few words
/// the server is willing to show a free user (see `peek_next_question`, a pure
/// read that consumes nothing). Excludes the served daily so the wall never
/// teases the question sitting right behind the back swipe.
///
/// Deliberately NOT autoDispose: QuestionBody warms it while the free user is
/// still on the feed, so the wall arrives with the teaser already readable
/// instead of popping it in a beat after the RPC returns. The cached pick then
/// holds for the day — every wall visit shows the same tease — and refetches
/// whenever the daily re-resolves (midnight rollover, identity switch).
final wallTeaserProvider = FutureProvider<String?>((ref) async {
  // Await the daily rather than reading its snapshot: peeking before it lands
  // would fetch without the exclusion and refetch moments later.
  final daily = await ref.watch(todaysDailyQuestionProvider.future);
  if (daily == null) return null;
  final repo = ref.watch(questionRepositoryProvider);
  return repo.peekNextQuestion(excludeIds: [daily.id]);
});

/// The local calendar day the current daily was (re)fetched for.
///
/// [todaysDailyQuestionProvider] deliberately captures "now" once per build so
/// it doesn't refetch on every rebuild — which also means an app left open
/// across local midnight would keep serving yesterday's daily forever. This
/// provider recomputes alongside it, so comparing its value against today (see
/// [maybeRolloverDaily]) detects exactly that staleness.
final dailyFetchDayProvider = Provider<String>((ref) {
  ref.watch(todaysDailyQuestionProvider);
  return dateOnlyKey(DateTime.now());
});

/// Rolls the feed over to the new local day when the daily on screen was
/// fetched for a date that has since passed — the "app left open across
/// midnight" fix, called from the day wall's countdown and the feed's
/// lifecycle watcher. A no-op while the fetch day is still today, so it is
/// safe to call every tick.
///
/// Invalidating [todaysDailyQuestionProvider] re-draws the daily for the new
/// date (the server assigns per LOCAL date), drops the stale vote snapshots,
/// and — via the notifier's watch — hides the day wall; the index snaps back
/// so every tier opens the new day on its daily.
void maybeRolloverDaily(WidgetRef ref) {
  if (ref.read(dailyFetchDayProvider) == dateOnlyKey(DateTime.now())) return;
  ref.invalidate(todaysDailyQuestionProvider);
  ref.invalidate(dailyVoteStateProvider);
  ref.invalidate(questionsProvider);
  ref.read(questionIndexProvider.notifier).toDaily();
  ref.read(furthestIndexProvider.notifier).reset();
}
