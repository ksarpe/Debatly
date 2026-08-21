import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/locale/app_locale.dart' show sharedPreferencesProvider;
import '../../../core/locale/l10n_extension.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../services/reminder_scheduler.dart';

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
class ReminderRefreshWatcher extends ConsumerStatefulWidget {
  const ReminderRefreshWatcher({super.key});

  @override
  ConsumerState<ReminderRefreshWatcher> createState() =>
      _ReminderRefreshWatcherState();
}

class _ReminderRefreshWatcherState extends ConsumerState<ReminderRefreshWatcher>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    // Read everything context/ref-bound up front — the re-arm outlives this
    // callback, and the screen can be torn down while it's still in flight.
    unawaited(_rearm(ref.read(sharedPreferencesProvider), context.l10n));
  }

  /// Best-effort: reminder upkeep must never surface as a crash, and a failed
  /// re-arm self-corrects on the next resume, vote or launch.
  Future<void> _rearm(SharedPreferences prefs, AppLocalizations l10n) async {
    try {
      await rescheduleReminderLoop(prefs: prefs, l10n: l10n);
    } catch (_) {
      // Swallowed by design — see above.
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
