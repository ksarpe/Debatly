import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart'
    show Package, PackageType;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/feedback/app_toast.dart';
import '../../../core/locale/l10n_extension.dart';
import '../../../core/monitoring/monitoring.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/analytics.dart';
import '../../../services/purchases_service.dart';
import '../../account/screens/auth_screen.dart';
import '../../account/widgets/restore_sign_in_prompt.dart';
import 'paywall_benefit_row.dart';
import 'paywall_cta_button.dart';
import 'paywall_footer_links.dart';
import 'paywall_hero.dart';
import 'paywall_offer_error.dart';
import 'paywall_offer_section.dart';

/// Where the user opened the paywall from. Each entry point leads with the
/// headline and benefit that match the desire that brought them here (the
/// locked feature they just tapped), instead of one generic pitch. The enum
/// name doubles as the analytics `source` value in the paywall funnel events.
enum PaywallSource {
  /// Settings row and other neutral entry points — the generic pitch.
  general,

  /// The full-screen hard wall gating the whole app for non-PRO users.
  hardWall,

  /// The locked PRO argument on the smaczki panel.
  smaczki,

  /// The greyed-out favorite star.
  favorites,

  /// The history upsell (voting record).
  history,
}

/// The paywall body shared by the modal sheet ([ProPaywallSheet]) and the
/// full-screen hard wall ([HardPaywallScreen]): a scrollable pitch (hero +
/// headline + live package picker + benefit list + restore/legal footer) with
/// the CTA pinned in a sticky bar underneath, so the buy button stays on
/// screen while the user scrolls the full "everything you get" list.
///
/// The owner provides the chrome and decides what happens once the user is
/// entitled ([onEntitled] — pop the sheet, or let the session flip swap the
/// screen). [loadPackages]/[buy] exist for widget tests (RevenueCat can't be
/// configured there); production always uses [PurchasesService].
class ProPaywallContent extends ConsumerStatefulWidget {
  const ProPaywallContent({
    super.key,
    required this.source,
    required this.onEntitled,
    this.onBusyChanged,
    this.showSignInLink = false,
    this.fillHeight = false,
    this.loadPackages,
    this.buy,
    this.retryBackoff,
  });

  /// How long to wait before each automatic re-fetch of the offering, and
  /// therefore how many of them there are.
  ///
  /// Play's billing client routinely isn't ready in the first seconds of a
  /// session — and on a flaky connection isn't ready at all for a while — and
  /// answers product lookups with a flat `NETWORK_ERROR`. One shot at
  /// `initState` turned that into a paywall the user had to rescue by hand,
  /// which on a hard-walled app means the whole product is a retry button.
  /// Three quiet attempts absorb the blip without making a genuinely-down
  /// store feel hung. Tests pass their own schedule (`const []` disables the
  /// automatic retries entirely).
  static const List<Duration> defaultRetryBackoff = [
    Duration(milliseconds: 800),
    Duration(milliseconds: 2500),
  ];

  final PaywallSource source;

  /// Called after a completed purchase or successful restore. The owner
  /// refreshes the session / closes its chrome; the content itself stays put.
  ///
  /// Must complete only once the owner has finished reacting — the content
  /// keeps every control locked until then, and treats "still mounted and
  /// still not premium" afterwards as a failed reconcile (see [_settleEntitled]).
  final Future<void> Function() onEntitled;

  /// Reports the in-flight purchase/restore state so the owner's own chrome
  /// (e.g. the sheet's close button) can lock itself alongside the content.
  final ValueChanged<bool>? onBusyChanged;

  /// Offers "Already have PRO? Sign in" in the sticky bar — for the hard
  /// wall, where a returning user's entitlement may live on their account
  /// rather than in this device's store history.
  final bool showSignInLink;

  /// Full-screen owners (the hard wall) pass true so the scroll area expands
  /// and the sticky bar pins to the bottom of the screen; the sheet keeps
  /// false so it can shrink-wrap short content.
  final bool fillHeight;

  final Future<List<Package>> Function()? loadPackages;
  final Future<PurchaseOutcome> Function(Package package)? buy;

  /// Overrides [defaultRetryBackoff] — for tests, which need the retry
  /// schedule to be deterministic (and usually absent).
  final List<Duration>? retryBackoff;

  @override
  ConsumerState<ProPaywallContent> createState() => _ProPaywallContentState();
}

class _ProPaywallContentState extends ConsumerState<ProPaywallContent>
    with WidgetsBindingObserver {
  /// null while the offering is loading; empty list = nothing to sell (renders
  /// the same retry state as a failed fetch).
  List<Package>? _packages;
  bool _loadFailed = false;

  /// The package the user has tapped; defaults to the lifetime one (the
  /// recommended plan) as soon as the offering loads.
  Package? _selected;

  /// Blocks every interaction while a purchase or restore is in flight.
  bool _busy = false;

  /// Bumped by every (re)start of the offering load, so a retry still sleeping
  /// on the backoff can tell it has been superseded — by a manual "try again"
  /// tap, or by this surface going away entirely.
  int _loadGeneration = 0;

  void _setBusy(bool value) {
    setState(() => _busy = value);
    widget.onBusyChanged?.call(value);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Analytics.log('paywall_shown', {'source': widget.source.name});
    _loadOffer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _loadGeneration++;
    super.dispose();
  }

  /// Re-fetches a failed offer when the user comes back to the app.
  ///
  /// The realistic recovery from a store/network failure is the user leaving
  /// to do something about it — toggle airplane mode, find signal, update the
  /// Play Store — and the wall they return to must not still be the dead one
  /// they left. Only when the offer actually failed: a resume after the store's
  /// own purchase sheet (or any other trip out) has nothing to reload.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!_loadFailed || _busy) return;
    _retryLoad();
  }

  void _retryLoad() {
    setState(() {
      _packages = null;
      _loadFailed = false;
    });
    _loadOffer();
  }

  /// Fetches the offering — retrying transient store failures on its own
  /// before falling back to the manual retry state, and reporting an offer we
  /// never managed to show so funnel drop-offs between `shown` and
  /// `purchase_started` can be told apart from plain disinterest.
  Future<void> _loadOffer() async {
    final generation = ++_loadGeneration;
    final backoff =
        widget.retryBackoff ?? ProPaywallContent.defaultRetryBackoff;

    for (var attempt = 0; ; attempt++) {
      final List<Package> packages;
      try {
        packages =
            await (widget.loadPackages ?? PurchasesService.paywallPackages)();
      } catch (e, st) {
        // Live installs hit this persistently (Play answering product lookups
        // with NETWORK_ERROR) and a bare `reason: error` made the cause
        // undiagnosable — carry the RevenueCat error code through.
        final code =
            PurchasesService.errorCodeOf(e)?.name ?? e.runtimeType.toString();
        final willRetry =
            attempt < backoff.length && PurchasesService.isRetryableFailure(e);
        Monitoring.addBreadcrumb(
          'Paywall offer fetch failed: $code',
          category: 'purchases',
          data: {
            'source': widget.source.name,
            'attempt': attempt + 1,
            'will_retry': willRetry,
          },
        );
        if (willRetry) {
          await Future<void>.delayed(backoff[attempt]);
          if (!mounted || generation != _loadGeneration) return;
          continue;
        }
        // Only now is the offer really unavailable to this user: one row per
        // user who gave up, not one per attempt, so the funnel keeps meaning
        // what it meant.
        Analytics.log('paywall_offer_unavailable', {
          'source': widget.source.name,
          'reason': 'error',
          'code': code,
          'attempts': attempt + 1,
        });
        // Environmental failures (offline, store outage, the Play pre-launch
        // bots that have no billing account at all) are breadcrumbed instead
        // of raised — they'd otherwise bury the real bugs in this feature.
        if (!PurchasesService.isEnvironmentFailure(e)) {
          await Monitoring.captureException(
            e,
            stackTrace: st,
            feature: 'purchases',
            extra: {
              'paywall_source': widget.source.name,
              'rc_code': code,
              'attempts': attempt + 1,
            },
          );
        }
        if (mounted && generation == _loadGeneration) {
          setState(() => _loadFailed = true);
        }
        return;
      }

      if (packages.isEmpty) {
        // Deliberately NOT retried: an offering that resolves with nothing in
        // it is a dashboard/product-configuration state, not a blip — the same
        // fetch keeps returning the same nothing.
        Analytics.log('paywall_offer_unavailable', {
          'source': widget.source.name,
          'reason': 'empty',
        });
      } else if (attempt > 0) {
        // How much the automatic retries are actually saving.
        Analytics.log('paywall_offer_recovered', {
          'source': widget.source.name,
          'attempts': attempt + 1,
        });
      }
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _packages = packages;
        // Commit the default selection (not just render it), otherwise the CTA
        // has nothing to buy until a card is tapped — the preselected card
        // already LOOKS selected, so a straight-to-CTA tap must work. The
        // lifetime plan is the one the paywall leads with.
        if (packages.isNotEmpty) {
          _selected = packages.firstWhere(
            (p) => p.packageType == PackageType.lifetime,
            orElse: () => packages.first,
          );
        }
      });
      return;
    }
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
    _setBusy(true);
    Analytics.log('paywall_purchase_started', {
      'source': widget.source.name,
      'plan': package.packageType.name,
    });

    final outcome = await (widget.buy ?? PurchasesService.purchase)(package);
    switch (outcome) {
      case PurchaseOutcome.entitled:
      case PurchaseOutcome.pending:
        Analytics.log('paywall_purchased', {
          'source': widget.source.name,
          'plan': package.packageType.name,
          'price': package.storeProduct.price,
          'currency': package.storeProduct.currencyCode,
          // Paid, but the entitlement wasn't visible yet — the reconcile below
          // is what resolves it, and it can come back still not premium.
          if (outcome == PurchaseOutcome.pending) 'pending': true,
        });
      case PurchaseOutcome.cancelled:
        Analytics.log('paywall_purchase_abandoned', {
          'source': widget.source.name,
          'plan': package.packageType.name,
        });
      case PurchaseOutcome.failed:
        Analytics.log('paywall_purchase_failed', {
          'source': widget.source.name,
          'plan': package.packageType.name,
        });
    }
    if (!mounted) return;

    switch (outcome) {
      // The money left their account either way: hand it to the owner, whose
      // reconcile decides, and which already has something to say if the
      // entitlement still doesn't land.
      case PurchaseOutcome.entitled:
      case PurchaseOutcome.pending:
        await _settleEntitled();
      // Their own decision — no toast, just give the surface back.
      case PurchaseOutcome.cancelled:
        _setBusy(false);
      // The store refused. Saying nothing here is what left users tapping the
      // CTA over and over on a paywall that looked broken.
      case PurchaseOutcome.failed:
        AppToast.error(context, context.l10n.storeUnreachable);
        _setBusy(false);
    }
  }

  /// Hands over to the owner and makes sure this surface is never left locked.
  ///
  /// The sheet pops (we unmount, so the unlock is a no-op) and the hard wall
  /// kicks off a session refresh that swaps the whole screen out once
  /// `isPremium` flips. But that reconcile can fail — a 502 from
  /// `sync-entitlement`, a RevenueCat webhook that hasn't landed — and then the
  /// wall STAYS MOUNTED. Leaving `_busy` set there stranded a user who had just
  /// paid on a spinning CTA with restore, sign-in and the legal links all
  /// disabled, recoverable only by killing the app. Whoever survives that is
  /// also the one who explains it (see [HardPaywallScreen]); all we owe the
  /// user here is a working screen.
  Future<void> _settleEntitled() async {
    await widget.onEntitled();
    if (mounted) _setBusy(false);
  }

  /// Store-required restore path. Guests are first steered towards signing in
  /// (see [confirmGuestRestore]) because a store restore would TRANSFER the
  /// entitlement onto their fresh anonymous identity.
  Future<void> _restore() async {
    if (_busy) return;
    if (!await confirmGuestRestore(context, ref)) return;
    if (!mounted) return;
    _setBusy(true);

    final outcome = await PurchasesService.restorePurchases();
    if (outcome == RestoreOutcome.restored) {
      Analytics.log('paywall_restored', {'source': widget.source.name});
    }
    if (!mounted) return;

    switch (outcome) {
      case RestoreOutcome.restored:
        AppToast.success(context, context.l10n.purchaseRestoredCelebrate);
        await _settleEntitled();
      case RestoreOutcome.none:
        AppToast.info(context, context.l10n.noPreviousPurchase);
        _setBusy(false);
      // Never "no previous purchase" for a store we never reached — that
      // reads as "your purchase is gone" to the one user most likely to be
      // tapping restore.
      case RestoreOutcome.failed:
        AppToast.error(context, context.l10n.storeUnreachable);
        _setBusy(false);
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
      case PaywallSource.hardWall:
        return l10n.paywallTitleHardWall;
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

  /// The hook line under the headline — only the hard wall carries one (the
  /// contextual headlines already name the desire that opened the sheet).
  String? _subheadline(BuildContext context) {
    return widget.source == PaywallSource.hardWall
        ? context.l10n.paywallSubtitleHardWall
        : null;
  }

  /// The full "everything you get" list, reordered so the benefit matching
  /// [PaywallSource] leads — the paywall should answer the exact desire that
  /// opened it before widening to the rest of PRO.
  List<Widget> _benefits(BuildContext context) {
    final l10n = context.l10n;
    final catalog = PaywallBenefitRow(
      icon: Icons.all_inclusive,
      title: l10n.paywallBenefitUnlimitedTitle,
      body: l10n.paywallBenefitUnlimitedBody,
    );
    final smaczki = PaywallBenefitRow(
      icon: Icons.psychology_alt_outlined,
      title: l10n.paywallBenefitSmaczkiTitle,
      body: l10n.paywallBenefitSmaczkiBody,
    );
    final split = PaywallBenefitRow(
      icon: Icons.public,
      title: l10n.paywallBenefitSplitTitle,
      body: l10n.paywallBenefitSplitBody,
    );
    final fresh = PaywallBenefitRow(
      icon: Icons.new_releases_outlined,
      title: l10n.paywallBenefitFreshTitle,
      body: l10n.paywallBenefitFreshBody,
    );
    final streak = PaywallBenefitRow(
      icon: Icons.local_fire_department_outlined,
      title: l10n.paywallBenefitStreakTitle,
      body: l10n.paywallBenefitStreakBody,
    );
    final favorites = PaywallBenefitRow(
      icon: Icons.star_outline_rounded,
      title: l10n.paywallBenefitFavoritesTitle,
      body: l10n.paywallBenefitFavoritesBody,
    );
    final offline = PaywallBenefitRow(
      icon: Icons.download_for_offline_outlined,
      title: l10n.paywallBenefitOfflineTitle,
      body: l10n.paywallBenefitOfflineBody,
    );
    switch (widget.source) {
      // The hard wall and neutral entry points lead with the core promise.
      case PaywallSource.general:
      case PaywallSource.hardWall:
        return [catalog, split, fresh, smaczki, streak, favorites, offline];
      case PaywallSource.smaczki:
        return [smaczki, catalog, split, fresh, streak, favorites, offline];
      // One benefit row covers both favorites and history.
      case PaywallSource.favorites:
      case PaywallSource.history:
        return [favorites, catalog, split, fresh, smaczki, streak, offline];
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Shown to everyone the wall stops, not just guests. It used to be hidden
    // from account holders as pointless — but the wall no longer has a profile
    // entry, so for a signed-in user without PRO this link is the only way to
    // reach a DIFFERENT account, the one their purchase actually sits on.
    final showSignIn = widget.showSignInLink;
    final subheadline = _subheadline(context);
    final hasOffer = _packages?.isNotEmpty ?? false;

    final scrollBody = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
        if (subheadline != null) ...[
          const SizedBox(height: 10),
          Text(
            subheadline,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.subtle, fontSize: 14, height: 1.4),
          ),
        ],
        const SizedBox(height: 22),
        _buildOffer(context),
        const SizedBox(height: 26),
        Text(
          context.l10n.paywallWhatYouGet,
          style: const TextStyle(
            color: AppTheme.spark,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        ..._benefits(context),
      ],
    );

    final scroll = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: scrollBody,
    );

    return Column(
      mainAxisSize: widget.fillHeight ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.fillHeight)
          Expanded(child: scroll)
        else
          Flexible(child: scroll),
        _StickyCtaBar(
          busy: _busy,
          // No CTA without a loaded offer — the body shows the retry state.
          onBuy: hasOffer ? _buy : null,
          note: _selected?.packageType == PackageType.lifetime
              ? context.l10n.paywallLifetimeNote
              : context.l10n.paywallSubscriptionNote,
          links: PaywallFooterLinks(
            busy: _busy,
            onSignIn: showSignIn ? () => showAuthSheet(context) : null,
            onRestore: _restore,
            onTerms: AppConfig.hasTermsOfService
                ? () => _openLegalUrl(AppConfig.termsOfServiceUrl)
                : null,
            onPrivacy: AppConfig.hasPrivacyPolicy
                ? () => _openLegalUrl(AppConfig.privacyPolicyUrl)
                : null,
          ),
        ),
      ],
    );
  }

  /// The live part of the pitch: the plan cards once the fetch resolves, with
  /// loading and retryable error states in the meantime.
  Widget _buildOffer(BuildContext context) {
    if (_loadFailed || (_packages?.isEmpty ?? false)) {
      return PaywallOfferError(onRetry: _retryLoad);
    }
    final packages = _packages;
    final selected = _selected;
    if (packages == null || selected == null) {
      return const SizedBox(
        height: 140,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
    }
    return PaywallOfferSection(
      packages: packages,
      selected: selected,
      busy: _busy,
      onSelect: _selectPackage,
    );
  }
}

/// The bar pinned under the scrollable pitch: the buy CTA with its
/// reassurance line ("one payment — forever" for the lifetime plan) and the
/// quiet sign-in / restore / legal links row — the escape hatches for
/// returning users, always on screen regardless of scroll position.
class _StickyCtaBar extends StatelessWidget {
  const _StickyCtaBar({
    required this.busy,
    required this.note,
    required this.onBuy,
    required this.links,
  });

  final bool busy;
  final String note;

  /// null hides the CTA (offer still loading or unavailable).
  final VoidCallback? onBuy;

  /// The sign-in / restore / legal row pinned at the very bottom.
  final Widget links;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // The sheet route leaves the bottom system inset to its content (see
    // ProPaywallSheet); on the hard wall the enclosing SafeArea has already
    // consumed it, so this padding resolves to 0 there.
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(24, 12, 24, 6 + bottomInset),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(top: BorderSide(color: colors.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (onBuy != null) ...[
            PaywallCtaButton(
              label: context.l10n.paywallCta,
              busy: busy,
              onTap: onBuy!,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 15,
                  color: colors.subtle,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    note,
                    style: TextStyle(color: colors.subtle, fontSize: 12.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
          ],
          links,
        ],
      ),
    );
  }
}
