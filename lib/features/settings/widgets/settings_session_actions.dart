import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/app_info_provider.dart';
import 'account_action_buttons.dart';

/// The bottom of the settings page: the session-action buttons (delete for a
/// real account — sign-out lives in the "Account" card as its last row; a
/// guest's "secure account" action sits at the TOP of the page, under the
/// profile header) followed by a quiet build stamp that signs off the page the
/// way mature apps do.
///
/// The owning [SettingsScreen] keeps the action logic; this widget is the
/// visual section and forwards taps.
class SettingsSessionActions extends StatelessWidget {
  const SettingsSessionActions({
    super.key,
    required this.hasAccount,
    required this.appInfo,
    required this.onDeleteAccount,
  });

  final bool hasAccount;
  final AppInfo? appInfo;
  final VoidCallback onDeleteAccount;

  @override
  Widget build(BuildContext context) {
    final appInfo = this.appInfo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---- Session actions --------------------------------
        if (hasAccount) ...[
          const SizedBox(height: 26),
          DeleteAccountButton(onTap: onDeleteAccount),
        ],

        // Quiet build stamp + copyright at the very bottom, the way
        // mature apps sign off their settings page.
        if (appInfo != null) ...[
          const SizedBox(height: 24),
          Center(
            child: Text(
              'Debatly · v${appInfo.version} (${appInfo.build}) · © 2026',
              style: TextStyle(color: context.colors.subtle, fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }
}
