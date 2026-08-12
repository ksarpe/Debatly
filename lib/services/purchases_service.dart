import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config/app_config.dart';
import '../core/monitoring/monitoring.dart';

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
/// [willRenew] is the cancellation signal: `false` means the user has already
/// turned off auto-renew (in the store) but keeps premium until [expirationDate].
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

  /// The user has cancelled but is still inside their paid period.
  bool get isCancelled => isActive && !willRenew;
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

  static Future<void> initialise() async {
    if (!isUsableKey(AppConfig.revenueCatApiKey)) {
      debugPrint(
        'PurchasesService: no usable API key — skipping RevenueCat configure. '
        'Pass --dart-define=REVENUECAT_API_KEY with a real public SDK key '
        '(goog_… on Android, appl_… on iOS) to enable premium.',
      );
      return;
    }

    // Degrade gracefully like SupabaseService / AdsService: a bad key must not
    // abort app launch. RevenueCat's native SDK ABORTS THE PROCESS on an invalid
    // key ("app will close now to protect the security"), so we both pre-screen
    // obvious placeholders in [isUsableKey] and guard the configure call here.
    try {
      await Purchases.setLogLevel(LogLevel.debug);
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

  /// Links the RevenueCat customer to a stable app user id (the Supabase
  /// anonymous UUID), so entitlements follow the same identity the backend uses.
  /// No-ops when RevenueCat is not configured.
  static Future<void> identify(String appUserId) async {
    if (!_configured) return;
    try {
      await Purchases.logIn(appUserId);
    } catch (e, st) {
      debugPrint('PurchasesService.identify failed: $e');
      // Entitlements may not follow the right identity if this fails — worth
      // knowing about, but the app keeps working off the anonymous RC user.
      await Monitoring.captureException(
        e,
        stackTrace: st,
        feature: 'purchases',
      );
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
    final offerings = await Purchases.getOfferings();
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

  /// Purchases [package] (launched from the in-app paywall sheet) and reports
  /// whether the premium entitlement is active afterwards.
  ///
  /// A user-cancelled purchase is a quiet `false`, not an error.
  static Future<bool> purchase(Package package) async {
    if (!_configured) return false;
    try {
      await Purchases.purchase(PurchaseParams.package(package));
      // Leave a trail of how the paywall resolved — invaluable when a later
      // "I paid but I'm still free" report comes in.
      Monitoring.addBreadcrumb(
        'Paywall purchase completed: ${package.identifier}',
        category: 'purchases',
      );
      // The entitlement is the source of truth — re-check it rather than
      // trusting the purchase call alone.
      return await isPremium();
    } on PlatformException catch (e, st) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        Monitoring.addBreadcrumb(
          'Paywall purchase cancelled',
          category: 'purchases',
        );
        return false;
      }
      debugPrint('PurchasesService.purchase failed: $e');
      await Monitoring.captureException(
        e,
        stackTrace: st,
        feature: 'purchases',
      );
      return false;
    } catch (e, st) {
      debugPrint('PurchasesService.purchase failed: $e');
      await Monitoring.captureException(
        e,
        stackTrace: st,
        feature: 'purchases',
      );
      return false;
    }
  }

  /// Restores a previous purchase (e.g. after reinstalling or switching device)
  /// and reports whether premium is active afterwards. Required by the App
  /// Store review guidelines for any app that sells a non-consumable.
  static Future<bool> restorePurchases() async {
    if (!_configured) return false;
    try {
      await Purchases.restorePurchases();
      return await isPremium();
    } catch (e, st) {
      debugPrint('PurchasesService.restorePurchases failed: $e');
      // A failed restore strands a paying user on the free tier — report it.
      await Monitoring.captureException(
        e,
        stackTrace: st,
        feature: 'purchases',
      );
      return false;
    }
  }
}
