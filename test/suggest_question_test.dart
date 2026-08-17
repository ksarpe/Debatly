import 'package:debatly/core/locale/app_locale.dart'
    show sharedPreferencesProvider;
import 'package:debatly/core/widgets/spark_cta_button.dart';
import 'package:debatly/data/repositories/question_repository.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:debatly/features/questions/widgets/suggest_question_nudge.dart';
import 'package:debatly/features/questions/widgets/suggest_question_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/localized_test_app.dart';

/// The "suggest a question" pipeline. What matters for release:
///   * the pure nudge decision — quiet until the second vote, then once ever;
///   * the sheet — send stays disabled below the server's minimum, a success
///     submits the TRIMMED text and closes, the RPC's daily cap keeps the
///     sheet open with its friendlier line;
///   * the nudge toast — shows after the second vote, its action opens the
///     sheet, and it never comes back.
void main() {
  group('shouldPromptSuggestQuestion', () {
    test('quiet until the trigger vote', () {
      expect(
        shouldPromptSuggestQuestion(
          votesCast: kSuggestQuestionNudgeAfterVotes - 1,
          alreadyPrompted: false,
        ),
        isFalse,
      );
    });

    test('due on the trigger vote', () {
      expect(
        shouldPromptSuggestQuestion(
          votesCast: kSuggestQuestionNudgeAfterVotes,
          alreadyPrompted: false,
        ),
        isTrue,
      );
    });

    test('a missed trigger fires on the NEXT vote (>= not ==)', () {
      // Another prompt (e.g. secure-streak) may own the trigger vote's moment;
      // the nudge must then come around instead of being lost forever.
      expect(
        shouldPromptSuggestQuestion(
          votesCast: kSuggestQuestionNudgeAfterVotes + 3,
          alreadyPrompted: false,
        ),
        isTrue,
      );
    });

    test('once ever — shown means never again', () {
      expect(
        shouldPromptSuggestQuestion(votesCast: 100, alreadyPrompted: true),
        isFalse,
      );
    });
  });

  group('SuggestQuestionSheet', () {
    Future<_RecordingRepo> pumpOpener(WidgetTester tester) async {
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
                    onPressed: () => showSuggestQuestionSheet(context),
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

    testWidgets('send unlocks at the server minimum and submits trimmed text', (
      tester,
    ) async {
      final repo = await pumpOpener(tester);
      expect(find.text('Zaproponuj pytanie'), findsOneWidget);

      // Below the RPC's minimum the button must not be tappable — the server
      // TOO_SHORT error is a backstop, not the UX.
      await tester.enterText(find.byType(TextField), 'Czy?');
      await tester.pumpAndSettle();
      expect(
        tester.widget<SparkCtaButton>(find.byType(SparkCtaButton)).onTap,
        isNull,
      );

      await tester.enterText(
        find.byType(TextField),
        '  Czy pies to lepszy współlokator niż kot?  ',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wyślij propozycję'));
      await tester.pumpAndSettle();

      expect(repo.submitted, ['Czy pies to lepszy współlokator niż kot?']);
      // Sheet closed, success toast riding the root overlay.
      expect(find.byType(SuggestQuestionSheet), findsNothing);
      expect(
        find.text('Dzięki! Twoja propozycja właśnie do nas dotarła.'),
        findsOneWidget,
      );
    });

    testWidgets('the daily cap keeps the sheet open with its own line', (
      tester,
    ) async {
      final repo = await pumpOpener(tester);
      repo.throwOnSubmit = Exception('RATE_LIMITED');

      await tester.enterText(
        find.byType(TextField),
        'Czy sąsiad może grillować na balkonie?',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wyślij propozycję'));
      await tester.pumpAndSettle();

      // Still open — the text isn't lost — and the cap line explains why.
      expect(find.byType(SuggestQuestionSheet), findsOneWidget);
      expect(
        find.text('Na dziś wystarczy — wróć jutro z kolejnym pomysłem.'),
        findsOneWidget,
      );
    });
  });

  group('maybePromptSuggestQuestion', () {
    testWidgets('shows after the second vote, opens the sheet, never returns', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final results = <bool>[];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            questionRepositoryProvider.overrideWithValue(_RecordingRepo()),
          ],
          child: LocalizedTestApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => Center(
                  child: TextButton(
                    // Mirrors the vote panel's order: count the vote, then let
                    // the nudge decide.
                    onPressed: () async {
                      await recordVoteForSuggestQuestionNudge(
                        ref.read(sharedPreferencesProvider),
                      );
                      if (!context.mounted) return;
                      results.add(
                        await maybePromptSuggestQuestion(context, ref),
                      );
                    },
                    child: const Text('vote'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      const nudge =
          'Masz pomysł na pytanie, które utkwi ludziom w głowie? Podrzuć je!';

      // First vote: quiet.
      await tester.tap(find.text('vote'));
      await tester.pumpAndSettle();
      expect(results, [false]);
      expect(find.text(nudge), findsNothing);

      // Second vote: the toast, with its tap-through action.
      await tester.tap(find.text('vote'));
      await tester.pumpAndSettle();
      expect(results, [false, true]);
      expect(find.text(nudge), findsOneWidget);

      await tester.tap(find.text('Zaproponuj'));
      await tester.pumpAndSettle();
      expect(find.byType(SuggestQuestionSheet), findsOneWidget);

      // Close the sheet and vote again: once ever means once ever.
      Navigator.of(tester.element(find.byType(TextField))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('vote'));
      await tester.pumpAndSettle();
      expect(results, [false, true, false]);
      expect(find.text(nudge), findsNothing);
    });
  });
}

/// Records what the sheet submits (and can fail on demand) — the mock parent
/// supplies every other repository call.
class _RecordingRepo extends MockQuestionRepository {
  final List<String> submitted = [];
  Object? throwOnSubmit;

  @override
  Future<void> submitQuestionSuggestion(String text) async {
    if (throwOnSubmit case final err?) throw err;
    submitted.add(text);
  }
}
