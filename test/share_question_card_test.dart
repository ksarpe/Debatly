import 'package:debatly/core/share/widget_to_image.dart';
import 'package:debatly/features/questions/widgets/share_question_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/localized_test_app.dart';

/// The shareable question poster and the off-screen renderer that turns it into
/// a PNG. Two things matter: the card lays out without overflow for both short
/// and long questions (long ones auto-shrink), and the renderer produces a real
/// PNG so the share button can attach an image (with a text fallback when it
/// can't).
void main() {
  testWidgets('card renders the wordmark, question and tagline', (
    tester,
  ) async {
    await tester.pumpWidget(
      const LocalizedTestApp(
        home: Scaffold(
          body: Center(
            child: QuestionShareCard(
              questionText: 'Czy zdrada myślami jest zdradą?',
              tagline: 'Pytania, które rozpalają rozmowę',
            ),
          ),
        ),
      ),
    );

    // The fallback wordmark is set uppercase in the display font.
    expect(find.text('DEBATLY'), findsOneWidget);
    // The question is rendered uppercased, in two stacked Text layers
    // (stroke + fill), so it appears twice.
    expect(find.text('CZY ZDRADA MYŚLAMI JEST ZDRADĄ?'), findsNWidgets(2));
    expect(find.text('PYTANIA, KTÓRE ROZPALAJĄ ROZMOWĘ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a very long question lays out without overflow', (tester) async {
    final long = 'Czy ' * 60; // ~240 chars, forces the smallest font size
    await tester.pumpWidget(
      LocalizedTestApp(
        home: Scaffold(
          body: Center(
            child: QuestionShareCard(questionText: long, tagline: 'x'),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('renderWidgetToPng returns a valid PNG', (tester) async {
    // toImage does real async rasterisation, which needs runAsync.
    await tester.runAsync(() async {
      final bytes = await renderWidgetToPng(
        child: const QuestionShareCard(
          questionText: 'Czy warto?',
          tagline: 'tag',
        ),
        logicalSize: const Size(360, 640),
        view: tester.view,
        pixelRatio: 1, // keep the test image small
      );

      expect(bytes, isNotNull);
      expect(bytes!.lengthInBytes, greaterThan(0));
      // PNG magic number: 89 50 4E 47 ("\x89PNG").
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    });
  });
}
