import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/monetization/widgets/purchase_settlement.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/localized_test_app.dart';

/// What the app says after `showProPaywall` comes back `true`.
///
/// That `true` covers TWO outcomes — the entitlement landed, or the store took
/// the money and the entitlement is still in flight — and every entry point
/// except the day wall used to announce "Premium aktywne 🎉" for both. The
/// surface behind the toast then contradicted it: the star still grey, the
/// vault still locked. [settleProPurchase] is that branch hoisted into one
/// place, so this is the test that keeps the two apart.
class _SettlingSession extends SessionNotifier {
  _SettlingSession(this._afterRefresh);

  final SessionState? _afterRefresh;

  @override
  Future<SessionState> build() async => guestSession();

  @override
  Future<SessionState?> refresh() async {
    final next = _afterRefresh;
    if (next != null) state = AsyncData(next);
    return next;
  }
}

void main() {
  Future<bool?> pumpAndSettleFor(
    WidgetTester tester,
    SessionState? afterRefresh,
  ) async {
    bool? settled;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith(() => _SettlingSession(afterRefresh)),
        ],
        child: LocalizedTestApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () async {
                  settled = await settleProPurchase(context, ref);
                },
                child: const Text('settle'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('settle'));
    await tester.pumpAndSettle();
    return settled;
  }

  testWidgets('an entitlement that landed is announced as active', (
    tester,
  ) async {
    final settled = await pumpAndSettleFor(
      tester,
      guestSession(isPremium: true),
    );

    expect(settled, isTrue);
    expect(find.text('Premium aktywne. 🎉'), findsOneWidget);
    expect(find.textContaining('nie udało się go jeszcze'), findsNothing);
  });

  testWidgets('a purchase the entitlement has not caught up with says so', (
    tester,
  ) async {
    // PurchaseOutcome.pending: the money moved, the webhook has not landed.
    final settled = await pumpAndSettleFor(tester, guestSession());

    expect(settled, isFalse);
    expect(find.textContaining('nie udało się go jeszcze'), findsOneWidget);
    expect(find.text('Premium aktywne. 🎉'), findsNothing);
  });

  testWidgets('a reconcile that fails outright never claims premium', (
    tester,
  ) async {
    // `refresh()` returns null when the reload threw — the safe direction is
    // to under-promise, never to announce an entitlement we could not see.
    final settled = await pumpAndSettleFor(tester, null);

    expect(settled, isFalse);
    expect(find.textContaining('nie udało się go jeszcze'), findsOneWidget);
  });
}
