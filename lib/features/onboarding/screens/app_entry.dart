import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/providers/session_providers.dart';
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

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      // Key on the phase so the switcher cross-fades between screens rather than
      // reusing the previous element.
      child: KeyedSubtree(key: ValueKey(_phase), child: child),
    );
  }
}

/// Home for every tier: the question feed with today's daily at position 0.
/// There is no hard paywall anymore — a free session gets the daily, the day
/// wall behind it, and the paywall SHEET as the conversion surface; premium
/// gets the whole catalog. The session still has to resolve first, because
/// the feed's shape (free vs premium deck) rides on it.
///
/// The gate outlives the entitlement flip, so it is also where the guest
/// "save your PRO to an account" nudge fires after a purchase.
class HomeGate extends ConsumerWidget {
  const HomeGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A guest's fresh entitlement (bought or restored) should be attached to a
    // recoverable account; the prompt no-ops for account holders. Trigger only
    // on a RESOLVED free→premium flip: the launch resolution
    // (loading→premium for an already-entitled user) must not re-prompt on
    // every open.
    ref.listen(sessionProvider, (prev, next) {
      final wasResolvedFree =
          prev?.hasValue == true && prev!.value!.isPremium == false;
      if (wasResolvedFree && next.value?.isPremium == true) {
        unawaited(promptSaveProAccount(context, ref));
      }
    });

    final session = ref.watch(sessionProvider);
    if (session.isLoading && !session.hasValue) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // A session that ERRORED outright resolves to "not premium", which would
    // silently downgrade a paying user's feed over a transient failure —
    // offer the retry instead.
    if (session.hasError && !session.hasValue) {
      return Scaffold(
        body: SafeArea(
          child: LoadError(onRetry: () => ref.invalidate(sessionProvider)),
        ),
      );
    }
    return const QuestionScreen();
  }
}
