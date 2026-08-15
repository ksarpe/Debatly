import 'package:debatly/features/monetization/widgets/paywall_content.dart';
import 'package:debatly/features/monetization/widgets/pro_paywall_sheet.dart';
import 'package:debatly/services/purchases_service.dart' show PurchaseOutcome;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'support/localized_test_app.dart';

/// The in-app PRO paywall sheet. Packages come from the current RevenueCat
/// offering in production; here they're injected via [ProPaywallSheet.loadPackages]
/// (RevenueCat can't be configured in tests), which is exactly the seam the
/// sheet exposes for this purpose. Copy is asserted against the Polish locale
/// pinned by [LocalizedTestApp].
void main() {
  Package fakePackage(
    PackageType type,
    String priceString, {
    double price = 9.99,
    String currencyCode = 'USD',
  }) => Package(
    '\$rc_${type.name}',
    type,
    StoreProduct(
      'prod_${type.name}',
      'description',
      'Debatly PRO',
      price,
      priceString,
      currencyCode,
    ),
    const PresentedOfferingContext('default', null, null),
  );

  // The live US prices in Google Play, so the fixtures double as a record of
  // what the sheet actually renders in production.
  final lifetime = fakePackage(PackageType.lifetime, r'$22.99', price: 22.99);
  final monthly = fakePackage(PackageType.monthly, r'$5.49', price: 5.49);

  Future<void> pumpSheet(
    WidgetTester tester, {
    required Future<List<Package>> Function() loadPackages,
    Future<PurchaseOutcome> Function(Package)? buy,
    PaywallSource source = PaywallSource.general,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        child: LocalizedTestApp(
          home: Scaffold(
            body: ProPaywallSheet(
              source: source,
              loadPackages: loadPackages,
              buy: buy,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders benefits, live prices and preselects the first plan', (
    tester,
  ) async {
    await pumpSheet(tester, loadPackages: () async => [lifetime, monthly]);

    // Headline + the full "everything you get" list.
    expect(
      find.text('Zyskaj dostęp do wszystkich pytań i głosów'),
      findsOneWidget,
    );
    expect(find.text('Cały katalog 500+ pytań'), findsOneWidget);
    expect(find.text('Głosy z całego świata'), findsOneWidget);
    expect(find.text('Dziesiątki nowych pytań'), findsOneWidget);
    expect(find.text('Argumenty ZA i PRZECIW'), findsOneWidget);
    expect(find.text('Seria i rangi'), findsOneWidget);
    expect(find.text('Ulubione i historia głosów'), findsOneWidget);
    expect(find.text('Działa offline'), findsOneWidget);

    // Both plans with their store-formatted prices; monthly gets the suffix.
    expect(find.text('Dożywotni'), findsOneWidget);
    expect(find.text(r'$22.99'), findsOneWidget);
    expect(find.text('Miesięczny'), findsOneWidget);
    expect(find.text(r'$5.49/mies.'), findsOneWidget);
    expect(find.text('NAJLEPSZA OFERTA'), findsOneWidget);

    // Lifetime is preselected, so the reassurance line is the one-time one.
    expect(find.text('Jedna płatność — na zawsze'), findsOneWidget);
    expect(find.text('Odblokuj pełny dostęp'), findsOneWidget);
  });

  testWidgets('smaczki source swaps the headline and leads with arguments', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      loadPackages: () async => [lifetime, monthly],
      source: PaywallSource.smaczki,
    );

    expect(
      find.text('Poznaj wszystkie argumenty do każdego pytania'),
      findsOneWidget,
    );
    expect(
      find.text('Zyskaj dostęp do wszystkich pytań i głosów'),
      findsNothing,
    );

    // The smaczki benefit is reordered above the default lead (the catalog).
    final smaczkiY = tester.getTopLeft(find.text('Argumenty ZA i PRZECIW')).dy;
    final catalogY = tester.getTopLeft(find.text('Cały katalog 500+ pytań')).dy;
    expect(smaczkiY, lessThan(catalogY));
  });

  testWidgets('history source leads with the favorites & history benefit', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      loadPackages: () async => [lifetime, monthly],
      source: PaywallSource.history,
    );

    expect(find.text('Wszystkie Twoje głosy w jednym miejscu'), findsOneWidget);

    final favoritesY = tester
        .getTopLeft(find.text('Ulubione i historia głosów'))
        .dy;
    final catalogY = tester.getTopLeft(find.text('Cały katalog 500+ pytań')).dy;
    expect(favoritesY, lessThan(catalogY));
  });

  testWidgets('hard-wall source shows its headline and default order', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      loadPackages: () async => [lifetime, monthly],
      source: PaywallSource.hardWall,
    );

    expect(find.text('Zobacz, jak zagłosował cały świat'), findsOneWidget);

    final catalogY = tester.getTopLeft(find.text('Cały katalog 500+ pytań')).dy;
    final smaczkiY = tester.getTopLeft(find.text('Argumenty ZA i PRZECIW')).dy;
    expect(catalogY, lessThan(smaczkiY));
  });

  testWidgets('lifetime card carries the months-of-subscription comparison', (
    tester,
  ) async {
    await pumpSheet(tester, loadPackages: () async => [lifetime, monthly]);

    // US store prices: 22.99 / 5.49 -> floor + 1 = 5, so the anchor line is
    // always true.
    expect(find.text('Mniej niż 5 miesięcy subskrypcji'), findsOneWidget);
  });

  testWidgets('Polish store prices render the few-plural comparison', (
    tester,
  ) async {
    // 69,99 / 19,99 zł -> floor + 1 = 4, which hits the Polish `few` plural
    // ("miesiące", not "miesięcy") — the form the base market actually shows.
    final lifetimePln = fakePackage(
      PackageType.lifetime,
      '69,99 zł',
      price: 69.99,
      currencyCode: 'PLN',
    );
    final monthlyPln = fakePackage(
      PackageType.monthly,
      '19,99 zł',
      price: 19.99,
      currencyCode: 'PLN',
    );
    await pumpSheet(
      tester,
      loadPackages: () async => [lifetimePln, monthlyPln],
    );

    expect(find.text('Mniej niż 4 miesiące subskrypcji'), findsOneWidget);
  });

  testWidgets('comparison line is omitted without a monthly plan to compare', (
    tester,
  ) async {
    await pumpSheet(tester, loadPackages: () async => [lifetime]);

    expect(find.textContaining('Mniej niż'), findsNothing);
  });

  testWidgets('comparison line is omitted when currencies differ', (
    tester,
  ) async {
    final monthlyPln = fakePackage(
      PackageType.monthly,
      '19,99 zł',
      price: 19.99,
      currencyCode: 'PLN',
    );
    await pumpSheet(tester, loadPackages: () async => [lifetime, monthlyPln]);

    expect(find.textContaining('Mniej niż'), findsNothing);
  });

  testWidgets('a third plan stacks instead of squeezing into the row', (
    tester,
  ) async {
    // The offering's shape is set in the RevenueCat dashboard, so adding an
    // annual package reshapes this screen with no code change at all — and
    // three cards across a phone start ellipsing their own labels.
    final annual = fakePackage(PackageType.annual, r'$39.99', price: 39.99);
    await pumpSheet(
      tester,
      loadPackages: () async => [lifetime, annual, monthly],
    );

    expect(find.text('Dożywotni'), findsOneWidget);
    expect(find.text('Roczny'), findsOneWidget);
    expect(find.text('Miesięczny'), findsOneWidget);

    // Stacked full-width: one column, increasing tops. (The left edges differ
    // by a fraction of a pixel — the SELECTED card draws a 2px border where
    // the others draw 1.4 — so match the column, not the exact offset.)
    final first = tester.getRect(find.text('Dożywotni'));
    final second = tester.getRect(find.text('Roczny'));
    final third = tester.getRect(find.text('Miesięczny'));
    expect(second.left, closeTo(first.left, 1));
    expect(third.left, closeTo(first.left, 1));
    expect(second.top, greaterThan(first.bottom));
    expect(third.top, greaterThan(second.bottom));
  });

  testWidgets('selecting the monthly plan switches the reassurance note', (
    tester,
  ) async {
    await pumpSheet(tester, loadPackages: () async => [lifetime, monthly]);

    await tester.ensureVisible(find.text('Miesięczny'));
    await tester.tap(find.text('Miesięczny'));
    await tester.pumpAndSettle();

    // The subscription note has to state the auto-renewal, not just the
    // cancel-anytime reassurance — App Store guideline 3.1.2 asks for it on
    // the purchase screen itself.
    expect(
      find.text('Odnawia się automatycznie — anulujesz w każdej chwili'),
      findsOneWidget,
    );
    expect(find.text('Jedna płatność — na zawsze'), findsNothing);
  });

  testWidgets('CTA purchases the selected package and pops with true', (
    tester,
  ) async {
    Package? bought;
    final results = <bool?>[];

    await tester.pumpWidget(
      ProviderScope(
        child: LocalizedTestApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    final result = await showModalBottomSheet<bool>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => ProPaywallSheet(
                        loadPackages: () async => [lifetime, monthly],
                        buy: (p) async {
                          bought = p;
                          return PurchaseOutcome.entitled;
                        },
                      ),
                    );
                    results.add(result);
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Miesięczny'));
    await tester.tap(find.text('Miesięczny'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Odblokuj pełny dostęp'));
    await tester.tap(find.text('Odblokuj pełny dostęp'));
    await tester.pumpAndSettle();

    expect(bought, monthly);
    expect(results, [true]);
    expect(find.text('Odblokuj pełny dostęp'), findsNothing); // sheet closed
  });

  testWidgets(
    'CTA buys the preselected first plan without tapping a card first',
    (tester) async {
      // Regression: _selected used to stay null until a card was tapped, so a
      // straight-to-CTA tap silently did nothing even though the first card
      // rendered as selected.
      Package? bought;
      await pumpSheet(
        tester,
        loadPackages: () async => [lifetime, monthly],
        buy: (p) async {
          bought = p;
          // Keep the sheet open (no pop) — this harness has no enclosing
          // modal route to pop.
          return PurchaseOutcome.cancelled;
        },
      );

      await tester.ensureVisible(find.text('Odblokuj pełny dostęp'));
      await tester.tap(find.text('Odblokuj pełny dostęp'));
      await tester.pumpAndSettle();

      expect(bought, lifetime);
    },
  );

  testWidgets('a cancelled purchase keeps the sheet open', (tester) async {
    await pumpSheet(
      tester,
      loadPackages: () async => [lifetime, monthly],
      buy: (_) async => PurchaseOutcome.cancelled,
    );

    await tester.ensureVisible(find.text('Odblokuj pełny dostęp'));
    await tester.tap(find.text('Odblokuj pełny dostęp'));
    await tester.pumpAndSettle();

    // Still on the paywall, CTA usable again.
    expect(find.text('Odblokuj pełny dostęp'), findsOneWidget);
  });

  testWidgets(
    'an empty package list (unconfigured RevenueCat) shows the error state '
    'without throwing',
    (tester) async {
      await pumpSheet(tester, loadPackages: () async => const []);

      expect(
        find.text(
          'Nie udało się wczytać oferty. Sprawdź połączenie i spróbuj ponownie.',
        ),
        findsOneWidget,
      );
      expect(find.text('Odblokuj pełny dostęp'), findsNothing);
    },
  );

  testWidgets('footer links clear the bottom system inset', (tester) async {
    // Regression: the sheet route uses `useSafeArea: true`, which is
    // `SafeArea(bottom: false)` — so the restore/terms/privacy row ended up
    // under the Android gesture bar, unreadable and untappable.
    const inset = 64.0;
    await tester.pumpWidget(
      ProviderScope(
        child: LocalizedTestApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                viewPadding: const EdgeInsets.only(bottom: inset),
                padding: const EdgeInsets.only(bottom: inset),
              ),
              child: Scaffold(
                body: ProPaywallSheet(
                  loadPackages: () async => [lifetime, monthly],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Scroll the sheet to its very end — the worst case for the footer.
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -2000),
    );
    await tester.pumpAndSettle();

    final sheetBottom = tester.getRect(find.byType(ProPaywallSheet)).bottom;
    final restoreBottom = tester.getBottomLeft(find.text('Przywróć zakup')).dy;
    expect(restoreBottom, lessThanOrEqualTo(sheetBottom - inset));
  });

  testWidgets('a refused purchase says so instead of failing silently', (
    tester,
  ) async {
    // The store refusing (Play unreachable, payment declined) used to be
    // indistinguishable from the user backing out: no message either way, so a
    // failed purchase read as a dead CTA and got tapped again and again.
    await pumpSheet(
      tester,
      loadPackages: () async => [lifetime, monthly],
      buy: (_) async => PurchaseOutcome.failed,
    );

    await tester.ensureVisible(find.text('Odblokuj pełny dostęp'));
    await tester.tap(find.text('Odblokuj pełny dostęp'));
    await tester.pump(); // resolve buy()
    await tester.pump(); // let the toast mount

    expect(
      find.text(
        'Nie udało się połączyć ze sklepem. Sprawdź połączenie i spróbuj ponownie.',
      ),
      findsOneWidget,
    );
    // And the paywall is usable again — the CTA renders its label, not a spinner.
    expect(find.text('Odblokuj pełny dostęp'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a transient store failure is retried before the user sees it', (
    tester,
  ) async {
    // The live incident: Play answers the product lookup with NETWORK_ERROR
    // (code 10) for the first seconds of a session. One shot at initState left
    // a hard-walled user staring at a retry button they had to tap themselves.
    var calls = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: LocalizedTestApp(
          home: Scaffold(
            body: ProPaywallContent(
              source: PaywallSource.hardWall,
              onEntitled: () async {},
              retryBackoff: const [
                Duration(milliseconds: 10),
                Duration(milliseconds: 10),
              ],
              loadPackages: () async {
                calls++;
                if (calls < 3) {
                  throw PlatformException(
                    code: '${PurchasesErrorCode.networkError.index}',
                    message: 'Error performing request.',
                  );
                }
                return [lifetime, monthly];
              },
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();

    expect(calls, 3);
    expect(find.text(r'$22.99'), findsOneWidget);
    expect(find.text('Odblokuj pełny dostęp'), findsOneWidget);
    // The user was never shown the failure at all.
    expect(find.text('Spróbuj ponownie'), findsNothing);
  });

  testWidgets('a store failure that keeps failing lands on the retry state', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: LocalizedTestApp(
          home: Scaffold(
            body: ProPaywallContent(
              source: PaywallSource.hardWall,
              onEntitled: () async {},
              retryBackoff: const [Duration(milliseconds: 10)],
              loadPackages: () async {
                calls++;
                throw PlatformException(
                  code: '${PurchasesErrorCode.networkError.index}',
                  message: 'Error performing request.',
                );
              },
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();

    // Bounded by the backoff schedule: one initial attempt plus one retry.
    expect(calls, 2);
    expect(
      find.text(
        'Nie udało się wczytać oferty. Sprawdź połączenie i spróbuj ponownie.',
      ),
      findsOneWidget,
    );
    expect(find.text('Spróbuj ponownie'), findsOneWidget);
  });

  testWidgets('coming back to the app re-fetches a failed offer', (
    tester,
  ) async {
    // The realistic fix for a store failure is the user leaving to sort their
    // connection out. Returning to the same dead wall — with a "try again" they
    // have to find and tap — is how a hard-walled app loses someone who was
    // actively trying to pay it.
    var calls = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: LocalizedTestApp(
          home: Scaffold(
            body: ProPaywallContent(
              source: PaywallSource.hardWall,
              onEntitled: () async {},
              retryBackoff: const [],
              loadPackages: () async {
                calls++;
                if (calls == 1) {
                  throw PlatformException(
                    code: '${PurchasesErrorCode.networkError.index}',
                    message: 'Error performing request.',
                  );
                }
                return [lifetime, monthly];
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Spróbuj ponownie'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text(r'$22.99'), findsOneWidget);
    expect(find.text('Odblokuj pełny dostęp'), findsOneWidget);
  });

  testWidgets('a configuration failure is not retried at all', (tester) async {
    // Nothing on the device fixes a broken offering — retrying just delays the
    // error state the user has to act on.
    var calls = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: LocalizedTestApp(
          home: Scaffold(
            body: ProPaywallContent(
              source: PaywallSource.hardWall,
              onEntitled: () async {},
              retryBackoff: const [Duration(milliseconds: 10)],
              loadPackages: () async {
                calls++;
                throw PlatformException(
                  code: '${PurchasesErrorCode.configurationError.index}',
                  message: 'There is an issue with your configuration.',
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.text('Spróbuj ponownie'), findsOneWidget);
  });

  testWidgets('offering failure shows a retryable error state', (tester) async {
    var calls = 0;
    await pumpSheet(
      tester,
      loadPackages: () async {
        calls++;
        if (calls == 1) throw StateError('offline');
        return [lifetime, monthly];
      },
    );

    expect(
      find.text(
        'Nie udało się wczytać oferty. Sprawdź połączenie i spróbuj ponownie.',
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Spróbuj ponownie'));
    await tester.tap(find.text('Spróbuj ponownie'));
    await tester.pumpAndSettle();

    expect(find.text(r'$22.99'), findsOneWidget);
    expect(find.text('Odblokuj pełny dostęp'), findsOneWidget);
  });
}
