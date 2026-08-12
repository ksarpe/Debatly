import 'package:debatly/data/models/smaczek.dart';
import 'package:debatly/data/repositories/question_repository.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:debatly/features/questions/widgets/smaczki_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/localized_test_app.dart';

/// The smaczki sheet is a monetization gate: a free user must see exactly the
/// first prompt readable, the locked rest as placeholders (never real text —
/// the server sends null), and one "go PRO" hook. Premium sees everything and
/// no upsell. These are the release-blocking guarantees checked here.
void main() {
  Future<void> pumpSheet(
    WidgetTester tester, {
    required List<Smaczek> smaczki,
    Object? throws,
  }) async {
    final repo = _SmaczkiRepo(smaczki: smaczki, throws: throws);
    final container = ProviderContainer(
      overrides: [questionRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LocalizedTestApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showSmaczkiSheet(context, 'q1'),
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
  }

  testWidgets(
    'free user: first smaczek readable, locked rest blurred with PRO badges '
    'and a single go-PRO hook — no real locked text anywhere',
    (tester) async {
      await pumpSheet(
        tester,
        smaczki: const [
          Smaczek(position: 1, isLocked: false, text: 'Pierwszy argument.'),
          Smaczek(position: 2, isLocked: true),
          Smaczek(position: 3, isLocked: true),
        ],
      );

      // The free teaser is readable.
      expect(find.text('Pierwszy argument.'), findsOneWidget);
      // Both locked rows carry the PRO badge and only the dummy blur filler —
      // the server sent text=null, so nothing real can leak.
      expect(find.text('PRO'), findsNWidgets(2));
      expect(find.textContaining('aaabbbb'), findsNWidgets(2));
      // Exactly one upsell hook.
      expect(find.text('Przejdź na PRO'), findsOneWidget);
    },
  );

  testWidgets('premium user: all smaczki readable, no badges, no upsell', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      smaczki: const [
        Smaczek(position: 1, isLocked: false, text: 'Pierwszy argument.'),
        Smaczek(position: 2, isLocked: false, text: 'Drugi argument.'),
        Smaczek(position: 3, isLocked: false, text: 'Trzeci pod włos.'),
      ],
    );

    expect(find.text('Pierwszy argument.'), findsOneWidget);
    expect(find.text('Drugi argument.'), findsOneWidget);
    expect(find.text('Trzeci pod włos.'), findsOneWidget);
    expect(find.text('PRO'), findsNothing);
    expect(find.text('Przejdź na PRO'), findsNothing);
  });

  testWidgets('a question without smaczki shows the quiet empty note', (
    tester,
  ) async {
    await pumpSheet(tester, smaczki: const []);

    expect(
      find.text('Do tego pytania nie ma jeszcze smaczków.'),
      findsOneWidget,
    );
    expect(find.text('Przejdź na PRO'), findsNothing);
  });

  testWidgets('a failed fetch renders the error line, not a crash', (
    tester,
  ) async {
    await pumpSheet(tester, smaczki: const [], throws: 'boom');

    expect(find.textContaining('boom'), findsOneWidget);
  });
}

/// Repo serving a fixed smaczki list (or a failure), standing in for the
/// server-gated `get_question_smaczki` RPC.
class _SmaczkiRepo extends MockQuestionRepository {
  _SmaczkiRepo({required this.smaczki, this.throws});

  final List<Smaczek> smaczki;
  final Object? throws;

  @override
  Future<List<Smaczek>> fetchSmaczki(String questionId) async {
    final error = throws;
    if (error != null) throw Exception(error);
    return smaczki;
  }
}
