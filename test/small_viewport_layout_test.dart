import 'package:debatly/core/locale/app_locale.dart';
import 'package:debatly/core/widgets/fit_or_scroll.dart';
import 'package:debatly/data/models/question.dart';
import 'package:debatly/data/models/vote_result.dart';
import 'package:debatly/data/repositories/question_repository.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/account/screens/auth_screen.dart';
import 'package:debatly/features/monetization/widgets/pro_paywall_screen.dart';
import 'package:debatly/features/onboarding/screens/onboarding_screen.dart';
import 'package:debatly/features/onboarding/widgets/onboarding_bridge_card.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:debatly/features/questions/widgets/favorite_star_button.dart';
import 'package:debatly/features/questions/widgets/go_deeper_button.dart';
import 'package:debatly/features/questions/widgets/question_body.dart';
import 'package:debatly/features/questions/widgets/share_question_button.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show Package;

import 'support/fakes.dart';
import 'support/localized_test_app.dart';
import 'support/test_prefs.dart';

/// Guards the class of bug behind the iPad App Review rejection: a control that
/// is *painted* where the finger can't reach it.
///
/// When a [Column] overflows, Flutter still paints the spilled children, but
/// `RenderBox.hitTest` only descends into a box whose own size contains the
/// pointer — so an overflowed button is visible and completely dead. That is how
/// the reveal wall's "restore purchase" disappeared on a short viewport, and how
/// the swipe hint came to sit on top of the share / history pills and swallow
/// their taps.
///
/// Phones are pinned to portrait now (see `OrientationLock`), but an iPad hands
/// out short, narrow windows in Split View and Slide Over, and iOS text sizes go
/// well past 1.6x — so every surface still has to survive both.
void main() {
  const swipeHint = 'Przesuń, aby zobaczyć następne pytanie';

  setUp(() => WidgetController.hitTestWarningShouldBeFatal = true);

  /// Whether a real pointer landing on the centre of [finder] would actually
  /// reach it, rather than a widget painted on top — or nothing at all, because
  /// the target sits outside its parent's box.
  bool isTappable(WidgetTester tester, Finder finder) {
    final target = finder.evaluate().first.renderObject!;
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      result,
      tester.getCenter(finder.first),
      tester.view.viewId,
    );
    return result.path.any((entry) => identical(entry.target, target));
  }

  Question q(String id, [String? text]) => Question(
    id: id,
    category: id.toUpperCase(),
    questionText: text ?? 'Czy warto?',
  );

  Future<void> pumpFeed(
    WidgetTester tester, {
    required Size size,
    double textScale = 1,
    bool premium = true,
    QuestionRepository? repo,
    List<Question> pool = const [],
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final daily = q('daily');
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await mockSharedPreferences(),
        ),
        questionsProvider.overrideWith((ref) async => pool),
        todaysDailyQuestionProvider.overrideWith((ref) async => daily),
        isPremiumProvider.overrideWithValue(premium),
        deckShuffleSeedProvider.overrideWithValue(1),
        sessionProvider.overrideWith(_FakeSession.new),
        questionRepositoryProvider.overrideWithValue(repo ?? _VotedRepo()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LocalizedTestApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: const Scaffold(body: QuestionBody()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the feed keeps its pills clear of the bottom overlay', () {
    // A short window (iPad Slide Over / Split View) and a large accessibility
    // font both used to push the centred group down under the swipe hint, which
    // is painted after it and therefore ate every tap.
    const viewports = <String, (Size, double)>{
      'short window': (Size(812, 375), 1.0),
      'phone at 1.6x text': (Size(375, 667), 1.6),
      'phone at 2.0x text': (Size(375, 667), 2.0),
      'small phone at 2.0x text': (Size(320, 568), 2.0),
      'tall phone': (Size(393, 851), 1.0),
      'iPad': (Size(820, 1180), 1.0),
    };

    viewports.forEach((name, spec) {
      testWidgets('share + favorites stay tappable — $name', (tester) async {
        final (size, scale) = spec;
        await pumpFeed(tester, size: size, textScale: scale);

        final share = find.byType(ShareQuestionButton);
        final star = find.byType(FavoriteStarButton);
        final hint = find.text(swipeHint);
        final goDeeper = tester.getRect(find.byType(GoDeeperButton));

        // The pills live in the bottom action bar now — one row with the
        // "go deeper" CTA, below the swipe hint. On every viewport they must
        // hold that row and stay reachable by a real pointer (nothing painted
        // over them, nothing stranded outside a parent's box).
        for (final pill in [share, star]) {
          final rect = tester.getRect(pill);
          expect(
            rect.top,
            greaterThanOrEqualTo(tester.getRect(hint).bottom),
            reason: 'the action bar sits under the swipe hint, never over it',
          );
          expect(
            rect.center.dy,
            closeTo(goDeeper.center.dy, 1),
            reason: 'the pills share the action bar row with the CTA',
          );
          expect(isTappable(tester, pill), isTrue);
        }
      });
    });
  });

  group('the paywall sheet never hides its exits', () {
    // "Przywróć zakup" and the sign-in link are the only ways an already-
    // entitled user recovers PRO from the sheet (App Review must be able to
    // reach the restore), so they have to survive short windows and large
    // fonts.
    const viewports = <String, (Size, double)>{
      'short window': (Size(812, 375), 1.0),
      'phone': (Size(375, 667), 1.0),
      'phone at 1.6x text': (Size(375, 667), 1.6),
      'small phone at 1.6x text': (Size(320, 568), 1.6),
    };

    viewports.forEach((name, spec) {
      testWidgets('restore + sign-in reachable — $name', (tester) async {
        final (size, scale) = spec;
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(
              await mockSharedPreferences(),
            ),
            sessionProvider.overrideWith(() => FakeSession(guestSession())),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: LocalizedTestApp(
              home: Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: Scaffold(
                    body: ProPaywallScreen(
                      loadPackages: () async => const <Package>[],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'the wall must fit or scroll, never overflow its box',
        );

        for (final label in const ['Przywróć zakup', 'Zaloguj się']) {
          final finder = find.text(label);
          expect(finder, findsOneWidget, reason: label);
          // Scrolling it into view is allowed; being unreachable is not.
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          expect(isTappable(tester, finder), isTrue, reason: label);
        }
      });
    });
  });

  group('onboarding survives a short window and a large font', () {
    const viewports = <String, (Size, double)>{
      'phone at 1.5x text': (Size(375, 667), 1.5),
      'phone at 2.0x text': (Size(375, 667), 2.0),
      'short window': (Size(740, 360), 1.0),
      'small phone': (Size(320, 568), 1.0),
    };

    viewports.forEach((name, spec) {
      testWidgets('the welcome card does not clip its copy — $name', (
        tester,
      ) async {
        final (size, scale) = spec;
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(
                await mockSharedPreferences(),
              ),
            ],
            child: LocalizedTestApp(
              home: Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: OnboardingScreen(onFinish: () {}),
                ),
              ),
            ),
          ),
        );
        // The welcome card glows perpetually, so pumpAndSettle never returns.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(tester.takeException(), isNull);
      });

      // The tallest card in the deck — glyph, title, body and two CTAs — so
      // it is the one that overflows first.
      testWidgets('the bridge card does not clip its copy — $name', (
        tester,
      ) async {
        final (size, scale) = spec;
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          LocalizedTestApp(
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: Scaffold(body: OnboardingBridgeCard(onContinue: () {})),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(FitOrScroll), findsOneWidget);
      });
    });
  });

  group('touch targets clear the platform minimums', () {
    testWidgets('the share and favorites pills are 48x48', (tester) async {
      await pumpFeed(tester, size: const Size(393, 851));

      for (final finder in [
        find.byType(ShareQuestionButton),
        find.byType(FavoriteStarButton),
      ]) {
        final size = tester.getSize(finder);
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
    });

    testWidgets('"forgot password?" is a real button, not bare text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(
              await mockSharedPreferences(),
            ),
          ],
          child: const LocalizedTestApp(home: Scaffold(body: AuthScreen())),
        ),
      );
      await tester.pumpAndSettle();

      final link = find.ancestor(
        of: find.text('NIE PAMIĘTASZ HASŁA?'),
        matching: find.byType(TextButton),
      );
      expect(link, findsOneWidget);
      // It used to be a GestureDetector wrapped straight around the Text, whose
      // hit box was the 19pt-tall glyph run.
      expect(tester.getSize(link).height, greaterThanOrEqualTo(48));
    });
  });

  group('FitOrScroll', () {
    testWidgets('centres its child while it fits, and never scrolls', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: FitOrScroll(child: SizedBox(height: 100, width: 100)),
            ),
          ),
        ),
      );

      expect(tester.getRect(find.byType(SizedBox).last).center.dy, 200);
      final scroll = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect(scroll.controller, isNull);
      expect(
        tester.getSize(find.byType(FitOrScroll)).height,
        400,
        reason: 'the viewport is unchanged when the content fits',
      );
    });

    testWidgets('scrolls once the child outgrows the viewport', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 200,
              child: FitOrScroll(child: SizedBox(height: 600, width: 100)),
            ),
          ),
        ),
      );

      // Reachable by scrolling — which is the whole point: nothing is stranded
      // outside a parent's box where hit testing can't follow.
      await tester.drag(find.byType(FitOrScroll), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('hands the child minContentHeight on a tiny viewport', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 100,
              child: FitOrScroll(
                minContentHeight: 300,
                // A Flexible only flexes against a bounded box; the floor is
                // what keeps one there once the viewport is too small.
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Flexible(child: SizedBox(height: 500, width: 10)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.getSize(find.byType(Column)).height, 300);
      expect(tester.takeException(), isNull);
    });
  });
}

class _FakeSession extends SessionNotifier {
  @override
  Future<SessionState> build() async =>
      const SessionState(userId: 'u1', isAnonymous: false);
}

/// Serves a question the user has already voted on, so the vote panel renders
/// its tallest state (the split bars plus the "Twój głos" caption).
class _VotedRepo extends MockQuestionRepository {
  @override
  Future<VoteResult> getDailyVoteState(String questionId) async =>
      const VoteResult(yesCount: 61, noCount: 39, myChoice: VoteResult.yes);
}
