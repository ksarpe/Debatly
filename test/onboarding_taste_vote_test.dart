import 'package:debatly/features/onboarding/screens/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/localized_test_app.dart';

/// The onboarding "aha" is a mind-change loop run twice: the user votes, is
/// stopped by the takeover ("Ale chwila…" in round one, "Czy aby na pewno?"
/// in round two) with four COUNTER-arguments (the pool depends on the side
/// they picked), then declares a stance — "Zmieniam zdanie" or "Zostaję przy
/// swoim" — and lands straight on the split under a stance-aware headline.
/// Round one's "Zobaczmy kolejne" rolls through the "Spróbujmy z kolejnym…"
/// interlude into round two; round two's reveal teases the catalog and its
/// "Co jeszcze macie?" carries them onwards — to the bridge that answers it
/// ("To były dwa. Zostało 500."), then the reminder ask, the last card before
/// the home gate.
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
  // button); pump all the way past it so the "Głosuję jeszcze raz!" CTA is visible
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

  // Walks welcome → the taste-vote page via the bottom "Zaczynajmy" CTA. The
  // vote is deliberately one swipe from the welcome card — nothing stands
  // before the aha. The welcome entrance staggers the copy over 4s and the
  // CTA ignores taps until its fade begins at 3.5s, so pump past the whole
  // timeline first.
  Future<void> reachVotePage(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 1000));
    }
    // The ACTION buttons render uppercased in the widgets, so every button
    // finder below matches the on-screen casing.
    await tester.tap(find.text('ZACZYNAJMY')); // welcome → taste vote
    await settlePage(tester);
  }

  // Walks one round: first vote → counter-arguments → the stance choice
  // ("Zmieniam zdanie" / "Zostaję przy swoim"), which lands straight on the
  // split reveal (50/50 in the test host) — there is no re-vote.
  Future<void> completeStanceRound(
    WidgetTester tester, {
    String vote = 'TAK',
    bool changeMind = true,
  }) async {
    await tapText(tester, vote);
    await settleArguments(tester);
    await tapText(
      tester,
      changeMind ? 'ZMIENIAM ZDANIE' : 'ZOSTAJĘ PRZY SWOIM',
    );
    await settlePage(tester);
  }

  // Round one's "Zobaczmy kolejne" rolls into the "Spróbujmy z kolejnym…"
  // interlude, which auto-advances into round two's question after two
  // seconds.
  Future<void> passInterlude(WidgetTester tester) async {
    await tapText(tester, 'ZOBACZMY KOLEJNE');
    await settlePage(tester);
    expect(find.text('SPRÓBUJMY Z KOLEJNYM…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await settlePage(tester);
  }

  testWidgets('the taste-vote page cannot be swiped away — the deck only '
      'moves via the vote loop', (tester) async {
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

  testWidgets('a TAK vote hides the split and serves the counter-NIE '
      'argument pool with the stance pair', (tester) async {
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
    // chwila…" (a TITLE, rendered uppercase) and four arguments AGAINST the
    // TAK just cast, closed by the stance pair instead of a re-vote button.
    expect(find.textContaining('%'), findsNothing);
    expect(find.text('TWÓJ RUCH'), findsNothing);
    expect(find.text('ALE CHWILA…'), findsOneWidget);
    expect(find.textContaining('centymetry'), findsOneWidget);
    expect(find.textContaining('Wysoki'), findsOneWidget);
    expect(find.textContaining('Bramka'), findsOneWidget);
    expect(find.textContaining('chorobę'), findsOneWidget);
    expect(find.text('ZMIENIAM ZDANIE'), findsOneWidget);
    expect(find.text('ZOSTAJĘ PRZY SWOIM'), findsOneWidget);
    expect(find.text('GŁOSUJĘ JESZCZE RAZ!'), findsNothing);
  });

  testWidgets('a tap during the arguments takeover fast-forwards the 5.6s '
      'stagger — the stance pair is tappable right away', (tester) async {
    await pumpOnboarding(tester);
    await reachVotePage(tester);

    await tester.tap(find.text('TAK'));
    await settlePage(tester); // the 280ms stage cross-fade, ~800ms into 5.6s

    // Mid-stagger the stance pair is still ignoring taps (its interval starts
    // at 5.3s). A tap anywhere on the takeover — no control claims it — makes
    // the card sprint the run to its resting frame in ~300ms.
    await tester.tapAt(tester.getCenter(find.byType(OnboardingScreen)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Well before the 5.6s timeline the stance choice already works.
    await tapText(tester, 'ZMIENIAM ZDANIE');
    await settlePage(tester);
    expect(find.textContaining('MAMY'), findsWidgets);
  });

  testWidgets('a NIE vote serves the counter-TAK argument pool', (
    tester,
  ) async {
    await pumpOnboarding(tester);
    await reachVotePage(tester);

    await tester.tap(find.text('NIE'));
    await settleArguments(tester);

    expect(find.text('ALE CHWILA…'), findsOneWidget);
    expect(find.textContaining('walizki'), findsOneWidget);
    expect(find.textContaining('komfortem'), findsOneWidget);
    expect(find.textContaining('pali więcej'), findsOneWidget);
    expect(find.textContaining('wciśnięty'), findsOneWidget);
    // None of the counter-NIE pool leaks in.
    expect(find.textContaining('centymetry'), findsNothing);
  });

  testWidgets('"Zmieniam zdanie" skips the re-vote and reveals the split '
      'under the gotcha headline', (tester) async {
    await pumpOnboarding(tester);
    await reachVotePage(tester);

    await tester.tap(find.text('TAK'));
    await settleArguments(tester);
    await tapText(tester, 'ZMIENIAM ZDANIE');
    await settlePage(tester);

    // Straight to the reveal — no "ZAGŁOSUJ PONOWNIE" ask. The headline
    // renders in the question font (uppercased, stroke + fill Text pairs —
    // hence textContaining and findsWidgets), with the small nudge line under
    // it, the 50/50 fallback split, and "Zobaczmy kolejne".
    expect(find.text('ZAGŁOSUJ PONOWNIE'), findsNothing);
    expect(find.textContaining('MAMY'), findsWidgets);
    expect(find.text('Zobacz, jak głosowali inni.'), findsOneWidget);
    expect(find.text('50%'), findsNWidgets(2));
    expect(find.text('VS'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.text('ZOBACZMY KOLEJNE'), findsOneWidget);
  });

  testWidgets('"Zostaję przy swoim" reveals the split under the respectful '
      'headline', (tester) async {
    await pumpOnboarding(tester);
    await reachVotePage(tester);

    await tester.tap(find.text('TAK'));
    await settleArguments(tester);
    await tapText(tester, 'ZOSTAJĘ PRZY SWOIM');
    await settlePage(tester);

    expect(find.textContaining('STANOWISKO'), findsWidgets);
    expect(find.text('Ale zobacz, jak głosowali inni.'), findsOneWidget);
    expect(find.text('50%'), findsNWidgets(2));
    expect(find.text('ZOBACZMY KOLEJNE'), findsOneWidget);
  });

  // The bridge between the taste card and the reminder ask: it explains the
  // freemium model and carries its own CTAs (the deck's bottom "Dalej" is
  // suppressed there) — the dominant one continues for free.
  Future<void> passBridge(WidgetTester tester) async {
    expect(find.text('TO BYŁY DWA — A ZOSTAŁY JESZCZE SETKI'), findsOneWidget);
    expect(find.text('ODBLOKUJ WSZYSTKIE'), findsOneWidget);
    await tapText(tester, 'ODBIERZ DZISIEJSZE PYTANIE');
    await settlePage(tester);
  }

  testWidgets('Continue after the reveal advances to the bridge and '
      'then the notifications ask, and "Maybe later" finishes onboarding', (
    tester,
  ) async {
    var finished = 0;
    await tester.pumpWidget(
      LocalizedTestApp(home: OnboardingScreen(onFinish: () => finished++)),
    );
    await settlePage(tester);
    await reachVotePage(tester);
    await completeStanceRound(tester);

    // Round one's "Zobaczmy kolejne" leads not out of the card but into round
    // two: the interlude, then the second question under the "Czy aby na
    // pewno?" takeover — same stance mechanic, its own counter-pool.
    await passInterlude(tester);
    expect(find.text('TWÓJ RUCH'), findsOneWidget);
    // The question renders uppercased, word by word, each word as a stacked
    // stroke + fill Text pair — hence uppercase and findsWidgets, not one.
    expect(find.textContaining('ILOMA'), findsWidgets);
    await tapText(tester, 'TAK');
    await settleArguments(tester);
    expect(find.text('CZY ABY NA PEWNO?'), findsOneWidget);
    // The counter-TAK pool for question two (arguing against telling).
    expect(find.textContaining('setka'), findsOneWidget);
    await tapText(tester, 'ZMIENIAM ZDANIE');
    await settlePage(tester);

    // Round two's reveal sells the catalog: the "nothing is obvious" headline
    // (question font — uppercased word pairs) with the "only question two"
    // teaser, and its "Co jeszcze macie?" (the bottom Next is suppressed on
    // this page) lands on the bridge — whose title answers it — and the
    // bridge's primary CTA on the reminder opt-in, the final card.
    expect(find.textContaining('OCZYWISTE'), findsWidgets);
    expect(find.text('A to było dopiero drugie pytanie…'), findsOneWidget);
    await tapText(tester, 'CO JESZCZE MACIE?');
    await settlePage(tester);
    await passBridge(tester);

    expect(find.text('HEJ, JESZCZE JEDNO'), findsOneWidget);
    expect(find.text('WŁĄCZ PRZYPOMNIENIA'), findsOneWidget);
    expect(finished, 0);

    // "Maybe later" ends the tutorial without enabling — the home gate (the
    // feed with today's daily) is next.
    await tapText(tester, 'MOŻE PÓŹNIEJ');
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
    await completeStanceRound(tester); // round one
    await passInterlude(tester);
    // Round two, holding the line this time — the respectful teaser reveal.
    await completeStanceRound(tester, changeMind: false);
    expect(find.text('Sprawdzimy. Pytań nam nie zabraknie…'), findsOneWidget);
    await tapText(tester, 'CO JESZCZE MACIE?'); // taste result → the bridge
    await settlePage(tester);
    await passBridge(tester); // → reminder ask

    await tapText(tester, 'WŁĄCZ PRZYPOMNIENIA');
    await settlePage(tester);

    expect(finished, 1);
  });
}
