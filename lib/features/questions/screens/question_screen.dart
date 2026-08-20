import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/content_width.dart';
import '../../../core/locale/l10n_extension.dart';
import '../../../core/monitoring/monitoring.dart';
import '../../../core/network/connectivity_providers.dart';
import '../../../services/question_cache.dart';
import '../../account/providers/session_providers.dart';
import '../../account/providers/stats_providers.dart';
import '../../settings/screens/settings_screen.dart';
import '../providers/question_providers.dart';
import '../widgets/challenge_session_watcher.dart';
import '../widgets/conformity_panel.dart';
import '../widgets/daily_rollover_watcher.dart';
import '../widgets/load_error.dart';
import '../widgets/offline_banner.dart';
import '../widgets/question_body.dart';
import '../widgets/rank_up_sheet.dart';
import '../widgets/stat_chips.dart';
import '../widgets/streak_up_celebration.dart';

/// The home screen: a single styled question centred on a clean canvas, with a
/// settings gear top-right and a small info icon just above the question.
class QuestionScreen extends ConsumerWidget {
  const QuestionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep the session warm (the home gate already resolved it) and sync the
    // user's engagement state — the streak chip and rank ride on it.
    ref.watch(sessionProvider);
    ref.watch(userStatsProvider);

    // Prefetch the conformity axis + debate profile and hold the
    // subscriptions for the screen's lifetime, so opening the panel shows
    // data instantly instead of a spinner. Freshness comes from invalidation
    // (after a vote, on identity switch, on reconnect), not from autoDispose
    // refetch-per-open.
    ref.watch(conformityStatsProvider);
    ref.watch(debateProfileProvider);

    // A failed `get_debate_profile` makes the flagship feature disappear with
    // no error state, no toast and no exception — the first signal that it
    // regressed would be a store review. It stays silent on SCREEN by design
    // (the axis above it stands on its own, and a stat panel is not worth a
    // dead end), so the failure has to be loud somewhere else.
    //
    // The listen belongs HERE rather than on the panel: `WidgetRef.listen` has
    // no `fireImmediately`, so it only ever sees transitions that happen while
    // it is registered. This is the site that triggers the first fetch, so it
    // is the only one guaranteed to be listening when the first error lands.
    ref.listen(debateProfileProvider, (_, next) {
      final error = next.error;
      if (error == null) return;
      unawaited(
        Monitoring.captureException(
          error,
          stackTrace: next.stackTrace,
          feature: 'debate_profile',
        ),
      );
    });

    // The daily's failure modes are not equal, and only ONE of them is an
    // exception. A dead pick, a gap in `daily_picks`, an exhausted calendar or
    // a cron that never ran all end the same way: the server falls back to the
    // personal draw and returns HTTP 200 with a real question — degraded, but
    // nothing to report. A THROW here is the different case: the daily didn't
    // load at all, and the deck has nothing to open onto.
    //
    // That case is not silent on screen — it shows [LoadError] with a retry —
    // but a retry button looks identical whether one user's wifi died or
    // `get_daily_question` is failing for everyone, and nobody is watching the
    // second one. It never left the device before. (Same registration rule as
    // the profile listener above: `WidgetRef.listen` has no `fireImmediately`,
    // and this build is what kicks off the first daily fetch — see the
    // `ref.watch(todaysDailyQuestionProvider)` further down — so the listener
    // is in place before the error it has to catch. The retry re-invalidates
    // while this screen is still mounted, so repeat failures land too.)
    ref.listen(todaysDailyQuestionProvider, (_, next) {
      final error = next.error;
      if (error == null) return;
      // A user on a train is not an incident — but that filter is NOT repeated
      // here: [Monitoring.captureException] drops connectivity errors itself,
      // deliberately in one place, so this call site stays a plain "report it".
      unawaited(
        Monitoring.captureException(
          error,
          stackTrace: next.stackTrace,
          feature: 'daily_question',
        ),
      );
    });

    // When the signed-in identity changes (log in / log out / account switch),
    // drop every per-user cache so the new user never inherits the previous
    // one's daily vote, unlocked text or smaczki. Providers keyed only on
    // question id (e.g. dailyVoteStateProvider) otherwise keep serving the prior
    // user's answer until the app restarts — which is why a logged-out user still
    // saw their daily vote. (userStatsProvider already watches the session, so it
    // refreshes on its own.)
    ref.listen(sessionProvider.select((s) => s.value?.userId), (prev, next) {
      // React only to a genuine identity SWITCH (log in / log out / account
      // change) — NOT the initial null→guest resolution at launch. Skipping that
      // first transition is what removes the double reload: the question fetches
      // already wait for the session to resolve (see todaysDailyQuestionProvider),
      // so invalidating here on the very same resolution would refetch everything
      // a second time and flash the deck.
      if (prev == null || prev == next) return;
      ref.invalidate(questionsProvider);
      ref.invalidate(todaysDailyQuestionProvider);
      ref.invalidate(dailyVoteStateProvider);
      ref.invalidate(smaczkiProvider);
      ref.invalidate(smaczkiMetaProvider);
      ref.invalidate(conformityStatsProvider);
      ref.invalidate(debateProfileProvider);
      // Snap back to the daily so a new user never inherits the previous
      // user's position in the deck.
      ref.read(questionIndexProvider.notifier).toDaily();
      ref.read(furthestIndexProvider.notifier).reset();
    });

    // Record each question the user lands on in the seen-memory — that's what
    // lets the next launch surface UNSEEN questions first instead of looping
    // the same ones forever. Premium-guarded for the lapse edge (the gate
    // swaps the feed out on the next frame); the daily is skipped here
    // (get_daily_question records it). Fire-and-forget: the repo swallows
    // errors, and we deliberately do NOT refetch the pool, so the current
    // session's deck order stays put.
    ref.listen(currentQuestionProvider, (prev, next) {
      if (next == null || next.isLocked == true) return;
      if (prev?.id == next.id) return;
      if (!ref.read(isPremiumProvider)) return;
      final daily = ref.read(todaysDailyQuestionProvider).asData?.value;
      if (daily != null && next.id == daily.id) return;
      ref.read(questionRepositoryProvider).markQuestionSeen(next.id);
    });

    // When connectivity returns after an outage, re-run the launch fetches so a
    // user who opened on cached content (or hit the offline error screen)
    // converges on fresh data without needing to tap "retry" or relaunch. Only
    // fires on the offline→online edge, so a normal online session never
    // refetches. The session refresh also re-reconciles premium, which reshapes
    // the deck if an entitlement changed while offline.
    ref.listen(isOnlineValueProvider, (wasOnline, isOnline) {
      if (wasOnline == false && isOnline == true) {
        // refresh() (not invalidate) so the session reload doesn't flash to
        // loading — that would null userId and trip the identity listener above,
        // wiping the revealed feed and snapping back to the daily.
        ref.read(sessionProvider.notifier).refresh();
        ref.invalidate(questionsProvider);
        ref.invalidate(todaysDailyQuestionProvider);
        ref.invalidate(userStatsProvider);
        // Swap the offline "you voted X" snapshot back for the live community
        // split now that we can reach the server.
        ref.invalidate(dailyVoteStateProvider);
        // The prefetched conformity axis + profile failed while offline —
        // retry them now so the panel has data (not a stale error) by the
        // time it's opened.
        ref.invalidate(conformityStatsProvider);
        ref.invalidate(debateProfileProvider);
      }
    });

    // Clear the cached content the moment premium lapses (true→false) so a former
    // subscriber can't keep reading the full catalog offline. Belt-and-suspenders
    // on top of the caching repo's read-time premium guard and the next online
    // refetch (which overwrites the cache with the now-locked free shape).
    ref.listen(isPremiumProvider, (wasPremium, isPremium) {
      if (wasPremium == true && isPremium == false) {
        ref.read(questionCacheProvider).clearContent();
      }
      // Either flip rebuilds the deck into a different shape (free feed vs full
      // catalog), so the furthest-reached position no longer refers to the same
      // questions — drop it rather than let "back to the latest" jump to an
      // arbitrary index of the new deck. It re-arms on the next forward swipe.
      if (wasPremium != null && wasPremium != isPremium) {
        ref.read(furthestIndexProvider.notifier).reset();
      }
    });

    // Drives the offline strip under the app bar. A hint only — the cached
    // content still renders; a failed request is the real offline signal.
    final isOnline = ref.watch(isOnlineValueProvider);

    // The deck drives the body: it stays empty until today's daily resolves, so
    // every user opens to the daily rather than a flash of the pool. Watching it
    // here also kicks off the daily fetch at launch, alongside the question pool.
    // Either fetch failing leaves the deck empty; surface BOTH so an offline
    // launch shows a retry instead of an endless spinner (the daily's error in
    // particular never reached the UI before, so the deck just stayed empty).
    final poolAsync = ref.watch(questionsProvider);
    final dailyAsync = ref.watch(todaysDailyQuestionProvider);
    final loadError = poolAsync.error ?? dailyAsync.error;
    final deck = ref.watch(questionDeckProvider);
    // An empty deck only means "still loading" while a fetch is actually in
    // flight. Once BOTH have RESOLVED and the deck is still empty, nothing is
    // ever coming: the daily RPC returned no row and the free pool is empty by
    // design. That happens for real — a failed anonymous sign-in leaves
    // `ensureSignedIn` returning null, so `get_daily_question` sees no uid and
    // returns nothing (Supabase rate-limits anonymous sign-ups per IP, which a
    // carrier CGNAT or an office network reaches), and a question with no
    // translation in either language resolves to blank text. Without this the
    // screen sat on a spinner with no message and no retry, forever.
    final resolvedEmpty =
        deck.isEmpty &&
        dailyAsync.hasValue &&
        !dailyAsync.isLoading &&
        poolAsync.hasValue &&
        !poolAsync.isLoading;
    // Zero on phones; on wider screens it is how far the capped question column
    // sits from each edge, which the app-bar icons follow.
    final gutter = horizontalGutter(context);

    return Scaffold(
      // Let the body fill the whole screen so the question centres against the
      // true midpoint; the (transparent) app bar floats over the top.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        // Status cluster centred at the top: the streak flame (guests build a
        // streak on their anonymous identity too — the account nudge, not a
        // hidden chip, is what argues for signing in).
        automaticallyImplyLeading: false,
        // The StreakChip's rank-up flame burst overflows the toolbar bounds —
        // don't clip it mid-celebration.
        clipBehavior: Clip.none,
        // The offline strip rides in the app bar's `bottom` slot so it grows the
        // bar when offline and reserves no space when connected (rather than
        // overlaying the status chips).
        // The scale is handed in: `preferredSize` is read without a context,
        // and it is what the app bar actually reserves for the strip.
        bottom: isOnline
            ? null
            : OfflineBanner(
                textScale: MediaQuery.textScalerOf(context).scale(1),
              ),
        // Top-left: the conformity axis ("how often am I with the majority?").
        // Not tied to the visible question — it's a whole-history stat, so it
        // stays put while the deck swipes. (The favorites star moved down into
        // the pill row under the question, next to share.)
        // On a tablet the question column is capped and centred, so icons left
        // at the screen edges end up stranded a few hundred points away from the
        // content they belong to. Pull both of them in by the gutter (zero on
        // phones, so their layout is untouched); `leadingWidth` has to grow with
        // the padding or the 56pt leading slot would clip it.
        leadingWidth: 56 + gutter,
        leading: Padding(
          padding: EdgeInsets.only(left: 4 + gutter),
          child: const ConformityAxisButton(),
        ),
        centerTitle: true,
        title: const StreakChip(),
        // Top-right action: the person icon opens the profile hub for everyone.
        // A guest has a profile too (streak, rank, preferences ride the
        // anonymous identity); securing the account is a clearly-labelled
        // action INSIDE the profile, not a gate in front of it.
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: context.l10n.settingsTooltip,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
              );
            },
          ),
          if (gutter > 0) SizedBox(width: gutter),
        ],
      ),
      // Only treat a load error as fatal when there's genuinely nothing to show:
      // a transient pool error while the daily loaded fine still renders the
      // daily rather than blocking the whole screen.
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: deck.isEmpty && (loadError != null || resolvedEmpty)
                ? LoadError(
                    // A thrown fetch really is usually the network; a resolved
                    // but empty one is not, so don't send that user off to
                    // check their wifi. The retry is the same either way — it
                    // re-runs sign-in, which is what recovers the empty case.
                    body: loadError == null
                        ? context.l10n.loadErrorBodyEmpty
                        : null,
                    onRetry: () {
                      ref.invalidate(sessionProvider);
                      ref.invalidate(questionsProvider);
                      ref.invalidate(todaysDailyQuestionProvider);
                      ref.invalidate(userStatsProvider);
                    },
                  )
                : deck.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : const QuestionBody(),
          ),
          // Rolls the feed to the new local day (resume + slow tick) so an app
          // left open across midnight serves the fresh daily. Zero-size.
          const DailyRolloverWatcher(),
          // Feeds app-lifecycle changes into the challenge session, so 30+
          // minutes in the background re-arms the gate cap. Zero-size.
          const ChallengeSessionWatcher(),
          // Celebrates a rank climb (confetti + shareable card) the moment the
          // synced stats cross a tier — caught on launch and after a daily vote.
          // Zero-size; mounts here so it lives for the whole session.
          const RankCelebrationListener(),
          // The everyday "+1": flies a flame up into the streak chip whenever the
          // streak grows (and it isn't a promotion day, which the rank-up owns).
          const StreakCelebrationListener(),
        ],
      ),
    );
  }
}
