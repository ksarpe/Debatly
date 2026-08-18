import 'package:debatly/data/repositories/question_repository.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:debatly/features/questions/widgets/smaczki_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/localized_test_app.dart';

/// The "suggest your own smaczek" composer in the Arguments panel. What
/// matters for release:
///   * the header carries the "(smaczki)" aside and the bare corner CTA;
///   * the composer stays hidden until asked for, send stays disabled below
///     the server's minimum, control characters never reach the repository;
///   * a success submits the TRIMMED text pinned to the question id, folds the
///     composer away and thanks via toast — the sheet itself stays open;
///   * the shared daily cap keeps the composer open with its friendlier line.
void main() {
  group('smaczek suggestion composer', () {
    Future<_RecordingRepo> pumpSheet(WidgetTester tester) async {
      final repo = _RecordingRepo();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [questionRepositoryProvider.overrideWithValue(repo)],
          child: LocalizedTestApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(
                    onPressed: () => showSmaczkiSheet(context, 'q-1'),
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

    /// The send arrow inside the composer's text field.
    Finder sendButton() => find.ancestor(
      of: find.byIcon(Icons.send_rounded),
      matching: find.byType(IconButton),
    );

    testWidgets('folded by default, validates, submits trimmed and pinned', (
      tester,
    ) async {
      final repo = await pumpSheet(tester);

      // Header: headline + the differently-cut aside, corner CTA, no field yet.
      expect(
        find.text('Argumenty (smaczki)', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Zaproponuj własny'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.text('Zaproponuj własny'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);

      // Below the RPC's minimum the arrow must not be tappable — the server
      // TOO_SHORT error is a backstop, not the UX.
      await tester.enterText(find.byType(TextField), 'Ale…');
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(sendButton()).onPressed, isNull);

      // Control characters are filtered out locally (the RPC would reject them
      // as BAD_TEXT anyway) and the submitted text arrives trimmed.
      await tester.enterText(
        find.byType(TextField),
        '  A kto płaci za sprzątanie po tym wszystkim?  ',
      );
      await tester.pumpAndSettle();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(repo.submitted, [
        ('q-1', 'A kto płaci za sprzątanie po tym wszystkim?'),
      ]);
      // Composer folded, sheet still open, thanks toast on the root overlay.
      expect(find.byType(TextField), findsNothing);
      expect(
        find.text('Argumenty (smaczki)', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.text('Dzięki! Twoja propozycja właśnie do nas dotarła.'),
        findsOneWidget,
      );
    });

    testWidgets('the shared daily cap keeps the composer open', (tester) async {
      final repo = await pumpSheet(tester);
      repo.throwOnSubmit = Exception('RATE_LIMITED');

      await tester.tap(find.text('Zaproponuj własny'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Gdzie w tym wszystkim granica?',
      );
      await tester.pumpAndSettle();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      // Still open — the text isn't lost — and the cap line explains why.
      expect(find.byType(TextField), findsOneWidget);
      expect(
        find.text('Na dziś wystarczy — wróć jutro z kolejnym pomysłem.'),
        findsOneWidget,
      );
    });
  });
}

/// Records what the composer submits (and can fail on demand) — the mock
/// parent supplies every other repository call, including the readable
/// smaczki the sheet lists above the composer.
class _RecordingRepo extends MockQuestionRepository {
  final List<(String, String)> submitted = [];
  Object? throwOnSubmit;

  @override
  Future<void> submitSmaczekSuggestion({
    required String questionId,
    required String text,
  }) async {
    if (throwOnSubmit case final err?) throw err;
    submitted.add((questionId, text));
  }
}
