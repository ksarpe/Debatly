import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config/app_config.dart';
import '../core/monitoring/monitoring.dart';
import '../core/network/network_error.dart';

/// Where the active subscription is billed — drives the wording and the
/// "manage" deep link, since cancellation lives in a different place on each
/// platform (Apple and Google both forbid cancelling from inside the app).
enum PremiumStore {
  appStore,
  playStore,

  /// Web / third-party billing (Stripe, RevenueCat Billing, an external store).
  web,

  /// Promotional grants, Amazon, or anything we don't surface a deep link for.
  other,
}

/// A read-only snapshot of the user's premium subscription, distilled from the
/// RevenueCat `EntitlementInfo` into just what the Manage-subscription UI needs.
///
/// [willRenew] alone is NOT the cancellation signal: RevenueCat reports `false`
/// both for a subscription the user turned off and for an entitlement that never
/// renews in the first place (a lifetime purchase, a permanent promo grant).
/// [expirationDate] is what separates them — see [isCancelled] / [isLifetime].
@immutable
class PremiumStatus {
  const PremiumStatus({
    required this.isActive,
    required this.willRenew,
    required this.store,
    this.expirationDate,
    this.managementUrl,
  });

  final bool isActive;
  final bool willRenew;
  final PremiumStore store;

  /// End of the current paid period. Null for lifetime/promotional grants.
  final DateTime? expirationDate;

  /// Store-specific deep link to the subscription-management page (the
  /// App Store / Google Play subscriptions screen). Null when RevenueCat can't
  /// build one (e.g. promotional entitlements).
  final String? managementUrl;

  /// An entitlement that simply never ends: a lifetime (non-consumable)
  /// purchase or a permanent promotional grant. There is no renewal to manage
  /// and nothing to cancel, so the manage sheet must not send these users to
  /// the store's Subscriptions screen.
  bool get isLifetime => isActive && !willRenew && expirationDate == null;

  /// The user has cancelled but is still inside their paid period.
  ///
  /// The expiry check is load-bearing: a lifetime purchase also reports
  /// `willRenew: false`, so without it the plan the paywall preselects and
  /// pitches as "one payment — forever" would greet its buyers with
  /// "Cancelled — won't renew".
  bool get isCancelled => isActive && !willRenew && expirationDate != null;
}

/// How long a single offering fetch is allowed to take before it counts as a
/// failure the paywall can retry. Bounded because the paywall can only retry
/// an attempt that actually ends — behind a hung request it would otherwise
/// spin forever, which on a hard-walled app is the whole product hanging.
const Duration kOfferFetchTimeout = Duration(seconds: 10);

/// How a purchase attempt ended.
///
/// A bare `bool` collapsed the last three cases into "nothing happened", so a
/// user whose payment was REFUSED (Play couldn't reach its backend, the card
/// bounced) got exactly the same silence as one who deliberately backed out of
/// the store sheet: no message, no retry hint — they just tap the CTA again.
enum PurchaseOutcome {
  /// Paid, and the premium entitlement is already visible.
  entitled,

  /// Paid, but the entitlement hasn't shown up yet (a webhook still in flight,
  /// a customer-info fetch that failed). The money left their account — this
  /// must never be reported to the user as a failure; the session reconcile
  /// decides, and the surfaces already say "couldn't confirm it yet".
  pending,

  /// The user backed out of the store sheet. Their choice — say nothing.
  cancelled,

  /// The store or the network refused. They tried to pay and it did not work.
  failed,
}

/// How a restore attempt ended. Same reasoning as [PurchaseOutcome]: a restore
/// that never reached the store is NOT the same as one that reached it and
/// found nothing, and telling a paying user "no previous purchase found"
/// because their train went into a tunnel is how refund requests start.
enum RestoreOutcome {
  /// The store had a purchase and premium is now active.
  restored,

  /// The store answered, and this account/device simply owns nothing.
  none,

  /// The store could not be reached at all.
  failed,
}

/// Wrapper around RevenueCat (`purchases_flutter`).
///
/// Handles SDK configuration and exposes a single [isPremium] check the rest of
/// the app can use to gate premium questions. Skips configuration when no API
/// key is supplied so the app runs without RevenueCat during development.
class PurchasesService {
  PurchasesService._();

  /// Entitlement identifier configured in the RevenueCat dashboard. Adjust here
  /// (one place) if the dashboard uses a different name.
  static const String _premiumEntitlementId = 'premium';

  static bool _configured = false;

  /// Whether RevenueCat was actually configured this run. False in mock /
  /// keyless development, where nothing can be bought or restored — the
  /// session layer uses this to decide the app is running against mock data.
  static bool get isConfigured => _configured;

  static Future<void> initialise() async {
    if (!isUsableKey(AppConfig.revenueCatApiKey)) {
      debugPrint(
        'PurchasesService: no usable API key — skipping RevenueCat configure. '
        'Pass --dart-define=REVENUECAT_API_KEY with a real public SDK key '
        '(goog_… on Android, appl_… on iOS) to enable premium.',
      );
      return;
    }

    // Degrade gracefully like SupabaseService: a bad key must not
    // abort app launch. RevenueCat's native SDK ABORTS THE PROCESS on an invalid
    // key ("app will close now to protect the security"), so we both pre-screen
    // obvious placeholders in [isUsableKey] and guard the configure call here.
    try {
      // Verbose RevenueCat logging is a debugging aid, not something to ship:
      // release builds keep it at `warn` so the SDK's per-request chatter stays
      // out of production logcat.
      await Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.warn);
      await Purchases.configure(
        PurchasesConfiguration(AppConfig.revenueCatApiKey),
      );
      _configured = true;
    } catch (e, st) {
      debugPrint(
        'PurchasesService: RevenueCat configure failed — premium disabled. $e',
      );
      // No RevenueCat = nobody can buy or restore PRO this session: a serious,
      // revenue-affecting failure, not a transient blip.
      await Monitoring.captureException(
        e,
        stackTrace: st,
        feature: 'purchases',
      );
    }
  }

  /// Whether [key] looks like a real RevenueCat public SDK key worth handing to
  /// the native SDK. Empty values, the env-file placeholders (which carry
  /// `REPLACE`) and the legacy `test_` sample are treated as "not configured",
  /// so an un-filled key degrades to "premium unavailable" instead of crashing
  /// the app on launch. Real keys are platform-prefixed (`goog_` / `appl_`).
  @visibleForTesting
  static bool isUsableKey(String key) {
    if (key.isEmpty) return false;
    if (key.contains('REPLACE')) return false;
    if (key.startsWith('test_')) return false;
    return true;
  }

  /// Reads the RevenueCat error code off a thrown [PlatformException], or null
  /// when the failure didn't come from RevenueCat at all.
  ///
  /// `PurchasesErrorHelper.getErrorCode` does a bare `num.parse(e.code)`, so
  /// handing it a PlatformException raised by ANY other plugin (a missing
  /// platform implementation, a channel error) throws a `FormatException` from
  /// inside the very catch block that was supposed to contain the failure —
  /// turning a handled error into an unhandled one.
  static PurchasesErrorCode? errorCodeOf(Object error) {
    if (error is! PlatformException) return null;
    try {
      return PurchasesErrorHelper.getErrorCode(error);
    } catch (_) {
      return null;
    }
  }

  /// Whether [error] describes the user's ENVIRONMENT rather than a defect in
  /// the app: the store client can't reach its backend, the device is offline,
  /// DNS is blocking RevenueCat, the store itself is having a bad day.
  ///
  /// These are not actionable as Sentry issues — nothing in this repo fixes
  /// them — and on a hard-paywalled app they arrive in bulk: every retry of
  /// every user on a bad connection, plus every Play pre-launch / review bot,
  /// which has no billing account at all and so fails product lookup by
  /// construction. They get a breadcrumb (so they still show up as context
  /// under a real crash) and a `paywall_offer_unavailable` analytics row, which
  /// is where their VOLUME belongs. Everything else still pages us.
  static bool isEnvironmentFailure(Object error) {
    switch (errorCodeOf(error)) {
      case PurchasesErrorCode.networkError:
      case PurchasesErrorCode.offlineConnectionError:
      case PurchasesErrorCode.storeProblemError:
      case PurchasesErrorCode.apiEndpointBlocked:
      case PurchasesErrorCode.productRequestTimeout:
        return true;
      case null:
        // Not a RevenueCat error — fall back to the app-wide "is this just a
        // dropped connection" test (Monitoring drops those anyway).
        return isOfflineError(error);
      default:
        return false;
    }
  }

  /// Whether [error] is worth simply trying again before giving up on the
  /// user's behalf: everything environmental, plus the backend blips. A
  /// configuration error, by contrast, will fail identically forever.
  static bool isRetryableFailure(Object error) {
    switch (errorCodeOf(error)) {
      case PurchasesErrorCode.networkError:
      case PurchasesErrorCode.offlineConnectionError:
      case PurchasesErrorCode.storeProblemError:
      case PurchasesErrorCode.productRequestTimeout:
      case PurchasesErrorCode.unknownBackendError:
      case PurchasesErrorCode.unexpectedBackendResponseError:
        return true;
      case null:
        return isOfflineError(error);
      default:
        return false;
    }
  }

  /// Routes a caught store failure to the right channel: a breadcrumb for the
  /// environmental ones (see [isEnvironmentFailure]), a real Sentry issue for
  /// everything else. [operation] names the call site.
  static Future<void> _report(
    Object error,
    StackTrace stackTrace, {
    required String operation,
    Map<String, dynamic>? extra,
  }) async {
    final code = errorCodeOf(error)?.name ?? error.runtimeType.toString();
    debugPrint('PurchasesService.$operation failed ($code): $error');
    if (isEnvironmentFailure(error)) {
      Monitoring.addBreadcrumb(
        'Store call "$operation" failed: $code',
        category: 'purchases',
        data: {'rc_code': code, ...?extra},
      );
      return;
    }
    await Monitoring.captureException(
      error,
      stackTrace: stackTrace,
      feature: 'purchases',
      extra: {'operation': operation, 'rc_code': code, ...?extra},
    );
  }

  /// Links the RevenueCat customer to a stable app user id (the Supabase
  /// anonymous UUID), so entitlements follow the same identity the backend uses.
  /// No-ops when RevenueCat is not configured.
  static Future<void> identify(String appUserId) async {
    if (!_configured) return;
    try {
      await Purchases.logIn(appUserId);
    } catch (e, st) {
      // Entitlements may not follow the right identity if this fails — worth
      // knowing about, but the app keeps working off the anonymous RC user.
      await _report(e, st, operation: 'identify');
    }
  }

  /// Registers [onChanged] to fire whenever RevenueCat pushes a customer-info
  /// update — a renewal, an expiry, a restore on another device, or a purchase
  /// completing outside the in-app paywall. The bool is whether premium is now
  /// active. Returns the underlying listener (pass it to [removePremiumListener]
  /// to detach) or null when RevenueCat isn't configured.
  ///
  /// Note RevenueCat fires this immediately on registration with the cached
  /// info; callers should ignore a no-op change.
  static CustomerInfoUpdateListener? addPremiumListener(
    void Function(bool isPremium) onChanged,
  ) {
    if (!_configured) return null;
    void listener(CustomerInfo info) =>
        onChanged(info.entitlements.active.containsKey(_premiumEntitlementId));
    Purchases.addCustomerInfoUpdateListener(listener);
    return listener;
  }

  static void removePremiumListener(CustomerInfoUpdateListener? listener) {
    if (!_configured || listener == null) return;
    Purchases.removeCustomerInfoUpdateListener(listener);
  }

  /// Whether the current user has the active premium entitlement.
  static Future<bool> isPremium() async {
    if (!_configured) return false;
    try {
      final info = await Purchases.getCustomerInfo();
      return info.entitlements.active.containsKey(_premiumEntitlementId);
    } catch (e) {
      debugPrint('PurchasesService.isPremium failed: $e');
      return false;
    }
  }

  /// Reads the active premium subscription's details (renewal date, whether it
  /// will renew, the billing store and its management deep link) for the
  /// Manage-subscription screen. Returns null when RevenueCat isn't configured
  /// or premium isn't active — the caller falls back to a generic state.
  static Future<PremiumStatus?> premiumStatus() async {
    if (!_configured) return null;
    try {
      final info = await Purchases.getCustomerInfo();
      final entitlement = info.entitlements.active[_premiumEntitlementId];
      if (entitlement == null) return null;
      final expiry = entitlement.expirationDate;
      return PremiumStatus(
        isActive: entitlement.isActive,
        willRenew: entitlement.willRenew,
        store: mapStore(entitlement.store),
        expirationDate: expiry == null ? null : DateTime.tryParse(expiry),
        managementUrl: info.managementURL,
      );
    } catch (e) {
      debugPrint('PurchasesService.premiumStatus failed: $e');
      return null;
    }
  }

  /// Opens the native subscription-management page (App Store / Google Play
  /// subscriptions) for the current customer. Neither store lets an app cancel
  /// a subscription itself, so "manage / cancel" always means deep-linking out
  /// to [PremiumStatus.managementUrl]. Returns whether the page could be opened.
  static Future<bool> openManagement(String? managementUrl) async {
    if (managementUrl == null || managementUrl.isEmpty) return false;
    final uri = Uri.tryParse(managementUrl);
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('PurchasesService.openManagement failed: $e');
      return false;
    }
  }

  @visibleForTesting
  static PremiumStore mapStore(Store store) {
    switch (store) {
      case Store.appStore:
      case Store.macAppStore:
        return PremiumStore.appStore;
      case Store.playStore:
        return PremiumStore.playStore;
      case Store.stripe:
      case Store.rcBilling:
      case Store.paddle:
      case Store.externalStore:
        return PremiumStore.web;
      case Store.amazon:
      case Store.galaxy:
      case Store.promotional:
      case Store.testStore:
      case Store.unknownStore:
        return PremiumStore.other;
    }
  }

  /// Loads the packages attached to the current offering, for the in-app
  /// paywall sheet. Sorted "recommended first" (lifetime, then longer
  /// subscriptions before shorter ones) so the sheet can preselect index 0.
  ///
  /// An unconfigured RevenueCat (dev build without an API key) or an empty
  /// offering is an EXPECTED state, not an exceptional one — it comes back as
  /// an empty list, which the paywall renders as its retry state. Only real
  /// failures (network, store) surface as errors from `getOfferings`.
  static Future<List<Package>> paywallPackages() async {
    if (!_configured) {
      debugPrint('PurchasesService: not configured — no paywall packages.');
      return const <Package>[];
    }
    // Bounded (see [kOfferFetchTimeout]); a TimeoutException reads as
    // retryable, so the caller tries again rather than giving up.
    final offerings = await Purchases.getOfferings().timeout(
      kOfferFetchTimeout,
    );
    final packages = offerings.current?.availablePackages ?? const <Package>[];
    return [...packages]
      ..sort((a, b) => packageRank(a.packageType) - packageRank(b.packageType));
  }

  @visibleForTesting
  static int packageRank(PackageType type) {
    switch (type) {
      case PackageType.lifetime:
        return 0;
      case PackageType.annual:
        return 1;
      case PackageType.sixMonth:
        return 2;
      case PackageType.threeMonth:
        return 3;
      case PackageType.twoMonth:
        return 4;
      case PackageType.monthly:
        return 5;
      case PackageType.weekly:
        return 6;
      case PackageType.custom:
      case PackageType.unknown:
        return 7;
    }
  }

  /// Purchases [package] (launched from a paywall CTA) and reports how it
  /// ended — see [PurchaseOutcome] for why the three non-success cases are
  /// kept apart instead of collapsing into one `false`.
  static Future<PurchaseOutcome> purchase(Package package) async {
    if (!_configured) return PurchaseOutcome.failed;
    try {
      await Purchases.purchase(PurchaseParams.package(package));
      // Leave a trail of how the paywall resolved — invaluable when a later
      // "I paid but I'm still free" report comes in.
      Monitoring.addBreadcrumb(
        'Paywall purchase completed: ${package.identifier}',
        category: 'purchases',
      );
      // The entitlement is the source of truth — re-check it rather than
      // trusting the purchase call alone. But the store having taken the money
      // is ALSO a fact, so a missing entitlement here is "not visible yet", not
      // "didn't happen": the caller hands it to the session reconcile, which
      // asks the backend and the store again.
      if (await isPremium()) return PurchaseOutcome.entitled;
      await Monitoring.captureException(
        StateError(
          'Purchase of ${package.identifier} completed but the premium '
          'entitlement is not active',
        ),
        feature: 'purchases',
        extra: {'package': package.identifier},
      );
      return PurchaseOutcome.pending;
    } catch (e, st) {
      if (errorCodeOf(e) == PurchasesErrorCode.purchaseCancelledError) {
        Monitoring.addBreadcrumb(
          'Paywall purchase cancelled',
          category: 'purchases',
        );
        return PurchaseOutcome.cancelled;
      }
      await _report(
        e,
        st,
        operation: 'purchase',
        extra: {'package': package.identifier},
      );
      return PurchaseOutcome.failed;
    }
  }

  /// Restores a previous purchase (e.g. after reinstalling or switching device)
  /// and reports how it ended. Required by the App Store review guidelines for
  /// any app that sells a non-consumable.
  ///
  /// [RestoreOutcome.none] means the store answered and this device/account
  /// owns nothing; a store we never reached is [RestoreOutcome.failed], so the
  /// caller doesn't tell a paying user their purchase doesn't exist.
  static Future<RestoreOutcome> restorePurchases() async {
    if (!_configured) return RestoreOutcome.none;
    try {
      await Purchases.restorePurchases();
      return await isPremium() ? RestoreOutcome.restored : RestoreOutcome.none;
    } catch (e, st) {
      // A failed restore strands a paying user on the free tier — report it
      // (unless it's plainly their connection; see [_report]).
      await _report(e, st, operation: 'restorePurchases');
      return RestoreOutcome.failed;
    }
  }
}
