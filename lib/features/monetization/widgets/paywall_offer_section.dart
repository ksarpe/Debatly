import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart'
    show Package, PackageType;

import '../../../core/locale/l10n_extension.dart';
import 'paywall_plan_card.dart';

/// The loaded offer: the plan cards side by side. Pure presentation —
/// selection state, analytics and the purchase flow stay with the owner (the
/// CTA itself lives in the paywall's sticky bottom bar).
class PaywallOfferSection extends StatelessWidget {
  const PaywallOfferSection({
    super.key,
    required this.packages,
    required this.selected,
    required this.busy,
    required this.onSelect,
  });

  final List<Package> packages;
  final Package selected;
  final bool busy;
  final ValueChanged<Package> onSelect;

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
    // The "best value" tag follows the lifetime plan (the one the paywall
    // preselects and pitches), wherever the offering ordered it.
    var recommendedIndex = packages.indexWhere(
      (p) => p.packageType == PackageType.lifetime,
    );
    if (recommendedIndex < 0) recommendedIndex = 0;

    PaywallPlanCard card(int i) => PaywallPlanCard(
      package: packages[i],
      selected: packages[i] == selected,
      recommended: i == recommendedIndex && packages.length > 1,
      subline: packages[i].packageType == PackageType.lifetime
          ? lifetimeSubline
          : null,
      onTap: busy ? null : () => onSelect(packages[i]),
    );

    // Three plans don't fit across a phone: the labels ("Dożywotni", the
    // lifetime-vs-monthly subline) start wrapping and ellipsing, and this is
    // the offering — someone adding an annual package in the RevenueCat
    // dashboard would reshape this screen with no code change at all. So past
    // two, the cards stack full-width instead.
    if (packages.length > 2) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < packages.length; i++) ...[
            // Room for the floating "best value" tag, which overhangs the top.
            if (i > 0) const SizedBox(height: 14),
            card(i),
          ],
        ],
      );
    }

    // IntrinsicHeight + stretch keep both cards the same height even though
    // only the lifetime one carries the comparison subline.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < packages.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: card(i)),
          ],
        ],
      ),
    );
  }
}
