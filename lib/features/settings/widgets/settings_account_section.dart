import 'package:flutter/material.dart';

import '../../../core/locale/l10n_extension.dart';
import 'account_action_buttons.dart';
import 'premium_active_row.dart';
import 'settings_nav_row.dart';
import 'settings_primitives.dart';

/// The "Account" card: subscription status (the active-premium row that opens
/// the manage sheet, or a gold "go Premium" upsell), the privacy & data entry,
/// restore-purchases and — for a signed-in user — the red sign-out row at the
/// very bottom.
///
/// The owning [SettingsScreen] keeps the actions; this widget is the visual
/// section and forwards taps back up through its callbacks.
class SettingsAccountSection extends StatelessWidget {
  const SettingsAccountSection({
    super.key,
    required this.isPremium,
    required this.localeCode,
    required this.hasAccount,
    required this.signingOut,
    required this.onManageSubscription,
    required this.onGoPremium,
    required this.onPrivacy,
    required this.onRestore,
    required this.onSignOut,
  });

  final bool isPremium;
  final String localeCode;
  final bool hasAccount;

  /// True while a sign-out is in flight — the row swaps its icon for a spinner
  /// and ignores taps so it can't fire twice.
  final bool signingOut;
  final VoidCallback onManageSubscription;
  final VoidCallback onGoPremium;
  final VoidCallback onPrivacy;
  final VoidCallback onRestore;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---- Account ----------------------------------------
        SettingsSectionLabel(context.l10n.settingsSectionAccount),
        const SizedBox(height: 12),
        SettingsCard(
          children: [
            if (isPremium)
              PremiumActiveRow(
                localeCode: localeCode,
                onTap: onManageSubscription,
              )
            else
              SettingsNavRow(
                icon: Icons.star_rounded,
                iconColor: kGold,
                title: context.l10n.settingsGoPremium,
                titleColor: kGold,
                onTap: onGoPremium,
              ),
            const SettingsRowDivider(),
            SettingsNavRow(
              icon: Icons.shield_outlined,
              title: context.l10n.settingsPrivacy,
              onTap: onPrivacy,
            ),
            const SettingsRowDivider(),
            SettingsNavRow(
              icon: Icons.restore_rounded,
              title: context.l10n.restorePurchase,
              onTap: onRestore,
            ),
            if (hasAccount) ...[
              const SettingsRowDivider(),
              SignOutRow(onTap: onSignOut, loading: signingOut),
            ],
          ],
        ),
      ],
    );
  }
}
