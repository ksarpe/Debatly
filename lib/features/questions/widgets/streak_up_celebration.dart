import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feedback/haptics.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/models/rank.dart';
import '../../../data/models/user_stats.dart';
import '../../account/providers/stats_providers.dart';
import '../../account/providers/streak_celebration_providers.dart';
import 'animated_flame_icon.dart';
import 'stat_chips.dart' show streakChipKeyProvider;

/// Watches the synced [UserStats] and, whenever the daily streak *grows*, plays a
/// quick, non-blocking flourish: a big flame pops in the middle of the screen and
/// then flies up into the streak chip — so the streak gaining a day reads as a
/// felt reward rather than a number silently ticking up in the corner.
///
/// Mounts once, high in the screen tree, as a zero-size widget (the same shape as
/// `RankCelebrationListener`) so a single place catches every streak bump.
/// Deliberately *quieter* than the rank-up takeover: it's the everyday "+1", not
/// the rare promotion, so it stays out of the way and never blocks input.
class StreakCelebrationListener extends ConsumerStatefulWidget {
  const StreakCelebrationListener({super.key});

  @override
  ConsumerState<StreakCelebrationListener> createState() =>
      _StreakCelebrationListenerState();
}

class _StreakCelebrationListenerState
    extends ConsumerState<StreakCelebrationListener> {
  /// Held from the moment a flourish is decided until its overlay removes itself,
  /// so two near-simultaneous stats updates can't stack two flames.
  bool _busy = false;
  bool _checkedInitial = false;

  @override
  Widget build(BuildContext context) {
    // Post-vote (and any later) refreshes flow through here.
    ref.listen<AsyncValue<UserStats?>>(userStatsProvider, (_, next) {
      final stats = next.value;
      if (stats != null) _maybeCelebrate(stats);
    });

    // Cover the case where stats resolved before this listener mounted — but note
    // this only ever *seeds* the baseline (a streak that didn't just grow won't
    // fire), so opening the app to an existing streak shows nothing.
    if (!_checkedInitial) {
      final initial = ref.read(userStatsProvider).value;
      if (initial != null) {
        _checkedInitial = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _maybeCelebrate(initial);
        });
      }
    }

    return const SizedBox.shrink();
  }

  Future<void> _maybeCelebrate(UserStats stats) async {
    if (_busy) return;
    // Set synchronously before the await so a second stats update during the
    // evaluate can't slip past the guard.
    _busy = true;
    var willShow = false;
    try {
      final reduceMotion = MediaQuery.of(context).disableAnimations;
      final ladder = ref.read(ranksProvider).value ?? kDefaultRanks;
      final streak = await ref
          .read(streakCelebrationControllerProvider.notifier)
          .evaluate(stats);
      if (streak == null || !mounted) return;

      // On a promotion day the rank-up celebration (its full-screen confetti
      // takeover) owns the moment and already shows the streak, so don't stack
      // this lighter flourish under it. The baseline was still advanced above, so
      // it won't re-fire later. Reduced motion skips the flight entirely (the
      // chip number still updates).
      final isPromotionDay = ladder.any(
        (r) => r.tier > 0 && r.minStreak == streak,
      );
      if (reduceMotion || isPromotionDay) return;

      willShow = true;
      _showBurst(streak);
    } finally {
      // The shown path clears _busy from the overlay's onDone instead.
      if (!willShow) _busy = false;
    }
  }

  /// Inserts the one-shot [_StreakBurst] into the root overlay (so the flame can
  /// fly up into the app bar) and tears it down when it finishes.
  void _showBurst(int streak) {
    final overlay = Overlay.of(context, rootOverlay: true);
    final media = MediaQuery.of(context);
    final target =
        _streakChipCenter() ??
        Offset(media.size.width / 2, media.padding.top + 28);
    final rankTier = ref.read(userStatsValueProvider).rankTier;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _StreakBurst(
        streak: streak,
        rankTier: rankTier,
        target: target,
        onDone: () {
          entry.remove();
          _busy = false;
        },
      ),
    );
    overlay.insert(entry);
  }

  /// The streak chip's centre in global coordinates, via the shared key the chip
  /// tags its flame with — or null if it isn't currently on screen (then the
  /// caller falls back to a top-centre point).
  Offset? _streakChipCenter() {
    final ctx = ref.read(streakChipKeyProvider).currentContext;
    final box = ctx?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(box.size.center(Offset.zero));
  }
}

/// The flourish itself: a big flame that pops in near the middle of the screen,
/// holds for a beat, then sails up to [target] (the streak chip), shrinking as it
/// goes — landing with a soft radial flash and a rising "+1". Non-blocking
/// ([IgnorePointer]) and self-removing via [onDone].
class _StreakBurst extends StatefulWidget {
  const _StreakBurst({
    required this.streak,
    required this.rankTier,
    required this.target,
    required this.onDone,
  });

  final int streak;
  final int rankTier;

  /// Where the flame flies TO, in global (overlay) coordinates.
  final Offset target;
  final VoidCallback onDone;

  @override
  State<_StreakBurst> createState() => _StreakBurstState();
}

class _StreakBurstState extends State<_StreakBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  // Big in the middle, chip-sized on arrival.
  static const double _bigSize = 96;
  static const double _smallSize = 22;

  /// Timeline point where the flame reaches the chip: the landing flash starts
  /// here, and so does the thump. Shared by the frame builder and the haptic
  /// listener so the buzz can never drift off the pixels that cause it.
  static const double _landAt = 0.80;

  /// One-shot latch for that thump — the listener fires every frame.
  bool _thumped = false;

  @override
  void initState() {
    super.initState();
    _c =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 1700),
        )..addStatusListener((s) {
          if (s == AnimationStatus.completed) widget.onDone();
        });
    // The flame striking the streak chip is the one beat of this flourish the
    // user is meant to *feel*: the number in the corner stops ticking up
    // silently and lands. The listener owns it rather than the frame builder,
    // so painting stays free of side effects.
    _c.addListener(() {
      if (_thumped || _c.value < _landAt) return;
      _thumped = true;
      Haptics.impact();
    });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          // Start a touch above the true middle, roughly where the question sits.
          final origin = Offset(size.width / 2, size.height * 0.42);
          return AnimatedBuilder(
            animation: _c,
            builder: (context, _) => _frame(origin),
          );
        },
      ),
    );
  }

  Widget _frame(Offset origin) {
    final t = _c.value;

    // Entrance: an elastic pop + fade-in over the first beat.
    final appear = Curves.easeOut.transform((t / 0.20).clamp(0.0, 1.0));
    final pop = Curves.elasticOut.transform((t / 0.34).clamp(0.0, 1.0));

    // Travel: hold, then ease up to the chip.
    final travelRaw = ((t - 0.46) / (0.86 - 0.46)).clamp(0.0, 1.0);
    final travel = Curves.easeInOutCubic.transform(travelRaw);
    final pos = Offset.lerp(origin, widget.target, travel)!;
    final flameSize = lerpDouble(_bigSize, _smallSize, travel)!;

    // The flame fades out quickly once it has landed.
    final landFade =
        1 - Curves.easeIn.transform(((t - 0.86) / 0.14).clamp(0.0, 1.0));
    final flameOpacity = appear * landFade;

    // The big soft halo behind the flame is brightest in the middle and gone by
    // the time it reaches the chip, so it doesn't smear up the screen.
    final haloOpacity = appear * (1 - travel) * 0.55;

    // The landing flash + the rising "+1", both keyed to arrival.
    final landRaw = ((t - _landAt) / (1 - _landAt)).clamp(0.0, 1.0);
    final flashScale = lerpDouble(0.4, 1.7, Curves.easeOut.transform(landRaw))!;
    final flashOpacity = (landRaw <= 0 ? 0.0 : (1 - landRaw)) * 0.9;

    final flame = flameColor(context);

    return Stack(
      children: [
        // Landing flash — a quick expanding ring on the chip.
        if (landRaw > 0)
          Positioned(
            left: widget.target.dx - flameSize,
            top: widget.target.dy - flameSize,
            width: flameSize * 2,
            height: flameSize * 2,
            child: Center(
              child: Transform.scale(
                scale: flashScale,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: flame.withValues(alpha: flashOpacity),
                      width: 3,
                    ),
                  ),
                ),
              ),
            ),
          ),

        // The travelling flame (with its soft halo).
        Positioned(
          left: pos.dx - flameSize,
          top: pos.dy - flameSize,
          width: flameSize * 2,
          height: flameSize * 2,
          child: Center(
            child: Opacity(
              opacity: flameOpacity.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: pop,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: flame.withValues(alpha: haloOpacity),
                        blurRadius: flameSize * 0.9,
                        spreadRadius: flameSize * 0.2,
                      ),
                    ],
                  ),
                  child: AnimatedFlameIcon(
                    streak: widget.streak,
                    rankTier: widget.rankTier,
                    size: flameSize,
                  ),
                ),
              ),
            ),
          ),
        ),

        // The "+1" lifting off the chip as the flame lands.
        if (landRaw > 0)
          Positioned(
            left: widget.target.dx + 14,
            top: widget.target.dy - 10 - 22 * Curves.easeOut.transform(landRaw),
            child: Opacity(
              opacity: ((1 - landRaw) * 1.0).clamp(0.0, 1.0),
              child: Text(
                '+1',
                style: AppTypography.numeric(16).copyWith(
                  color: flame,
                  shadows: [
                    Shadow(color: flame.withValues(alpha: 0.6), blurRadius: 10),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
