import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../providers/app_info_provider.dart';
import 'account_action_buttons.dart';

/// The bottom of the settings page: the delete-account button — sign-out lives
/// in the "Account" card as its last row; a guest's "secure account" action
/// sits at the TOP of the page, under the profile header — followed by a quiet
/// build stamp that signs off the page the way mature apps do.
///
/// **Delete is offered to GUESTS too**, and that is not an oversight. Every
/// user has a real Supabase identity from launch, and the overwhelming
/// majority of them never register: an anonymous user holds votes, a streak
/// and a debate profile, i.e. exactly the personal data App Store Guideline
/// 5.1.1(v) and Play require an in-app way to erase. Hiding the row behind
/// "has an email" left almost the whole install base with only the fallback
/// web form, which identifies people by an address a guest does not have. The
/// `delete-account` edge function works off the caller's JWT and deletes an
/// anonymous user exactly as happily as a registered one.
///
/// The owning [SettingsScreen] keeps the action logic; this widget is the
/// visual section and forwards taps.
class SettingsSessionActions extends StatelessWidget {
  const SettingsSessionActions({
    super.key,
    required this.appInfo,
    required this.onDeleteAccount,
  });

  final AppInfo? appInfo;
  final VoidCallback onDeleteAccount;

  @override
  Widget build(BuildContext context) {
    final appInfo = this.appInfo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---- Session actions --------------------------------
        const SizedBox(height: 26),
        DeleteAccountButton(onTap: onDeleteAccount),

        // Quiet build stamp + copyright at the very bottom, the way
        // mature apps sign off their settings page.
        if (appInfo != null) ...[
          const SizedBox(height: 24),
          Center(
            child: Text(
              'Debatly · v${appInfo.version} (${appInfo.build}) · © 2026',
              style: AppTypography.support().copyWith(
                color: context.colors.subtle,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
