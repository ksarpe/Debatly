import 'package:debatly/data/models/smaczek.dart';
import 'package:debatly/data/models/vote_result.dart';
import 'package:debatly/features/questions/widgets/smaczek_challenge_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/localized_test_app.dart';

/// The gate between a vote and the community split.
///
/// What has to hold for the mechanic to work at all:
///   * the argument is on screen, and the two answers to it only appear once it
///     has finished landing — answering before the hit lands is the one way to
///     make the whole beat pointless;
///   * "trzymam się" and "hmm, jednak nie" report distinct outcomes, because a
///     flip is what re-casts the user's vote;
///   * system back is never a trap: it resolves as "held" and the result
///     appears, so a confused user keeps the answer they already gave.
void main() {
  const smaczek = Smaczek(
    position: 1,
    isLocked: false,
    side: SmaczekSide.attacksYes,
    text: 'Twoje DNA wyda też krewnych którzy się nie zgodzili',
  );

  /// Records what the challenge reported back, so a test can assert on the
  /// value the vote panel would act on.
  final reported = <ChallengeOutcome>[];

  setUp(reported.clear);

  /// Pumps a host screen and opens the challenge from it, WITHOUT settling —
  /// the caller decides how far into the falling words to pump.
  Future<void> open(WidgetTester tester, {int choice = VoteResult.yes}) async {
    await tester.pumpWidget(
      LocalizedTestApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async => reported.add(
                  await showSmaczekChallenge(
                    context,
                    smaczek: smaczek,
                    choice: choice,
                  ),
                ),
                child: const Text('start'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('start'));
  }

  testWidgets('the argument lands before the answers can be given', (
    tester,
  ) async {
    await open(tester);

    // Mid-flight: the route is up and the words are still falling, so neither
    // answer is tappable yet.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('ZANIM POKAŻĘ WYNIK'), findsOneWidget);
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      0,
      reason: 'the answers stay hidden until the argument has hit',
    );

    await tester.pumpAndSettle();
    expect(find.text('TRZYMAM SIĘ'), findsOneWidget);
    expect(find.text('HMM, JEDNAK NIE'), findsOneWidget);
  });

  testWidgets('holding the ground reports "held"', (tester) async {
    await open(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('TRZYMAM SIĘ'));
    await tester.pumpAndSettle();
    expect(reported, [ChallengeOutcome.held]);
  });

  testWidgets('changing your mind reports "flipped"', (tester) async {
    await open(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('HMM, JEDNAK NIE'));
    await tester.pumpAndSettle();
    expect(reported, [ChallengeOutcome.flipped]);
  });

  testWidgets('system back is not a trap — it keeps the answer already given', (
    tester,
  ) async {
    await open(tester);
    await tester.pumpAndSettle();

    // The route refuses the pop and resolves itself instead, so the caller
    // still gets an outcome and goes on to show the split.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(reported, [ChallengeOutcome.held]);
  });
}
