import 'package:flutter/material.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
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
  ///
  /// An e-mail address cannot be uppercased (it would misrepresent the address
  /// and shout), so it is NOT a Barlow role — it stays in Manrope [BODY]. The
  /// spark colour and its position keep it reading as the identity line. The
  /// "Your account" fallback (no e-mail on file) CAN be uppercased, so it gets
  /// the screen-title treatment like the guest header.
  Widget _accountBlock(BuildContext context) {
    final email = account?.email ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        if (email.isNotEmpty)
          Text(
            email,
            textAlign: TextAlign.left,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.body(
              fontSize: 15,
            ).copyWith(color: AppTheme.spark),
          )
        else
          Text(
            context.l10n.yourAccount.toUpperCase(),
            textAlign: TextAlign.left,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.title(
              fontSize: 34,
            ).copyWith(color: AppTheme.spark),
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
          context.l10n.guestSession.toUpperCase(),
          textAlign: TextAlign.left,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.title(
            fontSize: 34,
          ).copyWith(color: AppTheme.spark),
        ),
        const SizedBox(height: 6),
        Text(
          context.l10n.accountUnsecuredNote,
          textAlign: TextAlign.left,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.support(
            fontSize: 13,
          ).copyWith(color: context.colors.subtle),
        ),
      ],
    );
  }
}
