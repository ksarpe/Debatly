import 'package:debatly/core/locale/app_locale.dart';
import 'package:debatly/data/models/question.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:debatly/features/questions/widgets/question_body.dart';
import 'package:debatly/features/questions/widgets/wind_question_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/localized_test_app.dart';
import 'support/test_prefs.dart';

/// Regression tests for the App Review iPad rejection ("when we tried to swipe
/// to see the next question the app did not react"):
///   * the swipe target used to be only the question text's bounding box — on
///     a tablet a thin strip in a sea of dead space. The whole feed body must
///     accept the gesture now.
///   * the commit gate used to be release-velocity only — a slow, deliberate
///     drag (typical on a tablet) ended with ~zero velocity and was silently
///     discarded. Sufficient finger travel must commit too.
void main() {
  Question q(String id) => Question(
    id: id,
    category: id.toUpperCase(),
    questionText: 'Question $id?',
  );

  Future<ProviderContainer> pumpBody(
    WidgetTester tester, {
    required Question daily,
    List<Question> pool = const [],
  }) async {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await mockSharedPreferences(),
        ),
        questionsProvider.overrideWith((ref) async => pool),
        todaysDailyQuestionProvider.overrideWith((ref) async => daily),
        isPremiumProvider.overrideWithValue(true),
        deckShuffleSeedProvider.overrideWithValue(1),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const LocalizedTestApp(home: Scaffold(body: QuestionBody())),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> settleSwipe(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets('a swipe far from the question text still advances (tablet)', (
    tester,
  ) async {
    // iPad-Air-11-landscape-sized surface: the one-line question text leaves
    // almost the entire screen outside its bounding box.
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final daily = q('daily');
    final container = await pumpBody(
      tester,
      daily: daily,
      pool: [daily, q('a'), q('b')],
    );

    // Fling in the top-left corner — nowhere near the centred question text.
    await tester.flingFrom(const Offset(80, 80), const Offset(-300, 0), 1000);
    await settleSwipe(tester);

    expect(container.read(questionIndexProvider), 1);
  });

  testWidgets('a slow drag with ~zero release velocity still advances', (
    tester,
  ) async {
    final daily = q('daily');
    final container = await pumpBody(
      tester,
      daily: daily,
      pool: [daily, q('a'), q('b')],
    );

    // 200px of travel over 3s ≈ 66px/s — under the 100px/s velocity gate, so
    // only the distance fallback can commit this swipe.
    await tester.timedDrag(
      find.byType(WindQuestionView),
      const Offset(-200, 0),
      const Duration(seconds: 3),
    );
    await settleSwipe(tester);

    expect(container.read(questionIndexProvider), 1);
  });
}
