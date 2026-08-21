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
///   * "zostawiam" and "zmieniam zdanie" report distinct outcomes, and the
///     dwell (gate opened → tap) rides along, because without it every future
///     decision about this mechanic is guesswork — and it counts the fall,
///     which is the second the user spends reading;
///   * the vote is FINAL: no outcome re-casts anything (the caller merely
///     records the answer on a separate axis);
///   * system back is never a trap: it resolves as "dismissed" — an exit, not
///     an answer — and the result appears anyway;
///   * the compact beat (every gate after the first) shows the text whole and
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
    expect(find.text('ZOSTAWIAM'), findsOneWidget);
    expect(find.text('ZMIENIAM ZDANIE'), findsOneWidget);
    // The old TAK/NIE tiles are gone — a muted line states the recorded side
    // instead, so nothing under the argument looks like a re-vote.
    expect(
      find.text('Wcześniej zagłosowałeś na TAK. Jak teraz brzmi Twoje zdanie?'),
      findsOneWidget,
    );
  });

  testWidgets('holding the ground reports "held" with a measured dwell', (
    tester,
  ) async {
    await open(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('ZOSTAWIAM'));
    await tester.pumpAndSettle();
    expect(reported, hasLength(1));
    expect(reported.single.outcome, ChallengeOutcome.held);
    expect(
      reported.single.dwellMs,
      isNotNull,
      reason: 'an answered gate always carries its dwell',
    );
    expect(reported.single.dwellMs, isNonNegative);
  });

  testWidgets('the dwell counts the fall, not just the pause after it', (
    tester,
  ) async {
    // The falling words ARE the reading: ~1.1s of it on this 9-word argument.
    // Measuring only the hesitation after the last word landed filed honest
    // readers as `skipped_fast` (server minimum 1500 ms) and locked their
    // debate profile with no way to find out why.
    await open(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ZOSTAWIAM'));
    await tester.pumpAndSettle();

    // 9 words: 90 ms of stagger each past the first, plus one 380 ms fall.
    expect(
      reported.single.dwellMs,
      greaterThanOrEqualTo(90 * 8 + 380),
      reason: 'the clock starts when the gate opens, not when the words land',
    );
  });

  testWidgets('"zmieniam zdanie" reports "moved" — nothing more', (
    tester,
  ) async {
    await open(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('ZMIENIAM ZDANIE'));
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

    await tester.tap(find.text('ZOSTAWIAM'));
    await tester.pumpAndSettle();
    expect(reported.single.outcome, ChallengeOutcome.held);
  });
}
