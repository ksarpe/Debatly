import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/content_width.dart';
import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/spark_cta_button.dart';
import '../../../services/analytics.dart';
import '../../../services/review_service.dart';
import '../providers/review_providers.dart';
import 'app_feedback_sheet.dart';

/// What the user told us on the pre-prompt. A dismissed sheet (system back /
/// tap outside / "later") is `null` — it counts as the one ask, but we learn
/// nothing from it.
enum ReviewPrePromptAnswer { loving, couldBeBetter }

/// Opens the "How's Debatly treating you?" sheet — our OWN card in front of
/// the OS review ask — and resolves with the user's answer.
///
/// Why a pre-prompt at all: the native rating sheet is quota-limited (iOS:
/// roughly three shows a year) and gives no signal back, so spending it on
/// someone who is about to leave a 2-star review is the worst possible use.
/// Asking first routes the happy to the store and the unhappy to us
/// ([showAppFeedbackSheet]). Deliberately NO stars, no rating widget of our
/// own: a custom prompt that mimics the store rating is what Apple rejects,
/// and there is no reward on either branch — both store policies forbid
/// incentivised reviews, and nothing could verify one anyway.
///
/// Pure UI: no counters, no prefs — the timing lives in
/// `ReviewPromptController.claimDueReviewAsk`, the follow-through in
/// [runReviewPrePromptFlow].
Future<ReviewPrePromptAnswer?> showReviewPrePrompt(BuildContext context) {
  return showModalBottomSheet<ReviewPrePromptAnswer>(
    context: context,
    backgroundColor: context.colors.cardSurface,
    // Tablets: keep the sheet a centred column instead of stretching two
    // buttons across an iPad.
    constraints: const BoxConstraints(maxWidth: kReadingMaxWidth),
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const ReviewPrePromptSheet(),
  );
}

/// Shows the pre-prompt and acts on the answer: "loving it" hands over to the
/// OS review sheet, "could be better" opens the feedback sheet, a dismissal
/// does nothing. Every answer is logged with the [milestone] that earned the
/// ask (null from the DEV preview).
///
/// Spends nothing — callers that gate the ask claim the milestone first
/// ([maybePromptForReview]); the DEV screen calls this directly to replay the
/// whole flow without touching the counters.
Future<ReviewPrePromptAnswer?> runReviewPrePromptFlow(
  BuildContext context, {
  int? milestone,
}) async {
  Analytics.log('review_pre_prompt_shown', {'milestone': milestone});
  final answer = await showReviewPrePrompt(context);
  Analytics.log('review_pre_prompt_answered', {
    'milestone': milestone,
    'answer': answer?.name ?? 'dismissed',
  });
  switch (answer) {
    case ReviewPrePromptAnswer.loving:
      // The OS decides whether its sheet actually appears (quota, debug
      // builds) and never tells us — best-effort by design.
      Analytics.log('review_prompt_requested', {'milestone': milestone});
      await ReviewService.requestReview();
    case ReviewPrePromptAnswer.couldBeBetter:
      if (context.mounted) await showAppFeedbackSheet(context);
    case null:
      break;
  }
  return answer;
}

/// Fires the review ask if a vote milestone is due; no-ops otherwise.
/// Returns whether an ask was spent, so the caller can keep the
/// one-dialog-per-vote rule.
///
/// The milestone is claimed BEFORE the sheet opens (see
/// `ReviewPromptController.claimDueReviewAsk`), so an unmounted caller or a
/// dismissed sheet still retires it instead of re-firing on the next vote.
Future<bool> maybePromptForReview(BuildContext context, WidgetRef ref) async {
  final milestone = await ref
      .read(reviewPromptControllerProvider.notifier)
      .claimDueReviewAsk();
  if (milestone == null) return false;
  if (!context.mounted) return true;
  await runReviewPrePromptFlow(context, milestone: milestone);
  return true;
}

/// The sheet body: spark-tinted star, the question, one line of why, and the
/// two answers — the happy path as the lit CTA, the other as a quiet outlined
/// button — plus a "later" escape. Never a trap: back / tap-outside dismiss.
class ReviewPrePromptSheet extends StatelessWidget {
  const ReviewPrePromptSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    return SafeArea(
      // Scrollable so a short viewport (landscape, split screen, a small
      // phone with a large font) clips nothing — the "later" escape at the
      // bottom must always be reachable.
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
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
                    Icons.star_rounded,
                    color: AppTheme.spark,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    l10n.reviewPrePromptTitle.toUpperCase(),
                    style: AppTypography.title(
                      fontSize: 30,
                    ).copyWith(color: colors.ink),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              l10n.reviewPrePromptBody,
              style: AppTypography.body(
                fontSize: 14,
                height: 1.4,
              ).copyWith(color: colors.subtle),
            ),
            const SizedBox(height: 20),
            SparkCtaButton(
              label: l10n.reviewPrePromptLoving,
              icon: Icons.favorite_rounded,
              expand: true,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 15),
              onTap: () =>
                  Navigator.of(context).pop(ReviewPrePromptAnswer.loving),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => Navigator.of(
                context,
              ).pop(ReviewPrePromptAnswer.couldBeBetter),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.ink,
                side: BorderSide(color: colors.hairline),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 15,
                ),
                textStyle: AppTypography.action(fontSize: 14),
              ),
              child: Text(l10n.reviewPrePromptCouldBeBetter.toUpperCase()),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: colors.subtle,
                textStyle: AppTypography.action(),
              ),
              child: Text(l10n.later.toUpperCase()),
            ),
          ],
        ),
      ),
    );
  }
}
