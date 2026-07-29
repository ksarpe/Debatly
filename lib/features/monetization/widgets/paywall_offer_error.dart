import 'package:flutter/material.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';

/// Retryable failure state shown when the offering can't be fetched (offline,
/// RevenueCat unconfigured, empty offering).
class PaywallOfferError extends StatelessWidget {
  const PaywallOfferError({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 220,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off_rounded, color: colors.subtle, size: 32),
          const SizedBox(height: 12),
          Text(
            context.l10n.paywallLoadError,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.subtle, fontSize: 13.5, height: 1.4),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(foregroundColor: AppTheme.spark),
            child: Text(
              context.l10n.tryAgain,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
