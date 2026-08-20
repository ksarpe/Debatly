import 'package:debatly/data/models/smaczek.dart';
import 'package:debatly/data/repositories/question_repository.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/questions/providers/challenge_providers.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:debatly/features/questions/widgets/smaczki_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/localized_test_app.dart';

/// The smaczki sheet is a monetization gate: a free user must see exactly the
/// first prompt readable, the locked rest as placeholders (never real text —
/// the server sends null), each with an inline "unlock" label. Premium sees
/// everything and no upsell. These are the release-blocking guarantees
/// checked here.
void main() {
  Future<void> pumpSheet(
    WidgetTester tester, {
    required List<Smaczek> smaczki,
    Object? throws,
    bool? premium,
    ChallengeRecord? gateRecord,
  }) async {
    final repo = _SmaczkiRepo(smaczki: smaczki, throws: throws);
    final container = ProviderContainer(
      overrides: [
        questionRepositoryProvider.overrideWithValue(repo),
        if (premium != null) isPremiumProvider.overrideWithValue(premium),
      ],
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
    // Settle FIRST so the (mock) session has resolved — the records notifier
    // resets on an identity change, which would wipe a record primed earlier.
    await tester.pumpAndSettle();
    if (gateRecord != null) {
      container
          .read(challengeRecordsProvider.notifier)
          .record('q1', gateRecord);
    }
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'free user: first smaczek readable, locked rest blurred with lock icons '
    'and inline unlock labels — no real locked text anywhere',
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
      // Both locked rows carry the lock icon and only the dummy blur filler —
      // the server sent text=null, so nothing real can leak.
      expect(find.byIcon(Icons.lock_rounded), findsNWidgets(2));
      expect(find.textContaining('aaabbbb'), findsNWidgets(2));
      // Each locked row carries its own bare "unlock" label next to the lock
      // (an ACTION label, rendered uppercase).
      expect(find.text('ODBLOKUJ'), findsNWidgets(2));
    },
  );

  testWidgets(
    'free user AFTER the gate (untagged catalog): the served argument is not '
    'repeated — two locked cards, the honest count header, numbering picks up '
    'at 2',
    (tester) async {
      await pumpSheet(
        tester,
        premium: false,
        gateRecord: const ChallengeRecord(
          outcome: ChallengeOutcome.held,
          smaczekPosition: 1,
          smaczekTagged: false,
          choice: 1,
        ),
        smaczki: const [
          Smaczek(position: 1, isLocked: false, text: 'Pierwszy argument.'),
          Smaczek(position: 2, isLocked: true),
          Smaczek(position: 3, isLocked: true),
        ],
      );

      // The argument read in the gate does NOT reappear — repeating it right
      // at the paywall is the broken promise this view exists to avoid.
      expect(find.text('Pierwszy argument.'), findsNothing);
      // Straight to the locked state: two locked cards, numbered 2 and 3.
      expect(find.byIcon(Icons.lock_rounded), findsNWidgets(2));
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('1'), findsNothing);
      // Untagged rows can't promise a defense, so the header only counts.
      expect(
        find.text('Pierwszy masz za sobą. Zostały jeszcze dwa.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'free user who BACKED OUT of the gate keeps their readable argument — a '
    'dismissal is not a reading',
    (tester) async {
      // System back out of the gate, often inside the first second (a
      // mis-tap, a notification, a change of mind). The outcome is recorded
      // for the statistic, but nothing was delivered — so binding the sheet
      // to the mere EXISTENCE of a record spent the free tier's headline
      // promise on an accidental back press, and only an app restart undid
      // it.
      await pumpSheet(
        tester,
        premium: false,
        gateRecord: const ChallengeRecord(
          outcome: ChallengeOutcome.dismissed,
          smaczekPosition: 1,
          smaczekTagged: false,
          choice: 1,
        ),
        smaczki: const [
          Smaczek(position: 1, isLocked: false, text: 'Pierwszy argument.'),
          Smaczek(position: 2, isLocked: true),
          Smaczek(position: 3, isLocked: true),
        ],
      );

      expect(find.text('Pierwszy argument.'), findsOneWidget);
      expect(find.byIcon(Icons.lock_rounded), findsNWidgets(2));
      // …and the sheet does not claim the first one is behind them.
      expect(find.textContaining('Pierwszy masz za sobą'), findsNothing);
    },
  );

  testWidgets(
    'free user AFTER the gate on a fully tagged question: the header sells '
    'attack → defense (one card defends the answer, one complicates it)',
    (tester) async {
      await pumpSheet(
        tester,
        premium: false,
        gateRecord: const ChallengeRecord(
          outcome: ChallengeOutcome.moved,
          smaczekPosition: 2,
          smaczekTagged: true,
          choice: 1, // voted TAK; the gate served the attacks_yes row (pos 2)
        ),
        smaczki: const [
          Smaczek(
            position: 2,
            isLocked: false,
            text: 'Atak na TAK.',
            side: SmaczekSide.attacksYes,
          ),
          Smaczek(position: 1, isLocked: true, side: SmaczekSide.attacksNo),
          Smaczek(position: 3, isLocked: true, side: SmaczekSide.neutral),
        ],
      );

      expect(find.text('Atak na TAK.'), findsNothing);
      expect(find.byIcon(Icons.lock_rounded), findsNWidgets(2));
      expect(
        find.text(
          'Dostałeś argument przeciwko sobie. Zostały dwa: jeden, który Cię '
          'broni, i jeden, który komplikuje sprawę.',
        ),
        findsOneWidget,
      );
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
    expect(find.byIcon(Icons.lock_rounded), findsNothing);
    expect(find.text('ODBLOKUJ'), findsNothing);
  });

  testWidgets('a question without smaczki shows the quiet empty note', (
    tester,
  ) async {
    await pumpSheet(tester, smaczki: const []);

    expect(
      find.text('Do tego pytania nie ma jeszcze smaczków.'),
      findsOneWidget,
    );
    expect(find.text('ODBLOKUJ'), findsNothing);
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
