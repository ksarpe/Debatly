import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feedback/app_toast.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/locale/l10n_extension.dart';
import '../../../core/network/network_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/spark_cta_button.dart';
import '../../questions/providers/question_providers.dart';

/// Shortest feedback the server accepts — mirrors the `submit_app_feedback`
/// RPC, which rejects anything shorter as TOO_SHORT. The send button stays
/// disabled below it so the server error is only ever a backstop.
const int kAppFeedbackMinChars = 10;

/// Longest feedback the server accepts (RPC: TOO_LONG). Enforced client-side
/// by the field's maxLength, so the counter blocks instead of the server.
const int kAppFeedbackMaxChars = 500;

/// Opens the "What should we fix?" bottom sheet — the "could be better" branch
/// of the review pre-prompt (`showReviewPrePrompt`). The text goes to the
/// team's review inbox (`question_suggestions`, kind = 'feedback'), never to
/// the store: an unhappy user gets heard by us instead of by the rating.
Future<void> showAppFeedbackSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.colors.cardSurface,
    // The keyboard eats most of a phone screen; without this the sheet is
    // capped at 9/16 and the send button ends up underneath the keyboard.
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: kReadingMaxWidth),
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const AppFeedbackSheet(),
  );
}

/// The sheet body: a short pitch, a free-text field and a send button — the
/// same one-field shape as the question-suggestion sheet, because a form with
/// categories and ratings here would only lower the number of people who
/// actually tell us what's wrong.
class AppFeedbackSheet extends ConsumerStatefulWidget {
  const AppFeedbackSheet({super.key});

  @override
  ConsumerState<AppFeedbackSheet> createState() => _AppFeedbackSheetState();
}

class _AppFeedbackSheetState extends ConsumerState<AppFeedbackSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _trimmedLength => _controller.text.trim().length;

  bool get _canSend => !_busy && _trimmedLength >= kAppFeedbackMinChars;

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
          .submitAppFeedback(_controller.text.trim());
      navigator.pop();
      AppToast.showOn(overlay, l10n.appFeedbackThanks, type: ToastType.success);
    } catch (e) {
      // The RPC's daily cap gets its own friendlier line; offline gets the
      // calm "no connection"; anything else is the generic failure.
      final message = e.toString().contains('RATE_LIMITED')
          ? l10n.appFeedbackRateLimited
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
                      Icons.build_rounded,
                      color: AppTheme.spark,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      context.l10n.appFeedbackTitle.toUpperCase(),
                      style: AppTypography.title(
                        fontSize: 30,
                      ).copyWith(color: colors.ink),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                context.l10n.appFeedbackIntro,
                style: AppTypography.body(
                  fontSize: 14,
                  height: 1.4,
                ).copyWith(color: colors.subtle),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                enabled: !_busy,
                autofocus: true,
                minLines: 3,
                maxLines: 6,
                maxLength: kAppFeedbackMaxChars,
                textCapitalization: TextCapitalization.sentences,
                style: AppTypography.body(
                  fontSize: 15,
                  height: 1.35,
                ).copyWith(color: colors.ink),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: context.l10n.appFeedbackHint,
                  hintStyle: AppTypography.support(
                    fontSize: 13,
                  ).copyWith(color: colors.subtle),
                  // Nudges toward the minimum while typing the first few words,
                  // then gets out of the way.
                  helperText:
                      _trimmedLength > 0 &&
                          _trimmedLength < kAppFeedbackMinChars
                      ? context.l10n.suggestQuestionMinChars
                      : null,
                  helperStyle: AppTypography.support().copyWith(
                    color: colors.subtle,
                  ),
                  counterStyle: AppTypography.support().copyWith(
                    color: colors.subtle,
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
              ),
              const SizedBox(height: 8),
              SparkCtaButton(
                label: context.l10n.appFeedbackSend,
                busy: _busy,
                expand: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 15,
                ),
                onTap: _canSend ? _submit : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
