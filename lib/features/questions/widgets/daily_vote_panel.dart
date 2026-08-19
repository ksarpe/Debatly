import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feedback/app_toast.dart';
import '../../../core/locale/app_locale.dart' show sharedPreferencesProvider;
import '../../../core/locale/l10n_extension.dart';
import '../../../core/network/network_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/models/rank.dart';
import '../../../data/models/smaczek.dart';
import '../../../data/models/vote_result.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../services/analytics.dart';
import '../../../services/reminder_scheduler.dart';
import '../../account/providers/stats_providers.dart';
import '../../account/widgets/secure_streak_prompt.dart';
import '../../settings/providers/reminder_providers.dart';
import '../../settings/providers/review_providers.dart';
import '../providers/challenge_providers.dart';
import '../providers/question_providers.dart';
import 'prototype_history_entry.dart';
import 'smaczek_challenge_screen.dart';
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
      var result = await ref
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

      // Activation, the step the onboarding funnel drives toward, is a vote on
      // the served daily; feed votes get their own event.
      Analytics.log(widget.isDaily ? 'daily_vote_cast' : 'question_vote_cast', {
        'choice': choiceLabel,
      });

      // The argument comes BEFORE the percentages: the split stops being a fact
      // and becomes a verdict on whether the user held. `_local` is deliberately
      // still unset here — assigning it is what reveals the bars, so it waits
      // until the challenge is done with. The VOTE the user just cast is final:
      // the gate records its outcome on a separate axis and never re-casts.
      final challenged = await _runChallenge(choice);
      if (!mounted) return;
      if (challenged != null) result = challenged;
      setState(() => _local = result);
      // EVERY vote may move the streak now (server: once per UTC day), so the
      // engagement upkeep runs for all of them: refresh the streak chip, flip
      // today's reminder to a post-vote message, maybe ask for a review.
      ref.invalidate(userStatsProvider);
      // The vote just moved the conformity axis too; refresh it in the
      // background so the panel opens up-to-date without a spinner (the
      // question screen keeps it subscribed — see conformityStatsProvider).
      ref.invalidate(conformityStatsProvider);
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

  /// Runs the post-vote challenge: the argument aimed at the side the user just
  /// picked, dropped on them before the community split appears.
  ///
  /// The vote is FINAL before this runs — whatever happens in the gate, the
  /// choice on record never changes. The gate's answer (held / moved /
  /// dismissed, plus how long the user sat with the argument) is recorded on a
  /// separate axis via `record_smaczek_challenge`.
  ///
  /// Returns the freshest vote state when the outcome was persisted, or null
  /// when no gate ran (session cap, nothing readable, offline) or the record
  /// failed — the caller then keeps the split it already has. A skipped gate
  /// is a normal outcome, not an error: the percentages are the thing the user
  /// voted for, and they must never wait on a smaczek.
  Future<VoteResult?> _runChallenge(int choice) async {
    final session = ref.read(challengeSessionProvider.notifier);
    // The per-session valve for PRO: the fourth and later votes of a session
    // go straight to the percentages. Free users never reach it — they have
    // one question a day.
    if (session.capReached) {
      Analytics.log('smaczek_challenge_skipped', {
        'question_id': widget.questionId,
        'reason': 'session_cap',
      });
      return null;
    }

    final smaczek = await _resolveChallenger(choice);
    if (!mounted || smaczek == null) return null;

    // From the second gate of a session on, the beat is shortened: the text
    // appears whole and only the hit remains.
    final compact = session.nextIsCompact;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    session.recordShown();

    final challenge = await showSmaczekChallenge(
      context,
      smaczek: smaczek,
      choice: choice,
      compact: compact,
    );
    if (!mounted) return null;

    // The surfaces around the gate — the bottom bar's label and the free
    // tier's smaczki sheet — tell the truth from this record.
    ref
        .read(challengeRecordsProvider.notifier)
        .record(
          widget.questionId,
          ChallengeRecord(
            outcome: challenge.outcome,
            smaczekPosition: smaczek.position,
            smaczekTagged: smaczek.isTagged,
          ),
        );

    Analytics.log('smaczek_challenge', {
      'question_id': widget.questionId,
      'position': smaczek.position,
      'side': smaczek.side?.wire,
      'outcome': challenge.outcome.name,
      if (challenge.dwellMs != null) 'dwell_ms': challenge.dwellMs,
      'choice': choice == VoteResult.yes ? 'tak' : 'nie',
      'compact': compact,
    });
    if (reducedMotion) {
      // NOT a skip — the gate did show — but flagged with the same event so
      // the share of votes where the beat ran without motion is measurable
      // alongside the real skips.
      Analytics.log('smaczek_challenge_skipped', {
        'question_id': widget.questionId,
        'reason': 'reduce_motion_ok',
      });
    }

    // Persist the outcome on the vote row. Best-effort: the vote already
    // counted and the split is already in hand, so a failure here costs only
    // the statistic, never the user's result.
    try {
      final fresh = await ref
          .read(questionRepositoryProvider)
          .recordSmaczekChallenge(
            questionId: widget.questionId,
            position: smaczek.position,
            outcome: challenge.outcome,
            dwellMs: challenge.dwellMs,
          );
      if (!mounted || !fresh.hasVoted) return null;
      ref.invalidate(dailyVoteStateProvider(widget.questionId));
      return fresh;
    } catch (_) {
      return null;
    }
  }

  /// Picks the argument to throw at a user who just voted [choice].
  ///
  /// Prefers what was already warmed while they were reading the question — for
  /// a PRO user, and for the whole untagged catalog, that is a hit with no round
  /// trip. Only when nothing readable there is aimed at this side does it go
  /// back to the server, which now knows the vote and unlocks the argument that
  /// matches it (see the `get_question_smaczki` RPC).
  ///
  /// Every null return logs `smaczek_challenge_skipped` with its reason, so
  /// the share of votes that silently bypass the gate is measurable.
  Future<Smaczek?> _resolveChallenger(int choice) async {
    final id = widget.questionId;
    void logSkip(String reason) => Analytics.log('smaczek_challenge_skipped', {
      'question_id': id,
      'reason': reason,
    });
    try {
      final warmed = _pickChallenger(
        ref.read(smaczkiProvider(id)).value,
        choice,
      );
      if (warmed != null) return warmed;
      ref.invalidate(smaczkiProvider(id));
      final fresh = await ref.read(smaczkiProvider(id).future);
      final pick = _pickChallenger(fresh, choice);
      if (pick == null) {
        logSkip(fresh.isEmpty ? 'no_smaczki' : 'no_match_after_refetch');
      }
      return pick;
    } catch (e) {
      // Offline, a slow RPC, an empty question — all mean "no challenge",
      // never "no result".
      logSkip(isOfflineError(e) ? 'offline' : 'no_smaczki');
      return null;
    }
  }

  /// The first readable argument written against [choice]; failing that, the
  /// first readable neutral one. An argument aimed at the OTHER side is skipped
  /// on purpose — it is not a challenge to this user, it is agreement.
  ///
  /// Untagged smaczki read as neutral, so this picks a sensible one across the
  /// whole catalog before any of it has been tagged.
  static Smaczek? _pickChallenger(List<Smaczek>? smaczki, int choice) {
    if (smaczki == null) return null;
    Smaczek? neutral;
    for (final s in smaczki) {
      if ((s.text ?? '').trim().isEmpty) continue;
      final side = s.side;
      if (side != null && side != SmaczekSide.neutral) {
        if (s.attacks(choice)) return s;
        continue;
      }
      neutral ??= s;
    }
    return neutral;
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
  /// extended a streak — run at most ONE follow-up prompt: first the
  /// store-review ask when a vote milestone is due (3rd and 7th vote — see
  /// reviewPromptControllerProvider), then a guest's "secure your streak"
  /// account nudge, then the one-time "suggest a question" toast. One dialog
  /// per vote, so the moment never turns into a gauntlet.
  ///
  /// Best-effort and fired last: a prompt must never interfere with the vote
  /// that already counted, so any failure (offline stats refetch, missing prefs
  /// in tests) is swallowed.
  Future<void> _maybeNudgeAfterVote() async {
    try {
      // Count this vote toward the one-time "suggest a question" nudge and the
      // review milestones before any prompt below claims the moment —
      // whichever one shows, both counters must reflect the vote.
      await recordVoteForSuggestQuestionNudge(
        ref.read(sharedPreferencesProvider),
      );
      final review = ref.read(reviewPromptControllerProvider.notifier);
      await review.recordVote();

      final stats = await ref.read(userStatsProvider.future);
      // Swiping away unmounts this panel; skipping the ask is always acceptable,
      // so bail rather than reach through a `ref` that's no longer usable.
      if (!mounted) return;
      final streak = stats?.currentStreak ?? 0;

      // The freemium funnel's activation event, with the post-vote streak the
      // engagement mechanics ride on. Only the served daily counts here.
      if (widget.isDaily) {
        Analytics.log('daily_question_voted', {'streak': streak});
      }

      // On the day the streak crosses into a new rank, the rank-up celebration
      // (confetti + share card) owns the moment — neither prompt fires on top
      // of it. Both come around again on the next eligible day.
      final ladder = ref.read(ranksProvider).value ?? kDefaultRanks;
      final isPromotionDay = ladder.any(
        (r) => r.tier > 0 && r.minStreak == streak,
      );

      // On a promotion day the celebration owns the moment and the review ask
      // rides right behind it instead (RankCelebrationListener); otherwise a
      // due milestone claims this vote's single prompt slot here.
      if (!isPromotionDay && await review.maybePromptForReview()) return;
      if (!mounted) return;

      final nudged = await maybePromptSecureStreak(
        context,
        ref,
        streak: streak,
        isPromotionDay: isPromotionDay,
      );
      if (nudged || isPromotionDay) return;

      // The one-time "got an idea? send it in" toast — after the second vote,
      // once the loop has been felt.
      if (!mounted) return;
      await maybePromptSuggestQuestion(context, ref);
    } catch (_) {
      // Non-critical: skipping the ask is always an acceptable outcome.
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(dailyVoteStateProvider(widget.questionId));
    final result = _local ?? async.value;

    if (result == null) {
      // A state that FAILED to load must not swallow the product's main action.
      // The caching layer rethrows here on purpose "so the buttons stay" — but
      // this panel then rendered a blank 52px gap, so a user who opened the app
      // offline, or hit a 500 / expired JWT, saw the question with nothing to
      // tap and no explanation. As far as we know they haven't voted, so offer
      // the buttons: the cast is an upsert, and it surfaces its own "no
      // connection" / "vote failed" toast if the backend is still down.
      if (async.hasError) {
        return VoteButtonsRow(
          key: const ValueKey('buttons'),
          busy: _busy,
          onVote: _vote,
        );
      }
      // Still in flight: reserve the space with a slim placeholder so the
      // overlay doesn't jump when the buttons/bars appear.
      return const SizedBox(height: 52);
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: result.hasVoted
          ? Column(
              key: const ValueKey('results'),
              mainAxisSize: MainAxisSize.min,
              children: [
                VoteResultsRow(
                  result: result,
                  // Always spell out which side was mine under the bars...
                  confirmMyVote: true,
                  // ...and offline, withhold the (possibly stale) community
                  // split until we're back online.
                  communityHidden: result.fromCache,
                ),
                // The second number: how many gate-takers the counter-argument
                // flipped. The server only sends it past 30 answered gates, so
                // a non-null value is always worth showing — except offline,
                // where the community numbers are withheld wholesale.
                if (result.flipPct != null && !result.fromCache) ...[
                  const SizedBox(height: 10),
                  Text(
                    context.l10n.resultFlipLine(result.flipPct!),
                    textAlign: TextAlign.center,
                    style: AppTypography.support(
                      fontSize: 12,
                    ).copyWith(color: context.colors.subtle),
                  ),
                ],
                // PROTOTYPE (debug-only, renders nothing in release): the
                // post-vote "see your history" entry — see
                // prototype_history_entry.dart. Remove with it.
                const SizedBox(height: 14),
                const PrototypeHistoryEntry(),
              ],
            )
          : VoteButtonsRow(
              key: const ValueKey('buttons'),
              busy: _busy,
              onVote: _vote,
            ),
    );
  }
}
