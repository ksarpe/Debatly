import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';

/// The orange gradient "Next" call-to-action, matching the auth sheet's primary
/// button so onboarding and sign-in feel like one family.
class OnboardingPrimaryButton extends StatelessWidget {
  const OnboardingPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppTheme.ctaGradient,
        borderRadius: AppTheme.ctaRadius,
        boxShadow: AppTheme.ctaGlow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: AppTheme.ctaRadius,
          child: SizedBox(
            height: 56,
            width: double.infinity,
            child: Center(
              child: Text(
                label.toUpperCase(),
                style: AppTypography.action(
                  fontSize: 14,
                ).copyWith(color: AppTheme.ctaForeground),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
