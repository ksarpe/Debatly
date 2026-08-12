import 'package:debatly/services/rewarded_ad_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// The reward/dismiss contract of [RewardedAdService.showRewardedAd].
///
/// AdMob does NOT guarantee `onUserEarnedReward` fires before the dismiss /
/// failed-to-show callback — mediation adapters differ, and the original
/// implementation mis-reported a late-but-before-dismiss reward as "no reward"
/// (the user watched the whole ad and got an error). These tests replay the
/// callback orders the adapters actually produce against a scripted fake ad
/// (see [LoadedRewardedAd]) and pin the resolved value of the returned future.
void main() {
  late RewardedAdService service;
  late _ScriptedAd ad;

  setUp(() {
    service = RewardedAdService();
    ad = _ScriptedAd();
    service.debugSetLoadedAd(ad);
  });

  /// Starts the show and yields until the fake ad has captured the service's
  /// callbacks, so the test can replay them in a chosen order.
  Future<Future<bool>> startShow({String? userId, String? questionId}) async {
    final result = service.showRewardedAd(
      userId: userId,
      questionId: questionId,
    );
    await pumpEventQueue();
    expect(ad.shown, isTrue);
    return result;
  }

  test('reward then dismiss resolves true', () async {
    final result = await startShow();

    ad.reward();
    ad.dismiss();

    expect(await result, isTrue);
  });

  test('dismiss without a reward resolves false', () async {
    final result = await startShow();

    ad.dismiss();

    expect(await result, isFalse);
  });

  test('an earned reward survives a failed-to-show callback', () async {
    final result = await startShow();

    ad.reward();
    ad.failToShow(AdError(1, 'test', 'adapter crashed mid-close'));

    expect(await result, isTrue);
  });

  test('failed to show without a reward resolves false', () async {
    final result = await startShow();

    ad.failToShow(AdError(3, 'test', 'no fill'));

    expect(await result, isFalse);
  });

  test(
    'a duplicate terminal callback completes once, without throwing',
    () async {
      final result = await startShow();

      ad.reward();
      ad.dismiss();
      ad.dismiss(); // some adapters double-fire — must not throw or flip the value
      ad.failToShow(AdError(1, 'test', 'late duplicate'));

      expect(await result, isTrue);
    },
  );

  test(
    'the ad is consumed up front — the same ad can never show twice',
    () async {
      final first = await startShow();
      expect(
        service.isReady,
        isFalse,
        reason: 'reference consumed before show',
      );

      // A second call while the first ad is still on screen finds no ad.
      expect(await service.showRewardedAd(), isFalse);

      ad.reward();
      ad.dismiss();
      expect(await first, isTrue);
    },
  );

  test('with no ad loaded it resolves false straight away', () async {
    final empty = RewardedAdService();
    expect(empty.isReady, isFalse);
    expect(await empty.showRewardedAd(), isFalse);
  });

  test('SSV options carry the user and question to the impression', () async {
    final result = await startShow(userId: 'user-7', questionId: 'q-42');

    expect(ad.ssvOptions?.userId, 'user-7');
    expect(ad.ssvOptions?.customData, 'q-42');

    ad.reward();
    ad.dismiss();
    expect(await result, isTrue);
  });

  test('SSV is skipped when there is nothing to attribute', () async {
    final result = await startShow();

    expect(ad.ssvOptions, isNull);

    ad.dismiss();
    expect(await result, isFalse);
  });

  test('an SSV failure must not abort the reward flow', () async {
    ad.throwOnSsv = true;
    final result = await startShow(userId: 'user-7', questionId: 'q-42');

    ad.reward();
    ad.dismiss();

    expect(
      await result,
      isTrue,
      reason: 'SSV is audit-only — its failure cannot cost the user the unlock',
    );
  });
}

/// Scripted stand-in for a loaded AdMob rewarded ad: `show` captures the
/// service's callbacks so each test can replay them in whatever order the
/// mediation adapter under simulation would fire them.
class _ScriptedAd implements LoadedRewardedAd {
  ServerSideVerificationOptions? ssvOptions;
  bool throwOnSsv = false;
  bool shown = false;

  late void Function() reward;
  late void Function() dismiss;
  late void Function(AdError error) failToShow;

  @override
  Future<void> setServerSideOptions(
    ServerSideVerificationOptions options,
  ) async {
    if (throwOnSsv) throw StateError('SSV channel down');
    ssvOptions = options;
  }

  @override
  Future<void> show({
    required void Function() onUserEarnedReward,
    required void Function() onDismissed,
    required void Function(AdError error) onFailedToShow,
  }) async {
    shown = true;
    reward = onUserEarnedReward;
    dismiss = onDismissed;
    failToShow = onFailedToShow;
  }

  @override
  void dispose() {}
}
