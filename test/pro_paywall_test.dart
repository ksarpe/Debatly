import 'package:debatly/data/models/user_stats.dart';
import 'package:debatly/features/account/providers/stats_providers.dart';
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
    int streak = 0,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // The streak the headline map personalises on.
          userStatsProvider.overrideWith(
            (ref) async => UserStats(
              currentStreak: streak,
              longestStreak: streak,
              rankTier: 0,
              rankName: 'Tester',
              nextRankStreak: 3,
            ),
          ),
        ],
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

  testWidgets('renders the benefit list in spec order, the Free/PRO table, '
      'live prices — no badge, nothing preselected', (tester) async {
    await pumpSheet(tester, loadPackages: () async => [lifetime, monthly]);

    // Streak 0 → the default headline, with the freemium subtitle under it.
    expect(find.text('Zostało 500 pytań'), findsOneWidget);
    expect(
      find.text(
        'Jedno pytanie dziennie zostaje darmowe. PRO zdejmuje limit i '
        'otwiera wszystkie argumenty.',
      ),
      findsOneWidget,
    );

    // The six benefits, arguments second — the one differentiator no
    // competitor has, so it must sit above the fold.
    expect(find.text('Bez limitu dziennego'), findsOneWidget);
    expect(find.text('Wszystkie argumenty ZA i PRZECIW'), findsOneWidget);
    expect(find.text('Zero reklam'), findsOneWidget);
    expect(find.text('Historia Twoich głosów'), findsOneWidget);
    expect(find.text('Nowe pytania co tydzień'), findsOneWidget);
    // Benefit row + comparison-table row share the label.
    expect(find.text('Tryb offline'), findsNWidgets(2));

    // The Free/PRO comparison table — the daily-limit row is the pitch.
    expect(find.text('Limit dzienny'), findsOneWidget);
    expect(find.text('1 pytanie'), findsOneWidget);
    expect(find.text('Bez limitu'), findsOneWidget);
    expect(find.text('Wynik społeczności'), findsOneWidget);
    expect(find.text('Seria i rangi'), findsOneWidget);

    // Both plans with their store-formatted prices; monthly gets the suffix.
    expect(find.text('Dożywotni'), findsOneWidget);
    expect(find.text(r'$22.99'), findsOneWidget);
    expect(find.text('Miesięczny'), findsOneWidget);
    expect(find.text(r'$5.49/mies.'), findsOneWidget);

    // No steering: no badge, and no plan preselected (no selected-card check
    // icon anywhere until the user taps one).
    expect(find.text('NAJLEPSZA OFERTA'), findsNothing);
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    expect(find.text('Odblokuj pełny dostęp'), findsOneWidget);
  });

  testWidgets('the streak escalates the headline: 3–6 days is personal', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      loadPackages: () async => [lifetime, monthly],
      source: PaywallSource.wall,
      streak: 4,
    );

    expect(
      find.text('Masz 4-dniową serię. Nie przerywaj jej.'),
      findsOneWidget,
    );
    expect(find.text('Zostało 500 pytań'), findsNothing);
  });

  testWidgets('…and 7+ days gets the earned-it headline', (tester) async {
    await pumpSheet(
      tester,
      loadPackages: () async => [lifetime, monthly],
      source: PaywallSource.wall,
      streak: 8,
    );

    expect(
      find.text('8 dni z rzędu. Należy Ci się cały katalog.'),
      findsOneWidget,
    );
  });

  testWidgets('smaczki source keeps its contextual headline', (tester) async {
    await pumpSheet(
      tester,
      loadPackages: () async => [lifetime, monthly],
      source: PaywallSource.smaczki,
    );

    expect(
      find.text('Poznaj wszystkie argumenty do każdego pytania'),
      findsOneWidget,
    );
    expect(find.text('Zostało 500 pytań'), findsNothing);

    // The list order is fixed regardless of source: catalog first, then the
    // arguments row.
    final catalogY = tester.getTopLeft(find.text('Bez limitu dziennego')).dy;
    final smaczkiY = tester
        .getTopLeft(find.text('Wszystkie argumenty ZA i PRZECIW'))
        .dy;
    expect(catalogY, lessThan(smaczkiY));
  });

  testWidgets('history source keeps its contextual headline', (tester) async {
    await pumpSheet(
      tester,
      loadPackages: () async => [lifetime, monthly],
      source: PaywallSource.history,
    );

    expect(find.text('Wszystkie Twoje głosy w jednym miejscu'), findsOneWidget);
    expect(find.text('Historia Twoich głosów'), findsOneWidget);
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

  testWidgets('the weekly entry plan renders and three plans stack '
      'instead of squeezing into the row', (tester) async {
    // The offering's shape is set in the RevenueCat dashboard: adding the
    // 9,99 zł weekly reshapes this screen with no code change at all — and
    // three cards across a phone would start ellipsing their own labels.
    final weekly = fakePackage(PackageType.weekly, '9,99 zł', price: 9.99);
    await pumpSheet(
      tester,
      loadPackages: () async => [lifetime, monthly, weekly],
    );

    expect(find.text('Dożywotni'), findsOneWidget);
    expect(find.text('Miesięczny'), findsOneWidget);
    expect(find.text('Tygodniowy'), findsOneWidget);
    expect(find.text('9,99 zł'), findsOneWidget);

    // Stacked full-width: one column, increasing tops. (The left edges differ
    // by a fraction of a pixel — a SELECTED card draws a 2px border where
    // the others draw 1.4 — so match the column, not the exact offset.)
    final first = tester.getRect(find.text('Dożywotni'));
    final second = tester.getRect(find.text('Miesięczny'));
    final third = tester.getRect(find.text('Tygodniowy'));
    expect(second.left, closeTo(first.left, 1));
    expect(third.left, closeTo(first.left, 1));
    expect(second.top, greaterThan(first.bottom));
    expect(third.top, greaterThan(second.bottom));
  });

  testWidgets('the reassurance note follows the selected plan', (tester) async {
    await pumpSheet(tester, loadPackages: () async => [lifetime, monthly]);

    // Nothing selected yet → the generic auto-renewal note (App Store
    // guideline 3.1.2 wants renewal terms on the purchase screen itself).
    expect(
      find.text('Odnawia się automatycznie — anulujesz w każdej chwili'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Dożywotni'));
    await tester.tap(find.text('Dożywotni'));
    await tester.pumpAndSettle();

    expect(find.text('Jedna płatność — na zawsze'), findsOneWidget);
    expect(
      find.text('Odnawia się automatycznie — anulujesz w każdej chwili'),
      findsNothing,
    );
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
    'with nothing preselected the CTA stays disabled until a plan is tapped',
    (tester) async {
      // The deliberate inverse of the old behaviour: no plan is preselected,
      // so a straight-to-CTA tap buys NOTHING — the pick has to be the
      // user's own.
      Package? bought;
      await pumpSheet(
        tester,
        loadPackages: () async => [lifetime, monthly],
        buy: (p) async {
          bought = p;
          return PurchaseOutcome.cancelled;
        },
      );

      await tester.ensureVisible(find.text('Odblokuj pełny dostęp'));
      await tester.tap(find.text('Odblokuj pełny dostęp'));
      await tester.pumpAndSettle();
      expect(bought, isNull);

      // Tapping a plan arms it.
      await tester.ensureVisible(find.text('Miesięczny'));
      await tester.tap(find.text('Miesięczny'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Odblokuj pełny dostęp'));
      await tester.tap(find.text('Odblokuj pełny dostęp'));
      await tester.pumpAndSettle();
      expect(bought, monthly);
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

    // Arm a plan first — nothing is preselected anymore.
    await tester.ensureVisible(find.text('Dożywotni'));
    await tester.tap(find.text('Dożywotni'));
    await tester.pumpAndSettle();

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
              source: PaywallSource.wall,
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
              source: PaywallSource.wall,
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
              source: PaywallSource.wall,
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
              source: PaywallSource.wall,
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
