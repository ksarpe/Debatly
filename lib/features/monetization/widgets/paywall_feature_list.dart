import 'package:flutter/material.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';

/// The paywall's compact feature list: four one-line rows separated by
/// hairlines. Replaces the old Free/PRO table + six-row benefit list — the
/// whole pitch now fits above the fold, and the daily-limit row leads because
/// removing that limit IS the product.
class PaywallFeatureList extends StatelessWidget {
  const PaywallFeatureList({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rows = <(IconData, String)>[
      (Icons.all_inclusive, l10n.paywallFeatureUnlimited),
      (Icons.check_rounded, l10n.paywallFeatureSmaczki),
      (Icons.check_rounded, l10n.paywallFeatureHistory),
      (Icons.check_rounded, l10n.paywallFeatureNoAds),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, (icon, label)) in rows.indexed) ...[
          if (i > 0) Divider(height: 1, color: context.colors.hairline),
          _FeatureRow(icon: icon, label: label),
        ],
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.spark),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: context.colors.ink,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
