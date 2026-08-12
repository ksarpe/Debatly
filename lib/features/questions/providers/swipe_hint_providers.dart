import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/app_locale.dart';

/// SharedPreferences key recording that the user has swiped forward at least
/// once — i.e. they have discovered that the feed extends past the daily. Absent
/// until the first forward swipe.
const String kSwipeDiscoveredPrefKey = 'swipe_discovered';

/// Whether the user has already discovered the "swipe for more" gesture.
///
/// Mirrors [OnboardingController]: it reads the persisted flag synchronously off
/// the injected [sharedPreferencesProvider] (so the very first frame already
/// knows whether to show the teaching affordance — no flash) and flips it, once,
/// the first time the user swipes forward off the daily. The choice survives
/// restarts, so the animated swipe affordance teaches exactly once per install,
/// for guests and accounts alike.
class SwipeDiscoveredController extends Notifier<bool> {
  @override
  bool build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getBool(kSwipeDiscoveredPrefKey) ?? false;
  }

  /// Records that the user has swiped forward. A no-op once already set, so
  /// callers can fire it on every forward swipe without guarding.
  Future<void> markDiscovered() async {
    if (state) return;
    state = true;
    await ref
        .read(sharedPreferencesProvider)
        .setBool(kSwipeDiscoveredPrefKey, true);
  }

  /// DEV tools only: clears the flag so the swipe affordance teaches again,
  /// matching a fresh install when replaying onboarding.
  Future<void> reset() async {
    state = false;
    await ref.read(sharedPreferencesProvider).remove(kSwipeDiscoveredPrefKey);
  }
}

final swipeDiscoveredControllerProvider =
    NotifierProvider<SwipeDiscoveredController, bool>(
      SwipeDiscoveredController.new,
    );
