import 'package:debatly/data/models/smaczek.dart';
import 'package:debatly/data/models/vote_result.dart';
import 'package:debatly/data/repositories/question_repository.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/questions/providers/challenge_providers.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:debatly/features/questions/widgets/daily_vote_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/localized_test_app.dart';

/// The daily TAK/NIE panel. Two guarantees matter for release:
///   * ANY user — guest or account — can vote: the vote rides the (anonymous)
///     Supabase identity, so a tap records it and reveals the community split
///     (green %, red %, with "VS" between) with their own side marked;
///   * the split never leaks before a vote, and returning to a voted question
///     shows the split again rather than allowing a second vote.
void main() {
  SessionState guest() => const SessionState(userId: 'anon', isAnonymous: true);
  SessionState account() =>
      const SessionState(userId: 'u1', isAnonymous: false);

  Future<_VotePanelRepo> pumpPanel(
    WidgetTester tester, {
    required SessionState session,
    required VoteResult initial,
    VoteResult? castReturns,
  }) async {
    final repo = _VotePanelRepo(initial: initial)..castReturns = castReturns;
    final container = ProviderContainer(
      overrides: [
        sessionProvider.overrideWith(() => _FakeSession(session)),
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
    return repo;
  }

  /// The post-vote smaczek challenge now stands between the tap and the split:
  /// the argument aimed at the side just picked falls in, and the bars appear
  /// only once the user has answered it. These tests take the "held" branch;
  /// the vote is final regardless of the answer.
  Future<void> holdGround(WidgetTester tester) async {
    await tester.pumpAndSettle();
    expect(
      find.text('ZANIM POKAŻĘ WYNIK'),
      findsOneWidget,
      reason: 'the argument comes before the percentages',
    );
    await tester.tap(find.text('TRZYMAM SIĘ'));
    await tester.pumpAndSettle();
  }

  testWidgets('a guest votes like anyone else — recorded, split revealed', (
    tester,
  ) async {
    final repo = await pumpPanel(
      tester,
      session: guest(),
      initial: VoteResult.empty,
      castReturns: const VoteResult(
        yesCount: 60,
        noCount: 40,
        myChoice: VoteResult.yes,
      ),
    );

    // Before the vote no split leaks — buttons only.
    expect(find.text('TAK'), findsOneWidget);
    expect(find.text('NIE'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);

    await tester.tap(find.text('TAK'));
    await holdGround(tester);

    // The tap voted — it did NOT open the sign-in sheet.
    expect(repo.castCalls, 1, reason: 'a guest vote is a real vote');
    expect(
      find.byType(TextField),
      findsNothing,
      reason: 'no sign-in gate on voting',
    );
    expect(find.text('60%'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
    expect(find.text('VS'), findsOneWidget);
  });

  testWidgets(
    'an account that has not voted sees the buttons, no split leaked',
    (tester) async {
      await pumpPanel(
        tester,
        session: account(),
        initial: VoteResult.empty, // myChoice null → not voted
      );

      expect(find.text('TAK'), findsOneWidget);
      expect(find.text('NIE'), findsOneWidget);
      expect(find.text('VS'), findsNothing);
      expect(find.textContaining('%'), findsNothing);
    },
  );

  testWidgets('voting reveals the green/red split with VS and marks my side', (
    tester,
  ) async {
    final repo = await pumpPanel(
      tester,
      session: account(),
      initial: VoteResult.empty,
      castReturns: const VoteResult(
        yesCount: 60,
        noCount: 40,
        myChoice: VoteResult.yes,
      ),
    );

    await tester.tap(find.text('TAK'));
    await holdGround(tester); // cast + challenge + AnimatedSwitcher to results

    expect(repo.castCalls, 1);
    expect(repo.lastChoice, VoteResult.yes);

    // The split: both percentages plus the "VS" separator between them.
    expect(find.text('60%'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
    expect(find.text('VS'), findsOneWidget);
    // The user's own side carries the check mark.
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    // ...and a muted "Twój głos" caption sits under the picked tile
    // (rendered uppercase, like every eyebrow).
    expect(find.text('TWÓJ GŁOS'), findsOneWidget);
  });

  testWidgets(
    'an offline cached vote confirms my side but withholds the community split',
    (tester) async {
      // A snapshot served from cache offline: the user's own vote is known, but
      // the community split must not be shown (it may be stale).
      await pumpPanel(
        tester,
        session: account(),
        initial: const VoteResult(
          yesCount: 61,
          noCount: 39,
          myChoice: VoteResult.yes,
          fromCache: true,
        ),
      );

      // My side is still confirmed (check mark + the VS shell), so it reads as
      // "you voted" rather than an empty gap...
      expect(find.byKey(const ValueKey('results')), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      // ...but no percentage leaks — a dash stands in on both sides, with a
      // caption explaining the numbers return online.
      expect(find.textContaining('%'), findsNothing);
      expect(find.text('–'), findsNWidgets(2));
      expect(find.text('Wyniki wrócą po połączeniu'), findsOneWidget);
      // The "your vote" caption still shows offline (it's my own data).
      expect(find.text('TWÓJ GŁOS'), findsOneWidget);
    },
  );

  testWidgets(
    'after voting, leaving the daily and returning still shows the split — '
    'no second vote',
    (tester) async {
      // Server-faithful repo: once a vote is cast, get_daily_vote_state reports
      // the post-vote state (myChoice set), exactly like the real RPC.
      final repo = _PersistingVoteRepo();
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith(() => _FakeSession(account())),
          questionRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      // A panel that can be mounted/unmounted to simulate swiping off the daily
      // (isDaily=false → panel gone) and back to it.
      Widget tree({required bool showPanel}) => UncontrolledProviderScope(
        container: container,
        child: LocalizedTestApp(
          home: Scaffold(
            body: Center(
              child: showPanel
                  ? const DailyVotePanel(questionId: 'q1')
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      );

      await tester.pumpWidget(tree(showPanel: true));
      await tester.pumpAndSettle();

      await tester.tap(find.text('TAK'));
      await holdGround(tester);
      expect(repo.castCalls, 1);
      // The result bars (keyed 'results'), not the vote buttons (keyed 'buttons').
      expect(find.byKey(const ValueKey('results')), findsOneWidget);

      // Swipe to another question: the daily panel unmounts (its local state is
      // discarded).
      await tester.pumpWidget(tree(showPanel: false));
      await tester.pumpAndSettle();

      // Come back to the daily: a fresh panel mounts with no local state.
      await tester.pumpWidget(tree(showPanel: true));
      await tester.pumpAndSettle();

      // It must still show the split, never the buttons — and must not let the
      // user cast a second vote. (Both rows label their sides "TAK"/"NIE", so the
      // distinguishing signal is the AnimatedSwitcher child key, not the text.)
      expect(find.byKey(const ValueKey('results')), findsOneWidget);
      expect(find.byKey(const ValueKey('buttons')), findsNothing);
      expect(
        repo.castCalls,
        1,
        reason: 'returning to the daily is not a re-vote',
      );
    },
  );

  testWidgets(
    '"to mnie ruszyło" never re-casts — the vote is final, the bars keep '
    'the side that was picked',
    (tester) async {
      final repo = await pumpPanel(
        tester,
        session: account(),
        initial: VoteResult.empty,
        castReturns: const VoteResult(
          yesCount: 80,
          noCount: 20,
          myChoice: VoteResult.yes,
        ),
      );

      await tester.tap(find.text('TAK'));
      await tester.pumpAndSettle();
      expect(find.text('ZANIM POKAŻĘ WYNIK'), findsOneWidget);

      await tester.tap(find.text('TO MNIE RUSZYŁO'));
      await tester.pumpAndSettle();

      // ONE cast — admitting the argument landed records an outcome on a
      // separate axis, it does not change the vote. (The old behaviour, a
      // second cast for the other side, is what made every split drift
      // toward 50/50.)
      expect(repo.castCalls, 1, reason: 'the gate must never re-cast');
      expect(repo.lastChoice, VoteResult.yes);
      // The bars appear and still mark the ORIGINAL side as mine.
      expect(find.byKey(const ValueKey('results')), findsOneWidget);
      expect(find.text('80%'), findsOneWidget);
      expect(find.text('20%'), findsOneWidget);
    },
  );

  testWidgets(
    'the vote past the session cap skips the gate — percentages straight away',
    (tester) async {
      final repo = _VotePanelRepo(initial: VoteResult.empty);
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith(() => _FakeSession(account())),
          questionRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      // One question past the cap, all voted back-to-back in ONE session
      // (same container). Written against the constant rather than a literal:
      // the cap is a product dial (3 → 10 on 2026-08-20) and moving it must
      // not mean rewriting the test that guards it.
      const votes = kChallengeSessionCap + 1;
      for (var i = 1; i <= votes; i++) {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: LocalizedTestApp(
              home: Scaffold(
                body: Center(
                  // Keyed like the real feed keys it, so swapping the question
                  // resets the panel's local state instead of reusing it.
                  child: DailyVotePanel(
                    key: ValueKey('q$i'),
                    questionId: 'q$i',
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('TAK'));
        await tester.pumpAndSettle();

        if (i <= kChallengeSessionCap) {
          expect(
            find.text('ZANIM POKAŻĘ WYNIK'),
            findsOneWidget,
            reason: 'gate $i of the session still shows',
          );
          await tester.tap(find.text('TRZYMAM SIĘ'));
          await tester.pumpAndSettle();
        } else {
          // The valve for PRO: the first vote past the cap goes straight to
          // the split.
          expect(
            find.text('ZANIM POKAŻĘ WYNIK'),
            findsNothing,
            reason: 'the session cap is $kChallengeSessionCap gates',
          );
          expect(find.byKey(const ValueKey('results')), findsOneWidget);
        }
      }
      expect(repo.castCalls, votes);
    },
  );

  // A vote state that FAILS to load used to render a blank 52px gap: the user
  // saw the question with nothing to tap and no explanation. Offline with
  // nothing cached, a 500, or an expired JWT all land here — and the caching
  // layer rethrows precisely "so the buttons stay".
  testWidgets('a failed vote-state read still offers the buttons', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        sessionProvider.overrideWith(() => _FakeSession(guest())),
        questionRepositoryProvider.overrideWithValue(_UnreadableStateRepo()),
      ],
    );
    // Disposed inline rather than via addTearDown: a provider that throws makes
    // Riverpod schedule its own retry timer, and teardown runs too late to stop
    // the "timer still pending" invariant from firing.

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

    expect(find.byKey(const ValueKey('buttons')), findsOneWidget);
    expect(find.byKey(const ValueKey('results')), findsNothing);

    container.dispose();
  });

  // REGRESSION: the split used to be able to paint BEFORE the gate. The panel
  // invalidated the vote state straight after the cast, which — this widget
  // being a listener — refetches at once; that PK read beats the smaczki round
  // trip a free user always pays, and `_local ?? async.value` then faded the
  // bars in under the argument. The panel's other repo returns the SAME
  // pre-vote state forever, which is exactly why no test saw it: the reveal
  // order only breaks when the server answers "voted".
  testWidgets('the split waits for the gate, not for the vote-state refetch', (
    tester,
  ) async {
    final repo = _SlowSmaczkiRepo();
    final container = ProviderContainer(
      overrides: [
        sessionProvider.overrideWith(() => _FakeSession(guest())),
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
    // Long enough for the cast and any refetch of the now-"voted" state to
    // resolve, well short of the argument's fetch.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(
      find.textContaining('%'),
      findsNothing,
      reason: 'the server knows the vote — the user must not, not yet',
    );
    expect(find.byKey(const ValueKey('results')), findsNothing);

    // The gate arrives. The route below a transition is still painted, so the
    // bars must not be sitting behind it either.
    await tester.pumpAndSettle();
    expect(find.text('ZANIM POKAŻĘ WYNIK'), findsOneWidget);
    expect(
      find.textContaining('%'),
      findsNothing,
      reason: 'the split must not be revealed under the opening gate',
    );

    // Answering it is what releases the percentages.
    await tester.tap(find.text('TRZYMAM SIĘ'));
    await tester.pumpAndSettle();
    expect(find.text('60%'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
    expect(repo.castCalls, 1, reason: 'the gate never re-casts the vote');
  });

  // cast_daily_vote is first-write-wins server-side (20260820120000): a cast on
  // a question already voted writes nothing and answers with the STORED choice.
  // That happens for real when a cast times out at 15 s but committed — the
  // panel keeps the buttons live on a failed vote-state read, so the next tap
  // can be the other side. Whatever the finger did, the argument must be the
  // one aimed at the vote ON RECORD, or the gate attacks a side the user never
  // voted for.
  testWidgets('a cast the server refuses to overwrite challenges the stored '
      'side, not the tapped one', (tester) async {
    final repo = _StoredChoiceRepo();
    final container = ProviderContainer(
      overrides: [
        sessionProvider.overrideWith(() => _FakeSession(account())),
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

    // The tap says NIE; the server says "you already voted TAK".
    await tester.tap(find.text('NIE'));
    await holdGround(tester);

    expect(repo.lastChoice, VoteResult.no, reason: 'the tap is sent as-is');
    expect(
      repo.challengedPosition,
      1,
      reason: 'position 1 attacks TAK — the side actually on record',
    );
    // And the bars mark the stored side, not the tapped one.
    expect(find.byKey(const ValueKey('results')), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
  });
}

/// A repo whose vote-state read always fails — the offline / 500 / expired-JWT
/// case.
class _UnreadableStateRepo extends MockQuestionRepository {
  @override
  Future<VoteResult> getDailyVoteState(String questionId) async =>
      throw Exception('vote state unavailable');
}

/// A repo that remembers a cast vote, so `getDailyVoteState` reflects it on the
/// next read — mirroring the server, where the vote is persisted and the panel
/// is meant to read it back as "already voted".
class _PersistingVoteRepo extends MockQuestionRepository {
  VoteResult? _voted;
  int castCalls = 0;

  @override
  Future<VoteResult> getDailyVoteState(String questionId) async =>
      _voted ?? VoteResult.empty;

  @override
  Future<VoteResult> castDailyVote(String questionId, int choice) async {
    castCalls++;
    return _voted = VoteResult(
      yesCount: choice == VoteResult.yes ? 60 : 40,
      noCount: choice == VoteResult.no ? 60 : 40,
      myChoice: choice,
    );
  }
}

/// A persisting repo whose ARGUMENT is slow while its vote state is instant —
/// the free tier's real shape (the smaczek text is only unlocked server-side
/// once the vote exists, so their gate always costs a round trip).
class _SlowSmaczkiRepo extends _PersistingVoteRepo {
  @override
  Future<List<Smaczek>> fetchSmaczki(String questionId) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return const [
      Smaczek(
        position: 1,
        isLocked: false,
        side: SmaczekSide.neutral,
        text: 'Odpowiedziałeś od razu. Ile z tego było decyzją?',
      ),
    ];
  }
}

/// The first-write-wins server: whatever side is cast, the vote already on
/// record is TAK, and the RPC answers with THAT in `my_choice`. Its two
/// arguments are tagged one per side, so which one the gate throws says
/// exactly which choice the panel believed.
class _StoredChoiceRepo extends MockQuestionRepository {
  int? lastChoice;
  int? challengedPosition;

  static const _stored = VoteResult(
    yesCount: 80,
    noCount: 20,
    myChoice: VoteResult.yes,
  );

  @override
  Future<VoteResult> getDailyVoteState(String questionId) async =>
      VoteResult.empty;

  @override
  Future<VoteResult> castDailyVote(String questionId, int choice) async {
    lastChoice = choice;
    return _stored;
  }

  @override
  Future<List<Smaczek>> fetchSmaczki(String questionId) async => const [
    Smaczek(
      position: 1,
      isLocked: false,
      side: SmaczekSide.attacksYes,
      text: 'Powiedziałeś tak. Komu to było wygodne?',
    ),
    Smaczek(
      position: 2,
      isLocked: false,
      side: SmaczekSide.attacksNo,
      text: 'Powiedziałeś nie. Co takiego chronisz?',
    ),
  ];

  @override
  Future<VoteResult> recordSmaczekChallenge({
    required String questionId,
    required int position,
    required ChallengeOutcome outcome,
    int? dwellMs,
  }) async {
    challengedPosition = position;
    return _stored;
  }
}

/// A session fixed to a known identity, so the account/guest branch can be
/// exercised without touching Supabase.
class _FakeSession extends SessionNotifier {
  _FakeSession(this._state);

  final SessionState _state;

  @override
  Future<SessionState> build() async => _state;
}

/// Mock repo with a controllable initial vote state and a recorded cast.
class _VotePanelRepo extends MockQuestionRepository {
  _VotePanelRepo({required this.initial});

  final VoteResult initial;
  VoteResult? castReturns;
  int castCalls = 0;
  int? lastChoice;

  @override
  Future<VoteResult> getDailyVoteState(String questionId) async => initial;

  @override
  Future<VoteResult> castDailyVote(String questionId, int choice) async {
    castCalls++;
    lastChoice = choice;
    return castReturns ??
        VoteResult(
          yesCount: choice == VoteResult.yes ? 60 : 40,
          noCount: choice == VoteResult.no ? 60 : 40,
          myChoice: choice,
        );
  }
}
