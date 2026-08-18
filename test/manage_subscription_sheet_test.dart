import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/settings/widgets/manage_subscription_sheet.dart';
import 'package:debatly/services/purchases_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/localized_test_app.dart';

/// The manage-subscription sheet cannot cancel anything (neither store allows
/// it) — its whole job is saying the right thing and deep-linking to the right
/// place PER STORE. Four parallel switches decide that wording; these tests pin
/// each store's variant and the renewal/cancellation status lines.
void main() {
  Future<void> pumpSheet(
    WidgetTester tester, {
    required PremiumStatus? status,
  }) async {
    final container = ProviderContainer(
      overrides: [premiumStatusProvider.overrideWith((ref) async => status)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const LocalizedTestApp(
          home: Scaffold(body: ManageSubscriptionSheet(localeCode: 'pl')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  PremiumStatus status({
    PremiumStore store = PremiumStore.playStore,
    bool willRenew = true,
    DateTime? expiry,
    String? managementUrl,
  }) => PremiumStatus(
    isActive: true,
    willRenew: willRenew,
    store: store,
    expirationDate: expiry,
    managementUrl: managementUrl,
  );

  testWidgets('Play Store: billed line, note, button all say Google Play', (
    tester,
  ) async {
    await pumpSheet(tester, status: status(expiry: DateTime(2026, 9, 15)));

    expect(find.text('Premium aktywne'), findsOneWidget);
    expect(find.textContaining('Odnowi się'), findsOneWidget);
    expect(find.text('Rozliczane przez Google Play'), findsOneWidget);
    expect(find.textContaining('subskrypcją zarządza Google'), findsOneWidget);
    expect(find.text('ZARZĄDZAJ W GOOGLE PLAY'), findsOneWidget);
  });

  testWidgets('App Store: the Apple wording throughout', (tester) async {
    await pumpSheet(tester, status: status(store: PremiumStore.appStore));

    expect(find.text('Rozliczane przez App Store'), findsOneWidget);
    expect(find.textContaining('subskrypcją zarządza Apple'), findsOneWidget);
    expect(find.text('ZARZĄDZAJ W APP STORE'), findsOneWidget);
  });

  testWidgets('web billing gets the generic wording', (tester) async {
    await pumpSheet(tester, status: status(store: PremiumStore.web));

    expect(find.text('Rozliczane online'), findsOneWidget);
    // The generic button label equals the sheet title, so two occurrences.
    expect(find.text('ZARZĄDZAJ SUBSKRYPCJĄ'), findsNWidgets(2));
  });

  testWidgets('promotional/other billing shares the generic wording', (
    tester,
  ) async {
    await pumpSheet(tester, status: status(store: PremiumStore.other));

    expect(find.text('Rozliczane online'), findsOneWidget);
    expect(find.text('ZARZĄDZAJ SUBSKRYPCJĄ'), findsNWidgets(2));
  });

  testWidgets(
    'a cancelled subscription reads "won\'t renew" with the end date',
    (tester) async {
      await pumpSheet(
        tester,
        status: status(willRenew: false, expiry: DateTime(2026, 9, 15)),
      );

      expect(find.text('Anulowano — nie odnowi się'), findsOneWidget);
      expect(find.textContaining('Aktywne do'), findsOneWidget);
      expect(find.textContaining('Odnowi się'), findsNothing);
    },
  );

  testWidgets(
    'a lifetime purchase reads as lifetime access, not a cancellation',
    (tester) async {
      // RevenueCat's shape for a non-consumable buy (and for a permanent promo
      // grant): active, never renews, no expiry. Read as a cancellation, it
      // told every buyer of the plan the paywall PRESELECTS and pitches as
      // "one payment — forever" that their purchase was "Anulowano".
      await pumpSheet(tester, status: status(willRenew: false));

      expect(find.text('Dostęp dożywotni'), findsOneWidget);
      expect(find.text('Anulowano — nie odnowi się'), findsNothing);
      // There is no subscription to manage, so the store deep link — which
      // RevenueCat gives no URL for here anyway — goes away with it.
      expect(find.text('ZARZĄDZAJ W GOOGLE PLAY'), findsNothing);
      expect(find.textContaining('subskrypcją zarządza Google'), findsNothing);
      expect(find.textContaining('jednorazowy zakup'), findsOneWidget);
      // ...which leaves the close action as the sheet's only button, so it
      // stops reading as "Later, I'll deal with this".
      expect(find.text('ZAMKNIJ'), findsOneWidget);
      expect(find.text('PÓŹNIEJ'), findsNothing);
    },
  );

  testWidgets(
    'a management link that cannot open shows the per-store fallback, '
    'and the sheet stays put',
    (tester) async {
      // No managementUrl (e.g. a promotional grant billed via Play) — the
      // deep link cannot open, so the tap must surface instructions instead
      // of silently doing nothing or closing the sheet.
      await pumpSheet(tester, status: status(managementUrl: null));

      await tester.tap(find.text('ZARZĄDZAJ W GOOGLE PLAY'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Nie udało się otworzyć Google Play'),
        findsOneWidget,
      );
      expect(find.text('ZARZĄDZAJ W GOOGLE PLAY'), findsOneWidget);
    },
  );
}
