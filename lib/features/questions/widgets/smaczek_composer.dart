import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feedback/app_toast.dart';
import '../../../core/locale/l10n_extension.dart';
import '../../../core/network/network_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../services/analytics.dart';
import '../providers/question_providers.dart';

/// Shortest smaczek suggestion the server accepts — mirrors the
/// `submit_smaczek_suggestion` RPC (TOO_SHORT). The send button stays disabled
/// below it so the server error is only ever a backstop.
const int kSmaczekSuggestionMinChars = 5;

/// Longest smaczek suggestion the server accepts (RPC: TOO_LONG). Enforced
/// client-side by the field's maxLength, so the counter blocks instead of the
/// server.
const int kSmaczekSuggestionMaxChars = 80;

/// The one-line "suggest your own smaczek" composer, unfolded under the
/// Arguments sheet's list in place of the "Zaproponuj własny" button (see
/// `smaczki_panel.dart`). Sends the raw idea to the same review inbox as
/// question suggestions (`question_suggestions`, kind = 'smaczek') — nothing
/// appears in the app until the team rewrites and publishes it.
///
/// Community-arguments step 0 (2026-09-05): this is the measurement surface —
/// whether daily voters write at all decides whether anything gets built to
/// publish from it. Events with `question_id`: `smaczek_composer_sent`
/// (with the length) and `smaczek_composer_failed` (`reason`: rate_limited /
/// offline / other); the button that unfolds it logs `_shown` and `_opened`.
///
/// Input hygiene: single line, hard 80-char cap, control characters filtered
/// out locally AND rejected server-side; the RPC is parameterised, so the text
/// is never interpolated into SQL.
class SmaczekComposer extends ConsumerStatefulWidget {
  const SmaczekComposer({
    required this.questionId,
    required this.onSent,
    super.key,
  });

  final String questionId;

  /// Called after a successful submit so the parent can fold the composer
  /// back into its button.
  final VoidCallback onSent;

  @override
  ConsumerState<SmaczekComposer> createState() => _SmaczekComposerState();
}

class _SmaczekComposerState extends ConsumerState<SmaczekComposer> {
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
    final text = _controller.text.trim();
    // Captured before the await: a success folds the composer away, after
    // which `context` is unusable — the toast rides the root overlay instead.
    final l10n = context.l10n;
    final overlay = AppToast.capture(context);
    try {
      await ref
          .read(questionRepositoryProvider)
          .submitSmaczekSuggestion(questionId: widget.questionId, text: text);
      Analytics.log('smaczek_composer_sent', {
        'question_id': widget.questionId,
        'length': text.length,
      });
      widget.onSent();
      AppToast.showOn(
        overlay,
        l10n.suggestQuestionThanks,
        type: ToastType.success,
      );
    } catch (e) {
      // The shared daily cap gets its own friendlier line; offline gets the
      // calm "no connection"; anything else is the generic failure. The
      // composer stays open with the text in every case — nobody retypes 80
      // characters.
      final rateLimited = e.toString().contains('RATE_LIMITED');
      final offline = !rateLimited && isOfflineError(e);
      Analytics.log('smaczek_composer_failed', {
        'question_id': widget.questionId,
        'reason': rateLimited
            ? 'rate_limited'
            : offline
            ? 'offline'
            : 'other',
      });
      final message = rateLimited
          ? l10n.suggestQuestionRateLimited
          : offline
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
      // Unfolded by a tap on the button, so the keyboard is what that tap
      // asked for.
      autofocus: true,
      maxLength: kSmaczekSuggestionMaxChars,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.send,
      inputFormatters: [
        // Belt and braces against pasted control characters — the RPC
        // rejects them too (BAD_TEXT), this just keeps the error out of
        // the UX.
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
