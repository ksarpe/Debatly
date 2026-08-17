import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:purchases_flutter/purchases_flutter.dart'
    show Package, PackageType;

import '../../../core/locale/l10n_extension.dart';
import 'paywall_plan_card.dart';

/// The loaded offer: the plan cards stacked full-width, the lifetime plan on
/// top as the tall hero card with its one-payment anchor line, the monthly
/// card with its weekly-equivalent price subline. Pure presentation —
/// selection state, analytics and the purchase flow stay with the owner (the
/// CTA itself lives in the paywall's sticky bottom bar; the owner preselects
/// the monthly plan).
class PaywallOfferSection extends StatelessWidget {
  const PaywallOfferSection({
    super.key,
    required this.packages,
    required this.selected,
    required this.busy,
    required this.onSelect,
  });

  final List<Package> packages;
  final Package? selected;
  final bool busy;
  final ValueChanged<Package> onSelect;

  /// Price-anchoring subline for the lifetime card: one payment, cheaper than
  /// N months of the monthly subscription.
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

  /// Weekly-equivalent price subline for the monthly card ("To ok. 4,61 zł
  /// tygodniowo"): the monthly price spread over an average week
  /// (price × 12 / 52), formatted in the store product's own currency so it
  /// never mixes currencies with the price it sits under.
  String? _monthlyWeeklySubline(BuildContext context, Package monthly) {
    final product = monthly.storeProduct;
    if (product.price <= 0) return null;
    final weekly = product.price * 12 / 52;
    final formatted = NumberFormat.simpleCurrency(
      locale: Localizations.localeOf(context).toString(),
      name: product.currencyCode,
    ).format(weekly);
    return context.l10n.paywallMonthlyWeekly(formatted);
  }

  String? _subline(BuildContext context, Package package) {
    switch (package.packageType) {
      case PackageType.lifetime:
        return _lifetimeSubline(context);
      case PackageType.monthly:
        return _monthlyWeeklySubline(context, package);
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Lifetime leads the stack; the rest keep the offering's own order. The
    // offering's shape is set in the RevenueCat dashboard, so a package added
    // there still slots straight into this column with no code change.
    final ordered = [
      ...packages.where((p) => p.packageType == PackageType.lifetime),
      ...packages.where((p) => p.packageType != PackageType.lifetime),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, package) in ordered.indexed) ...[
          if (i > 0) const SizedBox(height: 12),
          PaywallPlanCard(
            package: package,
            selected: package == selected,
            subline: _subline(context, package),
            onTap: busy ? null : () => onSelect(package),
          ),
        ],
      ],
    );
  }
}
