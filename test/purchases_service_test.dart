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

  group('PremiumStatus.isCancelled', () {
    PremiumStatus status({required bool isActive, required bool willRenew}) =>
        PremiumStatus(
          isActive: isActive,
          willRenew: willRenew,
          store: PremiumStore.playStore,
        );

    test('cancelled = still active but no longer renewing', () {
      expect(status(isActive: true, willRenew: false).isCancelled, isTrue);
      expect(status(isActive: true, willRenew: true).isCancelled, isFalse);
      // An expired entitlement is "gone", not "cancelled".
      expect(status(isActive: false, willRenew: false).isCancelled, isFalse);
      expect(status(isActive: false, willRenew: true).isCancelled, isFalse);
    });
  });
}
