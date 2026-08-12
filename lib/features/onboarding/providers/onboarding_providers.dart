import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/app_locale.dart';

/// SharedPreferences key holding whether the first-launch tutorial has been
/// completed (or skipped). Absent until the user gets through onboarding once.
const String kOnboardingCompletePrefKey = 'onboarding_complete';

/// Whether the welcome tutorial has already been seen.
///
/// Mirrors [LocaleController]'s shape: it reads the persisted flag synchronously
/// off the injected [sharedPreferencesProvider] (so `AppEntry` can branch on the
/// very first frame without a loading flash) and flips it — once — when the user
/// finishes or skips onboarding. The choice survives restarts, so the tutorial
/// runs exactly once per install, for guests and accounts alike.
class OnboardingController extends Notifier<bool> {
  @override
  bool build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getBool(kOnboardingCompletePrefKey) ?? false;
  }

  /// Marks onboarding as done and persists it. A no-op once already complete, so
  /// callers can fire it without guarding.
  Future<void> complete() async {
    if (state) return;
    state = true;
    await ref
        .read(sharedPreferencesProvider)
        .setBool(kOnboardingCompletePrefKey, true);
  }

  /// DEV tools only: clears the persisted flag so the tutorial runs again on
  /// the next launch ([AppEntry] reads it once at startup).
  Future<void> reset() async {
    state = false;
    await ref
        .read(sharedPreferencesProvider)
        .remove(kOnboardingCompletePrefKey);
  }
}

final onboardingControllerProvider =
    NotifierProvider<OnboardingController, bool>(OnboardingController.new);
