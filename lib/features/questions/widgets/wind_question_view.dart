import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feedback/app_toast.dart';
import '../../../core/locale/l10n_extension.dart';
import '../../../core/network/network_error.dart';
import '../../../data/models/question.dart';
import '../../../services/analytics.dart';
import '../../../services/purchases_service.dart';
import '../../../services/supabase_service.dart';
import '../../account/providers/session_providers.dart';
import '../../account/providers/stats_providers.dart';
import '../../account/screens/auth_screen.dart';
import '../../account/widgets/restore_sign_in_prompt.dart';
import '../../account/widgets/save_pro_prompt.dart';
import '../../monetization/providers/monetization_providers.dart';
import '../../monetization/widgets/pro_paywall_sheet.dart';
import '../providers/question_providers.dart';
import '../providers/swipe_hint_providers.dart';
import 'falling_words_text.dart';
import 'lock_reveal.dart';
import 'no_more_questions_view.dart';
import 'reveal_paywall.dart';
import 'revealing_indicator.dart';

/// Displays the current question and runs the signature "wind" transition.
///
/// On a horizontal swipe the current text accelerates off in the direction of
/// the swipe — as if blown away — then, after a short beat, the *next* question
/// assembles itself word by word, each word dropping in from above (see
/// [FallingWordsText]). No cards, no flips: just text in motion.
///
/// Navigation depends on the tier:
///   * PREMIUM walks the whole catalog, wrapping around; every question reads.
///   * A FREE user walks a forward "feed": the daily, then the questions they
///     reveal one at a time. Swiping LEFT goes forward; once past the last
///     revealed question they hit the "reveal slot" — if they hold the daily
///     credit it auto-reveals the next question, otherwise a paywall offers a
///     rewarded ad (or PRO). The server picks the next UNSEEN question and
///     returns its text; it is held in session memory only (see
///     [revealedFeedProvider]) and is not re-readable after the app closes.
///     Swiping RIGHT steps back through the questions revealed this session.
class WindQuestionView extends ConsumerStatefulWidget {
  const WindQuestionView({super.key});

  @override
  ConsumerState<WindQuestionView> createState() => _WindQuestionViewState();
}

class _WindQuestionViewState extends ConsumerState<WindQuestionView>
    with TickerProviderStateMixin {
  late final AnimationController _controller;

  /// Drives the lock-opening flourish played over the canvas right before a
  /// freely-unlocked question assembles (see [_playLockReveal]). Separate from
  /// the wind controller so the two never fight over a single timeline.
  late final AnimationController _lockController;

  /// True while the lock flourish owns the canvas — takes priority over the
  /// reveal-slot paywall/spinner in [build] so the big lock is what shows.
  bool _lockRevealing = false;

  // Offsets are expressed as a fraction of screen width and converted to pixels
  // at paint time, so the text fully clears the screen regardless of its size.
  Animation<Offset> _offset = const AlwaysStoppedAnimation(Offset.zero);
  Animation<double> _opacity = const AlwaysStoppedAnimation(1);

  /// The question currently painted. While idle it tracks the provider; during
  /// a transition it is frozen so the OUT phase keeps showing the old question.
  Question? _displayed;
  bool _animating = false;

  /// An ad or purchase flow is in flight — blocks the paywall buttons + swipes.
  bool _unlocking = false;

  /// A reveal RPC is in flight (credit or ad) — the slot shows a brief spinner.
  /// Off the slot (or once it clears) the paywall is what the slot shows by
  /// default, so there is no separate "show paywall" flag.
  bool _revealing = false;

  /// A reveal came back empty — the user has seen everything eligible for now.
  bool _exhausted = false;

  /// The `ad_cap_hit` analytics event fired for this stay on the reveal slot —
  /// build() runs repeatedly while the capped paywall is on screen, so the
  /// event is logged once per slot visit and re-armed on leaving the slot.
  bool _capHitLogged = false;

  /// The next question peeked for the paywall teaser ({id, teaser}), or null
  /// before it's fetched. Its id is passed to the ad reveal so the ad reveals the
  /// exact question that was teased.
  ({String id, String teaser})? _peeked;

  /// A peek RPC is in flight — the slot shows a spinner until the teaser arrives.
  bool _peeking = false;

  /// The in-flight peek future, or null. A peek is non-consuming (no text, no
  /// credit, not marked seen), so it is started EAGERLY while the user is still
  /// on the last feed item (see [_maybePrefetchPeek]) — by the time they swipe to
  /// the slot the teaser is usually already in [_peeked] and the paywall shows
  /// instantly, with no round-trip on the critical path. Held so a swipe that
  /// beats the prefetch reuses the same in-flight call instead of firing another.
  Future<({String id, String teaser})?>? _peekFuture;

  /// A credit reveal started BEFORE the wind-out animation, so its round-trip
  /// hides behind the ~320ms animation instead of a spinner afterwards. Held
  /// alongside its result/error and a "done" flag so the post-animation step can
  /// paint the revealed question in the same frame when the round-trip already
  /// won the race — and only fall back to the [_Revealing] spinner when the
  /// network is genuinely slower than the animation.
  Future<Question?>? _pendingReveal;
  Question? _pendingRevealResult;
  Object? _pendingRevealError;
  bool _pendingRevealDone = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _lockController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _lockController.dispose();
    super.dispose();
  }

  /// [direction] is the sign of the swipe: -1 leftward, +1 rightward.
  Future<void> _advance(int direction) async {
    if (_animating || _unlocking || _revealing || _peeking || _lockRevealing) {
      return;
    }

    // A leftward (forward) swipe is the gesture we teach: the moment the user
    // makes one — committed or not — they've discovered the feed extends past
    // the daily, so retire the right-edge swipe affordance (persisted once).
    if (direction < 0) {
      ref.read(swipeDiscoveredControllerProvider.notifier).markDiscovered();
    }

    // PREMIUM: any swipe advances forward through the wrapped catalog.
    if (ref.read(isPremiumProvider)) {
      _animating = true;
      await _animateOut(direction);
      if (!mounted) {
        _animating = false;
        return;
      }
      ref.read(questionIndexProvider.notifier).next();
      _settleIn(ref.read(currentQuestionProvider));
      _animating = false;
      return;
    }

    // FREE FEED.
    final notifier = ref.read(questionIndexProvider.notifier);
    final idx = ref.read(questionIndexProvider);
    final deckLen = ref.read(questionDeckProvider).length;
    final atSlot = idx >= deckLen;

    // RIGHT swipe — step back through this session's revealed questions.
    if (direction > 0) {
      if (idx == 0) return; // already on the daily
      _animating = true;
      await _animateOut(direction);
      if (!mounted) {
        _animating = false;
        return;
      }
      notifier.backLinear();
      _settleIn(ref.read(currentQuestionProvider));
      _animating = false;
      return;
    }

    // LEFT swipe while already on the slot — reveal with the credit if we have
    // one; otherwise the paywall buttons drive it.
    if (atSlot) {
      if (_exhausted) return;
      if (ref.read(freeUnlockCreditsProvider) >= 1) {
        setState(() => _revealing = true);
        await _reveal(viaAd: false);
      }
      return;
    }

    // LEFT swipe forward onto the next position (a revealed question, or the slot).
    //
    // If this swipe is going to land on the reveal slot, start its network work
    // NOW — concurrently with the wind-out animation — so the round-trip hides
    // behind the ~320ms animation instead of a spinner afterwards. With a credit
    // we auto-reveal the next question (the credit is spent ONLY here, on a
    // committed forward swipe, never while merely reading the daily); without one
    // we peek the teaser for the paywall. Both are awaited after the animation.
    // `willLandOnSlot` is exact: nothing mutates the deck during the animation
    // (we are the only writer and have not appended yet), so it equals the
    // post-animation slot check — the credit is never spent for a swipe that
    // ends up elsewhere.
    final willLandOnSlot = (idx + 1) >= deckLen;
    final hasCredit = ref.read(freeUnlockCreditsProvider) >= 1;
    if (willLandOnSlot && !_exhausted) {
      if (hasCredit) {
        _pendingRevealResult = null;
        _pendingRevealError = null;
        _pendingRevealDone = false;
        final reveal = ref
            .read(questionRepositoryProvider)
            .revealFreeQuestion(excludeIds: _sessionRevealedIds());
        _pendingReveal = reveal;
        // Record the outcome as it arrives so the post-animation step can skip
        // the spinner when the reveal already won the race against the animation.
        reveal
            .then(
              (q) => _pendingRevealResult = q,
              onError: (Object e) => _pendingRevealError = e,
            )
            .whenComplete(() => _pendingRevealDone = true);
      } else if (_peeked == null && _peekFuture == null) {
        // No eager prefetch yet (e.g. a very fast swipe) — start the peek now so
        // it at least overlaps the wind-out animation.
        _startPeek();
      }
    }

    _animating = true;
    await _animateOut(direction);
    if (!mounted) {
      _animating = false;
      return;
    }
    notifier.forwardLinear();

    if (!ref.read(isAtRevealSlotProvider)) {
      // Landed on an already-revealed question — step straight onto it.
      _settleIn(ref.read(currentQuestionProvider));
      _animating = false;
      return;
    }

    // On the reveal slot. Apply whatever we pre-started during the animation.
    final pendingReveal = _pendingReveal;
    _pendingReveal = null;
    if (pendingReveal != null) {
      if (_pendingRevealDone) {
        // The reveal beat the animation — paint it in the same frame, no spinner
        // and no paywall flash (these setStates coalesce into one rebuild).
        _animating = false;
        _settleIn(null); // snap the transform back to centre
        await _applyRevealResult(
          _pendingRevealResult,
          _pendingRevealError,
          viaAd: false,
        );
      } else {
        // Slower than the animation: show the brief spinner until it lands.
        setState(() => _revealing = true);
        _settleIn(ref.read(currentQuestionProvider));
        _animating = false;
        await _applyReveal(pendingReveal, viaAd: false);
      }
    } else {
      // No credit: show the paywall. Its teaser is usually already prefetched
      // (instant); only a swipe that beat the prefetch waits on the peek here.
      _settleIn(ref.read(currentQuestionProvider));
      _animating = false;
      await _peekNext();
    }
  }

  /// Eagerly prefetches the next teaser while the user is still parked on the
  /// last item of the feed (the daily, or the most recent revealed question), so
  /// the reveal-slot paywall is instant instead of waiting on a round-trip. Only
  /// for a free user who would actually hit the paywall: premium never does, and
  /// a user holding the daily credit auto-reveals (consuming) rather than peeks,
  /// so peeking ahead for them would be wasted. Cheap and idempotent — a single
  /// in-flight peek is kept and reused. Called from [build].
  void _maybePrefetchPeek() {
    if (_animating || ref.read(isPremiumProvider)) return;
    if (_peeked != null || _peekFuture != null) {
      return; // already have / getting it
    }
    final deck = ref.read(questionDeckProvider);
    if (deck.isEmpty) return;
    if (ref.read(questionIndexProvider) != deck.length - 1) {
      return; // not the last item
    }
    if (ref.read(freeUnlockCreditsProvider) >= 1) {
      return; // a credit reveals, not peeks
    }
    _startPeek();
  }

  /// This session's already-revealed question ids. The reveal pool is "not voted"
  /// (see reveal_pool_by_vote), so a shown-but-unvoted question stays eligible —
  /// passing these keeps a peek/reveal off a question already on screen this
  /// session (no wasted ad on a duplicate).
  List<String> _sessionRevealedIds() =>
      ref.read(revealedFeedProvider).map((q) => q.id).toList();

  /// Fires a peek and resolves it into [_peeked] whenever it lands — even if no
  /// one is awaiting (the eager prefetch case). Stores the future in [_peekFuture]
  /// so a concurrent swipe reuses it. A null result (ran out) is left for
  /// [_peekNext] / the slot to turn into the "no more" state.
  Future<({String id, String teaser})?> _startPeek() {
    final future = ref
        .read(questionRepositoryProvider)
        .peekNextQuestion(excludeIds: _sessionRevealedIds());
    _peekFuture = future;
    future
        .then((peeked) {
          if (!mounted || !identical(_peekFuture, future)) return;
          _peekFuture = null;
          if (peeked != null && _peeked == null) {
            setState(() => _peeked = peeked);
          }
        })
        .catchError((Object e) {
          debugPrint('peek failed: $e');
          if (mounted && identical(_peekFuture, future)) _peekFuture = null;
          return null;
        });
    return future;
  }

  /// Ensures the paywall has its teaser, awaiting the peek only when it isn't
  /// ready yet. Returns instantly when the teaser was already prefetched, so the
  /// common path shows no spinner; an empty result marks the slot "exhausted".
  Future<void> _peekNext() async {
    if (_peeked != null) return; // already prefetched — instant paywall
    final future = _peekFuture ?? _startPeek();
    setState(() => _peeking = true);
    try {
      final peeked = await future;
      if (!mounted) return;
      setState(() {
        _peeking = false;
        if (peeked != null) {
          _peeked = peeked;
        } else {
          _exhausted = true;
        }
      });
    } catch (e) {
      debugPrint('peek failed: $e');
      if (!mounted) return;
      setState(() => _peeking = false); // paywall shows without a teaser
    }
  }

  /// Accelerates the current text off the swiped edge, fading as it goes, then
  /// holds an empty canvas for a beat before the next content assembles.
  Future<void> _animateOut(int direction) async {
    final exitEnd = Offset(1.5 * direction, 0);
    _offset = Tween(
      begin: Offset.zero,
      end: exitEnd,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInCubic));
    _opacity = Tween(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));
    await _controller.forward(from: 0);
    await Future.delayed(const Duration(milliseconds: 80));
  }

  /// Snaps the outer transform back to centre and (when given) paints [q].
  void _settleIn(Question? q) {
    setState(() {
      _offset = const AlwaysStoppedAnimation(Offset.zero);
      _opacity = const AlwaysStoppedAnimation(1);
      if (q != null) _displayed = q;
    });
  }

  /// Reveals the next unseen question — via the daily credit or after an ad —
  /// and appends it to this session's feed. The index already points at the new
  /// question's slot, so appending lands the user on it. Empty result => the
  /// user has run out for now.
  Future<void> _reveal({required bool viaAd, String? questionId}) {
    final repo = ref.read(questionRepositoryProvider);
    final excludeIds = _sessionRevealedIds();
    final future = viaAd
        ? repo.revealAdQuestion(questionId: questionId, excludeIds: excludeIds)
        : repo.revealFreeQuestion(excludeIds: excludeIds);
    return _applyReveal(future, viaAd: viaAd);
  }

  /// Awaits an in-flight reveal [future] (started here or earlier, in parallel
  /// with the wind-out animation) and paints its result.
  Future<void> _applyReveal(
    Future<Question?> future, {
    required bool viaAd,
  }) async {
    Question? q;
    Object? error;
    try {
      q = await future;
    } catch (e) {
      error = e;
    }
    await _applyRevealResult(q, error, viaAd: viaAd);
  }

  /// Plays the lock-opening flourish over the canvas: a big padlock fades in,
  /// its shackle swings open, then it fades out — the moment a freely-unlocked
  /// question is "released" before it assembles. Awaited on the reveal path so
  /// the question only starts falling once the lock has opened.
  Future<void> _playLockReveal() async {
    if (!mounted) return;
    setState(() => _lockRevealing = true);
    await _lockController.forward(from: 0);
  }

  /// Paints a resolved reveal: appends the revealed [q] to this session's feed
  /// (which grows the deck and steps the user off the slot onto it), or shows the
  /// "exhausted" / error state. On a free (credit) unlock it first plays the
  /// lock-opening flourish ([_playLockReveal]) so the padlock visibly opens
  /// before the question assembles; an ad reveal skips it (the ad was
  /// interruption enough) and paints straight away.
  Future<void> _applyRevealResult(
    Question? q,
    Object? error, {
    required bool viaAd,
  }) async {
    if (!mounted) return;
    if (error != null) {
      debugPrint('reveal failed: $error');
      // The server refused because today's ad-reveal cap is spent (the synced
      // count was stale, or the client was tampered with). Re-sync so the
      // paywall re-renders in its capped, PRO-only variant.
      if (error.toString().contains('daily ad reveal limit')) {
        _notify(context.l10n.adLimitReachedToast, type: ToastType.error);
        ref.invalidate(userStatsProvider);
        setState(() => _revealing = false);
        return;
      }
      // Offline: a reveal needs the server (and, for ads, the ad network), so it
      // simply can't happen now — say "no connection" rather than the generic
      // "try again", which implies a retry would help.
      _notify(
        isOfflineError(error)
            ? context.l10n.noConnection
            : context.l10n.revealFailed,
        type: ToastType.error,
      );
      // Re-sync the server's view of the credit. A free reveal can fail because
      // the client thought it had a credit but the server disagreed (already
      // spent on another device, or stale after a UTC-midnight rollover). Without
      // this the next forward swipe re-reads the same stale credit and re-fires
      // the doomed reveal — an infinite retry loop. Re-syncing drops the credit
      // to 0 so the slot falls through to the ad / PRO paywall instead.
      ref.invalidate(userStatsProvider);
      // Stay on the slot; with _revealing cleared the paywall shows again so the
      // user can retry via ad / PRO.
      setState(() => _revealing = false);
      return;
    }
    if (q == null) {
      setState(() {
        _revealing = false;
        _exhausted = true;
      });
      return;
    }

    // Free credit unlock: open the padlock before the question appears.
    if (!viaAd) {
      await _playLockReveal();
      if (!mounted) return;
    }

    ref.read(revealedFeedProvider.notifier).append(q);
    // Re-sync server state: a credit was spent, or an ad-cap slot was consumed
    // (the count decides whether the next paywall still offers an ad).
    ref.invalidate(userStatsProvider);
    setState(() {
      _revealing = false;
      _lockRevealing = false;
      _peeked = null; // consumed
      _displayed = q;
    });
  }

  /// Watches a rewarded video, then reveals the next unseen question.
  Future<void> _watchAdReveal() async {
    if (_unlocking || _revealing) return;
    // Capped: the button is hidden, so only a stale rebuild can get here —
    // never start an ad whose reveal the server is guaranteed to refuse.
    if (ref.read(adCapReachedProvider)) return;
    setState(() => _unlocking = true);

    final ads = ref.read(rewardedAdServiceProvider);
    if (!ads.isReady) {
      ads.preload();
      _notify(context.l10n.adLoading);
      if (mounted) setState(() => _unlocking = false);
      return;
    }

    // showRewardedAd resolves to whether the reward was actually earned — the
    // reward is captured inside the service and is no longer raced by the
    // dismiss callback (see RewardedAdService). Wrapped so a throw here can't
    // leave the paywall stuck with _unlocking == true (a wedged spinner reads as
    // "it broke" to the user).
    bool earned;
    try {
      earned = await ads.showRewardedAd(
        userId: ref.read(sessionProvider).value?.userId,
        questionId: _peeked?.id,
      );
    } catch (e) {
      debugPrint('showRewardedAd failed: $e');
      earned = false;
    }
    if (!mounted) return; // widget torn down while the ad was on screen

    if (!earned) {
      _notify(context.l10n.adNoReward, type: ToastType.error);
      setState(() => _unlocking = false);
      return;
    }

    // Reward earned. Guarantee a live authenticated session BEFORE the reveal
    // RPC: the JWT can lapse during a 30s ad, or a guest's anon sign-in may have
    // failed silently at launch — either way reveal_ad_question (granted to
    // `authenticated` only) would throw a raw "permission denied" AFTER the user
    // already watched the whole ad. ensureSignedIn is a no-op fast path when a
    // session already exists.
    final userId = await SupabaseService.ensureSignedIn();
    if (!mounted) return;
    if (SupabaseService.isInitialised && userId == null) {
      _notify(context.l10n.noConnection, type: ToastType.error);
      setState(() => _unlocking = false);
      return;
    }

    setState(() {
      _unlocking = false;
      _revealing = true;
    });
    // Reveal the teased question (falls back to random server-side if it's no
    // longer eligible).
    await _reveal(viaAd: true, questionId: _peeked?.id);
  }

  /// Opens the PRO paywall. On a completed purchase the session is
  /// refreshed so the deck switches to the full premium catalog.
  Future<void> _goPremium() async {
    if (_unlocking) return;
    setState(() => _unlocking = true);

    final purchased = await showProPaywall(
      context,
      // At the daily ad cap PRO is the only way forward — funnel it separately
      // so conversion at this highest-intent wall is measurable on its own.
      source: ref.read(adCapReachedProvider)
          ? PaywallSource.adLimit
          : PaywallSource.readingLimit,
    );
    if (!mounted) return;

    if (purchased) {
      await ref.read(sessionProvider.notifier).refresh();
      if (!mounted) return;
      ref.invalidate(questionsProvider); // load the catalog premium now reads
      setState(() => _unlocking = false);
      // A guest's PRO rides on the anonymous identity — nudge them to save it to
      // a real account so a reinstall / new device can't lose it. No-ops for a
      // user who already has an account.
      await promptSaveProAccount(context, ref);
    } else {
      _notify(context.l10n.purchaseNotCompleted);
      setState(() => _unlocking = false);
    }
  }

  /// Escape hatch from the reveal slot back to the free daily — wired into both
  /// the paywall and the "no more questions" state so neither is a dead end.
  void _backToDaily() {
    if (_unlocking || _revealing) return;
    ref.read(questionIndexProvider.notifier).toDaily();
  }

  /// Restores a previous purchase — the store-required path for someone who
  /// already bought PRO (reinstalled, or a guest now on a fresh anonymous
  /// identity) so they aren't charged twice. Surfaced on the paywall because the
  /// other restore lives in Settings, which a guest can't reach.
  ///
  /// For a guest the restore is gated behind [confirmGuestRestore]: if the
  /// purchase was made on a real account, signing in brings PRO and the data
  /// back together, while a store restore would transfer the entitlement onto
  /// this empty anonymous identity.
  Future<void> _restorePurchases() async {
    if (_unlocking || _revealing) return;
    if (!await confirmGuestRestore(context, ref)) return;
    if (!mounted) return;
    setState(() => _unlocking = true);

    final restored = await PurchasesService.restorePurchases();
    if (!mounted) return;
    if (restored) {
      await ref.read(sessionProvider.notifier).refresh();
      if (!mounted) return;
      ref.invalidate(questionsProvider); // load the catalog premium now reads
    }
    _notify(
      restored
          ? context.l10n.purchaseRestoredCelebrate
          : context.l10n.noPreviousPurchase,
      type: restored ? ToastType.success : ToastType.info,
    );
    if (mounted) setState(() => _unlocking = false);
  }

  void _notify(String message, {ToastType type = ToastType.info}) {
    if (!mounted) return;
    AppToast.show(context, message, type: type);
  }

  /// Fires as each word of the new question lands. The hook is intentionally
  /// empty for now — this is where a per-word haptic tick will go.
  void _onWordLanded() {
    // TODO(vibration): add a short haptic here, e.g.
    // HapticFeedback.selectionClick(), so each landing word can be felt.
  }

  @override
  Widget build(BuildContext context) {
    final atRevealSlot = ref.watch(isAtRevealSlotProvider);

    // A new signed-in identity invalidates any teaser peeked for the previous one
    // (peek eligibility is per-uuid). Drop it so [_maybePrefetchPeek] re-peeks for
    // the new user rather than teasing a question they may already have seen.
    ref.listen(sessionProvider.select((s) => s.value?.userId), (prev, next) {
      if (prev != next) {
        _peeked = null;
        _peekFuture = null;
      }
    });

    // Keep the painted question in sync with the provider while idle. Assigning
    // the field here (rather than setState) is safe — we are already building.
    final current = ref.watch(currentQuestionProvider);
    if (!_animating && current != null) _displayed = current;

    // Off the slot, clear the in-flight flags so the next slot starts clean.
    // NOTE: we deliberately do NOT null _peeked here — a transient rebuild while
    // the paywall is on screen would otherwise wipe the teaser. It's harmless
    // off the slot (never read), and re-entering the slot re-peeks over it.
    if (!atRevealSlot) {
      _revealing = false;
      _exhausted = false;
      _peeking = false;
      _capHitLogged = false;
    }

    // Warm the next teaser while the user lingers on the last feed item, so the
    // reveal-slot paywall opens instantly instead of after a round-trip.
    _maybePrefetchPeek();

    final width = MediaQuery.of(context).size.width;
    final displayed = _displayed;

    final Widget child;
    if (_lockRevealing) {
      // The lock flourish owns the canvas until the question is ready to fall.
      child = LockReveal(controller: _lockController);
    } else if (atRevealSlot) {
      if (_revealing || _peeking) {
        child = const RevealingIndicator();
      } else if (_exhausted) {
        child = NoMoreQuestions(onBackToDaily: _backToDaily);
      } else {
        // Guests only: signing in earns the daily free-unlock credit, so the
        // paywall offers the sign-in path next to the ad. A signed-in user
        // holding the credit never even sees this paywall (auto-reveal).
        final hasAccount = ref.watch(
          sessionProvider.select((s) => s.value?.hasAccount ?? false),
        );
        // Today's ad allowance spent: the paywall drops the ad button and
        // pitches PRO as the only way to keep going (until tomorrow).
        final adCapReached = ref.watch(adCapReachedProvider);
        if (adCapReached && !_capHitLogged) {
          _capHitLogged = true;
          Analytics.log('ad_cap_hit');
        }
        child = RevealPaywall(
          teaser: _peeked?.teaser,
          adCapReached: adCapReached,
          // Midnight UTC passed while the capped wall was on screen — re-sync
          // so the fresh allowance brings the ad button back immediately.
          onAdCapExpired: () => ref.invalidate(userStatsProvider),
          onWatchAd: _watchAdReveal,
          onGetPremium: _goPremium,
          onBackToDaily: _backToDaily,
          onRestore: _restorePurchases,
          onSignIn: hasAccount ? null : () => showAuthSheet(context),
          busy: _unlocking,
        );
      }
    } else {
      child = FallingWordsText(
        displayed?.questionText ?? '',
        onWordLanded: _onWordLanded,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity.abs() > 100) _advance(velocity > 0 ? 1 : -1);
      },
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(_offset.value.dx * width, 0),
            child: Opacity(
              opacity: _opacity.value.clamp(0.0, 1.0),
              child: child,
            ),
          );
        },
        child: child,
      ),
    );
  }
}
