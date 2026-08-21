import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/locale/app_locale.dart' show sharedPreferencesProvider;
import '../../../core/locale/l10n_extension.dart';
import '../../../data/repositories/question_repository.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../services/reminder_scheduler.dart';
import '../../questions/providers/question_providers.dart'
    show questionRepositoryProvider;

/// Zero-size watcher that re-arms the reminder loop every time the app returns
/// to the foreground. Mounted once on the home screen, next to the other
/// lifecycle watchers.
///
/// The loop's cadence encodes absence: a slot at day-offset N can only fire if
/// nothing re-armed the loop for N days, which is what lets the far slots say
/// "you've been away" and mean it (see `ReminderHorizon`). `main()` covers a
/// cold start and the daily vote covers a vote — but a user who leaves the app
/// resident and simply resumes it each morning does neither, and would collect
/// win-back fires while using the app daily. Resuming is the missing signal.
///
/// It also refreshes the upcoming-daily teasers first, since this is the one
/// place that owns "keep the loop fed and honest": the scheduler reads them
/// from the cache (it has to work offline and before the provider graph), so
/// something has to top that cache up while the app is actually running.
class ReminderRefreshWatcher extends ConsumerStatefulWidget {
  const ReminderRefreshWatcher({super.key});

  @override
  ConsumerState<ReminderRefreshWatcher> createState() =>
      _ReminderRefreshWatcherState();
}

class _ReminderRefreshWatcherState extends ConsumerState<ReminderRefreshWatcher>
    with WidgetsBindingObserver {
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The cold-start re-arm in `main()` runs before any network is up, so it
    // bakes whatever teasers the last session cached. Refresh once the app is
    // actually alive, then re-arm on top of the fresh calendar.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _refresh();
  }

  void _refresh() {
    if (!mounted) return;
    // Read everything context/ref-bound up front — the work outlives this
    // callback, and the screen can be torn down while it's still in flight.
    unawaited(
      _rearm(
        ref.read(sharedPreferencesProvider),
        context.l10n,
        ref.read(questionRepositoryProvider),
      ),
    );
  }

  /// Best-effort throughout: reminder upkeep must never surface as a crash, and
  /// a failed pass self-corrects on the next resume, vote or launch.
  ///
  /// The teaser refresh is deliberately not fatal to the re-arm — an offline
  /// device still deserves an honest loop built from whatever it already has.
  Future<void> _rearm(
    SharedPreferences prefs,
    AppLocalizations l10n,
    QuestionRepository repo,
  ) async {
    try {
      await repo.fetchUpcomingDailyTeasers();
    } catch (_) {
      // Stale or absent teasers just mean the evergreen pool for those slots.
    }
    try {
      await rescheduleReminderLoop(prefs: prefs, l10n: l10n);
    } catch (_) {
      // Swallowed by design — see above.
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
