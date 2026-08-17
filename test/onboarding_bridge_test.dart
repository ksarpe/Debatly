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

    expect(find.text('To były dwa. Zostało 500.'), findsOneWidget);
    expect(
      find.textContaining('Codziennie dostajesz jedno nowe pytanie'),
      findsOneWidget,
    );
    expect(find.text('Odbierz dzisiejsze pytanie'), findsOneWidget);
    expect(find.text('Odblokuj wszystkie 500'), findsOneWidget);
  });

  testWidgets('the primary CTA continues for free — no paywall anywhere', (
    tester,
  ) async {
    var continued = false;
    await pumpBridge(tester, onContinue: () => continued = true);

    await tester.tap(find.text('Odbierz dzisiejsze pytanie'));
    await tester.pumpAndSettle();

    expect(continued, isTrue);
    expect(find.byType(ProPaywallScreen), findsNothing);
  });

  testWidgets('the secondary CTA opens the sheet; dismissing it lands back '
      'on the bridge without continuing', (tester) async {
    var continued = false;
    await pumpBridge(tester, onContinue: () => continued = true);

    await tester.tap(find.text('Odblokuj wszystkie 500'));
    await tester.pumpAndSettle();
    expect(find.byType(ProPaywallScreen), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(ProPaywallScreen), findsNothing);
    expect(continued, isFalse);
    // Both paths are still on offer.
    expect(find.text('Odbierz dzisiejsze pytanie'), findsOneWidget);
    expect(find.text('Odblokuj wszystkie 500'), findsOneWidget);
  });
}
