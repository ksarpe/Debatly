import 'dart:async' show TimeoutException;

import 'package:debatly/services/purchases_service.dart';
import 'package:flutter/services.dart' show PlatformException;
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
      ];
      for (var i = 1; i < order.length; i++) {
        expect(
          PurchasesService.packageRank(order[i - 1]),
          lessThan(PurchasesService.packageRank(order[i])),
          reason:
              '${order[i - 1]} must sort before ${order[i]} — this order is '
              'how the sheet presents the offering',
        );
      }
      // The catch-alls — weekly included, there is no weekly plan — sort
      // last, behind every plan the product stands by.
      for (final type in const [
        PackageType.weekly,
        PackageType.custom,
        PackageType.unknown,
      ]) {
        expect(
          PurchasesService.packageRank(type),
          greaterThan(PurchasesService.packageRank(PackageType.monthly)),
          reason: '$type must sort behind the real lineup',
        );
      }
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

  // How a caught store failure is triaged: retry it or give up, page us or
  // breadcrumb it. Wrong on the first axis and the paywall is a retry button
  // for anyone whose Play client blinks; wrong on the second and the real
  // purchase bugs drown in offline noise.
  group('store failure classification', () {
    /// A RevenueCat failure as it actually arrives: a PlatformException whose
    /// `code` is the [PurchasesErrorCode] index as a string.
    PlatformException rcError(PurchasesErrorCode code) => PlatformException(
      code: '${code.index}',
      message: 'Error performing request.',
      details: {'readableErrorCode': code.name},
    );

    test('reads the RevenueCat code off the platform exception', () {
      // The live incident: Play answering product lookup with NETWORK_ERROR,
      // which arrives as code "10".
      expect(
        PurchasesService.errorCodeOf(rcError(PurchasesErrorCode.networkError)),
        PurchasesErrorCode.networkError,
      );
      expect(PurchasesService.errorCodeOf(StateError('nope')), isNull);
    });

    test('a non-RevenueCat PlatformException does not blow up the lookup', () {
      // `PurchasesErrorHelper.getErrorCode` does a bare `num.parse(e.code)`, so
      // a channel error from any other plugin used to throw a FormatException
      // out of the catch block that was meant to contain it.
      expect(
        PurchasesService.errorCodeOf(
          PlatformException(code: 'channel-error', message: 'Unable to call'),
        ),
        isNull,
      );
    });

    test('the store/network failures are retryable and not our bug', () {
      const environmental = [
        PurchasesErrorCode.networkError,
        PurchasesErrorCode.offlineConnectionError,
        PurchasesErrorCode.storeProblemError,
        PurchasesErrorCode.productRequestTimeout,
      ];
      for (final code in environmental) {
        expect(PurchasesService.isEnvironmentFailure(rcError(code)), isTrue);
        expect(PurchasesService.isRetryableFailure(rcError(code)), isTrue);
      }
      // DNS-blocked RevenueCat is the user's network too, but retrying it in
      // the next two seconds fixes nothing.
      final blocked = rcError(PurchasesErrorCode.apiEndpointBlocked);
      expect(PurchasesService.isEnvironmentFailure(blocked), isTrue);
      expect(PurchasesService.isRetryableFailure(blocked), isFalse);
    });

    test('a device that cannot buy at all is not our bug either', () {
      // BILLING_UNAVAILABLE (emulators, the Play pre-launch bots, de-Googled
      // phones) and a barred account both arrive as this code, and both fail
      // identically forever — so: never Sentry, never retried.
      final notAllowed = rcError(PurchasesErrorCode.purchaseNotAllowedError);
      expect(PurchasesService.isEnvironmentFailure(notAllowed), isTrue);
      expect(PurchasesService.isRetryableFailure(notAllowed), isFalse);
    });

    test('a broken configuration is reported and never retried', () {
      // These fail identically forever — retrying just delays the error state,
      // and they are exactly the ones that must reach Sentry.
      for (final code in const [
        PurchasesErrorCode.configurationError,
        PurchasesErrorCode.invalidCredentialsError,
        PurchasesErrorCode.invalidAppUserIdError,
      ]) {
        expect(PurchasesService.isEnvironmentFailure(rcError(code)), isFalse);
        expect(PurchasesService.isRetryableFailure(rcError(code)), isFalse);
      }
    });

    test('a backend blip is retried but still reported', () {
      for (final code in const [
        PurchasesErrorCode.unknownBackendError,
        PurchasesErrorCode.unexpectedBackendResponseError,
      ]) {
        expect(PurchasesService.isRetryableFailure(rcError(code)), isTrue);
        expect(PurchasesService.isEnvironmentFailure(rcError(code)), isFalse);
      }
    });

    test('a dropped connection counts even without a RevenueCat code', () {
      // The bounded fetch in [paywallPackages] surfaces a hung request as a
      // TimeoutException, which carries no RevenueCat code at all.
      final timeout = TimeoutException('getOfferings', kOfferFetchTimeout);
      expect(PurchasesService.isRetryableFailure(timeout), isTrue);
      expect(PurchasesService.isEnvironmentFailure(timeout), isTrue);
      // An ordinary bug is neither.
      expect(PurchasesService.isRetryableFailure(StateError('bug')), isFalse);
      expect(PurchasesService.isEnvironmentFailure(StateError('bug')), isFalse);
    });
  });
}
