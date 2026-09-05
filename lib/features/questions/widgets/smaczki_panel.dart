import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feedback/app_toast.dart';
import '../../../core/feedback/haptics.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/models/smaczek.dart';
import '../../../services/analytics.dart';
import '../../account/providers/session_providers.dart';
import '../../monetization/widgets/pro_paywall_screen.dart';
import '../../monetization/widgets/purchase_settlement.dart';
import '../providers/challenge_providers.dart';
import '../providers/question_providers.dart';
import 'smaczek_composer.dart';

/// Opens the "Smaczki" panel as a modal sheet that slides up from the bottom.
///
/// Shows the discussion prompts for [questionId]: a free user sees the first one
/// plus the rest as blurred, locked placeholders; premium users see them all.
/// The gate is enforced server-side (the `get_question_smaczki` RPC) — locked
/// smaczki never carry real text, so the blur is purely cosmetic.
Future<void> showSmaczkiSheet(BuildContext context, String questionId) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.colors.background,
    showDragHandle: true,
    isScrollControlled: true,
    // Tablets: keep the sheet a centred column instead of letting one line
    // of text run the full width of an iPad.
    constraints: const BoxConstraints(maxWidth: kReadingMaxWidth),
    // Keeps the top edge below the notch / Dynamic Island once the sheet
    // grows tall with the keyboard up.
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _SmaczkiSheet(questionId: questionId),
  );
}

class _SmaczkiSheet extends ConsumerStatefulWidget {
  const _SmaczkiSheet({required this.questionId});

  final String questionId;

  @override
  ConsumerState<_SmaczkiSheet> createState() => _SmaczkiSheetState();
}

class _SmaczkiSheetState extends ConsumerState<_SmaczkiSheet> {
  /// Blocks the premium button while the paywall / purchase is in flight.
  bool _busy = false;

  /// Whether the "suggest your own smaczek" composer is unfolded in place of
  /// the footer button under the list.
  bool _composing = false;

  void _openComposer() {
    Analytics.log('smaczek_composer_opened', {
      'question_id': widget.questionId,
    });
    setState(() => _composing = true);
  }

  /// The sheet's footer under the list: the "Zaproponuj własny" button, or
  /// the composer it unfolds into. Null on the DEV pin, which has no server
  /// row the RPC could pin an argument to.
  Widget? _footer() {
    if (widget.questionId == kDevCustomQuestionId) return null;
    if (_composing) {
      return SmaczekComposer(
        questionId: widget.questionId,
        onSent: () => setState(() => _composing = false),
      );
    }
    return _SuggestSmaczekButton(
      questionId: widget.questionId,
      onTap: _openComposer,
    );
  }

  Future<void> _getPremium() async {
    // The tap that got here landed on a locked card: say "not yours yet" in the
    // hand before the paywall slides up, so the lock is felt at the moment of
    // the touch rather than only read a beat later.
    Haptics.blocked();
    setState(() => _busy = true);

    final purchased = await showProPaywall(
      context,
      source: PaywallSource.smaczki,
    );
    if (!mounted) return;

    if (purchased) {
      // The entitlement is the source of truth: refresh the session so the gate
      // sees the upgrade, then drop the cached smaczki so they re-fetch — this
      // time the RPC returns the now-unlocked text. A purchase the store hasn't
      // confirmed yet says so, instead of leaving the cards locked in silence.
      await settleProPurchase(context, ref);
      if (!mounted) return;
      ref.invalidate(smaczkiProvider(widget.questionId));
      setState(() => _busy = false);
      // The "save your PRO to an account" nudge is HomeGate's — it fires on the
      // free→premium flip the refresh above produces, for every entry point.
      // Calling it here too showed the same dialog twice.
    } else {
      AppToast.info(context, context.l10n.purchaseNotCompleted);
      setState(() => _busy = false);
    }
  }

  /// The post-gate free header — the sheet's sales line, so it may only
  /// promise what the locked cards actually hold. The strong "attack →
  /// defense → complication" frame (one argument FOR you, one that muddies
  /// it) needs exactly that set behind the paywall: two remaining cards, one
  /// tagged as defending the user's answer, one deliberately neutral. On the
  /// untagged catalog, partial tagging or odd mixes it degrades to the plain
  /// count — a header that oversells at the exact moment of the paywall is
  /// how trust dies.
  String _freeHeaderAfterGate(
    BuildContext context,
    ChallengeRecord record,
    List<Smaczek>? smaczki,
  ) {
    final l10n = context.l10n;
    if (smaczki == null) return l10n.smaczkiSubtitle;
    final remaining = [
      for (final s in smaczki)
        if (s.position != record.smaczekPosition) s,
    ];
    // "To mnie ruszyło" is the sheet's emotional peak — the user just felt the
    // product work on them, and the same header everyone else gets would waste
    // it. The acknowledged variant makes the flip itself the pitch; the same
    // honesty arithmetic applies to both (owner-approved copy, 2026-08-31).
    final moved = record.outcome == ChallengeOutcome.moved;
    final hasDefense = remaining.any(
      (s) =>
          s.isTagged &&
          s.side != SmaczekSide.neutral &&
          !s.attacks(record.choice),
    );
    final hasComplication = remaining.any((s) => s.side == SmaczekSide.neutral);
    if (record.smaczekTagged &&
        remaining.length == 2 &&
        hasDefense &&
        hasComplication) {
      return moved
          ? l10n.smaczkiSheetFreeHeaderMoved
          : l10n.smaczkiSheetFreeHeader;
    }
    return moved
        ? l10n.smaczkiSheetFreeHeaderMovedPlain(remaining.length)
        : l10n.smaczkiSheetFreeHeaderPlain(remaining.length);
  }

  @override
  Widget build(BuildContext context) {
    final smaczkiAsync = ref.watch(smaczkiProvider(widget.questionId));

    // A FREE user who already read the gate's argument on this question must
    // not meet it again here — that would be a broken promise at the exact
    // moment of the paywall. The sheet then opens straight on the locked
    // state: the gate's card is hidden and the remaining ones render locked
    // (the server sends free users one readable row — the gate's — anyway).
    //
    // Only a gate the user ANSWERED counts (see [ChallengeRecord.wasRead]).
    // A back press out of the gate reads as "not now", not as "read": binding
    // this to the bare existence of a record burned the free tier's headline
    // promise on an accidental swipe, leaving the sheet claiming "Pierwszy
    // masz za sobą" over nothing but locked cards until the app restarted.
    final record = ref.watch(challengeRecordsProvider)[widget.questionId];
    final ChallengeRecord? gateRead =
        !ref.watch(isPremiumProvider) && record != null && record.wasRead
        ? record
        : null;

    return Padding(
      // Rides above the keyboard when the smaczek composer has focus.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // The "Zaproponuj własny" CTA is the button under the list,
                // not a corner button here (community-arguments step 0,
                // 2026-09-05 — see [_SuggestSmaczekButton]).
                Text.rich(
                  TextSpan(
                    text: context.l10n.smaczkiTitle.toUpperCase(),
                    children: [
                      // The "(smaczki)" aside — deliberately a different
                      // cut than the condensed headline: small, quiet
                      // Manrope, lowercase.
                      TextSpan(
                        text: ' ${context.l10n.smaczkiTitleTag}',
                        style: AppTypography.support(
                          fontSize: 13,
                        ).copyWith(color: context.colors.subtle),
                      ),
                    ],
                  ),
                  style: AppTypography.title(
                    fontSize: 30,
                  ).copyWith(color: context.colors.ink),
                ),
                const SizedBox(height: 6),
                // How many arguments are still ahead of the reader — everything
                // past the one the post-vote challenge already threw at them.
                // A free reader who passed the gate gets the honest header
                // (see [_freeHeaderAfterGate]); otherwise it falls back to the
                // flat line until the list has loaded.
                Text(
                  gateRead != null
                      ? _freeHeaderAfterGate(
                          context,
                          gateRead,
                          smaczkiAsync.value,
                        )
                      : switch ((smaczkiAsync.value?.length ?? 0) - 1) {
                          final int rest when rest > 0 =>
                            context.l10n.smaczkiRemaining(rest),
                          _ => context.l10n.smaczkiSubtitle,
                        },
                  style: AppTypography.support(
                    fontSize: 13,
                  ).copyWith(color: context.colors.subtle),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                Flexible(
                  child: smaczkiAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, _) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        context.l10n.smaczkiLoadError(e.toString()),
                        style: AppTypography.body(
                          fontSize: 14,
                        ).copyWith(color: context.colors.subtle),
                      ),
                    ),
                    data: (smaczki) => _SmaczkiList(
                      smaczki: smaczki,
                      // Post-gate free view: hide the argument the gate already
                      // served and render everything else locked — never a
                      // repeat, never a second free smaczek.
                      hiddenPosition: gateRead?.smaczekPosition,
                      lockAll: gateRead != null,
                      onGetPremium: _busy ? null : _getPremium,
                    ),
                  ),
                ),
                // The way in for the user's own argument: pinned under the
                // list rather than scrolled with it, so it is on screen for
                // every list length and its glow is never clipped by the
                // scroll view. The cards' own 12px bottom margin plus this
                // gap keep the rhythm.
                if (_footer() case final footer?) ...[
                  const SizedBox(height: 4),
                  footer,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The resolved list: numbered cards for readable smaczki, blurred placeholders
/// for the locked ones — each locked card carries its own inline unlock hook.
///
/// [hiddenPosition] drops the card whose smaczek carries that position — the
/// argument the post-vote gate already served a free user. [lockAll] renders
/// every remaining card locked regardless of what the server sent, so the
/// post-gate free sheet can never leak a second readable argument. Cards keep
/// their pre-filter numbering ("2", "3"): the header just said the first one
/// is behind the reader.
class _SmaczkiList extends StatelessWidget {
  const _SmaczkiList({
    required this.smaczki,
    required this.onGetPremium,
    this.hiddenPosition,
    this.lockAll = false,
  });

  final List<Smaczek> smaczki;
  final VoidCallback? onGetPremium;
  final int? hiddenPosition;
  final bool lockAll;

  @override
  Widget build(BuildContext context) {
    final entries = <(int, Smaczek)>[
      for (var i = 0; i < smaczki.length; i++)
        if (smaczki[i].position != hiddenPosition) (i + 1, smaczki[i]),
    ];

    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          context.l10n.smaczkiEmpty,
          style: AppTypography.body(
            fontSize: 14,
          ).copyWith(color: context.colors.subtle),
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (index, smaczek) in entries)
            smaczek.isLocked || lockAll
                ? _LockedSmaczekCard(index: index, onUnlock: onGetPremium)
                : _SmaczekCard(index: index, text: smaczek.text ?? ''),
        ],
      ),
    );
  }
}

/// A readable smaczek: an orange index number and the prompt text.
class _SmaczekCard extends StatelessWidget {
  const _SmaczekCard({required this.index, required this.text});

  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: context.colors.accent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IndexDot(index: index),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: AppTypography.body(
                fontSize: 15,
                height: 1.4,
              ).copyWith(color: context.colors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// The way in for the user's own argument — the sheet's footer button
/// (community-arguments step 0, 2026-09-05; the owner's placement, over an
/// under-the-bars variant built and dropped the same day). It wears the
/// shared accent-CTA look — the spark gradient pill, its glow and the dark
/// label, the same as "go deeper" and the paywall button — and NOT a card: a
/// fourth numbered card read as a fourth smaczek, and the owner wants a
/// button. Tappable on BOTH tiers — a free user WRITES, the lock is only on
/// reading. A tap unfolds [SmaczekComposer] in its place. Logs
/// `smaczek_composer_shown` on mount — the measurement's "saw the way in"
/// denominator.
class _SuggestSmaczekButton extends StatefulWidget {
  const _SuggestSmaczekButton({required this.questionId, required this.onTap});

  final String questionId;
  final VoidCallback onTap;

  @override
  State<_SuggestSmaczekButton> createState() => _SuggestSmaczekButtonState();
}

class _SuggestSmaczekButtonState extends State<_SuggestSmaczekButton> {
  @override
  void initState() {
    super.initState();
    Analytics.log('smaczek_composer_shown', {'question_id': widget.questionId});
  }

  @override
  Widget build(BuildContext context) {
    final label = context.l10n.smaczekSuggestCta.toUpperCase();
    return Semantics(
      button: true,
      label: label,
      // One node, read once: the glyph and the text are the button's face.
      excludeSemantics: true,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: double.infinity,
          // A MINIMUM: the label follows the system font and must never be
          // painted outside the pill it belongs to (see GoDeeperButton).
          constraints: const BoxConstraints(minHeight: kMinTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            borderRadius: AppTheme.ctaRadius,
            gradient: AppTheme.ctaGradient,
            boxShadow: AppTheme.ctaGlow,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.edit_rounded,
                size: 18,
                color: AppTheme.ctaForeground,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: AppTypography.action(
                    fontSize: 14,
                  ).copyWith(color: AppTheme.ctaForeground),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A locked smaczek: a blurred dummy line plus a lock icon with a bare
/// "unlock" label beside it.
///
/// The server sent `text == null` for this one, so there is no real content on
/// the client. We render a fixed placeholder ([_dummy]) under a blur — even if
/// someone removes the blur, all they find is the dummy string, never the real
/// smaczek. Tapping the card opens the paywall ([onUnlock]; null while the
/// purchase flow is in flight).
class _LockedSmaczekCard extends StatelessWidget {
  const _LockedSmaczekCard({required this.index, required this.onUnlock});

  final int index;
  final VoidCallback? onUnlock;

  static const _dummy =
      'aaabbbbaaabbb aaabbbbaaabbb aaabbbbaaabbb aaabbbbaaabbb '
      'aaabbbbaaabbb aaabbbbaaabbb aaabbbbaaabbb aaabbbbaaabbb';

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onUnlock,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: context.colors.accent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _IndexDot(index: index, locked: true),
            const SizedBox(width: 12),
            Expanded(
              child: ClipRect(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                  child: Text(
                    _dummy,
                    maxLines: 2,
                    overflow: TextOverflow.clip,
                    style: AppTypography.body(
                      fontSize: 15,
                      height: 1.4,
                    ).copyWith(color: context.colors.subtle),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.lock_rounded, size: 18, color: AppTheme.spark),
            const SizedBox(width: 6),
            Text(
              context.l10n.smaczkiUnlockCta.toUpperCase(),
              style: AppTypography.action(
                fontSize: 12,
              ).copyWith(color: AppTheme.spark),
            ),
          ],
        ),
      ),
    );
  }
}

/// Number to the left of each smaczek: orange when readable, muted when locked.
class _IndexDot extends StatelessWidget {
  const _IndexDot({required this.index, this.locked = false});

  final int index;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 26,
      child: Text(
        '$index',
        textAlign: TextAlign.center,
        // Line box matches the 15px/1.4 smaczek text beside it, so the
        // number stays centered on the first line.
        style: AppTypography.numeric(
          20,
          height: 21 / 20,
        ).copyWith(color: locked ? context.colors.subtle : AppTheme.spark),
      ),
    );
  }
}
