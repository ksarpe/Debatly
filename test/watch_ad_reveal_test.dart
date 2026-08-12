import 'dart:io';

import 'package:debatly/core/locale/app_locale.dart';
import 'package:debatly/data/models/question.dart';
import 'package:debatly/data/repositories/question_repository.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/account/providers/stats_providers.dart';
import 'package:debatly/features/monetization/providers/monetization_providers.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:debatly/features/questions/widgets/wind_question_view.dart';
import 'package:debatly/services/rewarded_ad_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'support/localized_test_app.dart';
import 'support/test_prefs.dart';

/// The "watch an ad to unlock" flow on the reveal-slot paywall
/// ([WindQuestionView._watchAdReveal]): what happens when the ad isn't loaded
/// yet, when the user bails before the reward, when the reward lands, and when
/// the reveal RPC afterwards refuses (cap spent server-side, offline, other).
void main() {
  Question q(String id) => Question(
    id: id,
    category: id.toUpperCase(),
    questionText: 'Question $id?',
  );

  Future<ProviderContainer> pumpPaywall(
    WidgetTester tester, {
    required _AdRevealRepo repo,
    required RewardedAdService ads,
  }) async {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await mockSharedPreferences(),
        ),
        todaysDailyQuestionProvider.overrideWith((ref) async => q('daily')),
        isPremiumProvider.overrideWithValue(false),
        freeUnlockCreditsProvider.overrideWithValue(0),
        adCapReachedProvider.overrideWithValue(false),
        questionRepositoryProvider.overrideWithValue(repo),
        rewardedAdServiceProvider.overrideWithValue(ads),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const LocalizedTestApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                height: 600,
                child: WindQuestionView(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // A free user with no credit swipes forward off the daily onto the slot.
    await tester.fling(
      find.byType(WindQuestionView),
      const Offset(-300, 0),
      1000,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(container.read(isAtRevealSlotProvider), isTrue);
    return container;
  }

  Future<void> tapWatchAd(WidgetTester tester) async {
    await tester.tap(find.text('Odblokuj reklamą'.toUpperCase()));
    await tester.pump();
    await tester.pumpAndSettle();
  }

  /// Lets the toast's auto-dismiss timer (3s info / 5s error) fire so the test
  /// doesn't end with a pending timer.
  Future<void> drainToasts(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  }

  testWidgets('ad not loaded yet: a loading toast, no reveal, no reward lost', (
    tester,
  ) async {
    final repo = _AdRevealRepo();
    await pumpPaywall(tester, repo: repo, ads: RewardedAdService());

    await tapWatchAd(tester);

    expect(
      find.text('Reklama jeszcze się ładuje — spróbuj za chwilę.'),
      findsOneWidget,
    );
    expect(repo.adReveals, 0);
    // The spinner must not wedge: the paywall button is offered again.
    expect(find.text('Odblokuj reklamą'.toUpperCase()), findsOneWidget);
    await drainToasts(tester);
  });

  testWidgets('dismissed without the reward: toast, nothing revealed', (
    tester,
  ) async {
    final repo = _AdRevealRepo();
    final ads = RewardedAdService()..debugSetLoadedAd(_AutoAd(earn: false));
    final container = await pumpPaywall(tester, repo: repo, ads: ads);

    await tapWatchAd(tester);

    expect(
      find.text('Brak nagrody — obejrzyj całe wideo, aby odblokować.'),
      findsOneWidget,
    );
    expect(repo.adReveals, 0);
    expect(container.read(revealedFeedProvider), isEmpty);
    expect(container.read(isAtRevealSlotProvider), isTrue);
    await drainToasts(tester);
  });

  testWidgets('reward earned: the teased question is revealed and landed on', (
    tester,
  ) async {
    final repo = _AdRevealRepo();
    final ads = RewardedAdService()..debugSetLoadedAd(_AutoAd(earn: true));
    final container = await pumpPaywall(tester, repo: repo, ads: ads);

    await tapWatchAd(tester);

    expect(repo.adReveals, 1);
    expect(
      repo.lastQuestionId,
      'peek-1',
      reason: 'the ad must reveal the exact question that was teased',
    );
    expect(container.read(revealedFeedProvider).length, 1);
    expect(container.read(questionIndexProvider), 1);
    expect(container.read(isAtRevealSlotProvider), isFalse);
  });

  testWidgets(
    'server refuses (daily ad reveal limit): cap toast, back on the paywall',
    (tester) async {
      final repo = _AdRevealRepo()
        ..revealError = Exception('daily ad reveal limit reached');
      final ads = RewardedAdService()..debugSetLoadedAd(_AutoAd(earn: true));
      final container = await pumpPaywall(tester, repo: repo, ads: ads);

      await tapWatchAd(tester);

      expect(
        find.text('Dzienny limit odblokowań za reklamy został osiągnięty.'),
        findsOneWidget,
      );
      expect(container.read(revealedFeedProvider), isEmpty);
      expect(container.read(isAtRevealSlotProvider), isTrue);
      await drainToasts(tester);
    },
  );

  testWidgets('reveal fails offline: the "no connection" toast', (
    tester,
  ) async {
    final repo = _AdRevealRepo()
      ..revealError = const SocketException('network down');
    final ads = RewardedAdService()..debugSetLoadedAd(_AutoAd(earn: true));
    final container = await pumpPaywall(tester, repo: repo, ads: ads);

    await tapWatchAd(tester);

    expect(
      find.text('Brak połączenia — spróbuj ponownie za chwilę.'),
      findsOneWidget,
    );
    expect(container.read(isAtRevealSlotProvider), isTrue);
    await drainToasts(tester);
  });

  testWidgets('reveal fails for another reason: the generic failure toast', (
    tester,
  ) async {
    final repo = _AdRevealRepo()..revealError = StateError('rpc exploded');
    final ads = RewardedAdService()..debugSetLoadedAd(_AutoAd(earn: true));
    final container = await pumpPaywall(tester, repo: repo, ads: ads);

    await tapWatchAd(tester);

    expect(
      find.text('Nie udało się odsłonić pytania — spróbuj ponownie.'),
      findsOneWidget,
    );
    expect(container.read(isAtRevealSlotProvider), isTrue);
    await drainToasts(tester);
  });
}

/// Fake loaded ad that plays itself out the moment it is shown: optionally
/// grants the reward, then dismisses — the same callback order the plugin
/// produces on a normally completed ad.
class _AutoAd implements LoadedRewardedAd {
  _AutoAd({required this.earn});

  final bool earn;

  @override
  Future<void> setServerSideOptions(
    ServerSideVerificationOptions options,
  ) async {}

  @override
  Future<void> show({
    required void Function() onUserEarnedReward,
    required void Function() onDismissed,
    required void Function(AdError error) onFailedToShow,
  }) async {
    if (earn) onUserEarnedReward();
    onDismissed();
  }

  @override
  void dispose() {}
}

/// Repo with a teaser to peek and a scriptable ad reveal.
class _AdRevealRepo extends MockQuestionRepository {
  Object? revealError;
  int adReveals = 0;
  String? lastQuestionId;

  @override
  Future<({String id, String teaser})?> peekNextQuestion({
    List<String> excludeIds = const [],
  }) async => (id: 'peek-1', teaser: 'Czy coś');

  @override
  Future<Question?> revealAdQuestion({
    String? questionId,
    List<String> excludeIds = const [],
  }) async {
    adReveals++;
    lastQuestionId = questionId;
    final error = revealError;
    if (error != null) throw error;
    return Question(
      id: questionId ?? 'ad-q',
      category: 'C',
      questionText: 'Ad question?',
    );
  }
}
