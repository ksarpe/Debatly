import 'package:flutter/material.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';

/// The paywall's compact feature list: five one-line rows separated by
/// hairlines. Replaces the old Free/PRO table + six-row benefit list — the
/// whole pitch fits above the fold, the daily-limit row leads because
/// removing that limit IS the product, and the modes row (2026-09-02) sits
/// right under it because the modes are what the catalog now looks like.
class PaywallFeatureList extends StatelessWidget {
  const PaywallFeatureList({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rows = <(IconData, String)>[
      (Icons.all_inclusive, l10n.paywallFeatureUnlimited),
      (Icons.grid_view_rounded, l10n.paywallFeatureModes),
      (Icons.check_rounded, l10n.paywallFeatureSmaczki),
      (Icons.check_rounded, l10n.paywallFeatureHistory),
      (Icons.check_rounded, l10n.paywallFeatureOffline),
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
              style: AppTypography.body(
                fontSize: 15,
                height: 1.32,
              ).copyWith(color: context.colors.ink),
            ),
          ),
        ],
      ),
    );
  }
}
