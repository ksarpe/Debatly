import 'package:flutter/material.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import 'settings_primitives.dart';

/// "Sign out" row for the bottom of the "Account" card: red label, no chevron
/// (it's an action, not navigation). Shows a spinner and ignores taps while a
/// sign-out is in flight, so a slow token revoke never looks like a dead row
/// or fires twice.
class SignOutRow extends StatelessWidget {
  const SignOutRow({super.key, required this.onTap, this.loading = false});

  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: loading ? null : onTap,
      child: Padding(
        // Matches SettingsNavRow's metrics so the card reads as one list.
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            if (loading)
              const SizedBox(
                width: 22,
                height: 22,
                child: Padding(
                  padding: EdgeInsets.all(2),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: kDanger,
                  ),
                ),
              )
            else
              const Icon(Icons.logout_rounded, color: kDanger, size: 22),
            const SizedBox(width: 16),
            Text(
              context.l10n.signOut.toUpperCase(),
              style: AppTypography.action(
                fontSize: 14,
              ).copyWith(color: kDanger),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-width gradient "Secure account" action, shown to guests right under the
/// profile header. Opens the sign-in sheet: registering upgrades the anonymous
/// user in place (same UUID), which is what "securing" means — the streak,
/// votes and any PRO purchase survive a reinstall or a new phone.
class SecureAccountButton extends StatelessWidget {
  const SecureAccountButton({super.key, required this.onTap});

  final VoidCallback onTap;

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
          onTap: onTap,
          borderRadius: AppTheme.ctaRadius,
          child: SizedBox(
            height: 54,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.shield_outlined,
                  color: AppTheme.ctaForeground,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(
                  context.l10n.secureAccount.toUpperCase(),
                  style: AppTypography.action(
                    fontSize: 14,
                  ).copyWith(color: AppTheme.ctaForeground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Centred destructive "Delete account" text action.
class DeleteAccountButton extends StatelessWidget {
  const DeleteAccountButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: onTap,
        style: TextButton.styleFrom(foregroundColor: kDanger),
        icon: const Icon(Icons.delete_outline_rounded, size: 18),
        // Colour comes from the button's kDanger foreground, so the style
        // deliberately carries no colour of its own.
        label: Text(
          context.l10n.deleteAccount.toUpperCase(),
          style: AppTypography.action(fontSize: 13),
        ),
      ),
    );
  }
}
