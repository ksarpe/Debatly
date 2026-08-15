import 'package:debatly/services/purchases_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// The pure decision tables inside [PurchasesService]: which API keys are worth
/// configuring, how RevenueCat's ten billing stores collapse onto the four the
/// UI knows, the paywall's package ordering, and the "cancelled but still
/// paid-up" signal. Each is a switch someone will extend one day — these pin
/// what the existing cases must keep meaning.
void main() {
  group('isUsableKey', () {
    test('rejects empty, placeholder and legacy test keys', () {
      expect(PurchasesService.isUsableKey(''), isFalse);
      expect(PurchasesService.isUsableKey('REPLACE_WITH_REAL_KEY'), isFalse);
      expect(PurchasesService.isUsableKey('goog_REPLACE_ME'), isFalse);
      expect(PurchasesService.isUsableKey('test_abcdef'), isFalse);
    });

    test('accepts real platform-prefixed keys', () {
      expect(PurchasesService.isUsableKey('goog_AbCdEf123'), isTrue);
      expect(PurchasesService.isUsableKey('appl_AbCdEf123'), isTrue);
    });
  });

  group('mapStore', () {
    test('maps every RevenueCat store onto the four UI stores', () {
      const expected = {
        Store.appStore: PremiumStore.appStore,
        Store.macAppStore: PremiumStore.appStore,
        Store.playStore: PremiumStore.playStore,
        Store.stripe: PremiumStore.web,
        Store.rcBilling: PremiumStore.web,
        Store.paddle: PremiumStore.web,
        Store.externalStore: PremiumStore.web,
        Store.amazon: PremiumStore.other,
        Store.galaxy: PremiumStore.other,
        Store.promotional: PremiumStore.other,
        Store.testStore: PremiumStore.other,
        Store.unknownStore: PremiumStore.other,
      };
      for (final store in Store.values) {
        expect(
          PurchasesService.mapStore(store),
          expected[store],
          reason:
              'Store.$store must map to ${expected[store]} — a new enum '
              'value needs an explicit decision here, not a fall-through',
        );
      }
    });
  });

  group('packageRank', () {
    test('orders the paywall lifetime-first, then longest-to-shortest', () {
      const order = [
        PackageType.lifetime,
        PackageType.annual,
        PackageType.sixMonth,
        PackageType.threeMonth,
        PackageType.twoMonth,
        PackageType.monthly,
        PackageType.weekly,
      ];
      for (var i = 1; i < order.length; i++) {
        expect(
          PurchasesService.packageRank(order[i - 1]),
          lessThan(PurchasesService.packageRank(order[i])),
          reason:
              '${order[i - 1]} must sort before ${order[i]} — the sheet '
              'preselects index 0, so this order IS the default plan',
        );
      }
      // The catch-alls sort last, behind every real duration.
      expect(
        PurchasesService.packageRank(PackageType.custom),
        greaterThan(PurchasesService.packageRank(PackageType.weekly)),
      );
      expect(
        PurchasesService.packageRank(PackageType.unknown),
        greaterThan(PurchasesService.packageRank(PackageType.weekly)),
      );
    });
  });

  // RevenueCat reports `willRenew: false` for BOTH a cancelled subscription and
  // an entitlement that never renews in the first place (a lifetime purchase, a
  // permanent promo grant). Only the expiry date separates them — and getting
  // that wrong greeted every buyer of the plan the paywall preselects with
  // "Cancelled — won't renew".
  group('PremiumStatus.isCancelled / isLifetime', () {
    PremiumStatus status({
      required bool isActive,
      required bool willRenew,
      DateTime? expiry,
    }) => PremiumStatus(
      isActive: isActive,
      willRenew: willRenew,
      store: PremiumStore.playStore,
      expirationDate: expiry,
    );

    final periodEnd = DateTime(2026, 9, 15);

    test('cancelled = still active, no longer renewing, and it runs out', () {
      expect(
        status(isActive: true, willRenew: false, expiry: periodEnd).isCancelled,
        isTrue,
      );
      expect(
        status(isActive: true, willRenew: true, expiry: periodEnd).isCancelled,
        isFalse,
      );
      // An expired entitlement is "gone", not "cancelled".
      expect(
        status(
          isActive: false,
          willRenew: false,
          expiry: periodEnd,
        ).isCancelled,
        isFalse,
      );
      expect(
        status(isActive: false, willRenew: true, expiry: periodEnd).isCancelled,
        isFalse,
      );
    });

    test('a lifetime purchase is NOT a cancelled subscription', () {
      // No renewal and no end date — the shape RevenueCat reports for a
      // non-consumable buy or a permanent grant.
      final lifetime = status(isActive: true, willRenew: false);
      expect(lifetime.isLifetime, isTrue);
      expect(
        lifetime.isCancelled,
        isFalse,
        reason: 'nothing was cancelled — there is nothing to renew',
      );
    });

    test('a live subscription is not lifetime', () {
      expect(
        status(isActive: true, willRenew: true, expiry: periodEnd).isLifetime,
        isFalse,
      );
      // Neither is one the user cancelled: it still has an end date.
      expect(
        status(isActive: true, willRenew: false, expiry: periodEnd).isLifetime,
        isFalse,
      );
    });

    test('an inactive entitlement is neither', () {
      final gone = status(isActive: false, willRenew: false);
      expect(gone.isLifetime, isFalse);
      expect(gone.isCancelled, isFalse);
    });
  });
}
