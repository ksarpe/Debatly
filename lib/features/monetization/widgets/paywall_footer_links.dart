import 'package:flutter/material.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';

/// Restore + legal links, quiet and small under the CTA. Restore lives ON the
/// paywall because it's the only restore path a guest can reach (Settings is
/// account-only) and the stores require one next to any purchase button.
class PaywallFooterLinks extends StatelessWidget {
  const PaywallFooterLinks({
    super.key,
    required this.busy,
    required this.onRestore,
    required this.onTerms,
    required this.onPrivacy,
  });

  final bool busy;
  final VoidCallback onRestore;
  final VoidCallback? onTerms;
  final VoidCallback? onPrivacy;

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
