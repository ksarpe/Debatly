import 'package:flutter/material.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';

/// Sign-in + restore + legal links, one quiet row under the CTA in the sticky
/// bar. Restore lives ON the paywall because it's the only restore path a
/// guest can reach (Settings is account-only) and the stores require one next
/// to any purchase button; sign-in sits beside it for returning users whose
/// PRO rides on an account instead of this device's store history.
class PaywallFooterLinks extends StatelessWidget {
  const PaywallFooterLinks({
    super.key,
    required this.busy,
    required this.onRestore,
    required this.onTerms,
    required this.onPrivacy,
    this.onSignIn,
  });

  final bool busy;
  final VoidCallback onRestore;
  final VoidCallback? onTerms;
  final VoidCallback? onPrivacy;

  /// null hides the sign-in link (sheet surface, or already signed in).
  final VoidCallback? onSignIn;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final style = TextButton.styleFrom(
      foregroundColor: context.colors.subtle,
      textStyle: const TextStyle(fontSize: 12.5),
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 10),
    );
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (onSignIn != null)
          TextButton(
            onPressed: busy ? null : onSignIn,
            style: style,
            child: Text(l10n.paywallSignInLink),
          ),
        TextButton(
          onPressed: busy ? null : onRestore,
          style: style,
          child: Text(l10n.restorePurchase),
        ),
        if (onTerms != null)
          TextButton(
            onPressed: busy ? null : onTerms,
            style: style,
            child: Text(l10n.paywallTermsLink),
          ),
        if (onPrivacy != null)
          TextButton(
            onPressed: busy ? null : onPrivacy,
            style: style,
            child: Text(l10n.paywallPrivacyLink),
          ),
      ],
    );
  }
}
