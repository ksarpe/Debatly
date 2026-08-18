import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../providers/session_providers.dart';
import '../screens/auth_screen.dart';

/// Guards a store restore behind a "sign in instead?" chooser for guests.
///
/// RevenueCat's restore TRANSFERS the receipt's entitlement onto the CURRENT
/// app user id — for a guest that's a fresh anonymous identity, so a user who
/// originally bought PRO while signed in ends up premium on an empty account
/// (favorites, votes, streak and rank stay behind on the old one) and the old
/// account loses the entitlement. Signing back in is the path that brings PRO
/// *and* the data back (identify + entitlement sync run on login), so it is
/// offered first; "restore on this device" stays available for people who
/// genuinely bought as a guest (Apple requires the store path to exist).
///
/// Returns true when the caller should proceed with the store restore: the
/// session already has a real account (no dialog shown), or the guest
/// explicitly chose to restore here. Choosing to sign in opens the auth sheet
/// (the login flow re-syncs premium by itself) and returns false; dismissing
/// the dialog returns false.
Future<bool> confirmGuestRestore(BuildContext context, WidgetRef ref) async {
  final session = ref.read(sessionProvider).value;
  if (session?.hasAccount ?? false) return true;

  final wantsSignIn = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.62),
    builder: (dialogContext) => AlertDialog(
      backgroundColor: context.colors.cardSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        context.l10n.restoreSignInTitle.toUpperCase(),
        style: AppTypography.title(
          fontSize: 30,
        ).copyWith(color: context.colors.ink),
      ),
      content: Text(
        context.l10n.restoreSignInBody,
        style: AppTypography.body(
          height: 1.4,
        ).copyWith(color: context.colors.subtle),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          style: TextButton.styleFrom(
            foregroundColor: context.colors.subtle,
            textStyle: AppTypography.action(),
          ),
          child: Text(context.l10n.restoreOnThisDevice.toUpperCase()),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.spark,
            textStyle: AppTypography.action(),
          ),
          child: Text(context.l10n.signIn.toUpperCase()),
        ),
      ],
    ),
  );

  if (wantsSignIn == null) return false; // dismissed — do nothing
  if (!wantsSignIn) return true; // "restore on this device"

  if (context.mounted) await showAuthSheet(context);
  return false;
}
