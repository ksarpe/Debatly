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
import '../../account/providers/session_providers.dart';
import '../../account/providers/stats_providers.dart';
import '../../account/screens/auth_screen.dart';
import '../../settings/providers/reminder_providers.dart';
import '../../settings/providers/review_providers.dart';
import '../providers/question_providers.dart';
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
/// Guests see the buttons too, but may neither vote nor see the community split:
/// tapping either side sends them to the sign-in sheet instead of casting a vote.
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
      await _maybeAskForReview();
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

  /// After a successful vote — a natural high point, especially when it
  /// just extended a streak — consider asking for a store rating. The streak is
  /// read from the now-refreshed stats; the controller enforces the milestone +
  /// weekly cooldown, so the vast majority of votes ask for nothing.
  ///
  /// Best-effort and fired last: a rating ask must never interfere with the vote
  /// that already counted, so any failure (offline stats refetch, missing prefs
  /// in tests) is swallowed.
  Future<void> _maybeAskForReview() async {
    try {
      final stats = await ref.read(userStatsProvider.future);
      // Swiping away unmounts this panel; skipping the ask is always acceptable,
      // so bail rather than reach through a `ref` that's no longer usable.
      if (!mounted) return;
      final streak = stats?.currentStreak ?? 0;

      // On the day the streak crosses into a new rank, the rank-up celebration
      // (confetti + share card) owns the moment — don't stack the OS review
      // sheet on top of it. The very first review milestone (streak 3) lines up
      // exactly with the first promotion, so this collision is the common case,
      // not an edge one. The review ask comes around again on the next eligible
      // day per its own cooldown.
      final ladder = ref.read(ranksProvider).value ?? kDefaultRanks;
      final isPromotionDay = ladder.any(
        (r) => r.tier > 0 && r.minStreak == streak,
      );
      if (isPromotionDay) return;

      await ref
          .read(reviewPromptControllerProvider.notifier)
          .maybePromptForStreak(streak);
    } catch (_) {
      // Non-critical: skipping the ask is always an acceptable outcome.
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasAccount = ref.watch(
      sessionProvider.select((s) => s.value?.hasAccount ?? false),
    );

    // Guests: show the buttons but never the split. Tapping either side opens the
    // sign-in sheet rather than casting a vote — so no community % leaks out and
    // a vote is only ever recorded for a real account. (No provider read here, so
    // we don't even fetch the split for a guest.)
    if (!hasAccount) {
      return VoteButtonsRow(busy: false, onVote: (_) => showAuthSheet(context));
    }

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
