import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/locale/app_locale.dart';
import '../../../core/time/epoch_day.dart';

/// SharedPreferences key holding whether the first-launch tutorial has been
/// completed (or skipped). Absent until the user gets through onboarding once.
const String kOnboardingCompletePrefKey = 'onboarding_complete';

/// SharedPreferences key: the local epoch day (days since 1970) onboarding was
/// completed — "day 0" of this install's life, the anchor for the `day_number`
/// analytics property on `wall_reached`.
const String kOnboardingCompletedDayPrefKey = 'onboarding_completed_day';

/// Which day of this install's life today is (0 = the onboarding day), for the
/// `wall_reached` funnel split. Installs from before the key existed are
/// backfilled to "today is day 0" on first use — a floor, not a lie the other
/// way (their walls can only look YOUNGER than they are).
int installDayNumber(SharedPreferences prefs) {
  final today = epochDay(DateTime.now());
  final stored = prefs.getInt(kOnboardingCompletedDayPrefKey);
  if (stored == null) {
    // Fire-and-forget: a failed persist just re-backfills tomorrow.
    prefs.setInt(kOnboardingCompletedDayPrefKey, today);
    return 0;
  }
  return today - stored;
}

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
    final prefs = ref.read(sharedPreferencesProvider);
    // Stamp day 0 of this install (see [installDayNumber]) alongside the flag.
    if (prefs.getInt(kOnboardingCompletedDayPrefKey) == null) {
      await prefs.setInt(
        kOnboardingCompletedDayPrefKey,
        epochDay(DateTime.now()),
      );
    }
    await prefs.setBool(kOnboardingCompletePrefKey, true);
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
