import 'package:debatly/core/locale/app_locale.dart';
import 'package:debatly/features/monetization/widgets/pro_paywall_screen.dart';
import 'package:debatly/features/onboarding/widgets/onboarding_bridge_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/localized_test_app.dart';
import 'support/test_prefs.dart';

/// The bridge card that replaced the hard paywall after onboarding: it
/// explains the freemium model and hands the user FORWARD. The free path is
/// the primary CTA; the paywall sheet opens only on the secondary tap and is
/// always dismissible back to the bridge — never a trap, never forced.
void main() {
  Future<void> pumpBridge(
    WidgetTester tester, {
    required VoidCallback onContinue,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await mockSharedPreferences(),
          ),
        ],
        child: LocalizedTestApp(
          home: Scaffold(body: OnboardingBridgeCard(onContinue: onContinue)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the model explainer with the free path as the '
      'dominant CTA', (tester) async {
    await pumpBridge(tester, onContinue: () {});

    // The DISPLAY headline and the ACTION buttons render uppercased in the
    // widgets, so the finders match the on-screen casing.
    expect(find.text('TO BYŁY DWA — A ZOSTAŁY JESZCZE SETKI'), findsOneWidget);
    expect(find.text('(i wiele innych korzyści)'), findsOneWidget);
    expect(
      find.textContaining('Codziennie dostajesz jedno nowe pytanie'),
      findsOneWidget,
    );
    expect(find.text('ODBIERZ DZISIEJSZE PYTANIE'), findsOneWidget);
    expect(find.text('ODBLOKUJ WSZYSTKIE'), findsOneWidget);
  });

  testWidgets('the free path carries the visual weight, the paywall the quiet '
      'outline', (tester) async {
    await pumpBridge(tester, onContinue: () {});

    final free = find.text('ODBIERZ DZISIEJSZE PYTANIE');
    final paywall = find.text('ODBLOKUJ WSZYSTKIE');

    // The outlined treatment belongs to the paywall, not the free path. These
    // two were swapped once — with the analytics event names left behind on the
    // strings, so `bridge_cta_primary` was being logged by the quiet button and
    // every funnel built on the pair read backwards.
    expect(
      find.ancestor(of: paywall, matching: find.byType(OutlinedButton)),
      findsOneWidget,
    );
    expect(
      find.ancestor(of: free, matching: find.byType(OutlinedButton)),
      findsNothing,
    );
    // And it is the one on top.
    expect(tester.getCenter(free).dy, lessThan(tester.getCenter(paywall).dy));
  });

  testWidgets('the primary CTA continues for free — no paywall anywhere', (
    tester,
  ) async {
    var continued = false;
    await pumpBridge(tester, onContinue: () => continued = true);

    await tester.tap(find.text('ODBIERZ DZISIEJSZE PYTANIE'));
    await tester.pumpAndSettle();

    expect(continued, isTrue);
    expect(find.byType(ProPaywallScreen), findsNothing);
  });

  testWidgets('the secondary CTA opens the sheet; dismissing it lands back '
      'on the bridge without continuing', (tester) async {
    var continued = false;
    await pumpBridge(tester, onContinue: () => continued = true);

    await tester.tap(find.text('ODBLOKUJ WSZYSTKIE'));
    await tester.pumpAndSettle();
    expect(find.byType(ProPaywallScreen), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(ProPaywallScreen), findsNothing);
    expect(continued, isFalse);
    // Both paths are still on offer.
    expect(find.text('ODBIERZ DZISIEJSZE PYTANIE'), findsOneWidget);
    expect(find.text('ODBLOKUJ WSZYSTKIE'), findsOneWidget);
  });
}
