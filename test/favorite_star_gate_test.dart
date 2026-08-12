import 'dart:io';

import 'package:debatly/core/locale/app_locale.dart';
import 'package:debatly/data/repositories/question_repository.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/monetization/widgets/pro_paywall_sheet.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:debatly/features/questions/widgets/favorite_star_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/localized_test_app.dart';
import 'support/test_prefs.dart';

/// The favorite star's error routing rides on a STRING contract with the RPC:
/// a rejection whose message contains 'premium' means "the gate said no" and
/// must open the paywall; anything else is a real failure and must toast. If
/// the RPC's error message ever changes, these tests fail instead of users
/// silently getting a raw error where the paywall belongs.
void main() {
  Future<void> pumpStar(WidgetTester tester, _StarRepo repo) async {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await mockSharedPreferences(),
        ),
        sessionProvider.overrideWith(
          () => FakeSession(accountSession(isPremium: true)),
        ),
        questionRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const LocalizedTestApp(
          home: Scaffold(
            body: Center(child: FavoriteStarButton(questionId: 'q1')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Lets the toast's auto-dismiss timer (up to 5s for errors) fire so the
  /// test doesn't end with a pending timer.
  Future<void> drainToasts(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  }

  testWidgets("a 'premium required' rejection from the RPC opens the paywall", (
    tester,
  ) async {
    // A premium user whose entitlement lapsed mid-session: the client still
    // thinks premium, the server gate refuses the write.
    final repo = _StarRepo(error: Exception('premium required'));
    await pumpStar(tester, repo);

    await tester.tap(find.byType(FavoriteStarButton));
    await tester.pumpAndSettle();

    expect(find.byType(ProPaywallSheet), findsOneWidget);
    expect(
      find.text('Nie udało się zaktualizować ulubionych.'),
      findsNothing,
      reason: 'the gate is an upsell moment, not an error',
    );

    // Tear the sheet down so the test ends with a clean tree.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an offline failure toasts "no connection", no paywall', (
    tester,
  ) async {
    final repo = _StarRepo(error: const SocketException('down'));
    await pumpStar(tester, repo);

    await tester.tap(find.byType(FavoriteStarButton));
    await tester.pumpAndSettle();

    expect(
      find.text('Brak połączenia — spróbuj ponownie za chwilę.'),
      findsOneWidget,
    );
    expect(find.byType(ProPaywallSheet), findsNothing);
    await drainToasts(tester);
  });

  testWidgets('any other failure toasts the favorites error', (tester) async {
    final repo = _StarRepo(error: StateError('rpc exploded'));
    await pumpStar(tester, repo);

    await tester.tap(find.byType(FavoriteStarButton));
    await tester.pumpAndSettle();

    expect(
      find.text('Nie udało się zaktualizować ulubionych.'),
      findsOneWidget,
    );
    expect(find.byType(ProPaywallSheet), findsNothing);
    await drainToasts(tester);
  });
}

/// Repo whose favorite toggle always fails with [error].
class _StarRepo extends MockQuestionRepository {
  _StarRepo({required this.error});

  final Object error;

  @override
  Future<Set<String>> fetchFavoriteIds() async => const {};

  @override
  Future<bool> toggleFavorite(String questionId) async => throw error;
}
