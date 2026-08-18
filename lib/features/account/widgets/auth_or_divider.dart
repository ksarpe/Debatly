import 'package:flutter/material.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';

/// "—— LUB ——" separator.
class AuthOrDivider extends StatelessWidget {
  const AuthOrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: context.colors.hairline)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            context.l10n.orDivider.toUpperCase(),
            style: AppTypography.eyebrow(
              fontSize: 11,
            ).copyWith(color: context.colors.subtle),
          ),
        ),
        Expanded(child: Divider(color: context.colors.hairline)),
      ],
    );
  }
}
