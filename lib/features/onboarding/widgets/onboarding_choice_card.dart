import 'package:flutter/material.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/fit_or_scroll.dart';

/// The final card: the user picks how to start. Sign-in is the highlighted path
/// (it saves progress); starting anonymously is the quieter secondary option.
class OnboardingChoiceCard extends StatelessWidget {
  const OnboardingChoiceCard({
    super.key,
    required this.onStartAnonymous,
    required this.onSignIn,
  });

  final VoidCallback onStartAnonymous;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Both paths out of onboarding live on this card, so neither may ever be
    // pushed past the bottom of a short window or a large-font viewport —
    // overflowed children are still painted, but they stop being tappable.
    return FitOrScroll(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.onboardingChoiceTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.ink,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              l10n.onboardingChoiceBody,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.subtle,
                fontSize: 15,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 36),
            _ChoiceButton(
              label: l10n.onboardingSignInCta,
              hint: l10n.onboardingSignInHint,
              icon: Icons.person_rounded,
              primary: true,
              onTap: onSignIn,
            ),
            const SizedBox(height: 14),
            _ChoiceButton(
              label: l10n.onboardingStartAnon,
              hint: l10n.onboardingStartAnonHint,
              icon: Icons.bolt,
              primary: false,
              onTap: onStartAnonymous,
            ),
          ],
        ),
      ),
    );
  }
}

/// A full-width option on the choice card: an icon, a bold label and a small
/// hint underneath. [primary] gives it the orange gradient; otherwise it's a
/// hairline-outlined surface.
class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.label,
    required this.hint,
    required this.icon,
    required this.primary,
    required this.onTap,
  });

  final String label;
  final String hint;
  final IconData icon;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final labelColor = primary ? Colors.white : context.colors.ink;
    final hintColor = primary
        ? Colors.white.withValues(alpha: 0.85)
        : context.colors.subtle;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            gradient: primary
                ? const LinearGradient(
                    colors: [Color(0xFFF97316), Color(0xFFEA580C)],
                  )
                : null,
            color: primary ? null : context.colors.accent,
            borderRadius: BorderRadius.circular(16),
            border: primary ? null : Border.all(color: context.colors.hairline),
            boxShadow: primary
                ? [
                    BoxShadow(
                      color: AppTheme.spark.withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                Icon(icon, color: labelColor, size: 24),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: labelColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hint,
                        style: TextStyle(color: hintColor, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward, color: labelColor, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
