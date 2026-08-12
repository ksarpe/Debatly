import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/network/connectivity_providers.dart';
import '../../../services/question_cache.dart';
import '../../account/providers/session_providers.dart';
import '../../account/providers/stats_providers.dart';
import '../../monetization/providers/monetization_providers.dart';
import '../../settings/screens/settings_screen.dart';
import '../providers/question_providers.dart';
import '../widgets/favorite_star_button.dart';
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
    // Kick off silent anonymous auth + entitlement loading at launch, and start
    // pre-loading a rewarded ad so the unlock sheet is responsive the first time
    // a free user is gated. Reading them here is enough to instantiate them; the
    // daily question every user opens to is free.
    ref.watch(sessionProvider);
    ref.watch(rewardedAdServiceProvider);

    // Sync the user's engagement state once the session resolves. This drives
    // the streak + free-unlock chips AND performs today's free-credit top-up
    // (server-side, once per UTC day) — the replacement for the old random
    // bonus claim. Premium users get no credit; guests are signed in too.
    ref.watch(userStatsProvider);

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
      // Revealed questions are per-identity and held only in memory — drop them
      // and snap back to the daily so a new user never inherits the previous
      // user's feed.
      ref.read(revealedFeedProvider.notifier).clear();
      ref.read(questionIndexProvider.notifier).toDaily();
      ref.read(furthestIndexProvider.notifier).reset();
    });

    // Premium walks the whole catalog, so record each question it lands on in the
    // seen-memory — that's what lets the next launch surface UNSEEN questions
    // first instead of looping the same ones forever. Free users only ever reach
    // the daily + their reveals (both recorded server-side already), so this is
    // premium-only; the daily is also skipped here (get_daily_question records
    // it). Fire-and-forget: the repo swallows errors, and we deliberately do NOT
    // refetch the pool, so the current session's deck order stays put.
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
    final loadError =
        ref.watch(questionsProvider).error ??
        ref.watch(todaysDailyQuestionProvider).error;
    final deck = ref.watch(questionDeckProvider);

    // The question currently on screen drives the top-left favorite star: it
    // saves THIS question. Premium fills it; a free user's tap opens the paywall
    // (favorites are premium). Hidden when there's nothing readable to save (the
    // free reveal slot).
    final current = ref.watch(currentQuestionProvider);

    return Scaffold(
      // Let the body fill the whole screen so the question centres against the
      // true midpoint; the (transparent) app bar floats over the top.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        // Status cluster centred at the top. The streak flame shows for everyone
        // — guests vote and build a streak on their anonymous identity too (the
        // account nudge, not a hidden chip, is what argues for signing in); the
        // free-unlock chip self-hides off the daily / for guests.
        automaticallyImplyLeading: false,
        // The offline strip rides in the app bar's `bottom` slot so it grows the
        // bar when offline and reserves no space when connected (rather than
        // overlaying the status chips).
        bottom: isOnline ? null : const OfflineBanner(),
        leading: current != null
            ? Padding(
                padding: const EdgeInsets.only(left: 4),
                child: FavoriteStarButton(questionId: current.id),
              )
            : null,
        centerTitle: true,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [StreakChip(), FreeUnlockChip()],
        ),
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
        ],
      ),
      // Only treat a load error as fatal when there's genuinely nothing to show:
      // a transient pool error while the daily loaded fine still renders the
      // daily rather than blocking the whole screen.
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: deck.isEmpty && loadError != null
                ? LoadError(
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
