import 'package:debatly/features/onboarding/screens/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/localized_test_app.dart';

/// The onboarding "aha" is a mind-change loop: the user votes on a real
/// question, is stopped with "Ale chwila…" and three arguments, votes again,
/// and only then sees the community split. Then "Dalej" carries them onwards to
/// the reminder ask and the account choice.
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

  // The arguments takeover runs a 3.6s staggered entrance ("Ale chwila…", a
  // beat of silence, one argument per second, then the button); pump all the
  // way past it so the "Głosuję jeszcze raz" CTA is visible and tappable.
  Future<void> settleArguments(WidgetTester tester) async {
    await settlePage(tester); // the 280ms stage cross-fade
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump(const Duration(milliseconds: 1000));
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

  // Walks the whole taste loop: first vote → arguments → "Przeczytałem" →
  // second vote. Lands on the split reveal (50/50 in the test host).
  Future<void> completeTasteLoop(
    WidgetTester tester, {
    String first = 'TAK',
    String second = 'TAK',
  }) async {
    await tester.tap(find.text(first));
    await settleArguments(tester);
    await tapText(tester, 'Przeczytane!');
    await settlePage(tester);
    // The revote stage (question + prompt + buttons) is taller than the test
    // viewport, so the buttons sit below the fold — scroll them in first.
    await tapText(tester, second);
    await settlePage(tester);
  }

  testWidgets('the first vote hides the split and shows the three arguments', (
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
    // chwila…" and the three arguments, with the question and kicker gone.
    expect(find.textContaining('%'), findsNothing);
    expect(find.text('TWÓJ RUCH'), findsNothing);
    expect(find.text('Ale chwila…'), findsOneWidget);
    expect(find.textContaining('walizkę'), findsOneWidget);
    expect(find.textContaining('komfortem'), findsOneWidget);
    expect(find.textContaining('bramka'), findsOneWidget);
    expect(find.text('Przeczytane!'), findsOneWidget);
  });

  testWidgets('after reading, the user votes again and the split is '
      'revealed', (tester) async {
    await pumpOnboarding(tester);
    await reachVotePage(tester);

    await tester.tap(find.text('TAK'));
    await settleArguments(tester);
    await tapText(tester, 'Przeczytane!');
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

  testWidgets('Continue after the reveal advances to the notifications ask, '
      'then the account choice', (tester) async {
    await pumpOnboarding(tester);
    await reachVotePage(tester);
    await completeTasteLoop(tester);

    // The card's own "Dalej" (the bottom Next is suppressed on this page)
    // lands on the reminder opt-in, not yet the account choice.
    await tapText(tester, 'Dalej');
    await settlePage(tester);

    expect(find.text('Jutro czeka nowe pytanie'), findsOneWidget);
    expect(find.text('Włącz przypomnienia'), findsOneWidget);
    expect(find.text('Zacznij anonimowo'), findsNothing);

    // "Not now" carries the user on to the account choice without enabling.
    await tapText(tester, 'Nie teraz');
    await settlePage(tester);

    expect(find.text('Zacznij anonimowo'), findsOneWidget);
    expect(find.text('Zaloguj / Załóż konto'), findsOneWidget);
  });

  testWidgets('the reminder ask never traps the user — "Enable" advances even '
      'when the notification plugin is unavailable', (tester) async {
    // The native plugin no-ops in the test host, so the permission request
    // resolves false; the card must still carry the user to the account choice
    // rather than stalling on its busy spinner.
    await pumpOnboarding(tester);
    await reachVotePage(tester);
    await completeTasteLoop(tester);
    await tapText(tester, 'Dalej'); // taste result → reminder ask
    await settlePage(tester);

    await tapText(tester, 'Włącz przypomnienia');
    await settlePage(tester);

    expect(find.text('Zacznij anonimowo'), findsOneWidget);
  });
}
