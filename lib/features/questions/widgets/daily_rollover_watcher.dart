import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/question_providers.dart';

/// Zero-size watcher that rolls the feed over to the new LOCAL day — the fix
/// for "the app stayed open across midnight and still shows yesterday's
/// daily". Mounted once on the home screen, for both tiers.
///
/// Two triggers, both funnelled through [maybeRolloverDaily] (a no-op while
/// the daily's fetch day is still today):
///   * app resume — the common case: the phone slept past midnight;
///   * a slow periodic check — the screen-left-on case. The day wall's own
///     1-second countdown covers the free user staring at the wall; this
///     timer only needs to catch the feed itself, so a minute is plenty.
class DailyRolloverWatcher extends ConsumerStatefulWidget {
  const DailyRolloverWatcher({super.key});

  @override
  ConsumerState<DailyRolloverWatcher> createState() =>
      _DailyRolloverWatcherState();
}

class _DailyRolloverWatcherState extends ConsumerState<DailyRolloverWatcher>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) maybeRolloverDaily(ref);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      maybeRolloverDaily(ref);
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
