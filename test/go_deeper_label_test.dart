import 'package:debatly/core/locale/app_locale.dart';
import 'package:debatly/data/models/question.dart';
import 'package:debatly/data/models/smaczek.dart';
import 'package:debatly/data/models/vote_result.dart';
import 'package:debatly/data/repositories/question_repository.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/questions/providers/challenge_providers.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:debatly/features/questions/widgets/go_deeper_button.dart';
import 'package:debatly/features/questions/widgets/question_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/localized_test_app.dart';
import 'support/test_prefs.dart';

/// The "go deeper" pill's post-gate label is a PROMISE about the sheet one tap
/// away, so it has to count what the sheet actually still holds. The catalog
/// runs 2–4 smaczki per question (550 questions at three, six at two, three at
/// four), which is exactly why the untagged label may not hard-code "two": on
/// a two-smaczek question the pill would promise two more and the sheet would
/// then say one, and on a four-smaczek one it would undersell by a whole
/// argument.
///
/// The untagged arm deliberately outranks the premium one — an argument with
/// no `side` can't promise "against you" to EITHER tier — so the last test
/// here is the lock on "KONTRA" still being reachable once a smaczek is
/// tagged, rather than dead code hidden behind the untagged branch.
void main() {
  Question q(String id, [String? text]) =>
      Question(id: id, category: 'TEST', questionText: text ?? 'Czy $id?');

  /// Pumps the feed on a voted question, then replays a post-vote gate that
  /// served [gateOn] — the same record DailyVotePanel writes — and settles.
  Future<void> pumpAfterGate(
    WidgetTester tester, {
    required List<Smaczek> smaczki,
    required int gateOn,
    bool premium = false,
  }) async {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await mockSharedPreferences(),
        ),
        sessionProvider.overrideWith(
          () => FakeSession(guestSession(isPremium: premium)),
        ),
        isPremiumProvider.overrideWithValue(premium),
        questionsProvider.overrideWith((ref) async => const <Question>[]),
        todaysDailyQuestionProvider.overrideWith(
          (ref) async => q('daily', 'Czy pytanie dnia jest darmowe?'),
        ),
        deckShuffleSeedProvider.overrideWithValue(1),
        questionRepositoryProvider.overrideWithValue(_SmaczkiRepo(smaczki)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const LocalizedTestApp(home: Scaffold(body: QuestionBody())),
      ),
    );
    // Settle FIRST: the records notifier resets on an identity change, so a
    // record primed before the (fake) session resolves would be wiped.
    await tester.pumpAndSettle();

    final served = smaczki.firstWhere((s) => s.position == gateOn);
    container
        .read(challengeRecordsProvider.notifier)
        .record(
          'daily',
          ChallengeRecord(
            outcome: ChallengeOutcome.held,
            smaczekPosition: served.position,
            smaczekTagged: served.isTagged,
            choice: VoteResult.yes,
          ),
        );
    await tester.pumpAndSettle();
  }

  Smaczek untagged(int position) =>
      Smaczek(position: position, isLocked: false, text: 'Argument $position.');

  testWidgets('three smaczki, one spent on the gate — the pill counts two', (
    tester,
  ) async {
    await pumpAfterGate(
      tester,
      smaczki: [untagged(1), untagged(2), untagged(3)],
      gateOn: 1,
    );

    expect(find.text('JESZCZE DWA ARGUMENTY'), findsOneWidget);
  });

  testWidgets('a two-smaczek question promises ONE more, not two', (
    tester,
  ) async {
    await pumpAfterGate(tester, smaczki: [untagged(1), untagged(2)], gateOn: 1);

    expect(find.text('JESZCZE JEDEN ARGUMENT'), findsOneWidget);
    expect(find.text('JESZCZE DWA ARGUMENTY'), findsNothing);
  });

  testWidgets('a four-smaczek question promises three', (tester) async {
    await pumpAfterGate(
      tester,
      smaczki: [untagged(1), untagged(2), untagged(3), untagged(4)],
      gateOn: 2,
    );

    expect(find.text('JESZCZE 3 ARGUMENTY'), findsOneWidget);
  });

  testWidgets(
    'a TAGGED smaczek still hands PRO the short "KONTRA" — the untagged arm '
    'must not swallow it',
    (tester) async {
      await pumpAfterGate(
        tester,
        premium: true,
        gateOn: 1,
        smaczki: const [
          Smaczek(
            position: 1,
            isLocked: false,
            side: SmaczekSide.attacksYes,
            text: 'Argument 1.',
          ),
          Smaczek(position: 2, isLocked: false, text: 'Argument 2.'),
          Smaczek(position: 3, isLocked: false, text: 'Argument 3.'),
        ],
      );

      expect(find.text('KONTRA'), findsOneWidget);
    },
  );

  testWidgets('before the gate the pill keeps the standing promise', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await mockSharedPreferences(),
        ),
        sessionProvider.overrideWith(() => FakeSession(guestSession())),
        isPremiumProvider.overrideWithValue(false),
        questionsProvider.overrideWith((ref) async => const <Question>[]),
        todaysDailyQuestionProvider.overrideWith(
          (ref) async => q('daily', 'Czy pytanie dnia jest darmowe?'),
        ),
        deckShuffleSeedProvider.overrideWithValue(1),
        questionRepositoryProvider.overrideWithValue(
          _SmaczkiRepo([untagged(1), untagged(2)]),
        ),
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

    expect(find.byType(GoDeeperButton), findsOneWidget);
    expect(find.text('PRZECIWKO TOBIE'), findsOneWidget);
  });
}

/// A voted question with a caller-controlled smaczki set — the count IS the
/// thing under test, so the mock's canned three won't do.
class _SmaczkiRepo extends MockQuestionRepository {
  _SmaczkiRepo(this.smaczki);

  final List<Smaczek> smaczki;

  @override
  Future<VoteResult> getDailyVoteState(String questionId) async =>
      const VoteResult(yesCount: 61, noCount: 39, myChoice: VoteResult.yes);

  @override
  Future<List<Smaczek>> fetchSmaczki(String questionId) async => smaczki;

  @override
  Future<List<SmaczekMeta>> fetchSmaczkiMeta(String questionId) async => [
    for (final s in smaczki)
      SmaczekMeta(position: s.position, approxLen: (s.text ?? '').length),
  ];
}
