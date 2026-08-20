import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/startup/supabase_init_provider.dart';
import '../../../services/supabase_service.dart';
import '../../account/providers/session_providers.dart';
import '../../account/widgets/password_recovery_listener.dart';
import '../../account/widgets/pending_registration_watcher.dart';
import '../../account/widgets/save_pro_prompt.dart';
import '../../questions/screens/question_screen.dart';
import '../../questions/widgets/load_error.dart';
import '../providers/onboarding_providers.dart';
import 'onboarding_screen.dart';
import 'splash_screen.dart';

/// The app's first widget under `MaterialApp`: a tiny launch state machine that
/// shows the brand splash, then routes to the welcome tutorial on a first run
/// or straight to the home gate for a returning user.
///
/// The onboarding flag is read synchronously (it's resolved off SharedPreferences
/// before the first frame in `main()`), so the branch is decided up front with no
/// loading flash. Phases cross-fade into one another.
class AppEntry extends ConsumerStatefulWidget {
  const AppEntry({super.key});

  @override
  ConsumerState<AppEntry> createState() => _AppEntryState();
}

enum _Phase { splash, onboarding, home }

class _AppEntryState extends ConsumerState<AppEntry> {
  _Phase _phase = _Phase.splash;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final onboardingDone = ref.read(onboardingControllerProvider);
    // A brand moment on every launch — a touch longer on a first run (it leads
    // into the tutorial) than for a returning user.
    final splashFor = onboardingDone
        ? const Duration(milliseconds: 1100)
        : const Duration(milliseconds: 1900);
    _timer = Timer(splashFor, () {
      if (!mounted) return;
      setState(() {
        _phase = onboardingDone ? _Phase.home : _Phase.onboarding;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _finishOnboarding() {
    // Persist so the tutorial never runs again, then reveal the live app —
    // every tier lands on the feed with today's daily (see [HomeGate]).
    ref.read(onboardingControllerProvider.notifier).complete();
    if (mounted) setState(() => _phase = _Phase.home);
  }

  @override
  Widget build(BuildContext context) {
    final Widget child = switch (_phase) {
      _Phase.splash => const SplashView(),
      _Phase.onboarding => OnboardingScreen(onFinish: _finishOnboarding),
      _Phase.home => const HomeGate(),
    };

    // Above the phase switcher: a tapped password-reset link can arrive in any
    // phase, splash included, and must not be swallowed — and a registration
    // confirmed in the browser has to be picked up wherever the user happens to
    // be when they come back (see [PendingRegistrationWatcher]).
    return PasswordRecoveryListener(
      child: PendingRegistrationWatcher(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 450),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          // Key on the phase so the switcher cross-fades between screens rather
          // than reusing the previous element.
          child: KeyedSubtree(key: ValueKey(_phase), child: child),
        ),
      ),
    );
  }
}

/// How long [HomeGate] waits on an unresolved session before it stops showing
/// a bare spinner and offers a way out.
///
/// A backstop, not a deadline: every call the session load makes is itself
/// bounded, so a launch that is merely slow still resolves and the gate swaps
/// the retry back for the feed on its own. This exists for the case the
/// timeouts can't cover — a future that resolves to neither a value nor an
/// error — because `session.hasError` is the ONLY branch that offers a retry
/// and a hang never errors. Without it the sole exit is a force-quit.
///
/// So it has to sit ABOVE the bounded chain, not inside it. `_load` can spend
/// 15s on sign-in + 10s linking the store identity + 10s syncing the
/// entitlement + 15s reading the profile + 10s on the store's own answer = 60s
/// of legitimate, self-resolving slowness. Firing at 20s put a retry on screen
/// while that was still running, and taking it threw the 20s of progress away
/// and started the whole 60s again — a button that made the launch strictly
/// worse the more it was pressed. Past 70s nothing bounded can still be
/// running, so anything the watchdog catches now is a genuine hang.
const Duration kSessionWatchdogTimeout = Duration(seconds: 70);

/// Home for every tier: the question feed with today's daily at position 0.
/// There is no hard paywall anymore — a free session gets the daily, the day
/// wall behind it, and the paywall SHEET as the conversion surface; premium
/// gets the whole catalog. The session still has to resolve first, because
/// the feed's shape (free vs premium deck) rides on it.
///
/// The gate outlives the entitlement flip, so it is also where the guest
/// "save your PRO to an account" nudge fires after a purchase.
class HomeGate extends ConsumerStatefulWidget {
  const HomeGate({super.key});

  @override
  ConsumerState<HomeGate> createState() => _HomeGateState();
}

class _HomeGateState extends ConsumerState<HomeGate> {
  Timer? _watchdog;

  /// A backend retry is in flight — the init is bounded but not instant, and a
  /// button that looks inert for several seconds reads as a broken app on top
  /// of a broken backend.
  bool _retryingBackend = false;

  /// The session has been loading past [kSessionWatchdogTimeout] — show the
  /// retry instead of the spinner. Only consulted while the session is still
  /// unresolved, so a load that lands late still wins and reveals the feed.
  bool _stuck = false;

  @override
  void initState() {
    super.initState();
    _armWatchdog();
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    super.dispose();
  }

  void _armWatchdog() {
    _watchdog?.cancel();
    _stuck = false;
    _watchdog = Timer(kSessionWatchdogTimeout, () {
      if (!mounted) return;
      final session = ref.read(sessionProvider);
      if (session.isLoading && !session.hasValue) setState(() => _stuck = true);
    });
  }

  void _retry() {
    setState(_armWatchdog);
    ref.invalidate(sessionProvider);
  }

  /// Re-runs the Supabase init behind the backend error state. The session
  /// reload rides on the status listener in [build], so a retry that succeeds
  /// also mints the guest the failed launch never got.
  Future<void> _retryBackend() async {
    if (_retryingBackend) return;
    setState(() => _retryingBackend = true);
    try {
      await ref.read(supabaseInitProvider.notifier).retry();
    } finally {
      if (mounted) setState(() => _retryingBackend = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // A guest's fresh entitlement (bought or restored) should be attached to a
    // recoverable account; the prompt no-ops for account holders. Trigger only
    // on a RESOLVED free→premium flip: the launch resolution
    // (loading→premium for an already-entitled user) must not re-prompt on
    // every open.
    ref.listen(sessionProvider, (prev, next) {
      final wasResolvedFree =
          prev?.hasValue == true && prev!.value!.isPremium == false;
      if (wasResolvedFree && next.value?.isPremium == true) {
        // Next frame, not this one. The same entitlement flip can be seen by a
        // paywall that is still on screen, and pushing a dialog into the middle
        // of that route's own exit put the two in a race for the navigator.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(promptSaveProAccount(context, ref));
        });
      }
    });

    // A backend that came up LATE — after the launch already gave up on it —
    // has to be answered with a session reload: that launch resolved with no
    // identity at all, so the guest was never minted.
    ref.listen(supabaseInitProvider, (prev, next) {
      if (prev != next && next == SupabaseInitStatus.ready) {
        // Re-arm alongside the invalidate: this starts a FRESH session load,
        // and a load with no watchdog on it is exactly the spinner-with-no-exit
        // the watchdog exists to prevent.
        setState(_armWatchdog);
        ref.invalidate(sessionProvider);
      }
    });

    // A CONFIGURED backend that never came up is NOT mock mode. Left to the
    // branches below, the feed would render on invented mock questions with a
    // fabricated split and quietly discard every vote — indistinguishable from
    // the real app. Say it out loud instead, and retry the INIT rather than the
    // session load, because the init is what actually failed.
    if (ref.watch(supabaseInitProvider) == SupabaseInitStatus.failed) {
      return Scaffold(
        body: SafeArea(
          child: _retryingBackend
              ? const Center(child: CircularProgressIndicator())
              : LoadError(
                  title: context.l10n.backendUnavailableTitle,
                  body: context.l10n.backendUnavailableBody,
                  onRetry: _retryBackend,
                ),
        ),
      );
    }

    final session = ref.watch(sessionProvider);
    if (session.isLoading && !session.hasValue) {
      // A load that never ends can't reach the error branch below, so the
      // watchdog is what turns it into something the user can act on.
      return _stuck
          ? _retryScaffold()
          : const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // A session that ERRORED outright resolves to "not premium", which would
    // silently downgrade a paying user's feed over a transient failure —
    // offer the retry instead.
    if (session.hasError && !session.hasValue) return _retryScaffold();
    return const QuestionScreen();
  }

  Widget _retryScaffold() => Scaffold(
    body: SafeArea(child: LoadError(onRetry: _retry)),
  );
}
