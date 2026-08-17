import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart'
    show Package, PackageType;

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';

/// A selectable plan card. The selected card gets the spark border + glow and
/// a filled check. No "best value" tag and no preselection — every card
/// starts equal, so the picks in the data are the users' own.
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

  /// Optional quiet line under the price (e.g. the lifetime-vs-monthly
  /// comparison); null keeps the card exactly as before.
  final String? subline;

  /// Human label for the plan; predefined durations are localized, custom
  /// packages fall back to the store product title.
  String _label(BuildContext context) {
    switch (package.packageType) {
      case PackageType.lifetime:
        return context.l10n.paywallLifetime;
      case PackageType.annual:
        return context.l10n.paywallAnnual;
      case PackageType.monthly:
        return context.l10n.paywallMonthly;
      case PackageType.weekly:
        return context.l10n.paywallWeekly;
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

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? AppTheme.spark : colors.hairline,
          width: selected ? 2 : 1.4,
        ),
        boxShadow: selected
            ? const [BoxShadow(color: Color(0x33EA6A12), blurRadius: 16)]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _label(context),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.ink,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked,
                size: 20,
                color: selected ? AppTheme.spark : colors.subtle,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${package.storeProduct.priceString}$priceSuffix',
            style: TextStyle(
              color: colors.ink,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (subline != null) ...[
            const SizedBox(height: 4),
            Text(
              subline!,
              style: TextStyle(
                color: colors.subtle,
                fontSize: 11.5,
                height: 1.25,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
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
