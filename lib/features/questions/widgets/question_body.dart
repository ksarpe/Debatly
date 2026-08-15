import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/fit_or_scroll.dart';
import '../../account/providers/session_providers.dart';
import '../providers/question_providers.dart';
import '../providers/swipe_hint_providers.dart';
import '../screens/history_screen.dart';
import 'daily_vote_panel.dart';
import 'go_deeper_button.dart';
import 'new_question_badge.dart';
import 'share_question_button.dart';
import 'smaczki_panel.dart';
import 'swipe_hand_hint.dart';
import 'vote_visuals.dart' show voteRowMaxHeight;
import 'wind_question_view.dart';

/// Widest the centred question group is allowed to get.
///
/// Every other surface caps itself for tablets (onboarding and the auth sheet at
/// 480, settings at 520, the vote row and the paywall CTAs at 320) — the feed
/// was the only one that let the question stretch the full width, which on an
/// 11" iPad turns a one-line question into an unreadable 1148pt ribbon.
const double _kFeedMaxWidth = 560;

/// Smallest height worth giving the question. Below this the text has stopped
/// being the point of the screen, so the group stops shrinking and the feed
/// scrolls instead — see [FitOrScroll].
const double _kMinQuestionHeight = 56;

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
    // drives the analytics split in the vote panel.
    final isDaily = ref.watch(isShowingDailyProvider);

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

    // The rows that sit under the question: the vote panel and the share /
    // history pills. Present on every readable question, absent on a locked
    // teaser.
    final hasRows = isReadable && questionId != null;

    // The small "NOWE" pill over a question added within the freshness window
    // — pre-empts reading its thin vote count as disinterest. The provider is
    // already false for locked teasers (current == null).
    final showNewBadge = ref.watch(currentQuestionIsNewProvider);

    // What the bottom overlay carries. The swipe hint and the "go deeper" pill
    // belong to a readable question; the "back to the latest →" link appears
    // whenever back swipes have left the user behind the furthest question
    // reached this session, so a run of back swipes is undone in one tap
    // instead of re-swiped forward one by one. (Going the other way needs no
    // link: a back swipe already steps backwards.)
    final showHintAndDeeper = hasRows;
    final showJumpToLatest = ref.watch(canJumpToLatestProvider);
    final showOverlay = showHintAndDeeper || showJumpToLatest;

    final bottomInset = MediaQuery.paddingOf(context).bottom;

    // The whole feed is one swipe surface: WindQuestionView's own detector only
    // spans the question text's bounds, which on a tablet is a thin strip in a
    // sea of dead space (App Review swiped an iPad and "the app did not
    // react"). This outer layer catches horizontal drags anywhere on screen and
    // forwards them into the same handlers; taps still reach the buttons —
    // only horizontal drags are claimed here.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (details) =>
          windQuestionViewKey.currentState?.handleDragStart(details),
      onHorizontalDragUpdate: (details) =>
          windQuestionViewKey.currentState?.handleDragUpdate(details),
      onHorizontalDragEnd: (details) =>
          windQuestionViewKey.currentState?.handleDragEnd(details),
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              // The app bar floats over the body (extendBodyBehindAppBar), so
              // the space it covers has to be reserved here or the question
              // would centre underneath the status chips.
              padding: EdgeInsets.only(
                top: MediaQuery.paddingOf(context).top + kToolbarHeight,
              ),
              child: Column(
                children: [
                  Expanded(
                    child: _CentredGroup(
                      votePanelKey: hasRows
                          ? ValueKey('${userId ?? ''}:$questionId')
                          : null,
                      questionId: hasRows ? questionId : null,
                      questionText: hasRows ? current.questionText : null,
                      isDaily: isDaily,
                      showNewBadge: showNewBadge,
                    ),
                  ),
                  // The bottom overlay is a SIBLING of the group above, not a
                  // free-floating Stack layer measured by a hand-maintained
                  // "reserve" constant. Whatever height it takes is height the
                  // group simply doesn't get, so the two can never overlap —
                  // they used to, and the swipe hint then sat on the share /
                  // history pills and swallowed their taps.
                  if (showOverlay)
                    _BottomOverlay(
                      showHintAndDeeper: showHintAndDeeper,
                      showJumpToLatest: showJumpToLatest,
                      onGoDeeper: questionId == null
                          ? null
                          : () => showSmaczkiSheet(context, questionId),
                      onJumpToLatest: () =>
                          ref.read(questionIndexProvider.notifier).toLatest(),
                    )
                  else
                    SizedBox(height: bottomInset + 24),
                ],
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
          if (showHintAndDeeper && (!swipeDiscovered || kDebugMode))
            const Positioned.fill(child: SwipeHandHint()),
        ],
      ),
    );
  }
}

/// The question and, under a readable one, the vote row and the share / history
/// pills — centred in whatever band the feed's [Column] leaves them.
///
/// Everything here is laid out inside a bounded box, and [FitOrScroll] keeps it
/// that way even when the band is tiny: an overflowing [Column] is still painted
/// but stops being hit-tested, and that is how the pills and the reveal wall's
/// "restore purchase" used to become unreachable.
class _CentredGroup extends StatelessWidget {
  const _CentredGroup({
    required this.votePanelKey,
    required this.questionId,
    required this.questionText,
    required this.isDaily,
    required this.showNewBadge,
  });

  /// Non-null exactly when the question is readable, i.e. when the vote panel
  /// and the pill row are part of the group. Keyed by (user, question) so the
  /// panel's local state resets both on a swipe and on an account change.
  final Key? votePanelKey;
  final String? questionId;
  final String? questionText;

  /// Only picks the analytics event inside the vote panel.
  final bool isDaily;

  /// Whether the visible question wears the "NOWE" pill (added to the catalog
  /// within the freshness window — see `newQuestionIdsProvider`).
  final bool showNewBadge;

  @override
  Widget build(BuildContext context) {
    final hasRows = questionId != null && questionText != null;

    return Padding(
      // Narrow side margins: the question is the widest thing here, and every
      // pixel of line width is a word that doesn't wrap onto another line.
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kFeedMaxWidth),
          child: FitOrScroll(
            // The question flexes against a bounded box (it shrinks its
            // font to fit), so the floor keeps that box bounded once the
            // viewport itself is too small.
            minContentHeight: _minGroupHeight(context, withRows: hasRows),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // "NOWE" sits above the question, not inside the wind
                // canvas, so the falling-words animation stays untouched
                // — the pill just appears with the question it labels.
                if (showNewBadge) ...[
                  const NewQuestionBadge(),
                  const SizedBox(height: 16),
                ],
                // The GlobalKey does double duty: it keeps the State
                // stable across unrelated rebuilds (so the peeked teaser
                // survives a sibling toggling), and it gives the
                // full-screen gesture layer its handle into the swipe
                // handlers.
                //
                // Flexible hands the leftover height to the text, which
                // shrinks to fit — see QuestionTextStyles.fitFontSize.
                Flexible(child: WindQuestionView(key: windQuestionViewKey)),
                // Vote under EVERY readable question — casting reveals the
                // community split, the feed's core hook, and any vote can
                // move the streak (server: once per UTC day).
                if (hasRows) ...[
                  const SizedBox(height: 28),
                  DailyVotePanel(
                    key: votePanelKey,
                    questionId: questionId!,
                    isDaily: isDaily,
                  ),
                  // Share sits right under the question rather than as the
                  // faint icon it used to be down in the bottom overlay,
                  // paired with "Historia" — every question is votable
                  // now, so the PRO voting record is one tap away
                  // anywhere.
                  const SizedBox(height: 24),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ShareQuestionButton(questionText: questionText!),
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
    );
  }
}

/// The height at which the centred group is known to fit: a readable question
/// plus the two gaps, the vote row at its tallest, and the pill row. Once the
/// band between the app bar and the bottom overlay drops below this, the feed
/// hands the group this much height anyway and scrolls (see [FitOrScroll]) —
/// which is strictly better than letting the [Column] overflow, because
/// overflowed children are painted where nothing hit-tests them.
double _minGroupHeight(BuildContext context, {required bool withRows}) {
  if (!withRows) return _kMinQuestionHeight;
  return _kMinQuestionHeight +
      28 +
      voteRowMaxHeight(context) +
      24 +
      kMinTouchTarget;
}

/// The strip at the foot of the feed: the swipe hint and the "go deeper" pill on
/// a readable question, plus the borderless "back to the latest →" link (BOTH
/// tiers), whenever back swipes have left the user behind the furthest question
/// reached this session — the one-tap undo for a run of back swipes. (The
/// mirror direction needs no link: a back swipe already steps backwards.)
class _BottomOverlay extends StatelessWidget {
  const _BottomOverlay({
    required this.showHintAndDeeper,
    required this.showJumpToLatest,
    required this.onGoDeeper,
    required this.onJumpToLatest,
  });

  final bool showHintAndDeeper;
  final bool showJumpToLatest;
  final VoidCallback? onGoDeeper;
  final VoidCallback onJumpToLatest;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showHintAndDeeper) ...[
              // Subtle hint that questions are swipeable.
              Text(
                context.l10n.swipeHint,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.colors.subtle, fontSize: 13),
              ),
              const SizedBox(height: 14),
              // The glowing "go deeper" pill. (Share lives up by the question
              // now, not down here.)
              GoDeeperButton(onTap: onGoDeeper ?? () {}),
            ],
            if (showJumpToLatest) ...[
              if (showHintAndDeeper) const SizedBox(height: 12),
              _FeedLinkButton(
                label: context.l10n.backToLatestQuestion,
                icon: Icons.arrow_forward,
                iconAfterLabel: true,
                onTap: onJumpToLatest,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A borderless link at the foot of the feed — the quiet navigation escape
/// hatch ("back to the latest →"). The arrow sits on the side it points to, so
/// the icon itself says which way the jump goes.
class _FeedLinkButton extends StatelessWidget {
  const _FeedLinkButton({
    required this.label,
    required this.icon,
    required this.iconAfterLabel,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool iconAfterLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: context.colors.subtle),
      iconAlignment: iconAfterLabel ? IconAlignment.end : IconAlignment.start,
      label: Text(
        label,
        textAlign: TextAlign.center,
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
