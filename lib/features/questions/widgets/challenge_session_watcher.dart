import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/challenge_providers.dart';

/// Zero-size watcher that turns app-lifecycle changes into the challenge
/// session's clock: leaving the foreground stamps the moment, and a resume
/// after 30+ minutes away starts a fresh session (re-arming the per-session
/// gate cap). Mounted once on the home screen, next to [DailyRolloverWatcher].
class ChallengeSessionWatcher extends ConsumerStatefulWidget {
  const ChallengeSessionWatcher({super.key});

  @override
  ConsumerState<ChallengeSessionWatcher> createState() =>
      _ChallengeSessionWatcherState();
}

class _ChallengeSessionWatcherState
    extends ConsumerState<ChallengeSessionWatcher>
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
    if (!mounted) return;
    final session = ref.read(challengeSessionProvider.notifier);
    switch (state) {
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        session.markBackgrounded();
      case AppLifecycleState.resumed:
        session.maybeResetOnResume();
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        // Inactive is too twitchy to count as "in background" (it fires for
        // the notification shade and app-switcher peeks); detached has no
        // resume to pair with.
        break;
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
