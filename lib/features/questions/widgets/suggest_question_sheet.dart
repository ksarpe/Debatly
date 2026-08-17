import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feedback/app_toast.dart';
import '../../../core/locale/l10n_extension.dart';
import '../../../core/network/network_error.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/question_providers.dart';

/// Shortest suggestion the server accepts — mirrors the
/// `submit_question_suggestion` RPC, which rejects anything shorter as
/// TOO_SHORT. The send button stays disabled below it so the server error is
/// only ever a backstop.
const int kSuggestionMinChars = 10;

/// Longest suggestion the server accepts (RPC: TOO_LONG). Enforced client-side
/// by the field's maxLength, so the counter blocks instead of the server.
const int kSuggestionMaxChars = 500;

/// Opens the "Suggest a question" bottom sheet — the user's raw idea goes to
/// the team's review inbox (`question_suggestions`), not into the catalog.
///
/// Reached from the Settings card and from the one-time post-vote nudge
/// (see `maybePromptSuggestQuestion`).
Future<void> showSuggestQuestionSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.colors.cardSurface,
    // The keyboard eats most of a phone screen; without this the sheet is
    // capped at 9/16 and the send button ends up underneath the keyboard.
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const SuggestQuestionSheet(),
  );
}

/// The sheet body: a short pitch for what makes a good question, a free-text
/// field and a send button. One field on purpose — ideas arrive raw and get
/// rewritten into proper PL/EN + smaczki by the content flow, so asking for
/// category/translation here would only raise the bar to zero submissions.
class SuggestQuestionSheet extends ConsumerStatefulWidget {
  const SuggestQuestionSheet({super.key});

  @override
  ConsumerState<SuggestQuestionSheet> createState() =>
      _SuggestQuestionSheetState();
}

class _SuggestQuestionSheetState extends ConsumerState<SuggestQuestionSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _trimmedLength => _controller.text.trim().length;

  bool get _canSend => !_busy && _trimmedLength >= kSuggestionMinChars;

  Future<void> _submit() async {
    if (!_canSend) return;
    setState(() => _busy = true);
    // Captured before the await: the sheet pops on success, after which
    // `context` is unusable — the toast rides the root overlay instead.
    final l10n = context.l10n;
    final navigator = Navigator.of(context);
    final overlay = AppToast.capture(context);
    try {
      await ref
          .read(questionRepositoryProvider)
          .submitQuestionSuggestion(_controller.text.trim());
      navigator.pop();
      AppToast.showOn(
        overlay,
        l10n.suggestQuestionThanks,
        type: ToastType.success,
      );
    } catch (e) {
      // The RPC's daily cap gets its own friendlier line; offline gets the
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
    return Padding(
      // Rides above the keyboard, which is what pushes the sheet up.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.spark.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lightbulb_outline_rounded,
                      color: AppTheme.spark,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      context.l10n.suggestQuestionTitle,
                      style: TextStyle(
                        color: colors.ink,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                context.l10n.suggestQuestionIntro,
                style: TextStyle(
                  color: colors.subtle,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                enabled: !_busy,
                autofocus: true,
                minLines: 3,
                maxLines: 5,
                maxLength: kSuggestionMaxChars,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(color: colors.ink, fontSize: 15, height: 1.35),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: context.l10n.suggestQuestionHint,
                  hintStyle: TextStyle(color: colors.subtle),
                  // Nudges toward the minimum while typing the first few words,
                  // then gets out of the way.
                  helperText:
                      _trimmedLength > 0 && _trimmedLength < kSuggestionMinChars
                      ? context.l10n.suggestQuestionMinChars
                      : null,
                  helperStyle: TextStyle(color: colors.subtle, fontSize: 12),
                  counterStyle: TextStyle(color: colors.subtle, fontSize: 12),
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
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _canSend ? _submit : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.spark,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        context.l10n.suggestQuestionSend,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
