import 'package:debatly/core/locale/app_locale.dart';
import 'package:debatly/data/models/question.dart';
import 'package:debatly/data/repositories/question_repository.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/account/providers/stats_providers.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:debatly/features/questions/widgets/wind_question_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/localized_test_app.dart';
import 'support/test_prefs.dart';

/// The daily ad-reveal cap on the reveal-slot paywall. The cap itself is
/// enforced server-side (reveal_ad_question raises once 3 ad reveals were
/// spent this UTC day); these tests pin the CLIENT contract: once the synced
/// stats say the cap is spent, the paywall must stop offering the ad button
/// entirely — PRO (plus "come back tomorrow" copy) is the only unlock left, so
/// a user can never sit through an ad whose reveal the server would refuse.
void main() {
  Question q(String id) => Question(
    id: id,
    category: id.toUpperCase(),
    questionText: 'Question $id?',
  );

  Future<void> pumpPaywall(WidgetTester tester, {required bool capped}) async {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await mockSharedPreferences(),
        ),
        questionsProvider.overrideWith((ref) async => const <Question>[]),
        todaysDailyQuestionProvider.overrideWith((ref) async => q('daily')),
        isPremiumProvider.overrideWithValue(false),
        freeUnlockCreditsProvider.overrideWithValue(0),
        adCapReachedProvider.overrideWithValue(capped),
        deckShuffleSeedProvider.overrideWithValue(1),
        questionRepositoryProvider.overrideWithValue(_RevealRepo()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const LocalizedTestApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                height: 600,
                child: WindQuestionView(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Swipe a free user with no credit onto the reveal slot → the paywall.
    await tester.fling(
      find.byType(WindQuestionView),
      const Offset(-300, 0),
      1000,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets('below the cap the paywall offers both the ad and PRO', (
    tester,
  ) async {
    await pumpPaywall(tester, capped: false);

    expect(find.text('Odblokuj reklamą'.toUpperCase()), findsOneWidget);
    expect(find.text('Przejdź na PRO'.toUpperCase()), findsOneWidget);
    expect(
      find.textContaining('Dzisiejsze darmowe odblokowania wykorzystane'),
      findsNothing,
    );
  });

  testWidgets('at the cap the ad button is gone and PRO is the only unlock', (
    tester,
  ) async {
    await pumpPaywall(tester, capped: true);

    expect(
      find.text('Odblokuj reklamą'.toUpperCase()),
      findsNothing,
      reason:
          'a capped user must never be offered (or start) an ad — '
          'the server is guaranteed to refuse its reveal',
    );
    expect(find.text('Przejdź na PRO'.toUpperCase()), findsOneWidget);
    expect(
      find.textContaining('Dzisiejsze darmowe odblokowania wykorzystane'),
      findsOneWidget,
    );
    // The escape hatch back to the free daily must survive the capped variant.
    expect(find.text('Wróć do darmowego pytania'), findsOneWidget);
  });
}

/// Minimal repo: a teaser to peek, no reveals expected on this path.
class _RevealRepo extends MockQuestionRepository {
  @override
  Future<({String id, String teaser})?> peekNextQuestion({
    List<String> excludeIds = const [],
  }) async => (id: 'peek', teaser: 'Czy coś');
}
