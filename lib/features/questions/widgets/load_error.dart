import 'package:flutter/material.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';

/// Shown when the launch fetch fails (typically no network) and there is nothing
/// to render. Replaces the old endless spinner with a friendly message and a
/// retry that re-runs sign-in + the question/daily/stats fetches.
class LoadError extends StatelessWidget {
  const LoadError({super.key, required this.onRetry, this.title, this.body});

  final VoidCallback onRetry;

  /// Overrides the headline. The default names the questions, which is right
  /// for a failed fetch; a backend that never came up isn't about questions at
  /// all, and saying so is the difference between "try again later" and
  /// "nothing you do right now is being saved".
  final String? title;

  /// Overrides the explanation under the title. The default blames the network,
  /// which is right for a thrown fetch — but the feed also lands here when every
  /// fetch SUCCEEDED and simply produced no question, where telling somebody
  /// with four bars to check their connection sends them chasing the wrong
  /// thing.
  final String? body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, color: context.colors.subtle, size: 40),
            const SizedBox(height: 16),
            Text(
              (title ?? context.l10n.loadErrorTitle).toUpperCase(),
              textAlign: TextAlign.center,
              style: AppTypography.title(
                fontSize: 30,
              ).copyWith(color: context.colors.ink),
            ),
            const SizedBox(height: 8),
            Text(
              body ?? context.l10n.loadErrorBody,
              textAlign: TextAlign.center,
              style: AppTypography.body(
                fontSize: 14,
              ).copyWith(color: context.colors.subtle),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onRetry,
              child: Text(
                context.l10n.tryAgain.toUpperCase(),
                style: AppTypography.action(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
