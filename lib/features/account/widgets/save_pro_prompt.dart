import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../providers/session_providers.dart';
import '../screens/auth_screen.dart';
import 'auth_segmented_tabs.dart' show AuthMode;

/// Gold accent shared with the "go Premium" upsell + auth notices.
const Color _kGold = Color(0xFFFFC857);

/// After a guest buys PRO, nudges them to attach the purchase to a real account.
///
/// A guest's entitlement rides on the anonymous Supabase identity, which is lost
/// on reinstall or a second device (store-level restore still works, but a saved
/// account is the friendlier, recoverable path — and registering with
/// email/password upgrades the anonymous user in place, so the same UUID keeps
/// the entitlement).
///
/// No-ops unless the session is now premium AND still a guest.
///
/// `HomeGate` owns the trigger: it fires this on the resolved free→premium
/// flip, which covers every entry point that can buy ONCE THE GATE IS MOUNTED.
/// Purchase sites under the gate must NOT call it as well — their own
/// `session.refresh()` is what produces that flip, so the two stacked and the
/// user dismissed the identical "PRO ACTIVE 🎉" dialog twice, seconds after
/// money changed hands.
///
/// The single exception is the onboarding bridge (`OnboardingBridgeCard`),
/// which sits in the onboarding phase — `HomeGate` isn't built yet, so its
/// `ref.listen` never sees that flip and cannot cover a purchase made there.
/// It calls this itself.
///
/// [_prompting] is the guard that keeps a stray second call (or a restore
/// landing on top of a purchase) from bringing it back.
Future<void> promptSaveProAccount(BuildContext context, WidgetRef ref) async {
  if (_prompting) return;
  final session = ref.read(sessionProvider).value;
  if (session == null || !session.isPremium || session.hasAccount) return;

  _prompting = true;
  try {
    await _showSavePrompt(context);
  } finally {
    _prompting = false;
  }
}

/// True while a prompt (or the account sheet behind it) is on screen — see
/// [promptSaveProAccount].
bool _prompting = false;

Future<void> _showSavePrompt(BuildContext context) async {
  final wantsAccount = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.62),
    builder: (dialogContext) => AlertDialog(
      backgroundColor: context.colors.cardSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 10),
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _kGold.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.workspace_premium_outlined,
              color: _kGold,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              context.l10n.proActiveTitle.toUpperCase(),
              style: AppTypography.title(
                fontSize: 30,
              ).copyWith(color: context.colors.ink),
            ),
          ),
        ],
      ),
      content: Text(
        context.l10n.savePromptBody,
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
          child: Text(context.l10n.later.toUpperCase()),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.spark,
            textStyle: AppTypography.action(),
          ),
          child: Text(context.l10n.createAccount.toUpperCase()),
        ),
      ],
    ),
  );

  if (wantsAccount == true && context.mounted) {
    // The REGISTER tab: PRO rides on the anonymous UUID, and only registering
    // keeps that UUID (it upgrades the user in place). Signing in would switch
    // to another account — the opposite of "attach this purchase to something
    // recoverable".
    await showAuthSheet(context, initialMode: AuthMode.register);
  }
}
