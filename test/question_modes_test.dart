import 'package:debatly/core/locale/app_locale.dart';
import 'package:debatly/data/models/question.dart';
import 'package:debatly/data/models/question_mode.dart';
import 'package:debatly/data/models/vote_result.dart';
import 'package:debatly/data/repositories/question_repository.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/monetization/widgets/pro_paywall_screen.dart';
import 'package:debatly/features/questions/providers/mode_providers.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:debatly/features/questions/screens/modes_screen.dart';
import 'package:debatly/features/questions/widgets/mode_badge.dart';
import 'package:debatly/features/questions/widgets/question_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/localized_test_app.dart';
import 'support/test_prefs.dart';

/// The feed's modes: four category groupings a PRO user pins the deck to.
/// The daily keeps index 0, the mode's questions follow, every non-daily card
/// wears the mode pill and the foot of the feed carries "Wróć do feedu". The
/// modes screen gates itself (free: locked tiles → paywall), and the only
/// pointer at it in the feed is the once-per-install link under the voted
/// daily.
void main() {
  Question q(String id, String category) =>
      Question(id: id, category: category, questionText: 'Question $id?');

  final pool = [
    q('a', 'Relationships'),
    q('b', 'Family'),
    q('c', 'Money'),
    q('d', 'Ethics'),
    q('e', 'Friendship'),
  ];

  Future<ProviderContainer> makeContainer({
    required bool premium,
    List<Question> pool = const [],
    bool voted = false,
    Map<String, Object> prefs = const {},
  }) async {
    final daily = Question(
      id: 'daily',
      category: 'Relationships',
      questionText: 'Czy para powinna dzielić wydatki na pół?',
    );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await mockSharedPreferences(prefs),
        ),
        sessionProvider.overrideWith(
          () => FakeSession(guestSession(isPremium: premium)),
        ),
        isPremiumProvider.overrideWithValue(premium),
        questionsProvider.overrideWith((ref) async => pool),
        todaysDailyQuestionProvider.overrideWith((ref) async => daily),
        deckShuffleSeedProvider.overrideWithValue(1),
        questionRepositoryProvider.overrideWithValue(_Repo(voted: voted)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<ProviderContainer> pumpFeed(
    WidgetTester tester, {
    required bool premium,
    List<Question> pool = const [],
    bool voted = false,
  }) async {
    final container = await makeContainer(
      premium: premium,
      pool: pool,
      voted: voted,
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const LocalizedTestApp(home: Scaffold(body: QuestionBody())),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  /// The modes screen's flame row shimmers forever, so pumpAndSettle would
  /// chase it — bounded pumps instead, wherever the screen is on stage.
  Future<void> settleModes(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  Future<ProviderContainer> pumpModes(
    WidgetTester tester, {
    required bool premium,
    List<Question> pool = const [],
  }) async {
    final container = await makeContainer(premium: premium, pool: pool);
    // In the app the feed underneath has long resolved the daily and the
    // pool; pumping the screen on its own, resolve them here so the deck a
    // tap pins is not the still-loading empty one.
    await container.read(todaysDailyQuestionProvider.future);
    await container.read(questionsProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const LocalizedTestApp(home: ModesScreen()),
      ),
    );
    await settleModes(tester);
    return container;
  }

  testWidgets('PRO: a pinned mode narrows the deck behind the daily, lands on '
      'its first question with the pill, and "back to the feed" undoes it', (
    tester,
  ) async {
    final container = await pumpFeed(tester, premium: true, pool: pool);
    expect(container.read(questionDeckProvider).length, 6);

    container
        .read(questionIndexProvider.notifier)
        .enterMode(QuestionMode.relationships);
    await tester.pumpAndSettle();

    // The daily stays at 0; only Relationships + Friendship follow it.
    final deck = container.read(questionDeckProvider);
    expect(deck.first.id, 'daily');
    // The two Relationships-mode questions, in the seeded shuffle's order.
    expect(deck.skip(1).map((q) => q.id), unorderedEquals(['a', 'e']));
    expect(container.read(questionIndexProvider), 1);
    expect(find.byType(ModeBadge), findsOneWidget);
    expect(find.text('ZWIĄZKI'), findsOneWidget);
    // The mode exit replaces the daily jump — one way back, not two.
    expect(find.text('WRÓĆ DO FEEDU'), findsOneWidget);
    expect(find.text('PYTANIE DNIA'), findsNothing);

    await tester.tap(find.text('WRÓĆ DO FEEDU'));
    await tester.pumpAndSettle();

    expect(container.read(activeModeProvider), isNull);
    expect(container.read(questionIndexProvider), 0);
    expect(container.read(questionDeckProvider).length, 6);
    expect(find.byType(ModeBadge), findsNothing);
    expect(find.text('WRÓĆ DO FEEDU'), findsNothing);
  });

  testWidgets('the modes screen: five rows, intimacy first with the flame; '
      'a PRO tap pins the mode and closes', (tester) async {
    final container = await pumpModes(tester, premium: true, pool: pool);

    for (final name in [
      'SEKS I INTYMNOŚĆ',
      'ZWIĄZKI',
      'RODZINA',
      'KASA I PRACA',
      'SPOŁECZEŃSTWO',
    ]) {
      expect(find.text(name), findsOneWidget);
    }
    // The adult-themes mode is always the first row, and wears the flame
    // instead of the arrow.
    expect(
      tester.getTopLeft(find.text('SEKS I INTYMNOŚĆ')).dy,
      lessThan(tester.getTopLeft(find.text('ZWIĄZKI')).dy),
    );
    expect(find.byIcon(Icons.local_fire_department_rounded), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsNothing);
    // The "now playing" card names the whole catalog while nothing is
    // pinned — and "all topics" is then NOT also a row (nothing to leave).
    expect(find.text('TERAZ GRASZ'), findsOneWidget);
    expect(find.text('WSZYSTKIE TEMATY'), findsOneWidget);
    expect(find.text('Wszystko, co mamy, wymieszane'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward), findsNWidgets(4));
    // The placeholder for the mode to come, and the footer.
    expect(find.text('KOLEJNY TRYB'), findsOneWidget);
    expect(find.text('Zmiana trybu nie usuwa Twojej historii'), findsOneWidget);

    await tester.tap(find.text('RODZINA'));
    await settleModes(tester);

    expect(container.read(activeModeProvider), QuestionMode.family);
    expect(container.read(questionIndexProvider), 1);
    expect(container.read(questionDeckProvider).map((q) => q.id).toList(), [
      'daily',
      'b',
    ]);
  });

  testWidgets('with a mode pinned, the "now playing" card names it, the mode '
      'leaves the list and "all topics" becomes the way back', (tester) async {
    final container = await pumpModes(tester, premium: true, pool: pool);
    await tester.tap(find.text('ZWIĄZKI'));
    await settleModes(tester);
    expect(container.read(activeModeProvider), QuestionMode.relationships);

    // Reopen the screen: the card names the mode, its row is gone, and "all
    // topics" is a row now.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const LocalizedTestApp(home: ModesScreen()),
      ),
    );
    await settleModes(tester);
    expect(find.text('ZWIĄZKI'), findsOneWidget);
    expect(find.text('Miłość, zdrada, granice'), findsOneWidget);
    expect(find.text('WSZYSTKIE TEMATY'), findsOneWidget);
    // Arrows: all topics + the three other plain modes (the flame row keeps
    // its flame).
    expect(find.byIcon(Icons.arrow_forward), findsNWidgets(4));

    await tester.tap(find.text('WSZYSTKIE TEMATY'));
    await settleModes(tester);

    expect(container.read(activeModeProvider), isNull);
    expect(container.read(questionIndexProvider), 0);
  });

  testWidgets('the modes screen for FREE: every row locked, "now playing" is '
      'the daily, a tap opens the paywall and pins nothing', (tester) async {
    final container = await pumpModes(tester, premium: false);

    // All topics + the five modes, every one behind the padlock (the flame
    // row too — its glyph yields to the lock, the shimmer stays).
    expect(find.byIcon(Icons.lock_outline), findsNWidgets(6));
    expect(find.byIcon(Icons.arrow_forward), findsNothing);
    expect(find.byIcon(Icons.local_fire_department_rounded), findsNothing);
    expect(find.text('PYTANIE DNIA'), findsOneWidget);
    expect(find.text('WSZYSTKIE TEMATY'), findsOneWidget);
    expect(find.byType(ProPaywallScreen), findsNothing);

    await tester.tap(find.text('SEKS I INTYMNOŚĆ'));
    await settleModes(tester);

    expect(find.byType(ProPaywallScreen), findsOneWidget);
    expect(container.read(activeModeProvider), isNull);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await settleModes(tester);
  });

  testWidgets('the hint under the voted daily names its topic, stamps the '
      'day, and a tap opens the modes screen and retires it', (tester) async {
    final container = await pumpFeed(tester, premium: false, voted: true);
    final prefs = container.read(sharedPreferencesProvider);

    // The daily is a Relationships question → the topic-specific label.
    expect(find.text('WIĘCEJ O ZWIĄZKACH'), findsOneWidget);
    expect(find.text('ZOBACZ TRYBY'), findsNothing);
    expect(
      prefs.getString(kModesHintPrefKey),
      dateOnlyKey(DateTime.now()),
      reason: 'first render stamps today',
    );

    await tester.tap(find.text('WIĘCEJ O ZWIĄZKACH'));
    await settleModes(tester);

    expect(find.byType(ModesScreen), findsOneWidget);
    expect(prefs.getString(kModesHintPrefKey), kModesHintDone);
  });

  testWidgets('no hint before the vote', (tester) async {
    await pumpFeed(tester, premium: false, voted: false);
    expect(find.text('WIĘCEJ O ZWIĄZKACH'), findsNothing);
    expect(find.text('ZOBACZ TRYBY'), findsNothing);
  });

  testWidgets('no hint once retired', (tester) async {
    final container = await makeContainer(
      premium: false,
      voted: true,
      prefs: {kModesHintPrefKey: kModesHintDone},
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const LocalizedTestApp(home: Scaffold(body: QuestionBody())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('WIĘCEJ O ZWIĄZKACH'), findsNothing);
  });
}

/// A mock repo whose daily vote state the tests control.
class _Repo extends MockQuestionRepository {
  _Repo({required this.voted});

  final bool voted;

  @override
  Future<VoteResult> getDailyVoteState(String questionId) async => voted
      ? const VoteResult(yesCount: 61, noCount: 39, myChoice: VoteResult.yes)
      : VoteResult.empty;
}
