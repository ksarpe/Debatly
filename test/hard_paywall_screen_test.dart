import 'package:debatly/core/locale/app_locale.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/monetization/screens/hard_paywall_screen.dart';
import 'package:debatly/features/settings/screens/settings_screen.dart';
import 'package:debatly/services/purchases_service.dart' show PurchaseOutcome;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'support/fakes.dart';
import 'support/localized_test_app.dart';
import 'support/test_prefs.dart';

/// The hard paywall's own contract — the screen a non-PRO user is left alone
/// with. Two rules it has to hold at once:
///
///   * there is NO way past it into the feed (no close, no back, no profile,
///     no chrome that leads anywhere but out of the purchase flow), yet
///   * it must not become a dead end either: restore and sign-in are on it for
///     EVERYONE, because either can be the path back to a purchase already
///     made — one through this device's store history, the other through an
///     account that secured it.
///
/// The wall is identical whether or not the user is signed in. Debatly's model
/// is "buy PRO to play; an account only secures a purchase you already made",
/// so there is no profile to reach from here — accounts don't exist before the
/// purchase, and nothing in Settings is anyone's yet.
///
/// Entitlement itself is never granted by this screen: a completed purchase is
/// handed to the session, and the home gate does the swap.
void main() {
  Package fakePackage(PackageType type, String priceString, double price) =>
      Package(
        '\$rc_${type.name}',
        type,
        StoreProduct(
          'prod_${type.name}',
          'description',
          'Debatly PRO',
          price,
          priceString,
          'PLN',
        ),
        const PresentedOfferingContext('default', null, null),
      );

  final lifetime = fakePackage(PackageType.lifetime, '69,99 zł', 69.99);

  /// Pumps the wall for [session]. [packages] defaults to a live offering so
  /// the CTA is present; pass `[]` for the offer-unavailable case.
  Future<_RecordingSession> pumpWall(
    WidgetTester tester, {
    required SessionState session,
    List<Package>? packages,
    Future<PurchaseOutcome> Function(Package)? buy,
    bool entitledOnRefresh = true,
  }) async {
    final notifier = _RecordingSession(session, entitledOnRefresh);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await mockSharedPreferences(),
        ),
        sessionProvider.overrideWith(() => notifier),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LocalizedTestApp(
          home: HardPaywallScreen(
            loadPackages: () async => packages ?? [lifetime],
            buy: buy,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return notifier;
  }

  testWidgets('a guest gets a bare wall — nothing that leads past it', (
    tester,
  ) async {
    await pumpWall(tester, session: guestSession());

    expect(find.byType(HardPaywallScreen), findsOneWidget);
    // No close / back affordance: the wall is not dismissible, and there is no
    // Settings to reach — the pitch is the whole screen.
    expect(find.byType(BackButton), findsNothing);
    expect(find.byType(CloseButton), findsNothing);
    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(find.byIcon(Icons.person_outline), findsNothing);
    expect(find.byType(IconButton), findsNothing);
  });

  testWidgets('a signed-in user without PRO gets the very same bare wall', (
    tester,
  ) async {
    // Being signed in buys no privileges here: the profile view is behind the
    // purchase for everyone. It used to open Settings for account holders,
    // which made the wall inconsistent AND kept alive an "account without PRO"
    // state the product no longer has — accounts are minted only to secure a
    // purchase that already happened.
    await pumpWall(tester, session: accountSession());

    expect(find.byIcon(Icons.person_outline), findsNothing);
    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.byType(IconButton), findsNothing);
  });

  testWidgets('restore and sign-in are offered to everyone the wall stops', (
    tester,
  ) async {
    // Both are recovery paths to a purchase already made — one through this
    // device's store history, the other through the account that secured it.
    await pumpWall(tester, session: guestSession());
    expect(find.text('Zaloguj się'), findsOneWidget);
    expect(find.text('Przywróć zakup'), findsOneWidget);
  });

  testWidgets('...including someone already signed into the wrong account', (
    tester,
  ) async {
    // With no profile entry left, this link is their ONLY way to reach a
    // different account — the one the purchase actually sits on. Hiding it as
    // "pointless, they're signed in" would leave them with nothing but buying
    // PRO a second time.
    await pumpWall(tester, session: accountSession());

    expect(find.text('Zaloguj się'), findsOneWidget);
    expect(find.text('Przywróć zakup'), findsOneWidget);
  });

  testWidgets('a completed purchase hands the entitlement to the session', (
    tester,
  ) async {
    // The wall does not decide it is entitled and it does not navigate: it
    // asks the session to re-reconcile, and the home gate swaps the screen
    // once `isPremium` flips. Skipping this refresh would strand a paying
    // user on the wall they just paid to leave.
    final session = await pumpWall(
      tester,
      session: guestSession(),
      buy: (_) async => PurchaseOutcome.entitled,
    );

    await tester.ensureVisible(find.text('Odblokuj pełny dostęp'));
    await tester.tap(find.text('Odblokuj pełny dostęp'));
    await tester.pumpAndSettle();

    expect(
      session.refreshes,
      1,
      reason: 'the purchase must trigger exactly one entitlement reconcile',
    );
    // The wall itself stays put and stays quiet — dismissing it is the gate's
    // job (it swaps in the feed the moment `isPremium` flips), not its own.
    expect(find.byType(HardPaywallScreen), findsOneWidget);
    expect(
      find.textContaining('nie udało się go jeszcze potwierdzić'),
      findsNothing,
    );
  });

  testWidgets('a purchase the backend cannot confirm is not swallowed', (
    tester,
  ) async {
    // The reconcile can fail (a 502 from sync-entitlement, a webhook still in
    // flight). The user paid and is STILL on the wall — the one thing that
    // must not happen is silence, which reads as "my money vanished".
    final session = await pumpWall(
      tester,
      session: guestSession(),
      buy: (_) async => PurchaseOutcome.entitled,
      entitledOnRefresh: false,
    );

    await tester.ensureVisible(find.text('Odblokuj pełny dostęp'));
    await tester.tap(find.text('Odblokuj pełny dostęp'));
    await tester.pumpAndSettle();

    expect(session.refreshes, 1);
    expect(
      find.textContaining('nie udało się go jeszcze potwierdzić'),
      findsOneWidget,
      reason: 'the user must be told, and pointed at restore',
    );
    // And the surface has to unlock itself. A busy CTA renders a spinner
    // INSTEAD of its label, so the label being back is the assertion: this
    // screen does not dismiss itself, and betting on being unmounted left a
    // user who had just paid on a dead wall — spinning CTA, restore and
    // sign-in disabled — recoverable only by killing the app.
    expect(find.text('Odblokuj pełny dostęp'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Przywróć zakup'), findsOneWidget);
  });

  testWidgets('a cancelled purchase leaves the session untouched', (
    tester,
  ) async {
    final session = await pumpWall(
      tester,
      session: guestSession(),
      buy: (_) async => PurchaseOutcome.cancelled,
    );

    await tester.ensureVisible(find.text('Odblokuj pełny dostęp'));
    await tester.tap(find.text('Odblokuj pełny dostęp'));
    await tester.pumpAndSettle();

    expect(session.refreshes, 0);
    // Still usable: the user can try the other plan.
    expect(find.text('Odblokuj pełny dostęp'), findsOneWidget);
  });

  testWidgets('an unavailable offer still leaves the escape hatches', (
    tester,
  ) async {
    // RevenueCat down / no products configured: the pitch degrades to the
    // retry state, but a user who ALREADY owns PRO must not be locked out of
    // the app by an outage — restore and sign-in stay.
    await pumpWall(tester, session: guestSession(), packages: const []);

    expect(find.text('Odblokuj pełny dostęp'), findsNothing);
    expect(find.text('Spróbuj ponownie'), findsOneWidget);
    expect(find.text('Przywróć zakup'), findsOneWidget);
    expect(find.text('Zaloguj się'), findsOneWidget);
  });
}

/// A [SessionNotifier] that records how often the screen asked it to reconcile
/// the entitlement, without touching Supabase / RevenueCat. [_entitledOnRefresh]
/// models whether the backend confirms the purchase on that reconcile.
class _RecordingSession extends SessionNotifier {
  _RecordingSession(this._state, this._entitledOnRefresh);

  final SessionState _state;
  final bool _entitledOnRefresh;
  int refreshes = 0;

  @override
  Future<SessionState> build() async => _state;

  @override
  Future<SessionState?> refresh() async {
    refreshes++;
    final reloaded = _state.copyWith(
      isPremium: _entitledOnRefresh || _state.isPremium,
    );
    state = AsyncValue.data(reloaded);
    return reloaded;
  }
}
