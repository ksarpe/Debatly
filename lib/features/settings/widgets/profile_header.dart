import 'package:flutter/material.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/sub_screen_chrome.dart';
import '../../account/providers/session_providers.dart';

/// Soft orange radial glow anchored to the top of the screen.
/// Left-aligned identity block with a close button floating in the
/// top-right corner.
///
/// For a signed-in user the identity is the e-mail itself (we don't collect a
/// login or display name). A guest keeps the "guest session" title + a note
/// that their progress lives only on this phone — the SecureAccountButton
/// right below the header is the fix it points at.
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.account,
    required this.hasAccount,
    required this.onClose,
  });

  final SessionState? account;
  final bool hasAccount;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topLeft,
      clipBehavior: Clip.none,
      children: [
        Padding(
          // Reserve room on the right so the title never slides under the
          // floating close button.
          padding: const EdgeInsets.only(right: 44),
          child: hasAccount ? _accountBlock(context) : _guestBlock(context),
        ),
        Align(
          alignment: Alignment.topRight,
          child: SubScreenCloseButton(onTap: onClose),
        ),
      ],
    );
  }

  /// E-mail as the orange title.
  Widget _accountBlock(BuildContext context) {
    final email = account?.email ?? '';
    final title = email.isNotEmpty ? email : context.l10n.yourAccount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Text(
          title,
          textAlign: TextAlign.left,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppTheme.spark,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  Widget _guestBlock(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Text(
          context.l10n.guestSession,
          textAlign: TextAlign.left,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppTheme.spark,
            fontSize: 23,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          context.l10n.accountUnsecuredNote,
          textAlign: TextAlign.left,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: context.colors.subtle, fontSize: 14),
        ),
      ],
    );
  }
}
