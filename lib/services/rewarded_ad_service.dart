import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/config/app_config.dart';
import '../core/monitoring/monitoring.dart';
import 'ads_service.dart';
import 'consent_service.dart';

/// The slice of a loaded [RewardedAd] that [RewardedAdService.showRewardedAd]
/// drives. A seam: [RewardedAd] has no public constructor, so the reward /
/// dismiss ordering logic (the part that has regressed before) could not be
/// tested against the plugin class directly. Production wraps the real ad in
/// [_PluginRewardedAd]; tests inject a fake via
/// [RewardedAdService.debugSetLoadedAd].
abstract class LoadedRewardedAd {
  /// Tags the impression for Server-Side Verification. May throw — the caller
  /// treats SSV as audit-only and continues regardless.
  Future<void> setServerSideOptions(ServerSideVerificationOptions options);

  /// Presents the ad. AdMob does NOT guarantee [onUserEarnedReward] fires
  /// before [onDismissed] / [onFailedToShow] — mediation adapters differ.
  Future<void> show({
    required VoidCallback onUserEarnedReward,
    required VoidCallback onDismissed,
    required void Function(AdError error) onFailedToShow,
  });

  void dispose();
}

/// Production adapter over the real plugin ad.
class _PluginRewardedAd implements LoadedRewardedAd {
  _PluginRewardedAd(this._ad);

  final RewardedAd _ad;

  @override
  Future<void> setServerSideOptions(ServerSideVerificationOptions options) =>
      _ad.setServerSideOptions(options);

  @override
  Future<void> show({
    required VoidCallback onUserEarnedReward,
    required VoidCallback onDismissed,
    required void Function(AdError error) onFailedToShow,
  }) {
    _ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        onDismissed();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        onFailedToShow(error);
      },
    );
    return _ad.show(onUserEarnedReward: (_, _) => onUserEarnedReward());
  }

  @override
  void dispose() => _ad.dispose();
}

/// Manages the lifecycle of a single Google AdMob *rewarded* ad: pre-loading one
/// in the background, showing it on demand, surfacing the
/// `onUserEarnedReward` callback, and immediately pre-loading the next.
///
/// Kept framework-agnostic (no Riverpod here) like the other services; a
/// provider owns the single shared instance and disposes it (see
/// `monetization_providers.dart`).
class RewardedAdService {
  RewardedAdService();

  LoadedRewardedAd? _ad;
  bool _isLoading = false;

  /// Whether an ad is loaded and ready to [showRewardedAd] right now.
  bool get isReady => _ad != null;

  /// Hands the service a pre-loaded (fake) ad, standing in for a completed
  /// [preload] — which tests can't run (no AdMob SDK).
  @visibleForTesting
  void debugSetLoadedAd(LoadedRewardedAd ad) {
    _ad = ad;
  }

  /// Starts loading a rewarded ad if one isn't already loaded or in flight.
  ///
  /// No-ops when the AdMob SDK hasn't been initialised (development / tests), so
  /// callers can preload freely without guarding.
  void preload() {
    if (!AdsService.isInitialised) return;
    // Respect the UMP decision: when consent is still outstanding (EEA user who
    // hasn't answered) don't request an ad yet. Defaults to permissive, so this
    // only blocks the genuine "no consent" case.
    if (!ConsentService.canRequestAds) return;
    if (_ad != null || _isLoading) return;

    _isLoading = true;
    RewardedAd.load(
      adUnitId: AppConfig.admobRewardedId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = _PluginRewardedAd(ad);
          _isLoading = false;
        },
        onAdFailedToLoad: (error) {
          debugPrint('RewardedAdService: failed to load — $error');
          // No-fill is routine, so this is a breadcrumb (context for a later
          // error), never an issue of its own.
          Monitoring.addBreadcrumb(
            'Rewarded ad failed to load',
            category: 'ads',
            data: {'code': error.code, 'message': error.message},
          );
          _ad = null;
          _isLoading = false;
        },
      ),
    );
  }

  /// Shows the loaded ad and resolves to `true` if (and only if) the user
  /// actually earned the reward, `false` otherwise (no ad ready, failed to
  /// show, or dismissed without earning). Always completes once the ad is
  /// dismissed. A replacement ad is always pre-loaded for next time.
  ///
  /// The reward is AUTHORITATIVE and decoupled from dismissal: AdMob does NOT
  /// guarantee `onUserEarnedReward` fires before `onAdDismissedFullScreenContent`
  /// — on several mediation adapters dismiss lands first. The old design read an
  /// `earned` bool set by a separate callback right after the future completed
  /// (on dismiss), so a late reward callback was mis-reported as "no reward",
  /// and the user who watched the whole ad got an error instead of their
  /// question. Now we record the reward when it lands and resolve the future
  /// with that flag on dismissal, never letting dismiss overwrite an earned
  /// reward.
  ///
  /// [userId] and [questionId] are forwarded to AdMob as Server-Side
  /// Verification options, so Google's SSV callback to our `admob-ssv` edge
  /// function knows WHO watched the ad and WHICH question. Best-effort — a
  /// failure setting them must not abort the reward flow (SSV is audit-only).
  Future<bool> showRewardedAd({String? userId, String? questionId}) async {
    final ad = _ad;
    if (ad == null) {
      preload();
      return false;
    }

    // Consume the reference up front so the same ad can't be shown twice.
    _ad = null;

    // Must be set before show(): tags the impression so the SSV callback can
    // attribute the verified reward to this user + question.
    if (userId != null || questionId != null) {
      try {
        await ad.setServerSideOptions(
          ServerSideVerificationOptions(userId: userId, customData: questionId),
        );
      } catch (e) {
        debugPrint('RewardedAdService: setServerSideOptions failed — $e');
        // SSV is audit-only and the reward flow continues regardless; record it
        // as context rather than failing the unlock.
        Monitoring.addBreadcrumb(
          'Rewarded SSV options failed',
          category: 'ads',
          data: {'error': e.toString()},
        );
      }
    }

    var earned = false;
    final completer = Completer<bool>();
    void finish() {
      if (!completer.isCompleted) completer.complete(earned);
    }

    await ad.show(
      onUserEarnedReward: () => earned = true,
      onDismissed: () {
        preload();
        finish();
      },
      onFailedToShow: (error) {
        debugPrint('RewardedAdService: failed to show — $error');
        Monitoring.addBreadcrumb(
          'Rewarded ad failed to show',
          category: 'ads',
          data: {'code': error.code, 'message': error.message},
        );
        preload();
        finish();
      },
    );
    return completer.future;
  }

  void dispose() {
    _ad?.dispose();
    _ad = null;
  }
}
