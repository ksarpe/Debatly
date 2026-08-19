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
import '../../../core/theme/app_typography.dart';
import '../../../services/analytics.dart';
import '../../../services/purchases_service.dart';
import '../../account/providers/session_providers.dart';
import '../../account/providers/stats_providers.dart';
import '../../account/screens/auth_screen.dart';
import '../../account/widgets/restore_sign_in_prompt.dart';
import '../../settings/providers/app_info_provider.dart';
import 'paywall_cta_button.dart';
import 'paywall_feature_list.dart';
import 'paywall_footer_links.dart';
import 'paywall_offer_error.dart';
import 'paywall_offer_section.dart';

/// Where the user opened the paywall from. Analytics-only: the pitch itself
/// is identical for every entry point (one slogan headline, one subline), and
/// the enum name becomes the `source` value in the paywall funnel events.
enum PaywallSource {
  /// Settings row and other neutral entry points.
  general,

  /// The post-onboarding bridge screen's "unlock all 500" CTA.
  bridge,

  /// The free tier's day wall — the main conversion surface.
  wall,

  /// The locked PRO argument on the smaczki panel.
  smaczki,

  /// The greyed-out favorite star.
  favorites,

  /// The history upsell (voting record).
  history,

  /// The locked PRO depth (trend / categories / moved list) under the debate
  /// profile in the conformity panel.
  profile,
}

/// The paywall body inside the fullscreen paywall ([ProPaywallScreen]): a
/// scrollable pitch (brand label + slogan headline + live package stack +
/// compact feature list) with the CTA pinned in a sticky bar underneath
/// together with the restore/legal footer, so the buy button stays on screen
/// while the user scrolls.
///
/// The monthly plan comes preselected (the CTA is armed as soon as the offer
/// loads); no "best value" badge on top of that. Should the offering ever
/// arrive without a monthly package, nothing is selected and the CTA stays
/// disabled until a plan is tapped.
///
/// The owner provides the chrome and decides what happens once the user is
/// entitled ([onEntitled] — pop the sheet). [loadPackages]/[buy] exist for
/// widget tests (RevenueCat can't be configured there); production always
/// uses [PurchasesService].
class ProPaywallContent extends ConsumerStatefulWidget {
  const ProPaywallContent({
    super.key,
    required this.source,
    required this.onEntitled,
    this.trigger = 'tap',
    this.headline,
    this.onBusyChanged,
    this.showSignInLink = false,
    this.loadPackages,
    this.buy,
    this.retryBackoff,
  });

  /// Optional headline override, already localized. Null renders the fixed
  /// slogan ([AppLocalizations.paywallTitleDefault]). The one sanctioned
  /// caller is the debate-profile entry — see [showProPaywall].
  final String? headline;

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

  /// How the sheet came up — `'auto'` for the once-a-day automatic open on the
  /// day wall, `'tap'` for every user-initiated open. Analytics-only: it lets
  /// the funnel separate "we showed it" from "they asked for it".
  final String trigger;

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

  /// Offers "Already have PRO? Sign in" in the sticky bar — a returning
  /// user's entitlement may live on their account rather than in this
  /// device's store history.
  final bool showSignInLink;

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

  /// The armed package: the monthly plan as soon as the offer loads
  /// (preselected), then whatever the user taps. Null only while the offer is
  /// loading or when the offering carries no monthly package.
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
    Analytics.log('paywall_shown', {
      'source': widget.source.name,
      'trigger': widget.trigger,
      'streak': ref.read(currentStreakProvider),
    });
    _loadOffer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _loadGeneration++;
    super.dispose();
  }

  /// Re-fetches an absent offer when the user comes back to the app.
  ///
  /// The realistic recovery from a store/network failure is the user leaving
  /// to do something about it — toggle airplane mode, find signal, update the
  /// Play Store — and the wall they return to must not still be the dead one
  /// they left. An EMPTY offering is refetched here too: it shows no retry
  /// button (nothing the user can do would change the answer), but a store
  /// configuration fixed while the app sat in the background should still heal
  /// on the next resume rather than needing a relaunch. Only when the offer is
  /// actually missing: a resume after the store's own purchase sheet (or any
  /// other trip out) has nothing to reload.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_busy) return;
    final emptyOffering = _packages?.isEmpty ?? false;
    if (!_loadFailed && !emptyOffering) return;
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
      // The monthly plan comes preselected so the CTA is armed on open; a
      // lifetime buyer makes one extra tap. `paywall_plan_selected` still only
      // fires on real taps, so the analytics keep telling picks from defaults.
      Package? monthly;
      for (final package in packages) {
        if (package.packageType == PackageType.monthly) {
          monthly = package;
          break;
        }
      }
      setState(() {
        _packages = packages;
        _selected ??= monthly;
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
        // The canonical conversion event of the freemium funnel
        // (wall_reached → paywall_shown → purchase_completed); the richer
        // paywall_purchased above stays for continuity with older data.
        Analytics.log('purchase_completed', {'plan': package.packageType.name});
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
  /// The sheet pops on entitlement (we unmount, so the unlock is a no-op) —
  /// but the owner's reconcile can fail (a 502 from `sync-entitlement`, a
  /// RevenueCat webhook that hasn't landed) and leave this content mounted.
  /// Leaving `_busy` set then would strand a user who had just paid on a
  /// spinning CTA with restore, sign-in and the legal links all disabled,
  /// recoverable only by killing the app — so the surface always unlocks.
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

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Shown to everyone the wall stops, not just guests. It used to be hidden
    // from account holders as pointless — but the wall no longer has a profile
    // entry, so for a signed-in user without PRO this link is the only way to
    // reach a DIFFERENT account, the one their purchase actually sits on.
    final showSignIn = widget.showSignInLink;
    final hasOffer = _packages?.isNotEmpty ?? false;

    // Version + short user code, the paywall's only identity breadcrumb. The
    // wall has no Settings and no profile, so a walled user has NOTHING to
    // read out when they contact support (or a promo grant is arranged for
    // them) — every install looks like an anonymous uuid from the dashboard
    // side. The last 4 uid characters are enough to find the account
    // (`auth.users.id::text ilike '%<code>'`) without exposing the uuid
    // itself. Hidden until both lookups resolve; nothing here is worth a
    // loading state.
    final appInfo = ref.watch(appInfoProvider).value;
    final userId = ref.watch(sessionProvider).value?.userId;
    final supportStamp =
        (appInfo != null && userId != null && userId.length >= 4)
        ? context.l10n.paywallBuildStamp(
            appInfo.version,
            appInfo.build,
            userId.substring(userId.length - 4).toUpperCase(),
          )
        : null;

    // Left-aligned editorial layout: the brand label anchors the top-left
    // (the screen's floating X keeps the top-right), then the slogan headline
    // over the pitch line, the plan stack, and the compact feature list. The
    // copy is identical for every entry point — the source only feeds
    // analytics — with ONE sanctioned exception: the debate-profile entry
    // passes its portrait headline via [ProPaywallContent.headline].
    final scrollBody = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        Text(
          context.l10n.paywallBrand,
          style: AppTypography.eyebrow(
            fontSize: 11,
          ).copyWith(color: AppTheme.spark),
        ),
        const SizedBox(height: 18),
        Text(
          (widget.headline ?? context.l10n.paywallTitleDefault).toUpperCase(),
          style: AppTypography.display(40).copyWith(color: colors.ink),
        ),
        const SizedBox(height: 12),
        Text(
          context.l10n.paywallSubtitle,
          style: AppTypography.body().copyWith(color: colors.subtle),
        ),
        const SizedBox(height: 24),
        _buildOffer(context),
        const SizedBox(height: 10),
        const PaywallFeatureList(),
      ],
    );

    final scroll = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: scrollBody,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(child: scroll),
        _StickyCtaBar(
          busy: _busy,
          stamp: supportStamp,
          // No CTA without a loaded offer (the body shows the retry state).
          // The monthly plan is preselected on load, so the CTA is usually
          // armed immediately; the DISABLED variant only shows for an
          // offering with no monthly package to preselect.
          onBuy: hasOffer && _selected != null ? _buy : null,
          showDisabledCta: hasOffer && _selected == null,
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
    // A failed fetch and an empty offering look the same here but are not the
    // same problem — see [PaywallOfferProblem].
    if (_loadFailed) {
      return PaywallOfferError(
        problem: PaywallOfferProblem.unreachable,
        onRetry: _retryLoad,
      );
    }
    if (_packages?.isEmpty ?? false) {
      return PaywallOfferError(
        problem: PaywallOfferProblem.unavailable,
        onRetry: _retryLoad,
      );
    }
    final packages = _packages;
    if (packages == null) {
      return const SizedBox(
        height: 140,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
    }
    return PaywallOfferSection(
      packages: packages,
      // The monthly plan on load, then whatever the user taps.
      selected: _selected,
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
    this.showDisabledCta = false,
    this.stamp,
  });

  final bool busy;
  final String note;

  /// null hides the CTA (offer still loading or unavailable) — unless
  /// [showDisabledCta] asks for the visible-but-disabled variant.
  final VoidCallback? onBuy;

  /// Renders the CTA disabled instead of hidden: the offer is loaded but no
  /// plan has been tapped yet, and a button that appears out of nowhere on the
  /// first tap would jump the layout.
  final bool showDisabledCta;

  /// The sign-in / restore / legal row pinned at the very bottom.
  final Widget links;

  /// Version + short user code under the links; null hides the line.
  final String? stamp;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // The screen's SafeArea leaves the bottom system inset to its content
    // (see ProPaywallScreen), so the sticky bar pads itself past the gesture
    // bar.
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
          if (onBuy != null || showDisabledCta) ...[
            PaywallCtaButton(
              label: context.l10n.paywallCta,
              busy: busy,
              onTap: onBuy,
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
                    style: AppTypography.support(
                      fontSize: 12.5,
                    ).copyWith(color: colors.subtle),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
          ],
          links,
          if (stamp != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                stamp!,
                textAlign: TextAlign.center,
                style: AppTypography.support(
                  fontSize: 11,
                ).copyWith(color: colors.subtle.withValues(alpha: 0.65)),
              ),
            ),
        ],
      ),
    );
  }
}
