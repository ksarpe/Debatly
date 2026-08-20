// End-to-end smoke test: boot the real app widget tree and walk the paths a
// human otherwise has to re-click by hand after every release, against the
// in-memory mock data with no SDK keys.
//
// What it covers (the ids are the cases in TESTY_MANUALNE.md):
//   * the daily loop — splash → daily → vote → contra gate → split (B1, B3)
//   * the smaczki sheet's vote gate — the pill answers with the hook (B5)
//   * the free day wall — forward swipe lands on it, back leaves it (C1)
//   * the wall's paywall rules — never before the vote, once after it (C2, C3)
//   * PRO and the shared daily — the pill on it, the jump link back to it (B9)
//   * sign-out — the settings hub falls back to its guest shape (E7)
//
// Why this lives here and not in test/: `flutter test` only scans test/, so this
// stays out of the unit suite (and CI) and is run on demand —
//   flutter test integration_test/app_smoke_test.dart
// It runs on the desktop host (flutter_tester) since nothing here touches a real
// platform channel, and on a connected device/emulator with `-d <device>`. See
// CONTRIBUTING.md → "Integration smoke test".
//
// It pumps the genuine [DebatlyApp] (the same `home: AppEntry()` launch state
// machine `main()` boots) rather than a stubbed screen, so the splash timer, the
// AppEntry → QuestionScreen routing, the mock repository's simulated delays and
// the real gestures are all exercised. Three overrides keep it deterministic and
// hermetic — everything else is the real tree:
//   * [sharedPreferencesProvider] — an in-memory store pinned to Polish with
//     onboarding marked complete, so AppEntry behaves like a returning user and
//     drops straight to the daily (no first-run tutorial) and the Polish strings
//     asserted below render regardless of the host device language. Fresh per
//     test, which is what makes the wall's once-per-local-day paywall latch
//     observable from both sides;
//   * [sessionProvider] — a signed-in account of the tier each test needs
//     ([_SmokeSession], free by default). Without SDK keys the real session
//     resolves to premium (mock mode is premium), and a premium user never
//     meets the day wall at all. Pinning the tier is the minimal seam that puts
//     both decks on screen — free's `[daily]`, PRO's daily-plus-catalog —
//     exactly as the widget tests do;
//   * [questionRepositoryProvider] — [_VoteRememberingMockRepo], the stock
//     [MockQuestionRepository] with one hole plugged: its `getDailyVoteState`
//     always answers "not voted", so the vote the UI just cast evaporates on the
//     re-read that follows it. The wall's auto-paywall rule reads exactly that
//     provider ("has today's daily been voted on?"), so without this the
//     after-the-vote leg could never be true. Nothing else about the repository
//     changes.
import 'package:debatly/app.dart';
import 'package:debatly/core/locale/app_locale.dart';
import 'package:debatly/data/models/vote_result.dart';
import 'package:debatly/data/repositories/question_repository.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/monetization/widgets/day_wall_view.dart';
import 'package:debatly/features/monetization/widgets/pro_paywall_screen.dart';
import 'package:debatly/features/onboarding/providers/onboarding_providers.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:debatly/features/questions/widgets/daily_question_badge.dart';
import 'package:debatly/features/questions/widgets/falling_words_text.dart';
import 'package:debatly/features/questions/widgets/go_deeper_button.dart';
import 'package:debatly/features/questions/widgets/wind_question_view.dart';
import 'package:debatly/features/settings/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory SharedPreferences pinned to Polish, with onboarding already
/// complete so [AppEntry] routes the post-splash phase straight to the daily
/// (the first-run tutorial has its own coverage in test/widget_test.dart). The
/// pinned locale makes the Polish assertions below deterministic on any host.
Future<SharedPreferences> _mockPrefs() async {
  SharedPreferences.setMockInitialValues({
    kLocalePrefKey: 'pl',
    kOnboardingCompletePrefKey: true,
  });
  return SharedPreferences.getInstance();
}

/// Boots the real app as a returning account and leaves it on the daily.
///
/// [premium] picks the tier, which is what picks the DECK: free is `[daily]`
/// (the day wall stands where the catalog would continue), PRO is the daily
/// followed by the whole catalog — the only shape in which the jump back to
/// the daily can exist at all.
Future<void> _pumpAppToDaily(
  WidgetTester tester, {
  bool premium = false,
}) async {
  final prefs = await _mockPrefs();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        sessionProvider.overrideWith(() => _SmokeSession(premium: premium)),
        questionRepositoryProvider.overrideWithValue(
          _VoteRememberingMockRepo(),
        ),
      ],
      child: const DebatlyApp(),
    ),
  );

  // Pass the splash, then let the mock repository's simulated delays resolve so
  // the daily question paints.
  await _passSplash(tester);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

/// Pumps past the launch splash so the routed-to daily is on screen. Driven by
/// fixed pumps rather than `pumpAndSettle` because the splash logo runs a looping
/// glow that never settles; once on the question screen the streak flame is still
/// (streak 0) so `pumpAndSettle` is safe again.
Future<void> _passSplash(WidgetTester tester) async {
  await tester.pump(); // first frame: the splash
  await tester.pump(const Duration(milliseconds: 2000)); // splash timer fires
  await tester.pump(const Duration(milliseconds: 500)); // phase cross-fade
}

/// Bounded pumps, for everything downstream of the day wall: the wall runs a
/// 1-second countdown timer, so `pumpAndSettle` would chase a clock that never
/// stops ticking.
Future<void> _pumpABit(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

/// A forward (leftward) fling on the feed — off the daily, which for a free
/// account is the whole deck.
Future<void> _swipeForward(WidgetTester tester) async {
  await tester.fling(
    find.byType(WindQuestionView),
    const Offset(-300, 0),
    1200,
  );
  await _pumpABit(tester);
}

/// A rightward fling on the wall — one of its two ways back to the daily (the
/// other is the system back gesture).
Future<void> _swipeBack(WidgetTester tester) async {
  await tester.fling(find.byType(DayWallView), const Offset(300, 0), 1200);
  await _pumpABit(tester);
}

/// Casts a daily vote and walks the contra gate that stands between the vote
/// and the community split, holding ground.
///
/// The gate is the reason this can't be a one-tap helper: the vote alone
/// reveals nothing, and the answer tiles stay inert until the argument has
/// finished falling word by word.
Future<void> _voteAndHoldGround(
  WidgetTester tester, {
  String side = 'TAK',
}) async {
  await tester.tap(find.text(side));
  await tester.pumpAndSettle();

  // The gate, not the split: the argument aimed at the side just picked.
  expect(
    find.text('ZANIM POKAŻĘ WYNIK'),
    findsOneWidget,
    reason: 'the contra gate stands between the vote and the percentages',
  );
  expect(
    find.textContaining('%'),
    findsNothing,
    reason: 'no split may be painted while the gate is up',
  );

  await tester.tap(find.text('TRZYMAM SIĘ'));
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'daily loop: splash → daily → vote → contra gate → split → settings',
    (tester) async {
      await _pumpAppToDaily(tester);

      // 1. The daily question renders: the "Daily" pill marks it, and the
      //    question text is on the canvas (FallingWordsText holds the live
      //    string — it is assembled word-by-word, so we read the widget rather
      //    than the full text).
      expect(find.text('PYTANIE DNIA'), findsOneWidget);
      final daily = tester.widget<FallingWordsText>(
        find.byType(FallingWordsText),
      );
      expect(
        daily.text.trim(),
        isNotEmpty,
        reason: 'the daily question text should be rendered',
      );

      // 2. Before the vote the panel shows TAK / NIE and no split at all.
      expect(find.text('TAK'), findsOneWidget);
      expect(find.text('NIE'), findsOneWidget);
      expect(
        find.textContaining('%'),
        findsNothing,
        reason: 'no community split is shown before voting',
      );

      // 3. Vote, then hold ground in the gate.
      await _voteAndHoldGround(tester);

      // 4. Only now the split: green % / red % with a "VS" seam and a check on
      //    the chosen side.
      expect(find.text('VS'), findsOneWidget);
      expect(
        find.textContaining('%'),
        findsWidgets,
        reason: 'the community split appears once the gate is done',
      );
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      // The gate's own statistic rides under the question (the mock RPC answers
      // with a flip share, as the server does past its 30-gate threshold).
      expect(find.textContaining('Kontra przewróciła'), findsOneWidget);

      // 5. Open the profile hub from the top-right person icon.
      final settingsButton = find.byIcon(Icons.person_outline);
      expect(settingsButton, findsOneWidget);
      await tester.tap(settingsButton);
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.text('USTAWIENIA APLIKACJI'), findsOneWidget);
    },
  );

  testWidgets(
    'the smaczki sheet is vote-gated: before the vote the pill answers with '
    'the hook, not the sheet',
    (tester) async {
      await _pumpAppToDaily(tester);

      // The sheet's own title, in the rich-text headline it is drawn with —
      // the "is it open?" signal, independent of which arguments the catalog
      // happens to serve.
      // (`textContaining`, and rich text: the headline is one span-built line —
      // "ARGUMENTY (smaczki)" — so an exact match would not find it.)
      final sheetIsOpen = find.textContaining('ARGUMENTY', findRichText: true);

      // The pill stays VISIBLE before the vote — knowing something waits there
      // is part of the reason to vote.
      expect(find.byType(GoDeeperButton), findsOneWidget);

      await tester.tap(find.byType(GoDeeperButton));
      await tester.pumpAndSettle();

      // ...but it answers with the hook instead of opening.
      expect(
        find.textContaining('Najpierw zagłosuj'),
        findsOneWidget,
        reason: 'the pre-vote tap must answer with the hook toast',
      );
      expect(
        sheetIsOpen,
        findsNothing,
        reason: 'no argument may be readable before the vote',
      );

      // After the vote (and its gate) the same pill opens the sheet.
      await _voteAndHoldGround(tester);
      await tester.tap(find.byType(GoDeeperButton));
      await tester.pumpAndSettle();

      expect(
        sheetIsOpen,
        findsOneWidget,
        reason: 'the sheet opens once a vote exists',
      );
    },
  );

  testWidgets(
    'a free forward swipe lands on the day wall, and back leaves it — '
    'the wall is never a trap',
    (tester) async {
      await _pumpAppToDaily(tester);
      expect(find.byType(DayWallView), findsNothing);

      await _swipeForward(tester);

      // The wall: the blurred 4-word teaser of tomorrow's question, the live
      // countdown to LOCAL midnight and the single unlock CTA.
      expect(find.byType(DayWallView), findsOneWidget);
      expect(find.text('DO DARMOWEGO'), findsOneWidget);
      expect(find.text('NIE CZEKAJ — ODBLOKUJ WSZYSTKIE'), findsOneWidget);
      // Not voted yet, so the sheet must stay shut (see the next test).
      expect(find.byType(ProPaywallScreen), findsNothing);

      // Way out #1: the back swipe.
      await _swipeBack(tester);
      expect(find.byType(DayWallView), findsNothing);
      expect(find.byType(WindQuestionView), findsOneWidget);
      expect(find.text('PYTANIE DNIA'), findsOneWidget);

      // Way out #2: the system back gesture — it must return to the daily, not
      // leave the app.
      await _swipeForward(tester);
      expect(find.byType(DayWallView), findsOneWidget);
      await tester.binding.handlePopRoute();
      await _pumpABit(tester);
      expect(find.byType(DayWallView), findsNothing);
      expect(find.text('PYTANIE DNIA'), findsOneWidget);
    },
  );

  testWidgets(
    'the wall paywall: never before the daily vote, automatically on the '
    'first hit after it, and only once that day',
    (tester) async {
      await _pumpAppToDaily(tester);

      // 1. Not voted yet → the wall shows, the paywall does not. The wall must
      //    never be the first thing that asks for money.
      await _swipeForward(tester);
      expect(find.byType(DayWallView), findsOneWidget);
      expect(
        find.byType(ProPaywallScreen),
        findsNothing,
        reason: 'no auto-paywall before the first vote of the day',
      );

      // 2. The manual CTA still opens it, of course — and it closes again.
      await tester.tap(find.text('NIE CZEKAJ — ODBLOKUJ WSZYSTKIE'));
      await _pumpABit(tester);
      expect(find.byType(ProPaywallScreen), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await _pumpABit(tester);
      expect(find.byType(ProPaywallScreen), findsNothing);

      // 3. Back to the daily and vote.
      await _swipeBack(tester);
      expect(find.byType(WindQuestionView), findsOneWidget);
      await _voteAndHoldGround(tester);

      // 4. First wall hit AFTER the vote → the sheet opens itself, over the
      //    wall (which stays mounted underneath).
      await _swipeForward(tester);
      expect(find.byType(DayWallView, skipOffstage: false), findsOneWidget);
      expect(
        find.byType(ProPaywallScreen),
        findsOneWidget,
        reason: 'first wall hit of the day + voted → the paywall opens itself',
      );
      await tester.tap(find.byIcon(Icons.close_rounded));
      await _pumpABit(tester);
      expect(find.byType(ProPaywallScreen), findsNothing);

      // 5. Second hit the same local day → the wall, in silence. Once per day
      //    means once.
      await _swipeBack(tester);
      await _swipeForward(tester);
      expect(find.byType(DayWallView), findsOneWidget);
      expect(
        find.byType(ProPaywallScreen),
        findsNothing,
        reason: 'the automatic open is latched for the rest of the local day',
      );
    },
  );

  testWidgets(
    'PRO: the daily wears its pill, and the catalog offers the one-tap jump '
    'back to it',
    (tester) async {
      await _pumpAppToDaily(tester, premium: true);

      // On the daily: the pill frames it as the question the whole community
      // is arguing about today. Being on it, there is nothing to jump to — so
      // the single "PYTANIE DNIA" on screen is the pill, not the link (both
      // render that same string, which is why the widget type is asserted too).
      expect(find.byType(DailyQuestionBadge), findsOneWidget);
      expect(find.text('PYTANIE DNIA'), findsOneWidget);

      // Forward into the catalog — the swipe a free account cannot make (it
      // meets the day wall instead; see the wall tests above).
      await _swipeForward(tester);
      await tester.pumpAndSettle();

      expect(
        find.byType(DayWallView),
        findsNothing,
        reason: 'PRO swipes into the catalog, never into the wall',
      );
      // Away from the daily the pill is gone and the link takes over the
      // string: one "PYTANIE DNIA" again, this time the way back.
      expect(find.byType(DailyQuestionBadge), findsNothing);
      final jumpLink = find.text('PYTANIE DNIA');
      expect(
        jumpLink,
        findsOneWidget,
        reason: 'mid-catalog PRO gets the jump back to the daily',
      );

      // One tap lands on the daily — the point of the link is that a PRO user
      // who wandered off can still see (or cast) today's shared vote.
      await tester.tap(jumpLink);
      await tester.pumpAndSettle();

      expect(find.byType(DailyQuestionBadge), findsOneWidget);
      expect(find.text('PYTANIE DNIA'), findsOneWidget);
      // The daily is still votable from here — landing on it is not a re-vote
      // and not a dead end.
      expect(find.text('TAK'), findsOneWidget);
      expect(find.text('NIE'), findsOneWidget);
    },
  );

  testWidgets('signing out returns the settings hub to its guest shape', (
    tester,
  ) async {
    await _pumpAppToDaily(tester);

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    // An account holder gets the sign-out row and no "secure your account"
    // pitch (there is nothing left to secure).
    expect(find.text('WYLOGUJ SIĘ'), findsOneWidget);
    expect(find.text('ZABEZPIECZ KONTO'), findsNothing);

    // The hub is a long scroll and the row sits near its foot — on a short
    // viewport it is mounted but off-screen, so bring it into view before
    // tapping (a plain tap would silently miss).
    await tester.ensureVisible(find.text('WYLOGUJ SIĘ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WYLOGUJ SIĘ'));
    await tester.pumpAndSettle();

    // Settings pops onto a feed that already shows the guest, with the
    // confirmation riding along.
    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.text('Wylogowano.'), findsOneWidget);

    // The app keeps working as a guest — there is no login gate in front of the
    // feed — and the hub has swapped the sign-out row for the pitch.
    expect(find.text('PYTANIE DNIA'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    expect(find.text('ZABEZPIECZ KONTO'), findsOneWidget);
    expect(find.text('WYLOGUJ SIĘ'), findsNothing);
  });
}

/// A session pinned to a signed-in, non-premium account, which drops to an
/// anonymous guest on sign-out.
///
/// Overriding [build] skips the real notifier's Supabase / RevenueCat wiring
/// (unavailable without SDK keys) while keeping the provider type the UI
/// watches — so `hasAccount` is true (the sign-out row shows, the vote casts)
/// and `isPremium` is false (the free daily-only deck, the path most users are
/// on and the only one that meets the day wall).
///
/// [signOutAndReload] is stubbed for the same reason and no further: the real
/// one calls `SupabaseService.signOut()` (a no-op with no keys) and then
/// re-runs `_load`, which would resolve the SAME pinned account back and leave
/// the sign-out invisible. Flipping the pinned state is what the SDK would have
/// done; everything the test then asserts — the pop, the toast, the hub's guest
/// shape — is the real UI reacting to it.
class _SmokeSession extends SessionNotifier {
  _SmokeSession({this.premium = false});

  final bool premium;

  bool _signedOut = false;

  @override
  Future<SessionState> build() async => _signedOut
      ? const SessionState(userId: 'smoke-guest', isAnonymous: true)
      : SessionState(
          userId: 'smoke-test-user',
          email: 'smoke@example.com',
          isAnonymous: false,
          createdAt: DateTime.utc(2026, 1, 1),
          isPremium: premium,
        );

  @override
  Future<void> signOutAndReload() async {
    _signedOut = true;
    state = AsyncData(await build());
  }
}

/// [MockQuestionRepository] that remembers the vote it was just handed.
///
/// The stock mock answers `getDailyVoteState` with a hard "not voted" — fine
/// for keyless dev (mock sessions are premium and never meet the wall), fatal
/// here: the vote panel invalidates that provider the moment the vote lands, so
/// the re-read wipes it, and the wall's rule ("has today's daily been voted
/// on?") could never see a vote no matter how many the test casts.
class _VoteRememberingMockRepo extends MockQuestionRepository {
  VoteResult? _cast;

  @override
  Future<VoteResult> castDailyVote(String questionId, int choice) async {
    final result = await super.castDailyVote(questionId, choice);
    _cast = result;
    return result;
  }

  @override
  Future<VoteResult> getDailyVoteState(String questionId) async =>
      _cast ?? await super.getDailyVoteState(questionId);
}
