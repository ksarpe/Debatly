import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feedback/app_toast.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/locale/l10n_extension.dart';
import '../../../core/network/network_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/models/smaczek.dart';
import '../../account/providers/session_providers.dart';
import '../../account/widgets/save_pro_prompt.dart';
import '../../monetization/widgets/pro_paywall_screen.dart';
import '../providers/challenge_providers.dart';
import '../providers/question_providers.dart';

/// Shortest smaczek suggestion the server accepts — mirrors the
/// `submit_smaczek_suggestion` RPC (TOO_SHORT). The send button stays disabled
/// below it so the server error is only ever a backstop.
const int kSmaczekSuggestionMinChars = 5;

/// Longest smaczek suggestion the server accepts (RPC: TOO_LONG). Enforced
/// client-side by the field's maxLength, so the counter blocks instead of the
/// server.
const int kSmaczekSuggestionMaxChars = 80;

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

  /// Whether the "suggest your own smaczek" composer is unfolded.
  bool _composing = false;

  Future<void> _getPremium() async {
    setState(() => _busy = true);

    final purchased = await showProPaywall(
      context,
      source: PaywallSource.smaczki,
    );
    if (!mounted) return;

    if (purchased) {
      // The entitlement is the source of truth: refresh the session so the gate
      // sees the upgrade, then drop the cached smaczki so they re-fetch — this
      // time the RPC returns the now-unlocked text.
      await ref.read(sessionProvider.notifier).refresh();
      if (!mounted) return;
      ref.invalidate(smaczkiProvider(widget.questionId));
      setState(() => _busy = false);
      // A guest's PRO rides on the anonymous identity — nudge them to save it to
      // a real account. No-ops for a user who already has an account.
      await promptSaveProAccount(context, ref);
    } else {
      AppToast.info(context, context.l10n.purchaseNotCompleted);
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final smaczkiAsync = ref.watch(smaczkiProvider(widget.questionId));

    // A FREE user who already read the gate's argument on this question must
    // not meet it again here — that would be a broken promise at the exact
    // moment of the paywall. The sheet then opens straight on the locked
    // state: the gate's card is hidden and the remaining ones render locked
    // (the server sends free users one readable row — the gate's — anyway).
    final record = ref.watch(challengeRecordsProvider)[widget.questionId];
    final gatePassed = !ref.watch(isPremiumProvider) && record != null;

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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text.rich(
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
                    ),
                    // Bare text button in the top-right corner — toggles the
                    // one-line composer below.
                    TextButton(
                      onPressed: () => setState(() => _composing = !_composing),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: AppTheme.spark,
                      ),
                      child: Text(
                        context.l10n.smaczekSuggestCta.toUpperCase(),
                        style: AppTypography.action(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // How many arguments are still ahead of the reader — everything
                // past the one the post-vote challenge already threw at them.
                // A free reader who passed the gate gets the honest header
                // ("the first is behind you"); otherwise it falls back to the
                // flat line until the list has loaded.
                Text(
                  gatePassed
                      ? context.l10n.smaczkiSheetFreeHeader
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
                if (_composing) ...[
                  _SmaczekComposer(
                    questionId: widget.questionId,
                    onSent: () => setState(() => _composing = false),
                  ),
                  const SizedBox(height: 16),
                ],
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
                      hiddenPosition: gatePassed
                          ? record.smaczekPosition
                          : null,
                      lockAll: gatePassed,
                      onGetPremium: _busy ? null : _getPremium,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The one-line "suggest your own smaczek" composer, unfolded by the header's
/// text button. Sends the raw idea to the same review inbox as question
/// suggestions (`question_suggestions`, kind = 'smaczek') — nothing appears in
/// the app until the team rewrites and publishes it.
///
/// Input hygiene: single line, hard 80-char cap, control characters filtered
/// out locally AND rejected server-side; the RPC is parameterised, so the text
/// is never interpolated into SQL.
class _SmaczekComposer extends ConsumerStatefulWidget {
  const _SmaczekComposer({required this.questionId, required this.onSent});

  final String questionId;

  /// Called after a successful submit so the parent can fold the composer.
  final VoidCallback onSent;

  @override
  ConsumerState<_SmaczekComposer> createState() => _SmaczekComposerState();
}

class _SmaczekComposerState extends ConsumerState<_SmaczekComposer> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _trimmedLength => _controller.text.trim().length;

  bool get _canSend => !_busy && _trimmedLength >= kSmaczekSuggestionMinChars;

  Future<void> _submit() async {
    if (!_canSend) return;
    setState(() => _busy = true);
    // Captured before the await: a success folds the composer away, after
    // which `context` is unusable — the toast rides the root overlay instead.
    final l10n = context.l10n;
    final overlay = AppToast.capture(context);
    try {
      await ref
          .read(questionRepositoryProvider)
          .submitSmaczekSuggestion(
            questionId: widget.questionId,
            text: _controller.text.trim(),
          );
      widget.onSent();
      AppToast.showOn(
        overlay,
        l10n.suggestQuestionThanks,
        type: ToastType.success,
      );
    } catch (e) {
      // The shared daily cap gets its own friendlier line; offline gets the
      // calm "no connection"; anything else is the generic failure.
      final message = e.toString().contains('RATE_LIMITED')
          ? l10n.suggestQuestionRateLimited
          : isOfflineError(e)
          ? l10n.noConnection
          : l10n.suggestQuestionFailed;
      AppToast.showOn(overlay, message, type: ToastType.error);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return TextField(
      controller: _controller,
      enabled: !_busy,
      autofocus: true,
      maxLength: kSmaczekSuggestionMaxChars,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.send,
      inputFormatters: [
        // Belt and braces against pasted control characters — the RPC rejects
        // them too (BAD_TEXT), this just keeps the error out of the UX.
        FilteringTextInputFormatter.deny(RegExp(r'[\x00-\x1F\x7F]')),
      ],
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _submit(),
      style: AppTypography.body(fontSize: 14).copyWith(color: colors.ink),
      decoration: InputDecoration(
        hintText: context.l10n.smaczekSuggestHint,
        hintStyle: AppTypography.support(
          fontSize: 13,
        ).copyWith(color: colors.subtle),
        isDense: true,
        // Nudges toward the minimum while typing the first few words, then
        // gets out of the way.
        helperText:
            _trimmedLength > 0 && _trimmedLength < kSmaczekSuggestionMinChars
            ? context.l10n.smaczekSuggestMinChars
            : null,
        helperStyle: AppTypography.support().copyWith(color: colors.subtle),
        counterStyle: AppTypography.support().copyWith(color: colors.subtle),
        suffixIcon: _busy
            ? const Padding(
                padding: EdgeInsets.all(10),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IconButton(
                tooltip: context.l10n.smaczekSuggestSend,
                icon: const Icon(Icons.send_rounded, size: 20),
                color: _canSend ? AppTheme.spark : colors.subtle,
                onPressed: _canSend ? _submit : null,
              ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.spark),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.hairline),
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
