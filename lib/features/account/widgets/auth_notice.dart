import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';

class AuthNotice extends StatelessWidget {
  const AuthNotice({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: context.colors.hairline),
        borderRadius: BorderRadius.circular(12),
        color: context.colors.cardSurface,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: context.colors.sparkInk, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: AppTypography.body(
                  fontSize: 14,
                  height: 1.35,
                ).copyWith(color: context.colors.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
