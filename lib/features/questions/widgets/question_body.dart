import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../account/providers/session_providers.dart';
import '../providers/question_providers.dart';
import '../providers/swipe_hint_providers.dart';
import '../screens/history_screen.dart';
import 'daily_vote_panel.dart';
import 'go_deeper_button.dart';
import 'share_question_button.dart';
import 'smaczki_panel.dart';
import 'swipe_hand_hint.dart';
import 'wind_question_view.dart';

class QuestionBody extends ConsumerWidget {
  const QuestionBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The question currently on screen. A locked question is a pure paywall —
    // WindQuestionView renders its lock + unlock CTA — so it gets NO bottom
    // overlay and NO smaczki affordance. Only a readable question does.
    final current = ref.watch(currentQuestionProvider);
    final questionId = current?.id;
    final isReadable = current != null && current.isLocked != true;

    // Whether the visible question is the served daily (deck position 0) —
    // drives the analytics split in the vote panel and hides the "back to the
    // free question" link while already on it.
    final isDaily = ref.watch(isShowingDailyProvider);

    // The "back to the free question" escape hatch is only meaningful to a free
    // user: premium has no paywall to escape and its feed just wraps, so "start"
    // is meaningless there. Used to hide _BackToDailyButton for premium below.
    final isPremium = ref.watch(isPremiumProvider);

    // On the reveal slot the paywall / "no more questions" body carries its own
    // visible "back to daily" link, so suppress the faint bottom one here to
    // avoid showing two competing back actions.
    final atRevealSlot = ref.watch(isAtRevealSlotProvider);

    // Whether the user has ever swiped forward. Until they have, a gentle
    // right-edge arrow nudges them to discover that the feed continues past the
    // daily — the swipe gesture isn't obvious from the faint text hint alone.
    // Flipped (and persisted) by the first forward swipe in WindQuestionView.
    final swipeDiscovered = ref.watch(swipeDiscoveredControllerProvider);

    // Folded into the vote panel's key so its local state (the cast result it
    // holds to avoid a refetch) resets when the account changes, not only when
    // the question does — otherwise a fresh user keeps seeing the old vote bars.
    final userId = ref.watch(sessionProvider.select((s) => s.value?.userId));

    // Warm the smaczki for a readable question in the background, so the "go
    // deeper" panel opens straight to content instead of a spinner. The result
    // is ignored here — the panel reads the same, now-resolved provider
    // (FutureProvider.family caches per question id). Each swipe re-warms the
    // newly visible question. Locked questions have no panel, so skip them.
    if (isReadable && questionId != null) {
      ref.watch(smaczkiProvider(questionId));
    }

    // Centred group: the question, and — under every readable one — the TAK/NIE
    // vote right beneath it, so the buttons sit by the question rather than
    // pinned to the screen bottom. Only the swipe hint + "go deeper" stay in the
    // bottom overlay (readable questions only).
    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Stable key so an unrelated rebuild (the vote panel below
                  // appearing/disappearing, a sibling toggling) doesn't rebuild
                  // this with a fresh State and drop its in-memory state (the
                  // peeked teaser).
                  const WindQuestionView(key: ValueKey('wind_question_view')),
                  // Vote under EVERY readable question — casting reveals the
                  // community split, the feed's core hook, and any vote can
                  // move the streak (server: once per UTC day). Keyed by
                  // (user, id) so it resets both when swiping to a new question
                  // and when the account changes. `isDaily` only picks the
                  // analytics event.
                  if (isReadable && questionId != null) ...[
                    const SizedBox(height: 28),
                    DailyVotePanel(
                      key: ValueKey('${userId ?? ''}:$questionId'),
                      questionId: questionId,
                      isDaily: isDaily,
                    ),
                  ],
                  // A visible share pill sitting right under the question (and
                  // under its vote panel), so it's an obvious action rather
                  // than the faint icon it used to be down in the bottom
                  // overlay. Readable questions only — never a teaser. Paired
                  // with the "Historia" pill — every question is votable now,
                  // so the PRO history of your votes is one tap away anywhere.
                  if (isReadable && questionId != null) ...[
                    const SizedBox(height: 24),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ShareQuestionButton(questionText: current.questionText),
                        const SizedBox(width: 12),
                        const HistoryButton(),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        // Bottom overlay. On a readable question it carries the swipe hint and
        // the "go deeper" pill. Whenever the user has swiped off the daily —
        // readable OR locked — it also offers a borderless "← Daily" return, so
        // a free user who landed on a locked teaser and doesn't want to watch an
        // ad can get back to the free daily in one tap instead of being stuck.
        if ((isReadable && questionId != null || !isDaily) && !atRevealSlot)
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isReadable && questionId != null) ...[
                      // Subtle hint that questions are swipeable.
                      Text(
                        context.l10n.swipeHint,
                        style: TextStyle(
                          color: context.colors.subtle,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 14),
                      // The glowing "go deeper" pill. (Share lives up by the
                      // question now, not down here.)
                      GoDeeperButton(
                        onTap: () => showSmaczkiSheet(context, questionId),
                      ),
                    ],
                    // Free-only: the escape hatch back to the free question.
                    // Premium has no paywall to escape and its feed wraps, so a
                    // "back to start" is meaningless — hide it entirely.
                    if (!isDaily && !isPremium) ...[
                      if (isReadable && questionId != null)
                        const SizedBox(height: 12),
                      _BackToDailyButton(
                        label: context.l10n.backToFreeQuestion,
                        onTap: () =>
                            ref.read(questionIndexProvider.notifier).toDaily(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        // A finger that demonstrates the leftward "swipe for more" gesture if
        // the user lingers ~10s on a readable question without swiping. Shown
        // only on a readable, non-slot question, and — in release — only until
        // the first forward swipe sets `swipeDiscovered`, so it teaches once per
        // install. In debug builds the gate is relaxed so the animation can be
        // eyeballed without clearing app data. Decorative (IgnorePointer), so
        // the real swipe underneath passes straight through.
        if (isReadable &&
            questionId != null &&
            !atRevealSlot &&
            (!swipeDiscovered || kDebugMode))
          const Positioned.fill(child: SwipeHandHint()),
      ],
    );
  }
}

/// A borderless link pinned at the bottom of the screen, shown only when a FREE
/// user has swiped off the first question — the escape hatch from a locked pool
/// teaser back to the free question. Hidden for premium (no paywall to escape,
/// and its wrapping feed has no meaningful "start").
class _BackToDailyButton extends StatelessWidget {
  const _BackToDailyButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(Icons.arrow_back, size: 18, color: context.colors.subtle),
      label: Text(
        label,
        style: TextStyle(
          color: context.colors.subtle,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      style: TextButton.styleFrom(
        foregroundColor: context.colors.subtle,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }
}
