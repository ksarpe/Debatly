import 'package:flutter/material.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';

/// Shown on the reveal slot when the user has run out of eligible questions.
/// Not a dead end even without an explicit link: a rightward swipe steps back
/// through the session's questions, same as everywhere else in the feed.
class NoMoreQuestions extends StatelessWidget {
  const NoMoreQuestions({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.check_circle_outline,
          color: context.colors.subtle,
          size: 40,
        ),
        const SizedBox(height: 16),
        Text(
          context.l10n.noMoreTitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.colors.ink,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.noMoreBody,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.colors.subtle, fontSize: 14),
        ),
      ],
    );
  }
}
