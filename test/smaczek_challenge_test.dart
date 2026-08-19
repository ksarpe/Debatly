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
///   * "trzymam się" and "to mnie ruszyło" report distinct outcomes, and the
///     dwell (argument landed → tap) rides along, because without it every
///     future decision about this mechanic is guesswork;
///   * the vote is FINAL: no outcome re-casts anything (the caller merely
///     records the answer on a separate axis);
///   * system back is never a trap: it resolves as "dismissed" — an exit, not
///     an answer — and the result appears anyway;
///   * the compact beat (gates 2 and 3 of a session) shows the text whole and
///     the buttons straight away, so the ~1s of falling words is cut while the
///     hit itself stays.
void main() {
  const smaczek = Smaczek(
    position: 1,
    isLocked: false,
    side: SmaczekSide.attacksYes,
    text: 'Twoje DNA wyda też krewnych którzy się nie zgodzili',
  );

  /// Records what the challenge reported back, so a test can assert on the
  /// value the vote panel would act on.
  final reported = <SmaczekChallengeResult>[];

  setUp(reported.clear);

  /// Pumps a host screen and opens the challenge from it, WITHOUT settling —
  /// the caller decides how far into the falling words to pump.
  Future<void> open(
    WidgetTester tester, {
    int choice = VoteResult.yes,
    bool compact = false,
  }) async {
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
                    compact: compact,
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
    expect(find.text('TO MNIE RUSZYŁO'), findsOneWidget);
  });

  testWidgets('holding the ground reports "held" with a measured dwell', (
    tester,
  ) async {
    await open(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('TRZYMAM SIĘ'));
    await tester.pumpAndSettle();
    expect(reported, hasLength(1));
    expect(reported.single.outcome, ChallengeOutcome.held);
    expect(
      reported.single.dwellMs,
      isNotNull,
      reason: 'the dwell clock starts when the argument lands',
    );
    expect(reported.single.dwellMs, isNonNegative);
  });

  testWidgets('"to mnie ruszyło" reports "moved" — nothing more', (
    tester,
  ) async {
    await open(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('TO MNIE RUSZYŁO'));
    await tester.pumpAndSettle();
    expect(reported, hasLength(1));
    expect(reported.single.outcome, ChallengeOutcome.moved);
  });

  testWidgets('system back is not a trap — it resolves as "dismissed"', (
    tester,
  ) async {
    await open(tester);
    await tester.pumpAndSettle();

    // The route refuses the pop and resolves itself instead, so the caller
    // still gets an outcome and goes on to show the split. Dismissed is kept
    // apart from "held": an exit must not pollute the resilience statistic.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(reported, hasLength(1));
    expect(reported.single.outcome, ChallengeOutcome.dismissed);
  });

  testWidgets('the compact beat shows the text whole, buttons right away', (
    tester,
  ) async {
    await open(tester, compact: true);

    // One frame past the route transition: no falling words to wait out — the
    // whole argument is on screen and the answers are already tappable.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      1,
      reason: 'compact gates do not make the user wait for the buttons',
    );

    await tester.tap(find.text('TRZYMAM SIĘ'));
    await tester.pumpAndSettle();
    expect(reported.single.outcome, ChallengeOutcome.held);
  });
}
