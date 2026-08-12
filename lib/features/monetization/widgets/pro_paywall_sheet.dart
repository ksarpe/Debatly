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
import 'paywall_footer_links.dart';
import 'paywall_offer_error.dart';
import 'paywall_offer_section.dart';
import 'paywall_perk_grid.dart';

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

  /// The reveal wall AFTER today's ad-reveal cap: PRO is the only way forward
  /// until tomorrow — the highest-intent entry point, tracked separately.
  adLimit,

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

/// The paywall content: headline + perk grid + live package picker + CTA,
/// sized to fit a phone screen in one view.
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
      case PaywallSource.adLimit:
        return l10n.paywallTitleAdLimit;
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

  /// The six PRO perks, reordered so the one matching [PaywallSource] takes
  /// the first (top-left) tile — the sheet should answer the exact desire that
  /// opened it before widening to the rest of PRO.
  List<PaywallPerk> _perks(BuildContext context) {
    final l10n = context.l10n;
    final unlimited = PaywallPerk(
      icon: Icons.all_inclusive,
      label: l10n.paywallPerkUnlimited,
      tint: AppTheme.spark,
    );
    final noAds = PaywallPerk(
      icon: Icons.block,
      label: l10n.paywallPerkNoAds,
      tint: AppTheme.no,
    );
    final smaczki = PaywallPerk(
      icon: Icons.psychology_alt_outlined,
      label: l10n.paywallPerkSmaczki,
      tint: _violet,
    );
    final favorites = PaywallPerk(
      icon: Icons.star_rounded,
      label: l10n.paywallPerkFavorites,
      tint: _amber,
    );
    final history = PaywallPerk(
      icon: Icons.history_rounded,
      label: l10n.paywallPerkHistory,
      tint: AppTheme.yes,
    );
    final offline = PaywallPerk(
      icon: Icons.download_rounded,
      label: l10n.paywallPerkOffline,
      tint: _sky,
    );
    switch (widget.source) {
      // The reveal wall is about reading more, which the default order
      // already leads with.
      case PaywallSource.general:
      case PaywallSource.readingLimit:
      case PaywallSource.adLimit:
        return [unlimited, noAds, smaczki, favorites, history, offline];
      case PaywallSource.smaczki:
        return [smaczki, unlimited, noAds, favorites, history, offline];
      case PaywallSource.favorites:
        return [favorites, unlimited, smaczki, history, noAds, offline];
      case PaywallSource.history:
        return [history, unlimited, smaczki, favorites, noAds, offline];
    }
  }

  /// Perk accents that aren't brand colours — one hue per tile so the grid
  /// reads as six distinct things.
  static const Color _violet = Color(0xFF8B5CF6);
  static const Color _amber = Color(0xFFF59E0B);
  static const Color _sky = Color(0xFF38BDF8);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // `useSafeArea: true` on the route is `SafeArea(bottom: false)` — it keeps
    // the sheet below the status bar but leaves the BOTTOM inset to us. Without
    // this the footer (restore / terms / privacy) sits under the Android
    // gesture bar and can't be read or tapped.
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      child: Stack(
        children: [
          SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomInset),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Clears the floating close chip in the corner.
                const SizedBox(height: 40),
                Text(
                  _headline(context),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.ink,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  context.l10n.paywallSubtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.subtle,
                    fontSize: 14,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 26),
                PaywallPerkGrid(perks: _perks(context)),
                const SizedBox(height: 30),
                _buildOffer(context),
                const SizedBox(height: 6),
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
          // Close affordance floating over the scrollable content: a quiet
          // round chip in the corner, out of the headline's way.
          Positioned(
            top: 10,
            left: 12,
            child: Material(
              color: colors.accent,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: IconButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).pop(false),
                iconSize: 18,
                constraints: const BoxConstraints.tightFor(
                  width: 38,
                  height: 38,
                ),
                padding: EdgeInsets.zero,
                icon: Icon(Icons.close_rounded, color: colors.subtle),
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              ),
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
