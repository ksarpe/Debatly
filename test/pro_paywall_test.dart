import 'package:debatly/features/monetization/widgets/pro_paywall_sheet.dart';
import 'package:flutter/material.dart';
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
    Future<bool> Function(Package)? buy,
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

  // Prices render as Text.rich (big price + small "/mies." suffix), which
  // plain find.text skips.
  Finder findPrice(String text) => find.text(text, findRichText: true);

  /// Reading order of a perk tile in the grid: rows first, then columns.
  Offset perkAt(WidgetTester tester, String label) =>
      tester.getTopLeft(find.text(label));

  void expectPerkBefore(WidgetTester tester, String first, String second) {
    final a = perkAt(tester, first);
    final b = perkAt(tester, second);
    expect(
      a.dy < b.dy || (a.dy == b.dy && a.dx < b.dx),
      isTrue,
      reason: '"$first" ($a) should come before "$second" ($b)',
    );
  }

  testWidgets('renders perks, live prices and preselects the first plan', (
    tester,
  ) async {
    await pumpSheet(tester, loadPackages: () async => [lifetime, monthly]);

    // Headline + subtitle + the six perk tiles.
    expect(
      find.text('Zyskaj dostęp do wszystkich pytań i głosów'),
      findsOneWidget,
    );
    expect(
      find.text('Cały katalog, wszystkie smaczki, zero reklam'),
      findsOneWidget,
    );
    expect(find.text('Bez limitu'), findsOneWidget);
    expect(find.text('Zero reklam'), findsOneWidget);
    expect(find.text('Wszystkie smaczki'), findsOneWidget);
    expect(find.text('Ulubione'), findsOneWidget);
    expect(find.text('Historia głosów'), findsOneWidget);
    expect(find.text('Tryb offline'), findsOneWidget);

    // Both plans with their store-formatted prices; monthly gets the suffix.
    expect(find.text('Dożywotni'), findsOneWidget);
    expect(findPrice(r'$22.99'), findsOneWidget);
    expect(find.text('Miesięczny'), findsOneWidget);
    expect(findPrice(r'$5.49/mies.'), findsOneWidget);
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

    // The smaczki perk takes the first tile, ahead of the default lead.
    expectPerkBefore(tester, 'Wszystkie smaczki', 'Bez limitu');
  });

  testWidgets('history source leads with the vote-history perk', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      loadPackages: () async => [lifetime, monthly],
      source: PaywallSource.history,
    );

    expect(find.text('Wszystkie Twoje głosy w jednym miejscu'), findsOneWidget);

    expectPerkBefore(tester, 'Historia głosów', 'Bez limitu');
  });

  testWidgets('reading-limit source keeps the default perk order', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      loadPackages: () async => [lifetime, monthly],
      source: PaywallSource.readingLimit,
    );

    expect(find.text('Czytaj dalej — bez limitów i czekania'), findsOneWidget);

    expectPerkBefore(tester, 'Bez limitu', 'Zero reklam');
  });

  testWidgets('the perk grid survives a narrow phone width', (tester) async {
    // Three tiles per row on a 360pt screen is the tightest the grid ever
    // gets; a fixed-width tile or a too-wide circle would overflow the Row
    // (which fails the test on its own).
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);

    await pumpSheet(tester, loadPackages: () async => [lifetime, monthly]);

    expect(find.text('Bez limitu'), findsOneWidget);
    expect(find.text('Tryb offline'), findsOneWidget);
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

  testWidgets('selecting the monthly plan switches the reassurance note', (
    tester,
  ) async {
    await pumpSheet(tester, loadPackages: () async => [lifetime, monthly]);

    await tester.ensureVisible(find.text('Miesięczny'));
    await tester.tap(find.text('Miesięczny'));
    await tester.pumpAndSettle();

    expect(
      find.text('Bez zobowiązań — anulujesz w każdej chwili'),
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
                          return true;
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
          return false;
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
      buy: (_) async => false,
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

    expect(findPrice(r'$22.99'), findsOneWidget);
    expect(find.text('Odblokuj pełny dostęp'), findsOneWidget);
  });
}
