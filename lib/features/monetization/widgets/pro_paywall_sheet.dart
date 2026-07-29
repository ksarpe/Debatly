import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show Package;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/feedback/app_toast.dart';
import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/analytics.dart';
import '../../../services/purchases_service.dart';
import '../../account/widgets/restore_sign_in_prompt.dart';
import 'paywall_benefit_row.dart';
import 'paywall_footer_links.dart';
import 'paywall_hero.dart';
import 'paywall_offer_error.dart';
import 'paywall_offer_section.dart';

/// Where the user opened the paywall from. Each entry point leads with the
/// headline and benefit that match the desire that brought them here (the
/// locked feature they just tapped), instead of one generic pitch. The enum
/// name doubles as the analytics `source` value once paywall funnel events
/// land.
enum PaywallSource {
  /// Settings row and other neutral entry points — the generic pitch.
  general,

  /// The reveal wall: the user wanted to read the next question.
  readingLimit,

  /// The locked PRO argument on the smaczki panel.
  smaczki,

  /// The greyed-out favorite star.
  favorites,

  /// The history upsell (voting record).
  history,
}

/// Opens the in-app PRO paywall as a modal sheet and reports whether the user
/// ended up with the premium entitlement (bought or restored).
///
/// This replaces the RevenueCat-hosted paywall: packages and localized prices
/// still come live from the current RevenueCat offering, but the presentation
/// is ours — themed to the app, bilingual via l10n, light/dark aware.
/// [source] picks the contextual headline + benefit order.
///
/// A dismissed sheet is a quiet `false`, matching the old
/// `PurchasesService.presentPaywall()` contract, so call sites keep their
/// "purchase not completed" handling unchanged.
Future<bool> showProPaywall(
  BuildContext context, {
  PaywallSource source = PaywallSource.general,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: context.colors.background,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => ProPaywallSheet(source: source),
  );
  final purchased = result ?? false;
  // The funnel exit: closed without ending up entitled (close button, swipe
  // down, or gave up after a cancelled purchase). Purchases and restores log
  // their own events inside the sheet.
  if (!purchased) {
    Analytics.log('paywall_dismissed', {'source': source.name});
  }
  return purchased;
}

/// The paywall content: hero + benefit list + live package picker + CTA.
///
/// [loadPackages] exists for widget tests (RevenueCat can't be configured
/// there); production always uses [PurchasesService.paywallPackages].
class ProPaywallSheet extends ConsumerStatefulWidget {
  const ProPaywallSheet({
    super.key,
    this.source = PaywallSource.general,
    this.loadPackages,
    this.buy,
  });

  final PaywallSource source;
  final Future<List<Package>> Function()? loadPackages;
  final Future<bool> Function(Package package)? buy;

  @override
  ConsumerState<ProPaywallSheet> createState() => _ProPaywallSheetState();
}

class _ProPaywallSheetState extends ConsumerState<ProPaywallSheet> {
  late Future<List<Package>> _packagesFuture;

  /// The package the user has tapped; defaults to the first (recommended)
  /// one as soon as the offering loads.
  Package? _selected;

  /// Blocks every interaction while a purchase or restore is in flight.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Analytics.log('paywall_shown', {'source': widget.source.name});
    _packagesFuture = _loadOffer();
  }

  void _retryLoad() {
    setState(() {
      _packagesFuture = _loadOffer();
    });
  }

  /// Fetches the offering, reporting an unusable one (fetch failure or empty —
  /// both render as the retry state) so funnel drop-offs between `shown` and
  /// `purchase_started` can be told apart from plain disinterest.
  Future<List<Package>> _loadOffer() async {
    final List<Package> packages;
    try {
      packages =
          await (widget.loadPackages ?? PurchasesService.paywallPackages)();
    } catch (_) {
      Analytics.log('paywall_offer_unavailable', {
        'source': widget.source.name,
        'reason': 'error',
      });
      rethrow;
    }
    if (packages.isEmpty) {
      Analytics.log('paywall_offer_unavailable', {
        'source': widget.source.name,
        'reason': 'empty',
      });
    }
    return packages;
  }

  void _selectPackage(Package package) {
    if (_selected != package) {
      Analytics.log('paywall_plan_selected', {
        'source': widget.source.name,
        'plan': package.packageType.name,
      });
    }
    setState(() => _selected = package);
  }

  Future<void> _buy() async {
    final package = _selected;
    if (_busy || package == null) return;
    setState(() => _busy = true);
    Analytics.log('paywall_purchase_started', {
      'source': widget.source.name,
      'plan': package.packageType.name,
    });

    final purchased = await (widget.buy ?? PurchasesService.purchase)(package);
    if (purchased) {
      Analytics.log('paywall_purchased', {
        'source': widget.source.name,
        'plan': package.packageType.name,
        'price': package.storeProduct.price,
        'currency': package.storeProduct.currencyCode,
      });
    } else {
      Analytics.log('paywall_purchase_abandoned', {
        'source': widget.source.name,
        'plan': package.packageType.name,
      });
    }
    if (!mounted) return;

    if (purchased) {
      Navigator.of(context).pop(true);
    } else {
      // Cancelled or failed — stay open so the user can try the other plan.
      setState(() => _busy = false);
    }
  }

  /// Store-required restore path. Guests are first steered towards signing in
  /// (see [confirmGuestRestore]) because a store restore would TRANSFER the
  /// entitlement onto their fresh anonymous identity.
  Future<void> _restore() async {
    if (_busy) return;
    if (!await confirmGuestRestore(context, ref)) return;
    if (!mounted) return;
    setState(() => _busy = true);

    final restored = await PurchasesService.restorePurchases();
    if (restored) {
      Analytics.log('paywall_restored', {'source': widget.source.name});
    }
    if (!mounted) return;

    if (restored) {
      AppToast.success(context, context.l10n.purchaseRestoredCelebrate);
      Navigator.of(context).pop(true);
    } else {
      AppToast.info(context, context.l10n.noPreviousPurchase);
      setState(() => _busy = false);
    }
  }

  /// Opens a legal page (terms / privacy) in the system browser, surfacing a
  /// toast if it can't be launched. Mirrors `AuthScreen._openLegalUrl`.
  Future<void> _openLegalUrl(String url) async {
    final uri = Uri.tryParse(url);
    var opened = false;
    if (uri != null) {
      try {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        opened = false;
      }
    }
    if (!opened && mounted) {
      AppToast.error(context, context.l10n.privacyLinkFailed);
    }
  }

  /// The contextual headline: names the locked feature the user just tapped,
  /// falling back to the generic pitch for neutral entry points.
  String _headline(BuildContext context) {
    final l10n = context.l10n;
    switch (widget.source) {
      case PaywallSource.readingLimit:
        return l10n.paywallTitleReadingLimit;
      case PaywallSource.smaczki:
        return l10n.paywallTitleSmaczki;
      case PaywallSource.favorites:
        return l10n.paywallTitleFavorites;
      case PaywallSource.history:
        return l10n.paywallTitleHistory;
      case PaywallSource.general:
        return l10n.paywallTitle;
    }
  }

  /// The four benefit rows, reordered so the one matching [PaywallSource]
  /// leads the list — the sheet should answer the exact desire that opened it
  /// before widening to the rest of PRO.
  List<Widget> _benefits(BuildContext context) {
    final l10n = context.l10n;
    final unlimited = PaywallBenefitRow(
      icon: Icons.all_inclusive,
      title: l10n.paywallBenefitUnlimitedTitle,
      body: l10n.paywallBenefitUnlimitedBody,
    );
    final noAds = PaywallBenefitRow(
      icon: Icons.block,
      title: l10n.paywallBenefitNoAdsTitle,
      body: l10n.paywallBenefitNoAdsBody,
    );
    final smaczki = PaywallBenefitRow(
      icon: Icons.psychology_alt_outlined,
      title: l10n.paywallBenefitSmaczkiTitle,
      body: l10n.paywallBenefitSmaczkiBody,
    );
    final favorites = PaywallBenefitRow(
      icon: Icons.star_outline_rounded,
      title: l10n.paywallBenefitFavoritesTitle,
      body: l10n.paywallBenefitFavoritesBody,
    );
    switch (widget.source) {
      // The reveal wall is about reading more, which the default order
      // already leads with.
      case PaywallSource.general:
      case PaywallSource.readingLimit:
        return [unlimited, noAds, smaczki, favorites];
      case PaywallSource.smaczki:
        return [smaczki, unlimited, noAds, favorites];
      // One benefit row covers both favorites and history.
      case PaywallSource.favorites:
      case PaywallSource.history:
        return [favorites, unlimited, smaczki, noAds];
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      child: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                const PaywallHero(),
                const SizedBox(height: 14),
                Text(
                  _headline(context),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.ink,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 24),
                ..._benefits(context),
                const SizedBox(height: 20),
                _buildOffer(context),
                const SizedBox(height: 8),
                PaywallFooterLinks(
                  busy: _busy,
                  onRestore: _restore,
                  onTerms: AppConfig.hasTermsOfService
                      ? () => _openLegalUrl(AppConfig.termsOfServiceUrl)
                      : null,
                  onPrivacy: AppConfig.hasPrivacyPolicy
                      ? () => _openLegalUrl(AppConfig.privacyPolicyUrl)
                      : null,
                ),
              ],
            ),
          ),
          // Close affordance floating over the scrollable content.
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
              icon: Icon(Icons.close_rounded, color: colors.subtle),
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            ),
          ),
        ],
      ),
    );
  }

  /// The live part of the sheet: the offer section once the fetch resolves,
  /// with loading and retryable error states in the meantime.
  Widget _buildOffer(BuildContext context) {
    return FutureBuilder<List<Package>>(
      future: _packagesFuture,
      builder: (context, snapshot) {
        // An empty list is how paywallPackages reports "nothing to sell"
        // (unconfigured RevenueCat, empty offering) without throwing — same
        // retry state as a real fetch failure.
        if (snapshot.hasError || (snapshot.data?.isEmpty ?? false)) {
          return PaywallOfferError(onRetry: _retryLoad);
        }
        final packages = snapshot.data;
        if (packages == null) {
          return const SizedBox(
            height: 220,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
          );
        }
        // Commit the default selection (not just render it), otherwise the
        // CTA has nothing to buy until a card is tapped — the first card
        // already LOOKS selected, so a straight-to-CTA tap must work.
        final selected = _selected ??= packages.first;
        return PaywallOfferSection(
          packages: packages,
          selected: selected,
          busy: _busy,
          onSelect: _selectPackage,
          onBuy: _buy,
        );
      },
    );
  }
}
