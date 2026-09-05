import 'package:debatly/core/widgets/spark_cta_button.dart';
import 'package:debatly/data/repositories/question_repository.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:debatly/features/settings/widgets/app_feedback_sheet.dart';
import 'package:debatly/features/settings/widgets/review_pre_prompt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/localized_test_app.dart';

/// The review pre-prompt — our own card in front of the OS rating sheet.
/// What matters for release:
///   * the sheet resolves with the answer that was tapped, and a "later" /
///     dismissal resolves with nothing (never a trap);
///   * the "could be better" branch of the flow opens the feedback sheet
///     instead of touching the store;
///   * the feedback sheet — send stays disabled below the server's minimum,
///     a success submits the TRIMMED text to the feedback RPC and closes, the
///     daily cap keeps the sheet open with its own line.
void main() {
  Future<_RecordingRepo> pumpOpener(
    WidgetTester tester, {
    required Future<void> Function(BuildContext) open,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final repo = _RecordingRepo();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [questionRepositoryProvider.overrideWithValue(repo)],
        child: LocalizedTestApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => open(context),
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
    return repo;
  }

  group('showReviewPrePrompt', () {
    testWidgets('resolves with the tapped answer', (tester) async {
      ReviewPrePromptAnswer? answer;
      var closed = false;
      await pumpOpener(
        tester,
        open: (context) async {
          answer = await showReviewPrePrompt(context);
          closed = true;
        },
      );
      // The title is a TITLE, rendered uppercase, and there is no star row of
      // our own — only the two answers and the escape.
      expect(find.text('JAK CI SIĘ GRA W DEBATLY?'), findsOneWidget);
      expect(find.byType(SparkCtaButton), findsOneWidget);
      expect(find.text('MOGŁOBY BYĆ LEPIEJ'), findsOneWidget);
      expect(find.text('PÓŹNIEJ'), findsOneWidget);

      await tester.tap(find.byType(SparkCtaButton));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(answer, ReviewPrePromptAnswer.loving);
      expect(find.byType(ReviewPrePromptSheet), findsNothing);
    });

    testWidgets('"later" resolves with nothing', (tester) async {
      ReviewPrePromptAnswer? answer = ReviewPrePromptAnswer.loving;
      await pumpOpener(
        tester,
        open: (context) async => answer = await showReviewPrePrompt(context),
      );
      await tester.tap(find.text('PÓŹNIEJ'));
      await tester.pumpAndSettle();
      expect(answer, isNull);
      expect(find.byType(ReviewPrePromptSheet), findsNothing);
    });
  });

  group('runReviewPrePromptFlow', () {
    testWidgets('"could be better" opens the feedback sheet', (tester) async {
      await pumpOpener(tester, open: runReviewPrePromptFlow);
      await tester.tap(find.text('MOGŁOBY BYĆ LEPIEJ'));
      await tester.pumpAndSettle();

      expect(find.byType(ReviewPrePromptSheet), findsNothing);
      expect(find.byType(AppFeedbackSheet), findsOneWidget);
      expect(find.text('CO POPRAWIĆ?'), findsOneWidget);
    });
  });

  group('AppFeedbackSheet', () {
    testWidgets('send unlocks at the server minimum and submits trimmed text', (
      tester,
    ) async {
      final repo = await pumpOpener(tester, open: showAppFeedbackSheet);

      // Below the RPC's minimum the button must not be tappable — the server
      // TOO_SHORT error is a backstop, not the UX.
      await tester.enterText(find.byType(TextField), 'Słabo.');
      await tester.pumpAndSettle();
      expect(
        tester.widget<SparkCtaButton>(find.byType(SparkCtaButton)).onTap,
        isNull,
      );

      await tester.enterText(
        find.byType(TextField),
        '  Za mało pytań na dzień, chcę więcej.  ',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('WYŚLIJ OPINIĘ'));
      await tester.pumpAndSettle();

      expect(repo.feedback, ['Za mało pytań na dzień, chcę więcej.']);
      expect(
        repo.suggestions,
        isEmpty,
        reason: 'feedback must go to the feedback RPC, not the question inbox',
      );
      // Sheet closed, success toast riding the root overlay.
      expect(find.byType(AppFeedbackSheet), findsNothing);
      expect(
        find.text('Dzięki! Twoja opinia właśnie do nas dotarła.'),
        findsOneWidget,
      );
    });

    testWidgets('the daily cap keeps the sheet open with its own line', (
      tester,
    ) async {
      final repo = await pumpOpener(tester, open: showAppFeedbackSheet);
      repo.throwOnSubmit = Exception('RATE_LIMITED');

      await tester.enterText(
        find.byType(TextField),
        'Pytania są za trudne jak na poranek.',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('WYŚLIJ OPINIĘ'));
      await tester.pumpAndSettle();

      // Still open — the text isn't lost — and the cap line explains why.
      expect(find.byType(AppFeedbackSheet), findsOneWidget);
      expect(
        find.text('Na dziś wystarczy — dzięki za wszystkie uwagi.'),
        findsOneWidget,
      );
    });
  });
}

class _RecordingRepo extends MockQuestionRepository {
  final List<String> feedback = [];
  final List<String> suggestions = [];
  Object? throwOnSubmit;

  @override
  Future<void> submitAppFeedback(String text) async {
    if (throwOnSubmit case final err?) throw err;
    feedback.add(text);
  }

  @override
  Future<void> submitQuestionSuggestion(String text) async {
    suggestions.add(text);
  }
}
