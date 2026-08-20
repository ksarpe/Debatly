import 'dart:io';

import 'package:debatly/data/models/smaczek.dart';
import 'package:debatly/data/models/vote_result.dart';
import 'package:debatly/data/repositories/question_repository.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:debatly/features/questions/widgets/daily_vote_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/localized_test_app.dart';

/// Every way the post-vote argument gate can decline to run.
///
/// The gate is a side quest between a vote and its result, and the invariant
/// that makes it safe to ship is that it can never cost the user the thing they
/// actually asked for. A question with no arguments, an argument that only
/// agrees with them, a fetch that is slow, a fetch that throws, a write that
/// fails — every one of those has to end with the community split on screen.
///
/// These branches were entirely uncovered, which is exactly why they are worth
/// pinning: nobody exercises them by hand, and a user only meets them on a bad
/// connection or an untagged question.
class _VotingRepo extends MockQuestionRepository {
  _VotingRepo({
    this.smaczki = const [],
    this.smaczkiDelay,
    this.smaczkiThrows = false,
    this.smaczkiError,
  });

  final List<Smaczek> smaczki;
  final Duration? smaczkiDelay;
  final bool smaczkiThrows;
  final Object? smaczkiError;

  VoteResult? _voted;
  int castCalls = 0;
  int recordCalls = 0;
  bool recordThrows = false;

  @override
  Future<VoteResult> getDailyVoteState(String questionId) async =>
      _voted ?? VoteResult.empty;

  @override
  Future<VoteResult> castDailyVote(String questionId, int choice) async {
    castCalls++;
    return _voted = VoteResult(
      yesCount: choice == VoteResult.yes ? 61 : 39,
      noCount: choice == VoteResult.no ? 61 : 39,
      myChoice: choice,
    );
  }

  @override
  Future<List<Smaczek>> fetchSmaczki(String questionId) async {
    final delay = smaczkiDelay;
    if (delay != null) await Future<void>.delayed(delay);
    if (smaczkiThrows) throw smaczkiError ?? Exception('smaczki unavailable');
    return smaczki;
  }

  @override
  Future<VoteResult> recordSmaczekChallenge({
    required String questionId,
    required int position,
    required ChallengeOutcome outcome,
    int? dwellMs,
  }) async {
    recordCalls++;
    if (recordThrows) throw Exception('record_smaczek_challenge failed');
    return _voted!;
  }
}

void main() {
  Future<void> pumpAndVote(WidgetTester tester, _VotingRepo repo) async {
    final container = ProviderContainer(
      overrides: [
        sessionProvider.overrideWith(() => FakeSession(guestSession())),
        questionRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const LocalizedTestApp(
          home: Scaffold(
            body: Center(child: DailyVotePanel(questionId: 'q1')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('TAK'));
  }

  /// The split is on screen and the gate never appeared.
  void expectResultWithoutGate({required String reason}) {
    expect(find.text('ZANIM POKAŻĘ WYNIK'), findsNothing, reason: reason);
    expect(find.text('61%'), findsOneWidget, reason: reason);
  }

  const readable = Smaczek(
    position: 1,
    isLocked: false,
    side: SmaczekSide.neutral,
    text: 'Odpowiedziałeś od razu. Ile z tego było decyzją?',
  );

  testWidgets('a question with no arguments goes straight to the split', (
    tester,
  ) async {
    final repo = _VotingRepo();
    await pumpAndVote(tester, repo);
    await tester.pumpAndSettle();

    expectResultWithoutGate(
      reason: 'no argument to throw is not a reason to withhold the result',
    );
    expect(repo.castCalls, 1);
    expect(repo.recordCalls, 0, reason: 'nothing happened, nothing to record');
  });

  testWidgets('an argument that only DEFENDS my side is not a challenge', (
    tester,
  ) async {
    // The user voted TAK; the only readable row attacks NIE, i.e. it argues
    // FOR them. Agreeing with someone is not making them think twice, so the
    // gate declines rather than serving a compliment as a counter-argument.
    final repo = _VotingRepo(
      smaczki: const [
        Smaczek(
          position: 1,
          isLocked: false,
          side: SmaczekSide.attacksNo,
          text: 'Masz rację, i to z bardzo dobrego powodu.',
        ),
      ],
    );
    await pumpAndVote(tester, repo);
    await tester.pumpAndSettle();

    expectResultWithoutGate(
      reason: 'an argument aimed at the other side is not aimed at me',
    );
  });

  testWidgets('a blank argument is treated as no argument', (tester) async {
    final repo = _VotingRepo(
      smaczki: const [
        Smaczek(
          position: 1,
          isLocked: false,
          side: SmaczekSide.neutral,
          text: '   ',
        ),
      ],
    );
    await pumpAndVote(tester, repo);
    await tester.pumpAndSettle();

    expectResultWithoutGate(
      reason: 'an empty gate is a dead end with nothing to read',
    );
  });

  testWidgets('a locked argument is never served — the text is not ours to '
      'show', (tester) async {
    final repo = _VotingRepo(
      smaczki: const [
        Smaczek(position: 1, isLocked: true, side: SmaczekSide.neutral),
      ],
    );
    await pumpAndVote(tester, repo);
    await tester.pumpAndSettle();

    expectResultWithoutGate(reason: 'locked rows carry no text');
  });

  testWidgets('an argument fetch that fails hands over the split AT ONCE, '
      'not after the budget', (tester) async {
    // The timing IS the assertion. A failed fetch is not a slow fetch, and
    // making the user sit through a 2.5s pause for a request that already came
    // back empty-handed is the worst of both: the delay of the gate with none
    // of the argument. `pumpAndSettle` advances no wall clock here, so the
    // split has to be up on the frame after the failure.
    final repo = _VotingRepo(smaczkiThrows: true);
    await pumpAndVote(tester, repo);
    await tester.pumpAndSettle();

    expectResultWithoutGate(
      reason: 'a failed fetch must not spend the gate budget before yielding',
    );
  });

  testWidgets('a transport failure yields just as fast as an empty question', (
    tester,
  ) async {
    // Same immediacy, via the error shape a real dropped connection takes —
    // the branch that decides whether this is reported as "offline" or as
    // "no arguments" must not be reached by way of the timeout.
    final repo = _VotingRepo(
      smaczkiThrows: true,
      smaczkiError: const SocketException('no route to host'),
    );
    await pumpAndVote(tester, repo);
    await tester.pumpAndSettle();

    expectResultWithoutGate(reason: 'offline is a skip, never a stall');
  });

  testWidgets('an argument slower than the budget yields — the split does not '
      'wait on it', (tester) async {
    // The budget exists because the percentages are what the user asked for
    // and the argument is what we asked of them. Past 2.5s the gate gives way.
    final repo = _VotingRepo(
      smaczki: const [readable],
      smaczkiDelay: const Duration(seconds: 6),
    );
    await pumpAndVote(tester, repo);

    // Just inside the budget: still holding, nothing revealed.
    await tester.pump(const Duration(milliseconds: 2400));
    expect(
      find.text('61%'),
      findsNothing,
      reason: 'inside the budget the gate is still entitled to the screen',
    );

    // Past it: the result lands without the argument ever arriving.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expectResultWithoutGate(reason: 'past the budget the percentages win');

    // Let the abandoned fetch finish so the test ends clean.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });

  testWidgets('a gate outcome that fails to persist still leaves the user '
      'their split', (tester) async {
    final repo = _VotingRepo(smaczki: const [readable])..recordThrows = true;

    await pumpAndVote(tester, repo);
    await tester.pumpAndSettle();

    expect(find.text('ZANIM POKAŻĘ WYNIK'), findsOneWidget);
    await tester.tap(find.text('TRZYMAM SIĘ'));
    await tester.pumpAndSettle();

    expect(repo.recordCalls, 1);
    expect(
      find.text('61%'),
      findsOneWidget,
      reason: 'the failed write is ours to worry about, not theirs to pay for',
    );
  });
}
