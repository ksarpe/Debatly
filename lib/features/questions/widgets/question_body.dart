import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feedback/app_toast.dart';
import '../../../core/feedback/haptics.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/fit_or_scroll.dart';
import '../../account/providers/session_providers.dart';
import '../../monetization/widgets/day_wall_view.dart';
import '../providers/challenge_providers.dart';
import '../providers/question_providers.dart';
import '../providers/swipe_hint_providers.dart';
import 'daily_question_badge.dart';
import 'daily_vote_panel.dart';
import 'favorite_star_button.dart';
import 'go_deeper_button.dart';
import 'new_question_badge.dart';
import 'share_question_button.dart';
import 'smaczki_panel.dart';
import 'swipe_hand_hint.dart';
import 'vote_visuals.dart' show voteRowMaxHeight;
import 'wind_question_view.dart';

/// Widest the centred question group is allowed to get: the shared reading
/// width, so the feed, the day wall and the paywall line up rather than each
/// picking their own tablet width. Uncapped, an 11" iPad turns a one-line
/// question into an unreadable 1148pt ribbon.
///
/// Denser surfaces keep tighter caps of their own (onboarding and the auth
/// sheets at 480, settings at 520, the vote row at 320).
const double _kFeedMaxWidth = kReadingMaxWidth;

/// Smallest height worth giving the question at the DEFAULT text scale. Below
/// this the text has stopped being the point of the screen, so the group stops
/// shrinking and the feed scrolls instead — see [FitOrScroll].
const double _kMinQuestionHeight = 56;

/// How far the question's floor follows the system font before it stops. Same
/// ceiling the vote tiles use ([voteRowMaxHeight] clamps identically): past it
/// the floor would push a short screen into scrolling on the strength of a
/// setting the text itself already answers by shrinking.
const double _kMaxQuestionTextScale = 1.6;

/// [_kMinQuestionHeight] grown for the system font.
///
/// It HAS to scale, because the other half of the floor does: the vote row
/// under it grows with the text scaler, so a fixed question floor made
/// [_minGroupHeight] under-report at large accessibility sizes. FitOrScroll
/// then took the non-scrolling branch on a box too small to hold the group,
/// and an overflowing Column still paints — so the question printed straight
/// over the TAK/NIE row (~54pt of overflow at 360×640 / 2.0× on the catalog's
/// longest question) instead of the feed scrolling.
double _minQuestionHeight(BuildContext context) {
  final scale = MediaQuery.textScalerOf(context).scale(1);
  return _kMinQuestionHeight *
      math.min(_kMaxQuestionTextScale, math.max(1, scale));
}

class QuestionBody extends ConsumerWidget {
  const QuestionBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The free tier's day wall takes over the whole body when a forward swipe
    // lands on it (see dayWallVisibleProvider) — it owns its own gestures and
    // its own layout, so nothing below renders behind it.
    if (ref.watch(dayWallVisibleProvider)) return const DayWallView();

    // The question currently on screen. A locked question is a pure paywall —
    // WindQuestionView renders its lock + unlock CTA — so it gets NO bottom
    // overlay and NO smaczki affordance. Only a readable question does.
    final current = ref.watch(currentQuestionProvider);
    final questionId = current?.id;
    final isReadable = current != null && current.isLocked != true;

    // Whether the visible question is the served daily (deck position 0) —
    // drives the "PYTANIE DNIA" pill and the analytics split in the vote panel.
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

    // The rows that sit under the question need this early: the smaczki warm
    // below picks its provider by it, and the sheet/pill gating reads it too.
    final isPremium = ref.watch(isPremiumProvider);

    // The smaczki sheet is VOTE-GATED, for both tiers (see the pill wiring
    // below) — and so is the smaczki TEXT itself for free users, server-side.
    final hasVoted =
        isReadable &&
        questionId != null &&
        (questionId == kDevCustomQuestionId ||
            (ref.watch(dailyVoteStateProvider(questionId)).value?.hasVoted ??
                false));

    // Warm the smaczki for a readable question in the background, so the "go
    // deeper" panel opens straight to content instead of a spinner. The result
    // is ignored here — the panel reads the same, now-resolved provider
    // (FutureProvider.family caches per question id). Each swipe re-warms the
    // newly visible question. Locked questions have no panel, so skip them.
    //
    // WHICH provider is the leak fix: before the vote a free user's device
    // must hold no readable argument, so only the metadata prefetch
    // (positions + rough lengths) runs. The full set is warmed once the vote
    // exists — and for PRO immediately (they own the text either way, and the
    // post-vote gate then opens with zero round trips).
    if (isReadable && questionId != null) {
      if (isPremium || hasVoted) {
        ref.watch(smaczkiProvider(questionId));
      } else {
        ref.watch(smaczkiMetaProvider(questionId));
      }
    }

    // Same trick for the day wall's teaser: warm it while the free user is
    // still on the feed, so the forward swipe lands on a wall whose first
    // words are already readable instead of popping in after the peek RPC.
    // Premium users never meet the wall, so they skip the fetch entirely.
    if (!ref.watch(isPremiumProvider)) {
      ref.watch(wallTeaserProvider);
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
    // The mirror jump: a PRO user somewhere in the catalog gets a one-tap way
    // back to the shared question of the day (the deck keeps it at index 0).
    final showJumpToDaily = ref.watch(canJumpToDailyProvider);
    final showOverlay =
        showHintAndDeeper || showJumpToLatest || showJumpToDaily;

    // The smaczki sheet is VOTE-GATED, for both tiers: a counter-argument read
    // before taking a side is just information without a target, and a vote
    // cast after reading the arguments is no longer the reflex the community
    // split claims to measure. The pill stays visible — knowing something
    // waits there is part of the reason to vote — but tapping it before the
    // vote answers with a hook instead of the sheet. The DEV custom pin is
    // exempt: it has no server vote row, so this gate could never open for it
    // (its sheet only renders the "no smaczki" note anyway). `hasVoted` is
    // computed above, next to the smaczki warm that keys off it.

    // What the "go deeper" pill promises. Default is the standing "PRZECIWKO
    // TOBIE"; once the post-vote gate has run on THIS question the label must
    // match what the sheet can actually deliver: an untagged argument can't
    // promise "against you" at all — for EITHER tier, which is why that arm
    // sits above the premium one — a tagged one leaves PRO the short "KONTRA"
    // (set larger) and free the "case FOR you" hook, the defense being exactly
    // what remains locked in the sheet.
    // Only a gate the user ANSWERED rewrites the promise: one left through
    // system back delivered no argument, so the pill goes on offering the
    // standing "PRZECIWKO TOBIE" and the sheet keeps its free row (see
    // [ChallengeRecord.wasRead]).
    final gate = hasRows
        ? ref.watch(challengeRecordsProvider)[questionId]
        : null;
    final record = gate != null && gate.wasRead ? gate : null;

    // How many arguments the sheet still holds beyond the one the gate already
    // showed. The catalog runs 2–4 smaczki per question, so a hard-coded "two"
    // was simply wrong on both ends of that range — and the sheet counts for
    // itself one tap later (smaczki_panel's _freeHeaderAfterGate), so the two
    // surfaces have to do the same arithmetic or they contradict each other.
    // Null only while the set is refetching (right after a purchase, say):
    // no honest number, so the standing promise stands in rather than a zero.
    final int? smaczkiLeft = record == null
        ? null
        : ref
              .watch(smaczkiProvider(questionId!))
              .value
              ?.where((s) => s.position != record.smaczekPosition)
              .length;

    final (goDeeperLabel, goDeeperProminent) = switch (record) {
      null => (context.l10n.goDeeper, false),
      ChallengeRecord(smaczekTagged: false) when smaczkiLeft != null => (
        context.l10n.smaczkiBarUntagged(smaczkiLeft),
        false,
      ),
      ChallengeRecord(smaczekTagged: false) => (context.l10n.goDeeper, false),
      _ when isPremium => (context.l10n.smaczkiBarPro, true),
      _ => (context.l10n.smaczkiBarFree, false),
    };

    final bottomInset = MediaQuery.paddingOf(context).bottom;

    // The whole feed is one swipe surface: WindQuestionView's own detector only
    // spans the question text's bounds, which on a tablet is a thin strip in a
    // sea of dead space (App Review swiped an iPad and "the app did not
    // react"). This outer layer catches horizontal drags anywhere on screen and
    // forwards them into the same handlers; taps still reach the buttons —
    // only horizontal drags are claimed here.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // A pure forwarding layer, and semantically invisible on purpose: the
      // scrollLeft/scrollRight actions live on the question itself (see
      // WindQuestionView), where a screen-reader user is focused. Left in,
      // this detector's auto-generated pair would blanket the whole screen
      // with a duplicate — and a non-working one, since the framework
      // synthesises only a drag update and the commit needs a drag end.
      excludeFromSemantics: true,
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
                      showJumpToDaily: showJumpToDaily,
                      questionId: hasRows ? questionId : null,
                      questionText: hasRows ? current.questionText : null,
                      goDeeperLabel: goDeeperLabel,
                      goDeeperProminent: goDeeperProminent,
                      onGoDeeper: questionId == null
                          ? null
                          : hasVoted
                          ? () => showSmaczkiSheet(context, questionId)
                          : () {
                              // Same refusal as a locked card: the arguments
                              // exist, they are just not readable until the
                              // vote is in.
                              Haptics.blocked();
                              AppToast.info(
                                context,
                                context.l10n.smaczkiLockedBeforeVote,
                              );
                            },
                      onJumpToLatest: () =>
                          ref.read(questionIndexProvider.notifier).toLatest(),
                      onJumpToDaily: () =>
                          ref.read(questionIndexProvider.notifier).toDaily(),
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
    required this.isDaily,
    required this.showNewBadge,
  });

  /// Non-null exactly when the question is readable, i.e. when the vote panel
  /// is part of the group. Keyed by (user, question) so the panel's local
  /// state resets both on a swipe and on an account change.
  final Key? votePanelKey;
  final String? questionId;

  /// Only picks the analytics event inside the vote panel.
  final bool isDaily;

  /// Whether the visible question wears the "NOWE" pill (added to the catalog
  /// within the freshness window — see `newQuestionIdsProvider`).
  final bool showNewBadge;

  @override
  Widget build(BuildContext context) {
    final hasRows = questionId != null;

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
            minContentHeight: _minGroupHeight(
              context,
              withRows: hasRows,
              withBadge: isDaily || showNewBadge,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The pills sit above the question, not inside the wind
                // canvas, so the falling-words animation stays untouched —
                // they just appear with the question they label. The daily
                // wears its identity pill; "NOWE" yields to it on the rare
                // day the shared pick is also freshly added (two pills would
                // shove the question down for no extra information).
                if (isDaily) ...[
                  const DailyQuestionBadge(),
                  const SizedBox(height: 16),
                ] else if (showNewBadge) ...[
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
                  // Share and the favorites star moved down into the bottom
                  // action bar, flanking the "go deeper" CTA — see
                  // [_BottomOverlay].
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
/// plus the gap and the vote row at its tallest (the share / favorite pills
/// live in the bottom action bar now, not in this group). Once the band
/// between the app bar and the bottom overlay drops below this, the feed
/// hands the group this much height anyway and scrolls (see [FitOrScroll]) —
/// which is strictly better than letting the [Column] overflow, because
/// overflowed children are painted where nothing hit-tests them.
double _minGroupHeight(
  BuildContext context, {
  required bool withRows,
  required bool withBadge,
}) {
  final question = _minQuestionHeight(context);
  // A pill above the question ("PYTANIE DNIA" / "NOWE") is group height too —
  // the daily wears one on EVERY free session, so leaving it out of the floor
  // would under-report on exactly the card most users see first.
  final badge = withBadge ? questionBadgeMaxHeight(context) + 16 : 0;
  if (!withRows) return question + badge;
  // Everything the panel can put UNDER the vote row counts too — the flip line
  // arrived in v2 below `voteRowMaxHeight` without either measurement being
  // told about it, which is exactly the kind of silent under-report this floor
  // exists to prevent.
  return question +
      badge +
      28 +
      voteRowMaxHeight(context) +
      votePanelExtrasMaxHeight(context);
}

/// The strip at the foot of the feed: on a readable question the swipe hint and
/// the full-width action bar — the glowing "go deeper" CTA (4/6 of the row)
/// flanked by the share pill on the left and the favorite star on the right
/// (1/6 each, same corner radius) — plus the borderless feed jumps: "back to
/// the latest →" (BOTH tiers) whenever back swipes have left the user behind
/// the furthest question reached this session, and "← pytanie dnia" whenever
/// the visible question is not the daily (in practice PRO mid-catalog — a
/// free deck is just the daily).
class _BottomOverlay extends StatelessWidget {
  const _BottomOverlay({
    required this.showHintAndDeeper,
    required this.showJumpToLatest,
    required this.showJumpToDaily,
    required this.questionId,
    required this.questionText,
    required this.goDeeperLabel,
    required this.goDeeperProminent,
    required this.onGoDeeper,
    required this.onJumpToLatest,
    required this.onJumpToDaily,
  });

  final bool showHintAndDeeper;
  final bool showJumpToLatest;
  final bool showJumpToDaily;

  /// Non-null exactly when the visible question is readable — the share pill
  /// needs its text, the star its id.
  final String? questionId;
  final String? questionText;

  /// The state-dependent promise on the "go deeper" pill — computed in
  /// [QuestionBody] from the post-vote gate's record for this question.
  final String goDeeperLabel;
  final bool goDeeperProminent;
  final VoidCallback? onGoDeeper;
  final VoidCallback onJumpToLatest;
  final VoidCallback onJumpToDaily;

  @override
  Widget build(BuildContext context) {
    // The overlay is a SIBLING of the centred group and takes its height off
    // the top of it, so it is the one part of the feed that cannot answer a
    // huge system font by shrinking — it just pushes the question out and
    // then runs off the bottom of the screen itself. At 3.0× on a 320pt
    // phone the one-line swipe hint alone wrapped to 371pt, taller than half
    // the viewport, and the action bar landed 120pt below the bottom edge:
    // painted, and completely untouchable.
    //
    // So the strip follows the system font exactly as far as the vote tiles
    // do and no further ([_kMaxQuestionTextScale] is the same 1.6). It is
    // the smallest thing on screen that can give: the question above it
    // still scales all the way, and a CTA the finger can reach beats a
    // slightly larger label it cannot.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: _kMaxQuestionTextScale,
      child: SafeArea(
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
                  style: AppTypography.support(
                    fontSize: 13,
                  ).copyWith(color: context.colors.subtle),
                ),
                const SizedBox(height: 14),
                // The action bar: "go deeper" carries the middle of the row
                // (4/6), flanked by the share pill on the left and the favorites
                // star on the right (1/6 each) in the same rounded-rectangle
                // chrome — one full-width family of controls. Capped at the
                // feed's width so it tracks the question column on tablets.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _kFeedMaxWidth),
                  child: Row(
                    children: [
                      if (questionText != null) ...[
                        Expanded(
                          child: ShareQuestionButton(
                            questionText: questionText!,
                            barStyle: true,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        flex: 4,
                        child: GoDeeperButton(
                          onTap: onGoDeeper ?? () {},
                          label: goDeeperLabel,
                          prominent: goDeeperProminent,
                        ),
                      ),
                      if (questionId != null) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: FavoriteStarButton(
                            questionId: questionId!,
                            barStyle: true,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (showJumpToDaily || showJumpToLatest) ...[
                if (showHintAndDeeper) const SizedBox(height: 12),
                // The two feed jumps share a row when both apply (mid-deck,
                // behind the furthest question) — a Wrap so narrow phones at
                // large text scales stack them instead of overflowing. The
                // daily jump points back (index 0), the latest jump forward.
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    if (showJumpToDaily)
                      _FeedLinkButton(
                        label: context.l10n.backToDailyQuestion,
                        icon: Icons.arrow_back,
                        iconAfterLabel: false,
                        onTap: onJumpToDaily,
                      ),
                    if (showJumpToLatest)
                      _FeedLinkButton(
                        label: context.l10n.backToLatestQuestion,
                        icon: Icons.arrow_forward,
                        iconAfterLabel: true,
                        onTap: onJumpToLatest,
                      ),
                  ],
                ),
              ],
            ],
          ),
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
        label.toUpperCase(),
        textAlign: TextAlign.center,
        style: AppTypography.action(
          fontSize: 13,
        ).copyWith(color: context.colors.subtle),
      ),
      style: TextButton.styleFrom(
        foregroundColor: context.colors.subtle,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }
}
