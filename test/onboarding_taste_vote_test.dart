import 'package:debatly/features/onboarding/screens/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/localized_test_app.dart';

/// The onboarding "aha" is a mind-change loop run twice: the user votes on a
/// real question, is stopped with "Ale chwila…" and four arguments, votes
/// again, and only then sees the community split. "Dalej" then rolls through
/// the "Spróbujmy z kolejnym…" interlude into a second question with the same
/// loop (its takeover titled "Czy aby na pewno?"), and only after that second
/// reveal does "Dalej" carry them onwards — first to the catalog pitch ("A
/// takich pytań mamy ponad 500"), then to the reminder ask, the last card
/// before the home gate (the hard paywall).
///
/// The split is live in production (fetched off the question's all-time tally);
/// in the test host Supabase is uninitialised, so the card renders its curated
/// dead-even fallback — which is what the assertions below pin.
///
/// The welcome card animates a perpetual glow, so `pumpAndSettle` never returns —
/// every step uses explicit `pump`s past the page/switcher transitions instead
/// (the same pattern as widget_test's onboarding flow).
void main() {
  // The page transition is 320ms; pump comfortably past it. A second timed pump
  // lets the PageView's post-animation ballistic settle finish — until that
  // frame lands the incoming page's buttons stay non-hit-testable, so a tap on
  // the freshly-arrived taste card would silently miss. (pumpAndSettle can't be
  // used here: the welcome card's perpetual glow means it never returns.)
  Future<void> settlePage(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  // The arguments takeover runs a 5.6s staggered entrance (the title, a beat
  // of silence, one argument per second, a second of silence, then the
  // button); pump all the way past it so the "Dobra, głosuję!" CTA is visible
  // and tappable.
  Future<void> settleArguments(WidgetTester tester) async {
    await settlePage(tester); // the 280ms stage cross-fade
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 1000));
    }
  }

  Future<void> pumpOnboarding(WidgetTester tester) async {
    await tester.pumpWidget(
      LocalizedTestApp(home: OnboardingScreen(onFinish: () {})),
    );
    await settlePage(tester);
  }

  // The taller stages (arguments, result, reminder) overflow the 600px test
  // viewport, so their bottom CTAs render below the fold inside the card's
  // scroll view — scroll them in first, or the tap lands off-screen and misses.
  Future<void> tapText(WidgetTester tester, String label) async {
    final finder = find.text(label);
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
  }

  // Walks welcome → the taste-vote page via the bottom "Next" CTA. The vote is
  // deliberately one swipe from the welcome card — nothing stands before the aha.
  Future<void> reachVotePage(WidgetTester tester) async {
    await tester.tap(find.text('Dalej')); // welcome → taste vote
    await settlePage(tester);
  }

  // Walks one round of the taste loop: first vote → arguments →
  // "Dobra, głosuję!" → second vote. Lands on the split reveal (50/50 in the
  // test host).
  Future<void> completeTasteLoop(
    WidgetTester tester, {
    String first = 'TAK',
    String second = 'TAK',
  }) async {
    await tapText(tester, first);
    await settleArguments(tester);
    await tapText(tester, 'Dobra, głosuję!');
    await settlePage(tester);
    // The revote stage (question + prompt + buttons) is taller than the test
    // viewport, so the buttons sit below the fold — scroll them in first.
    await tapText(tester, second);
    await settlePage(tester);
  }

  // Round one's "Dalej" rolls into the "Spróbujmy z kolejnym…" interlude,
  // which auto-advances into round two's question after two seconds.
  Future<void> passInterlude(WidgetTester tester) async {
    await tapText(tester, 'Dalej');
    await settlePage(tester);
    expect(find.text('Spróbujmy z kolejnym…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await settlePage(tester);
  }

  testWidgets('the taste-vote page cannot be swiped away — the deck only '
      'moves via the vote loop (or "Skip")', (tester) async {
    await pumpOnboarding(tester);
    await reachVotePage(tester);
    expect(find.text('TWÓJ RUCH'), findsOneWidget);

    // A hard forward swipe must not reach the catalog pitch, and a backward
    // one must not return to the welcome card — the page is a gate.
    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await settlePage(tester);
    expect(find.text('TWÓJ RUCH'), findsOneWidget);
    expect(find.text('A takich pytań mamy ponad 500'), findsNothing);

    await tester.drag(find.byType(PageView), const Offset(400, 0));
    await settlePage(tester);
    expect(find.text('TWÓJ RUCH'), findsOneWidget);
  });

  testWidgets('the first vote hides the split and shows the four arguments', (
    tester,
  ) async {
    await pumpOnboarding(tester);
    await reachVotePage(tester);

    // The taste page: kicker + the TAK/NIE buttons, and crucially NO split yet.
    expect(find.text('TWÓJ RUCH'), findsOneWidget);
    expect(find.text('TAK'), findsOneWidget);
    expect(find.text('NIE'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);

    await tester.tap(find.text('TAK'));
    await settleArguments(tester);

    // No reveal yet — the takeover replaces the question entirely: just "Ale
    // chwila…" and the four arguments, with the question and kicker gone.
    expect(find.textContaining('%'), findsNothing);
    expect(find.text('TWÓJ RUCH'), findsNothing);
    expect(find.text('Ale chwila…'), findsOneWidget);
    expect(find.textContaining('walizki'), findsOneWidget);
    expect(find.textContaining('komfortem'), findsOneWidget);
    expect(find.textContaining('Bramka'), findsOneWidget);
    expect(find.textContaining('chorobę'), findsOneWidget);
    expect(find.text('Dobra, głosuję!'), findsOneWidget);
  });

  testWidgets('after reading, the user votes again and the split is '
      'revealed', (tester) async {
    await pumpOnboarding(tester);
    await reachVotePage(tester);

    await tester.tap(find.text('TAK'));
    await settleArguments(tester);
    await tapText(tester, 'Dobra, głosuję!');
    await settlePage(tester);

    // The question returns for the second ask: the kicker flips to "ZAGŁOSUJ
    // PONOWNIE" over fresh TAK/NIE buttons, still no split.
    expect(find.text('ZAGŁOSUJ PONOWNIE'), findsOneWidget);
    expect(find.text('TWÓJ RUCH'), findsNothing);
    expect(find.textContaining('%'), findsNothing);

    await tapText(tester, 'NIE'); // changing sides is allowed
    await settlePage(tester);

    // The reveal: the split (the fallback 50/50 here) with the "VS" seam and
    // the check on the chosen side — and nothing else under the bars.
    expect(find.text('50%'), findsNWidgets(2));
    expect(find.text('VS'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  // The bridge between the taste card and the reminder ask: it explains the
  // freemium model and carries its own CTAs (the deck's bottom "Dalej" is
  // suppressed there) — the dominant one continues for free.
  Future<void> passBridge(WidgetTester tester) async {
    expect(find.text('To były dwa. Zostało 500.'), findsOneWidget);
    expect(find.text('Odblokuj wszystkie 500'), findsOneWidget);
    await tapText(tester, 'Odbierz dzisiejsze pytanie');
    await settlePage(tester);
  }

  testWidgets('Continue after the reveal advances to the bridge and '
      'then the notifications ask, and "Not now" finishes onboarding', (
    tester,
  ) async {
    var finished = 0;
    await tester.pumpWidget(
      LocalizedTestApp(home: OnboardingScreen(onFinish: () => finished++)),
    );
    await settlePage(tester);
    await reachVotePage(tester);
    await completeTasteLoop(tester);

    // Round one's "Dalej" leads not out of the card but into round two: the
    // interlude, then the second question under the "Czy aby na pewno?"
    // takeover, walked with the same loop.
    await passInterlude(tester);
    expect(find.text('TWÓJ RUCH'), findsOneWidget);
    // The question renders uppercased, word by word, each word as a stacked
    // stroke + fill Text pair — hence uppercase and findsWidgets, not one.
    expect(find.textContaining('ILOMA'), findsWidgets);
    await tapText(tester, 'TAK');
    await settleArguments(tester);
    expect(find.text('Czy aby na pewno?'), findsOneWidget);
    await tapText(tester, 'Dobra, głosuję!');
    await settlePage(tester);
    await tapText(tester, 'NIE');
    await settlePage(tester);

    // The card's own "Dalej" (the bottom Next is suppressed on this page)
    // lands on the bridge, and its primary CTA on the reminder opt-in —
    // the final card, no account step follows.
    await tapText(tester, 'Dalej');
    await settlePage(tester);
    await passBridge(tester);

    expect(find.text('Jutro czeka nowe pytanie'), findsOneWidget);
    expect(find.text('Włącz przypomnienia'), findsOneWidget);
    expect(finished, 0);

    // "Not now" ends the tutorial without enabling — the home gate (the feed
    // with today's daily) is next.
    await tapText(tester, 'Nie teraz');
    await settlePage(tester);

    expect(finished, 1);
  });

  testWidgets('the reminder ask never traps the user — "Enable" finishes even '
      'when the notification plugin is unavailable', (tester) async {
    // The native plugin no-ops in the test host, so the permission request
    // resolves false; the card must still end the tutorial rather than
    // stalling on its busy spinner.
    var finished = 0;
    await tester.pumpWidget(
      LocalizedTestApp(home: OnboardingScreen(onFinish: () => finished++)),
    );
    await settlePage(tester);
    await reachVotePage(tester);
    await completeTasteLoop(tester); // round one
    await passInterlude(tester);
    await completeTasteLoop(tester); // round two
    await tapText(tester, 'Dalej'); // taste result → the bridge
    await settlePage(tester);
    await passBridge(tester); // → reminder ask

    await tapText(tester, 'Włącz przypomnienia');
    await settlePage(tester);

    expect(finished, 1);
  });
}
