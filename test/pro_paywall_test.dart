import 'package:debatly/data/models/user_stats.dart';
import 'package:debatly/features/account/providers/stats_providers.dart';
import 'package:debatly/features/monetization/widgets/paywall_content.dart';
import 'package:debatly/features/monetization/widgets/pro_paywall_screen.dart';
import 'package:debatly/services/purchases_service.dart' show PurchaseOutcome;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'support/localized_test_app.dart';

/// The in-app fullscreen PRO paywall. Packages come from the current
/// RevenueCat offering in production; here they're injected via
/// [ProPaywallScreen.loadPackages] (RevenueCat can't be configured in tests),
/// which is exactly the seam the screen exposes for this purpose. Copy is
/// asserted against the Polish locale pinned by [LocalizedTestApp].
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
          // The streak feeds the paywall_shown analytics event.
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
            body: ProPaywallScreen(
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

  testWidgets('renders the brand label, feature list in spec order and '
      'live prices — monthly preselected, no badge', (tester) async {
    await pumpSheet(tester, loadPackages: () async => [lifetime, monthly]);

    // The brand label anchors the top-left of the sheet.
    expect(find.text('DEBATLY PRO'), findsOneWidget);

    // Streak 0 → the default slogan headline, with the catalog pitch under it.
    expect(find.text('BEZ LIMITU.\nBEZ KOŃCA.\nGLOBALNIE.'), findsOneWidget);
    expect(
      find.text(
        '500+ pytań, wszystkie argumenty ZA i PRZECIW, cała Twoja '
        'historia głosów.',
      ),
      findsOneWidget,
    );

    // The four feature rows, arguments second — the one differentiator no
    // competitor has, so it must sit right under the daily-limit row.
    expect(find.text('Pytania bez limitu dziennego'), findsOneWidget);
    expect(find.text('Wszystkie argumenty, nie pierwszy'), findsOneWidget);
    expect(find.text('Historia i ulubione na zawsze'), findsOneWidget);
    // Offline, not "zero ads": the free tier has no ads either, so selling
    // their absence was selling something the user already had.
    expect(
      find.text('Tryb offline — cały katalog w telefonie'),
      findsOneWidget,
    );
    expect(find.textContaining('Zero reklam'), findsNothing);

    // Both plans with their store-formatted prices; every card renders its
    // label uppercase over the same big price, monthly gets the price suffix
    // plus the weekly-equivalent subline.
    expect(find.text('DOŻYWOTNI'), findsOneWidget);
    expect(find.text(r'$22.99'), findsOneWidget);
    expect(find.text('MIESIĘCZNIE'), findsOneWidget);
    expect(find.text(r'$5.49/MIES.'), findsOneWidget);
    expect(find.textContaining('tygodniowo'), findsOneWidget);

    // The monthly plan is preselected (exactly one filled radio) so the CTA
    // is armed on open; still no "best value" badge steering the pick.
    expect(find.text('NAJLEPSZA OFERTA'), findsNothing);
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    expect(find.text('ODBLOKUJ PEŁNY DOSTĘP'), findsOneWidget);
  });

  testWidgets('every entry point and streak shows the same slogan copy', (
    tester,
  ) async {
    // The pitch is deliberately identical everywhere: no streak escalation
    // and no per-feature headline — the source enum only feeds analytics.
    await pumpSheet(
      tester,
      loadPackages: () async => [lifetime, monthly],
      source: PaywallSource.smaczki,
      streak: 8,
    );

    expect(find.text('BEZ LIMITU.\nBEZ KOŃCA.\nGLOBALNIE.'), findsOneWidget);
    expect(
      find.text(
        '500+ pytań, wszystkie argumenty ZA i PRZECIW, cała Twoja '
        'historia głosów.',
      ),
      findsOneWidget,
    );

    // The feature list order is fixed regardless of source: catalog first,
    // then the arguments row.
    final catalogY = tester
        .getTopLeft(find.text('Pytania bez limitu dziennego'))
        .dy;
    final smaczkiY = tester
        .getTopLeft(find.text('Wszystkie argumenty, nie pierwszy'))
        .dy;
    expect(catalogY, lessThan(smaczkiY));
  });

  testWidgets('lifetime card carries the months-of-subscription comparison', (
    tester,
  ) async {
    await pumpSheet(tester, loadPackages: () async => [lifetime, monthly]);

    // US store prices: 22.99 / 5.49 -> floor + 1 = 5, so the anchor line is
    // always true.
    expect(find.text('Jednorazowo. Taniej niż 5 miesięcy.'), findsOneWidget);
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

    expect(find.text('Jednorazowo. Taniej niż 4 miesiące.'), findsOneWidget);

    // The monthly card carries the weekly-equivalent anchor: 19,99 zł × 12
    // / 52, formatted by the same intl call the widget uses (the pl locale
    // separates the amount from "zł" with a non-breaking space).
    final weekly = NumberFormat.simpleCurrency(
      locale: 'pl',
      name: 'PLN',
    ).format(19.99 * 12 / 52);
    expect(find.text('To ok. $weekly tygodniowo'), findsOneWidget);
  });

  testWidgets('comparison line is omitted without a monthly plan to compare', (
    tester,
  ) async {
    await pumpSheet(tester, loadPackages: () async => [lifetime]);

    expect(find.textContaining('Taniej niż'), findsNothing);

    // And with no monthly package there is nothing to preselect: no filled
    // radio, CTA visible but disarmed until the user taps a plan.
    expect(find.byIcon(Icons.radio_button_checked), findsNothing);
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

    expect(find.textContaining('Taniej niż'), findsNothing);
  });

  testWidgets('a third plan slots into the stack, lifetime still on top', (
    tester,
  ) async {
    // The offering's shape is set in the RevenueCat dashboard, so adding a
    // package there reshapes this screen with no code change at all. The
    // lifetime card leads regardless of the offering's own order.
    final annual = fakePackage(PackageType.annual, r'$39.99', price: 39.99);
    await pumpSheet(
      tester,
      loadPackages: () async => [annual, monthly, lifetime],
    );

    expect(find.text('DOŻYWOTNI'), findsOneWidget);
    expect(find.text('ROCZNY'), findsOneWidget);
    expect(find.text('MIESIĘCZNIE'), findsOneWidget);

    // Stacked full-width: one column, increasing tops. (The left edges differ
    // by a fraction of a pixel — a SELECTED card draws a 2px border where
    // the others draw 1.4 — so match the column, not the exact offset.)
    final first = tester.getRect(find.text('DOŻYWOTNI'));
    final second = tester.getRect(find.text('ROCZNY'));
    final third = tester.getRect(find.text('MIESIĘCZNIE'));
    expect(second.left, closeTo(first.left, 1));
    expect(third.left, closeTo(first.left, 1));
    expect(second.top, greaterThan(first.bottom));
    expect(third.top, greaterThan(second.bottom));
  });

  testWidgets('the reassurance note follows the selected plan', (tester) async {
    await pumpSheet(tester, loadPackages: () async => [lifetime, monthly]);

    // Monthly preselected → the auto-renewal note (App Store guideline 3.1.2
    // wants renewal terms on the purchase screen itself).
    expect(
      find.text('Odnawia się automatycznie — anulujesz w każdej chwili'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('DOŻYWOTNI'));
    await tester.tap(find.text('DOŻYWOTNI'));
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
                      builder: (_) => ProPaywallScreen(
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
    await tester.ensureVisible(find.text('MIESIĘCZNIE'));
    await tester.tap(find.text('MIESIĘCZNIE'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('ODBLOKUJ PEŁNY DOSTĘP'));
    await tester.tap(find.text('ODBLOKUJ PEŁNY DOSTĘP'));
    await tester.pumpAndSettle();

    expect(bought, monthly);
    expect(results, [true]);
    expect(find.text('ODBLOKUJ PEŁNY DOSTĘP'), findsNothing); // sheet closed
  });

  testWidgets(
    'the monthly plan is preselected — a straight CTA tap buys monthly',
    (tester) async {
      // The CTA is armed the moment the offer loads: a user who never touches
      // the plan stack buys the preselected monthly plan.
      Package? bought;
      await pumpSheet(
        tester,
        loadPackages: () async => [lifetime, monthly],
        buy: (p) async {
          bought = p;
          return PurchaseOutcome.cancelled;
        },
      );

      await tester.ensureVisible(find.text('ODBLOKUJ PEŁNY DOSTĘP'));
      await tester.tap(find.text('ODBLOKUJ PEŁNY DOSTĘP'));
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

    await tester.ensureVisible(find.text('ODBLOKUJ PEŁNY DOSTĘP'));
    await tester.tap(find.text('ODBLOKUJ PEŁNY DOSTĘP'));
    await tester.pumpAndSettle();

    // Still on the paywall, CTA usable again.
    expect(find.text('ODBLOKUJ PEŁNY DOSTĘP'), findsOneWidget);
  });

  // The two ways the plans can be missing are NOT the same problem, and used to
  // share one screen. An offering that resolves empty is a store-configuration
  // state — telling that user to check their connection is wrong, and the retry
  // provably cannot help, because the same call returns the same nothing. It is
  // also the state an App Review build lands in before its IAPs are approved,
  // where "network error" reads as a broken app.
  testWidgets(
    'an empty offering says the plans are unavailable, with no dead retry',
    (tester) async {
      await pumpSheet(tester, loadPackages: () async => const []);

      expect(
        find.textContaining('Plany są chwilowo niedostępne'),
        findsOneWidget,
      );
      // Not the connection copy, and no button that could not work.
      expect(find.textContaining('Sprawdź połączenie'), findsNothing);
      expect(find.text('SPRÓBUJ PONOWNIE'), findsNothing);
      expect(find.text('ODBLOKUJ PEŁNY DOSTĘP'), findsNothing);
      // The escape hatch for someone who already paid has to survive: it is the
      // only thing that gets their PRO back while the plans are missing.
      expect(find.text('Przywróć zakup'), findsOneWidget);
    },
  );

  testWidgets('a failed fetch keeps the connection copy and the retry', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      loadPackages: () async => throw Exception('store unreachable'),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Sprawdź połączenie'), findsOneWidget);
    expect(find.text('SPRÓBUJ PONOWNIE'), findsOneWidget);
    expect(find.text('ODBLOKUJ PEŁNY DOSTĘP'), findsNothing);
  });

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
                body: ProPaywallScreen(
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

    final sheetBottom = tester.getRect(find.byType(ProPaywallScreen)).bottom;
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

    // Switch to the lifetime plan (monthly comes preselected) — the failure
    // path should not depend on the default pick.
    await tester.ensureVisible(find.text('DOŻYWOTNI'));
    await tester.tap(find.text('DOŻYWOTNI'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('ODBLOKUJ PEŁNY DOSTĘP'));
    await tester.tap(find.text('ODBLOKUJ PEŁNY DOSTĘP'));
    await tester.pump(); // resolve buy()
    await tester.pump(); // let the toast mount

    expect(
      find.text(
        'Nie udało się połączyć ze sklepem. Sprawdź połączenie i spróbuj ponownie.',
      ),
      findsOneWidget,
    );
    // And the paywall is usable again — the CTA renders its label, not a spinner.
    expect(find.text('ODBLOKUJ PEŁNY DOSTĘP'), findsOneWidget);
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
    expect(find.text('ODBLOKUJ PEŁNY DOSTĘP'), findsOneWidget);
    // The user was never shown the failure at all.
    expect(find.text('SPRÓBUJ PONOWNIE'), findsNothing);
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
    expect(find.text('SPRÓBUJ PONOWNIE'), findsOneWidget);
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
    expect(find.text('SPRÓBUJ PONOWNIE'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text(r'$22.99'), findsOneWidget);
    expect(find.text('ODBLOKUJ PEŁNY DOSTĘP'), findsOneWidget);
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
    expect(find.text('SPRÓBUJ PONOWNIE'), findsOneWidget);
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

    await tester.ensureVisible(find.text('SPRÓBUJ PONOWNIE'));
    await tester.tap(find.text('SPRÓBUJ PONOWNIE'));
    await tester.pumpAndSettle();

    expect(find.text(r'$22.99'), findsOneWidget);
    expect(find.text('ODBLOKUJ PEŁNY DOSTĘP'), findsOneWidget);
  });
}
