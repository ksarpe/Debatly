import 'package:debatly/core/locale/app_locale.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/monetization/widgets/pro_paywall_sheet.dart';
import 'package:flutter/material.dart' show AlertDialog;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show Package;

import 'support/fakes.dart';
import 'support/localized_test_app.dart';
import 'support/test_prefs.dart';

/// The "Przywróć zakup" affordance on the paywall sheet — the freemium
/// model's one paywall surface, so the restore path must live right on it.
/// For a guest the tap first opens a chooser (confirmGuestRestore): a store
/// restore would TRANSFER the receipt onto this fresh anonymous identity, so
/// someone who bought PRO on a real account is steered to sign back in instead
/// — while "restore on this device" keeps the store path available (Apple
/// requires it). RevenueCat is unconfigured in tests, so restorePurchases()
/// reports "no purchase found" without any network call.
void main() {
  Future<void> pumpGuestPaywall(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await mockSharedPreferences(),
        ),
        sessionProvider.overrideWith(() => FakeSession(guestSession())),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LocalizedTestApp(
          home: ProPaywallSheet(loadPackages: () async => const <Package>[]),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a guest sees the restore affordance on the paywall sheet', (
    tester,
  ) async {
    await pumpGuestPaywall(tester);

    // Sanity: we're on the sheet (the streak-0 headline is the anchor) ...
    expect(find.text('Zostało 500 pytań'), findsOneWidget);
    // ... and the store-restore path is offered right there (below the fold
    // on a short test viewport — scrolling to it is fine, hiding it is not).
    expect(find.text('Przywróć zakup'), findsOneWidget);
    // A guest also gets the sign-in path, right next to restore in the
    // sticky bar's links row.
    expect(find.text('Zaloguj się'), findsOneWidget);
  });

  testWidgets('a guest tapping restore gets the sign-in-or-restore chooser', (
    tester,
  ) async {
    await pumpGuestPaywall(tester);

    await tester.ensureVisible(find.text('Przywróć zakup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Przywróć zakup'));
    await tester.pumpAndSettle();

    // The chooser is up, offering both paths; nothing has run yet. (The
    // sticky bar carries its own "Zaloguj się" link, so scope to the dialog.)
    expect(find.text('Przywrócić zakup?'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Zaloguj się'),
      ),
      findsOneWidget,
    );
    expect(find.text('Przywróć na tym urządzeniu'), findsOneWidget);
  });

  testWidgets('choosing "restore on this device" runs the store flow', (
    tester,
  ) async {
    await pumpGuestPaywall(tester);

    await tester.ensureVisible(find.text('Przywróć zakup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Przywróć zakup'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Przywróć na tym urządzeniu'));
    await tester.pump(); // pop the dialog + start the async restore
    await tester.pump(); // resolve restorePurchases() (false, unconfigured)
    await tester.pump(const Duration(milliseconds: 750)); // animate the toast

    // Store path ran and reported no purchase — no auth sheet was opened
    // (the sheet's social button is its telltale; tests report as Android).
    expect(find.text('Nie znaleziono wcześniejszego zakupu.'), findsOneWidget);
    expect(
      find.text('Kontynuuj z Google'),
      findsNothing,
      reason: 'the explicit store path must not become a login',
    );
  });

  testWidgets('choosing "sign in" opens the auth sheet, not the store flow', (
    tester,
  ) async {
    await pumpGuestPaywall(tester);

    await tester.ensureVisible(find.text('Przywróć zakup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Przywróć zakup'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Zaloguj się'),
      ),
    );
    await tester.pumpAndSettle();

    // The auth sheet is up (its social button is the telltale) and the store
    // flow never ran.
    expect(find.text('Kontynuuj z Google'), findsOneWidget);
    expect(
      find.text('Nie znaleziono wcześniejszego zakupu.'),
      findsNothing,
      reason: 'no store restore may run when the user chose to sign in',
    );
  });
}
