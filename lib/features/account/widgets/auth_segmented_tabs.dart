import 'package:flutter/material.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';

enum AuthMode { password, register }

/// Animated two-segment toggle between "sign in" and "create account".
class AuthSegmentedTabs extends StatelessWidget {
  const AuthSegmentedTabs({
    super.key,
    required this.mode,
    required this.enabled,
    required this.onChanged,
  });

  final AuthMode mode;
  final bool enabled;
  final ValueChanged<AuthMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final isLogin = mode == AuthMode.password;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.colors.accent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.hairline),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pillWidth = constraints.maxWidth / 2;
          return SizedBox(
            height: 44,
            child: Stack(
              children: [
                AnimatedAlign(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: isLogin
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  child: Container(
                    width: pillWidth,
                    height: 44,
                    decoration: BoxDecoration(
                      // The brand orange (same gradient as the primary CTA) so the
                      // selected tab matches the app accent instead of a stray violet.
                      gradient: const LinearGradient(
                        colors: [AppTheme.spark, Color(0xFFD9510B)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                Row(
                  children: [
                    _tab(
                      context,
                      context.l10n.authTabSignIn,
                      AuthMode.password,
                      isLogin,
                    ),
                    _tab(
                      context,
                      context.l10n.authTabSignUp,
                      AuthMode.register,
                      !isLogin,
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _tab(
    BuildContext context,
    String label,
    AuthMode tabMode,
    bool selected,
  ) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged(tabMode) : null,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : context.colors.subtle,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ),
    );
  }
}
