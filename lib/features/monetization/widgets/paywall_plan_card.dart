import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart'
    show Package, PackageType;

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';

/// A selectable plan card in the stacked plan list. Every plan gets the same
/// tall treatment — uppercase label, big price, plus an optional quiet
/// subline (the lifetime one-payment anchor, the monthly weekly-equivalent
/// price). Selection is a spark border + glow and a filled radio; the owner
/// preselects the monthly plan, but no card carries a "best value" tag.
class PaywallPlanCard extends StatelessWidget {
  const PaywallPlanCard({
    super.key,
    required this.package,
    required this.selected,
    required this.onTap,
    this.subline,
  });

  final Package package;
  final bool selected;
  final VoidCallback? onTap;

  /// Optional quiet line under the price (the lifetime one-payment anchor,
  /// the monthly weekly-equivalent price); null renders the card without it.
  final String? subline;

  /// Human label for the plan; the durations the product actually sells
  /// (lifetime / yearly / monthly) are localized, anything else falls back to
  /// the store product title. There is deliberately no weekly plan.
  String _label(BuildContext context) {
    switch (package.packageType) {
      case PackageType.lifetime:
        return context.l10n.paywallLifetime;
      case PackageType.annual:
        return context.l10n.paywallAnnual;
      case PackageType.monthly:
        return context.l10n.paywallMonthly;
      case PackageType.weekly:
      case PackageType.sixMonth:
      case PackageType.threeMonth:
      case PackageType.twoMonth:
      case PackageType.custom:
      case PackageType.unknown:
        return package.storeProduct.title;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final priceSuffix = package.packageType == PackageType.monthly
        ? context.l10n.paywallPerMonth
        : '';
    final price = '${package.storeProduct.priceString}$priceSuffix';

    final radio = Icon(
      selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
      size: 22,
      color: selected ? AppTheme.spark : colors.subtle,
    );

    final body = Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _label(context).toUpperCase(),
                style: const TextStyle(
                  color: AppTheme.spark,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                price,
                style: TextStyle(
                  color: colors.ink,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              if (subline != null) ...[
                const SizedBox(height: 4),
                Text(
                  subline!,
                  style: TextStyle(
                    color: colors.subtle,
                    fontSize: 12.5,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        radio,
      ],
    );

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? AppTheme.spark : colors.hairline,
          width: selected ? 2 : 1.4,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: AppTheme.sparkGlow.withValues(alpha: 0.28),
                  blurRadius: 16,
                ),
              ]
            : null,
      ),
      child: body,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: card,
      ),
    );
  }
}
