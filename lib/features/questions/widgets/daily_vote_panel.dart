import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feedback/app_toast.dart';
import '../../../core/locale/app_locale.dart' show sharedPreferencesProvider;
import '../../../core/locale/l10n_extension.dart';
import '../../../core/network/network_error.dart';
import '../../../data/models/rank.dart';
import '../../../data/models/vote_result.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../services/analytics.dart';
import '../../../services/reminder_scheduler.dart';
import '../../account/providers/stats_providers.dart';
import '../../account/widgets/secure_streak_prompt.dart';
import '../../settings/providers/reminder_providers.dart';
import '../../settings/providers/review_providers.dart';
import '../providers/question_providers.dart';
import 'suggest_question_nudge.dart';
import 'vote_visuals.dart';

/// The binary (TAK / NIE) vote shown under a question.
///
/// Before voting it shows the two buttons; after voting it shows the community
/// split as two bars with the user's own side highlighted. Give it a
/// `ValueKey(questionId)` so swiping to a new question resets its local state.
///
/// Shown under EVERY readable question, not only the daily — unlocking a
/// question and seeing how the crowd voted is the core feed hook. Since the
/// personal-daily migration the server advances the streak on ANY vote (once
/// per UTC day), so every vote runs the same side effects here: refresh the
/// stats chip, mark the reminder loop "voted today", maybe ask for a review.
/// [isDaily] only distinguishes the analytics event (the activation funnel
/// counts a vote on the served daily).
///
/// Guests vote too: every user — anonymous or not — has a stable Supabase UUID
/// (silent sign-in at launch), so the vote and the streak it advances are
/// recorded server-side either way. Signing in "secures" that identity rather
/// than gating the core mechanic; after a vote a guest with a streak worth
/// protecting is nudged to create an account (see [maybePromptSecureStreak]).
class DailyVotePanel extends ConsumerStatefulWidget {
  const DailyVotePanel({
    required this.questionId,
    this.isDaily = false,
    super.key,
  });

  final String questionId;

  /// True only for the served daily (deck position 0). Analytics-only since
  /// the personal-daily migration: it picks `daily_vote_cast` (the activation
  /// event) over `question_vote_cast`; the side effects run for every vote.
  final bool isDaily;

  @override
  ConsumerState<DailyVotePanel> createState() => _DailyVotePanelState();
}

class _DailyVotePanelState extends ConsumerState<DailyVotePanel> {
  /// The freshest result this session (from the cast RPC), preferred over the
  /// initially-loaded provider value so the bars appear without a refetch.
  VoteResult? _local;
  bool _busy = false;

  Future<void> _vote(int choice) async {
    if (_busy) return;
    // The DEV tools' custom pin isn't a server row — the cast RPC takes a uuid
    // and would just error. Fake a plausible split locally instead, so a tester
    // can preview the result bars too. Panel-local only; nothing is recorded.
    if (widget.questionId == kDevCustomQuestionId) {
      setState(
        () => _local = VoteResult(
          yesCount: choice == VoteResult.yes ? 61 : 60,
          noCount: choice == VoteResult.no ? 41 : 40,
          myChoice: choice,
        ),
      );
      return;
    }
    setState(() => _busy = true);
    // Captured before the await so we never read context across an async gap.
    final l10n = context.l10n;
    try {
      final result = await ref
          .read(questionRepositoryProvider)
          .castDailyVote(widget.questionId, choice);
      if (!mounted) return;
      final choiceLabel = choice == VoteResult.yes ? 'tak' : 'nie';
      // Persist the "already voted" state into the (non-autoDispose) provider, not
      // just this widget's `_local`. The panel unmounts when the user swipes off
      // the question, discarding `_local`; without this, returning to it would
      // re-read the provider's STALE pre-vote value and show the buttons again,
      // letting the user "vote" a second time. Invalidating forces a refetch of the
      // server's post-vote state (myChoice set → result bars on the next mount).
      ref.invalidate(dailyVoteStateProvider(widget.questionId));
      setState(() => _local = result);

      // Activation, the step the onboarding funnel drives toward, is a vote on
      // the served daily; feed votes get their own event.
      Analytics.log(widget.isDaily ? 'daily_vote_cast' : 'question_vote_cast', {
        'choice': choiceLabel,
      });
      // EVERY vote may move the streak now (server: once per UTC day), so the
      // engagement upkeep runs for all of them: refresh the streak chip, flip
      // today's reminder to a post-vote message, maybe ask for a review.
      ref.invalidate(userStatsProvider);
      await _refreshReminderAfterVote(result, l10n);
      await _maybeNudgeAfterVote();
    } catch (e) {
      if (!mounted) return;
      // Offline gets the calmer "no connection" line — the vote isn't lost, it
      // just needs a connection; any other failure is the generic vote error.
      AppToast.error(
        context,
        isOfflineError(e) ? context.l10n.noConnection : context.l10n.voteFailed,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A vote just counted for today (any question moves the streak now), so
  /// refresh the reminder loop.
  /// Stamps the local vote date — plus the share who disagreed with this vote,
  /// for the "X% disagreed with you today" nudge — then re-arms the loop, which
  /// now picks a post-vote message for today's slot instead of a "go vote" one.
  ///
  /// Best-effort: reminder upkeep must never break the vote, so a missing
  /// prefs/notification setup (dev/tests) is swallowed.
  Future<void> _refreshReminderAfterVote(
    VoteResult result,
    AppLocalizations l10n,
  ) async {
    try {
      final disagreePct = result.myChoice == VoteResult.yes
          ? result.noPct
          : result.yesPct;
      // Read both providers before the awaits: this panel unmounts the moment
      // the user swipes to the next question, and the upkeep should still
      // finish rather than throw on a dead `ref`.
      final reminder = ref.read(reminderControllerProvider.notifier);
      final prefs = ref.read(sharedPreferencesProvider);
      await reminder.markVotedToday(disagreePct: disagreePct);
      await rescheduleReminderLoop(prefs: prefs, l10n: l10n);
    } catch (_) {
      // Non-critical: the vote already counted; the reminder will self-correct
      // on the next launch / vote.
    }
  }

  /// After a successful vote — a natural high point, especially when it just
  /// extended a streak — run at most ONE follow-up prompt: first offer a guest
  /// the "secure your streak" account nudge; only when that doesn't show,
  /// consider the store-review ask. One dialog per vote, so the moment never
  /// turns into a gauntlet. Each prompt enforces its own milestone + cooldown,
  /// so the vast majority of votes ask for nothing.
  ///
  /// Best-effort and fired last: a prompt must never interfere with the vote
  /// that already counted, so any failure (offline stats refetch, missing prefs
  /// in tests) is swallowed.
  Future<void> _maybeNudgeAfterVote() async {
    try {
      // Count this vote toward the one-time "suggest a question" nudge before
      // any prompt below claims the moment — whichever one shows, the counter
      // must reflect the vote (the nudge then fires on the next one).
      await recordVoteForSuggestQuestionNudge(
        ref.read(sharedPreferencesProvider),
      );

      final stats = await ref.read(userStatsProvider.future);
      // Swiping away unmounts this panel; skipping the ask is always acceptable,
      // so bail rather than reach through a `ref` that's no longer usable.
      if (!mounted) return;
      final streak = stats?.currentStreak ?? 0;

      // On the day the streak crosses into a new rank, the rank-up celebration
      // (confetti + share card) owns the moment — neither prompt fires on top
      // of it. Both come around again on the next eligible day.
      final ladder = ref.read(ranksProvider).value ?? kDefaultRanks;
      final isPromotionDay = ladder.any(
        (r) => r.tier > 0 && r.minStreak == streak,
      );

      final nudged = await maybePromptSecureStreak(
        context,
        ref,
        streak: streak,
        isPromotionDay: isPromotionDay,
      );
      if (nudged || isPromotionDay) return;

      // The one-time "got an idea? send it in" toast — after the second vote,
      // once the loop has been felt. Skips the review ask when it shows, same
      // one-prompt-per-vote rule as above.
      if (!mounted) return;
      if (await maybePromptSuggestQuestion(context, ref)) return;

      await ref
          .read(reviewPromptControllerProvider.notifier)
          .maybePromptForStreak(streak);
    } catch (_) {
      // Non-critical: skipping the ask is always an acceptable outcome.
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(dailyVoteStateProvider(widget.questionId));
    final result = _local ?? async.value;

    // Until the state is known, reserve the space with a slim placeholder so the
    // overlay doesn't jump when the buttons/bars appear.
    if (result == null) {
      return const SizedBox(height: 52);
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: result.hasVoted
          ? VoteResultsRow(
              key: const ValueKey('results'),
              result: result,
              // Always spell out which side was mine under the bars...
              confirmMyVote: true,
              // ...and offline, withhold the (possibly stale) community split
              // until we're back online.
              communityHidden: result.fromCache,
            )
          : VoteButtonsRow(
              key: const ValueKey('buttons'),
              busy: _busy,
              onVote: _vote,
            ),
    );
  }
}
