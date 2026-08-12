import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart'
    show Package, PackageType;

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';

/// A selectable plan card. The selected card gets the spark border + glow and
/// a filled check; the recommended one carries the floating "best value" tag.
class PaywallPlanCard extends StatelessWidget {
  const PaywallPlanCard({
    super.key,
    required this.package,
    required this.selected,
    required this.recommended,
    required this.onTap,
    this.subline,
  });

  final Package package;
  final bool selected;
  final bool recommended;
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
    // Only the picked plan keeps full contrast; the other one recedes into the
    // background instead of competing with it.
    final ink = selected ? colors.ink : colors.subtle;

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
      decoration: BoxDecoration(
        color: selected ? colors.cardSurface : colors.accent,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? AppTheme.spark : Colors.transparent,
          width: 2,
        ),
        boxShadow: selected
            ? const [BoxShadow(color: Color(0x33F97316), blurRadius: 16)]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _label(context),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: ink,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          // Price and its per-month suffix share a baseline, the way the store
          // prints them: big number, small unit.
          Text.rich(
            TextSpan(
              text: package.storeProduct.priceString,
              style: TextStyle(
                color: ink,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
              children: [
                if (priceSuffix.isNotEmpty)
                  TextSpan(
                    text: priceSuffix,
                    style: TextStyle(
                      color: selected ? colors.subtle : ink,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
              ],
            ),
            maxLines: 1,
          ),
          if (subline != null) ...[
            const SizedBox(height: 6),
            Text(
              subline!,
              style: TextStyle(
                color: colors.subtle,
                fontSize: 11,
                height: 1.25,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      // Pass the Row's stretched height through so both cards fill it.
      fit: StackFit.passthrough,
      children: [
        // The border alone carries the selection visually, so the state has to
        // reach assistive tech some other way.
        Semantics(
          selected: selected,
          button: true,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onTap,
              child: card,
            ),
          ),
        ),
        if (recommended)
          Positioned(
            top: -9,
            left: 0,
            right: 0,
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.spark,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  context.l10n.paywallBestValue,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
