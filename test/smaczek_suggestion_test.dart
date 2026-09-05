import 'package:debatly/data/models/smaczek.dart';
import 'package:debatly/data/repositories/question_repository.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:debatly/features/questions/widgets/smaczki_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/localized_test_app.dart';

/// The "suggest your own smaczek" button and composer in the Arguments sheet —
/// community-arguments step 0 (2026-09-05, owner's placement). What matters
/// for release:
///   * the button sits under the list, after the last smaczek, wearing the
///     app's accent-CTA look (a button, not a fourth card — announced as a
///     button to assistive tech); it stays tappable for a free user whose
///     cards are locked, and it is there on a question with no smaczki;
///   * a tap unfolds the composer in its place with the keyboard up; send
///     stays disabled below the server's minimum, control characters never
///     reach the repository, the submitted text arrives TRIMMED and pinned to
///     the question id;
///   * a success folds the composer back into the button and thanks via
///     toast — the sheet itself stays open;
///   * the shared daily cap keeps the composer open with its friendlier line.
void main() {
  // The CTA is an ACTION label, rendered uppercase like every other one.
  const cta = 'ZAPROPONUJ WŁASNY';
  const thanks = 'Dzięki! Twoja propozycja właśnie do nas dotarła.';

  Future<_RecordingRepo> pumpSheet(
    WidgetTester tester, {
    List<Smaczek>? smaczki,
    bool premium = true,
  }) async {
    final repo = _RecordingRepo(smaczki: smaczki);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          questionRepositoryProvider.overrideWithValue(repo),
          isPremiumProvider.overrideWithValue(premium),
        ],
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

  /// The CTA's semantics wrapper — proof it is announced as a button.
  Finder ctaButton() => find.byWidgetPredicate(
    (w) =>
        w is Semantics &&
        w.properties.button == true &&
        w.properties.label == cta,
  );

  group('the "suggest your own" button', () {
    testWidgets('sits after the last smaczek as a button, and unfolds the '
        'composer', (tester) async {
      final repo = await pumpSheet(tester); // the mock serves three smaczki

      // Header (a TITLE, rendered uppercase — the "(smaczki)" aside stays
      // lowercase), three numbered cards, then the button. No field yet.
      expect(
        find.text('ARGUMENTY (smaczki)', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('3'), findsOneWidget);
      expect(find.text(cta), findsOneWidget);
      expect(ctaButton(), findsOneWidget);
      expect(find.byIcon(Icons.edit_rounded), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(
        tester.getRect(find.text(cta)).top,
        greaterThan(tester.getRect(find.text('3')).bottom),
        reason: 'the way in comes after the last argument, never before',
      );

      // A tap swaps the button for the composer, keyboard up.
      await tester.tap(find.text(cta));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text(cta), findsNothing);
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );

      // Below the RPC's minimum the arrow must not be tappable — the server
      // TOO_SHORT error is a backstop, not the UX.
      await tester.enterText(find.byType(TextField), 'Ale…');
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(sendButton()).onPressed, isNull);
      expect(find.text('Co najmniej 5 znaków'), findsOneWidget);

      // The submitted text arrives trimmed, pinned to the question id.
      await tester.enterText(
        find.byType(TextField),
        '  A kto płaci za sprzątanie po tym wszystkim?  ',
      );
      await tester.pumpAndSettle();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(repo.submitted, [
        ('q-1', 'A kto płaci za sprzątanie po tym wszystkim?'),
      ]);
      // Composer folded back into the button, sheet still open, thanks toast
      // on the root overlay.
      expect(find.byType(TextField), findsNothing);
      expect(find.text(cta), findsOneWidget);
      expect(
        find.text('ARGUMENTY (smaczki)', findRichText: true),
        findsOneWidget,
      );
      expect(find.text(thanks), findsOneWidget);
    });

    testWidgets('stays tappable for a free user whose cards are locked', (
      tester,
    ) async {
      await pumpSheet(
        tester,
        premium: false,
        smaczki: const [
          Smaczek(
            position: 1,
            isLocked: false,
            side: SmaczekSide.neutral,
            text: 'Odpowiedziałeś od razu. Ile z tego było decyzją?',
          ),
          Smaczek(position: 2, isLocked: true),
          Smaczek(position: 3, isLocked: true),
        ],
      );

      // Two locked cards with their unlock hooks — and the button, unlocked.
      expect(find.text('ODBLOKUJ'), findsNWidgets(2));
      expect(find.text(cta), findsOneWidget);

      await tester.tap(find.text(cta));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('a question with no smaczki still offers the button', (
      tester,
    ) async {
      await pumpSheet(tester, smaczki: const []);

      expect(find.text('Do tego pytania nie ma jeszcze smaczków.'), findsOne);
      expect(find.text(cta), findsOneWidget);
      expect(ctaButton(), findsOneWidget);
    });

    testWidgets('the shared daily cap keeps the composer open', (tester) async {
      final repo = await pumpSheet(tester);
      repo.throwOnSubmit = Exception('RATE_LIMITED');

      await tester.tap(find.text(cta));
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
      expect(find.text('Gdzie w tym wszystkim granica?'), findsOneWidget);
      expect(
        find.text('Na dziś wystarczy — wróć jutro z kolejnym pomysłem.'),
        findsOneWidget,
      );
      expect(find.text(thanks), findsNothing);
    });
  });
}

/// Records what the composer submits (and can fail on demand); serves the
/// given smaczki, or the mock parent's three when none are given. The mock
/// parent supplies every other repository call.
class _RecordingRepo extends MockQuestionRepository {
  _RecordingRepo({this.smaczki});

  final List<Smaczek>? smaczki;
  final List<(String, String)> submitted = [];
  Object? throwOnSubmit;

  @override
  Future<List<Smaczek>> fetchSmaczki(String questionId) async =>
      smaczki ?? await super.fetchSmaczki(questionId);

  @override
  Future<void> submitSmaczekSuggestion({
    required String questionId,
    required String text,
  }) async {
    if (throwOnSubmit case final err?) throw err;
    submitted.add((questionId, text));
  }
}
