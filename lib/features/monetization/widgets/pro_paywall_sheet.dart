import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart'
    show Package, PackageType;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/feedback/app_toast.dart';
import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/analytics.dart';
import '../../../services/purchases_service.dart';
import '../../account/widgets/restore_sign_in_prompt.dart';

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
    final unlimited = _Benefit(
      icon: Icons.all_inclusive,
      title: l10n.paywallBenefitUnlimitedTitle,
      body: l10n.paywallBenefitUnlimitedBody,
    );
    final noAds = _Benefit(
      icon: Icons.block,
      title: l10n.paywallBenefitNoAdsTitle,
      body: l10n.paywallBenefitNoAdsBody,
    );
    final smaczki = _Benefit(
      icon: Icons.psychology_alt_outlined,
      title: l10n.paywallBenefitSmaczkiTitle,
      body: l10n.paywallBenefitSmaczkiBody,
    );
    final favorites = _Benefit(
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
                const _ProHero(),
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
                _FooterLinks(
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

  /// Price-anchoring subline for the lifetime card: the lifetime price
  /// expressed in months of the monthly subscription ("less than N months").
  ///
  /// `floor + 1` keeps the claim strictly true even when the lifetime price
  /// is an exact multiple of the monthly one. Returns null (no subline) when
  /// the offering has no monthly/lifetime pair to compare, the currencies
  /// differ, or the comparison wouldn't flatter the lifetime plan (< 2).
  String? _lifetimeSubline(BuildContext context, List<Package> packages) {
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

  /// The live part of the sheet: package cards + CTA, with loading and
  /// retryable error states while the offering fetch resolves.
  Widget _buildOffer(BuildContext context) {
    return FutureBuilder<List<Package>>(
      future: _packagesFuture,
      builder: (context, snapshot) {
        // An empty list is how paywallPackages reports "nothing to sell"
        // (unconfigured RevenueCat, empty offering) without throwing — same
        // retry state as a real fetch failure.
        if (snapshot.hasError || (snapshot.data?.isEmpty ?? false)) {
          return _OfferError(onRetry: _retryLoad);
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
        final lifetimeSubline = _lifetimeSubline(context, packages);
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
                      child: _PlanCard(
                        package: packages[i],
                        selected: packages[i] == selected,
                        recommended: i == 0 && packages.length > 1,
                        subline: packages[i].packageType == PackageType.lifetime
                            ? lifetimeSubline
                            : null,
                        onTap: _busy
                            ? null
                            : () {
                                if (_selected != packages[i]) {
                                  Analytics.log('paywall_plan_selected', {
                                    'source': widget.source.name,
                                    'plan': packages[i].packageType.name,
                                  });
                                }
                                setState(() => _selected = packages[i]);
                              },
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            _CtaButton(
              label: context.l10n.paywallCta,
              busy: _busy,
              onTap: _buy,
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
                    style: TextStyle(
                      color: context.colors.subtle,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// The paywall hero: "PRO" as a brand sticker — the question text's signature
/// Anton stroke-and-fill treatment, but with a spark-gradient fill — slightly
/// tilted, glowing from behind, with a counter-tilted bolt badge pinned to its
/// corner. Pops in once when the sheet opens (one-shot, so tests can settle).
class _ProHero extends StatefulWidget {
  const _ProHero();

  @override
  State<_ProHero> createState() => _ProHeroState();
}

class _ProHeroState extends State<_ProHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static const double _fontSize = 56;

  /// Both text layers must share the exact same metrics to stay aligned; only
  /// the paint differs (stroke below, gradient fill above).
  static final TextStyle _stroke = QuestionTextStyles.strokeFor(
    _fontSize,
  ).copyWith(letterSpacing: 3);
  static final TextStyle _fill = QuestionTextStyles.fillFor(
    _fontSize,
  ).copyWith(letterSpacing: 3);

  static const Gradient _fillGradient = LinearGradient(
    colors: [Color(0xFFFFC168), AppTheme.spark, Color(0xFFEA580C)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 104,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.55, end: 1).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
        ),
        child: FadeTransition(
          opacity: CurvedAnimation(
            parent: _controller,
            curve: const Interval(0, 0.5),
          ),
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // Soft spark wash radiating from behind the sticker.
              Container(
                width: 260,
                height: 104,
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    colors: [Color(0x47F97316), Color(0x00F97316)],
                  ),
                ),
              ),
              Transform.rotate(
                angle: -0.055,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    Text('PRO', style: _stroke),
                    ShaderMask(
                      shaderCallback: _fillGradient.createShader,
                      child: Text('PRO', style: _fill),
                    ),
                    Positioned(
                      top: -8,
                      right: -26,
                      child: Transform.rotate(
                        angle: 0.30,
                        child: const _BoltSticker(),
                      ),
                    ),
                    Positioned(
                      bottom: -2,
                      left: -26,
                      child: Icon(
                        Icons.auto_awesome,
                        size: 18,
                        color: AppTheme.spark.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The little round bolt badge riding the corner of the "PRO" sticker. The
/// background-coloured ring separates it from the letters underneath.
class _BoltSticker extends StatelessWidget {
  const _BoltSticker();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.spark, Color(0xFFEA580C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
        border: Border.all(color: context.colors.background, width: 3),
        boxShadow: const [
          BoxShadow(color: Color(0x55F97316), blurRadius: 14, spreadRadius: 1),
        ],
      ),
      child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 20),
    );
  }
}

/// One benefit row: tinted icon chip + title + one-line explanation.
class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.spark.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: AppTheme.spark, size: 19),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colors.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: TextStyle(
                    color: colors.subtle,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A selectable plan card. The selected card gets the spark border + glow and
/// a filled check; the recommended one carries the floating "best value" tag.
class _PlanCard extends StatelessWidget {
  const _PlanCard({
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
            ? const [BoxShadow(color: Color(0x33F97316), blurRadius: 16)]
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

    return Stack(
      clipBehavior: Clip.none,
      // Pass the Row's stretched height through so both cards fill it.
      fit: StackFit.passthrough,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: card,
          ),
        ),
        if (recommended)
          Positioned(
            top: -9,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
      ],
    );
  }
}

/// The single primary CTA — a glowing spark-gradient pill.
class _CtaButton extends StatelessWidget {
  const _CtaButton({
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.spark, Color(0xFFEA580C)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(color: Color(0x55F97316), blurRadius: 22, spreadRadius: 1),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: busy ? null : onTap,
          child: SizedBox(
            height: 54,
            child: Center(
              child: busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Retryable failure state shown when the offering can't be fetched (offline,
/// RevenueCat unconfigured, empty offering).
class _OfferError extends StatelessWidget {
  const _OfferError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 220,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off_rounded, color: colors.subtle, size: 32),
          const SizedBox(height: 12),
          Text(
            context.l10n.paywallLoadError,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.subtle, fontSize: 13.5, height: 1.4),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(foregroundColor: AppTheme.spark),
            child: Text(
              context.l10n.tryAgain,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// Restore + legal links, quiet and small under the CTA. Restore lives ON the
/// paywall because it's the only restore path a guest can reach (Settings is
/// account-only) and the stores require one next to any purchase button.
class _FooterLinks extends StatelessWidget {
  const _FooterLinks({
    required this.busy,
    required this.onRestore,
    required this.onTerms,
    required this.onPrivacy,
  });

  final bool busy;
  final VoidCallback onRestore;
  final VoidCallback? onTerms;
  final VoidCallback? onPrivacy;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final style = TextButton.styleFrom(
      foregroundColor: context.colors.subtle,
      textStyle: const TextStyle(fontSize: 12.5),
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 10),
    );
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton(
          onPressed: busy ? null : onRestore,
          style: style,
          child: Text(l10n.restorePurchase),
        ),
        if (onTerms != null)
          TextButton(
            onPressed: busy ? null : onTerms,
            style: style,
            child: Text(l10n.paywallTermsLink),
          ),
        if (onPrivacy != null)
          TextButton(
            onPressed: busy ? null : onPrivacy,
            style: style,
            child: Text(l10n.paywallPrivacyLink),
          ),
      ],
    );
  }
}
