import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart'
    show Package, PackageType;

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import 'paywall_cta_button.dart';
import 'paywall_plan_card.dart';

/// The loaded offer: package cards side by side, the CTA and the small
/// store-terms note. Pure presentation — selection state, analytics and the
/// purchase flow stay with the sheet that owns them.
class PaywallOfferSection extends StatelessWidget {
  const PaywallOfferSection({
    super.key,
    required this.packages,
    required this.selected,
    required this.busy,
    required this.onSelect,
    required this.onBuy,
  });

  final List<Package> packages;
  final Package selected;
  final bool busy;
  final ValueChanged<Package> onSelect;
  final VoidCallback onBuy;

  /// Price-anchoring subline for the lifetime card: the lifetime price
  /// expressed in months of the monthly subscription ("less than N months").
  ///
  /// `floor + 1` keeps the claim strictly true even when the lifetime price
  /// is an exact multiple of the monthly one. Returns null (no subline) when
  /// the offering has no monthly/lifetime pair to compare, the currencies
  /// differ, or the comparison wouldn't flatter the lifetime plan (< 2).
  String? _lifetimeSubline(BuildContext context) {
    Package? monthly;
    Package? lifetime;
    for (final package in packages) {
      if (package.packageType == PackageType.monthly) monthly ??= package;
      if (package.packageType == PackageType.lifetime) lifetime ??= package;
    }
    if (monthly == null || lifetime == null) return null;
    if (monthly.storeProduct.currencyCode !=
        lifetime.storeProduct.currencyCode) {
      return null;
    }
    if (monthly.storeProduct.price <= 0) return null;

    final months =
        (lifetime.storeProduct.price / monthly.storeProduct.price).floor() + 1;
    if (months < 2) return null;
    return context.l10n.paywallLifetimeVsMonthly(months);
  }

  @override
  Widget build(BuildContext context) {
    final lifetimeSubline = _lifetimeSubline(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // IntrinsicHeight + stretch keep both cards the same height even
        // though only the lifetime one carries the comparison subline.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < packages.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(
                  child: PaywallPlanCard(
                    package: packages[i],
                    selected: packages[i] == selected,
                    recommended: i == 0 && packages.length > 1,
                    subline: packages[i].packageType == PackageType.lifetime
                        ? lifetimeSubline
                        : null,
                    onTap: busy ? null : () => onSelect(packages[i]),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        PaywallCtaButton(
          label: context.l10n.paywallCta,
          busy: busy,
          onTap: onBuy,
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.verified_user_outlined,
              size: 15,
              color: context.colors.subtle,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                selected.packageType == PackageType.lifetime
                    ? context.l10n.paywallLifetimeNote
                    : context.l10n.paywallSubscriptionNote,
                style: TextStyle(color: context.colors.subtle, fontSize: 12.5),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
