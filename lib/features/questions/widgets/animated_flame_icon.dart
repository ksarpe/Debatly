import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Warm amber base for the streak flame — a golden, yellow-leaning warm that
/// reads as "fire" and stays distinct from the more saturated, red-leaning
/// orange "spark" accent (and the free-unlock chip) next to it.
const Color kFlame = Color(0xFFF59E0B);

/// Deeper amber for the flame on light themes: the bright [kFlame] and its glow
/// wash out against the off-white canvas, so the still flame and the streak
/// count "get lost". On light we drop to this richer amber for legibility.
const Color kFlameLight = Color(0xFFD97706);

/// The flame base colour for the current theme — bright [kFlame] on dark, the
/// deeper [kFlameLight] on light. Use for the streak glyph and its count so
/// both stay readable on either canvas.
Color flameColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light ? kFlameLight : kFlame;

/// Cool sky-blue for the streak's "graces" — the forgiving grace window that
/// cushions a missed day. The deliberate cold counterpoint to [kFlame], used by
/// the rank sheet's grace warning.
const Color kGrace = Color(0xFF38BDF8);

/// The streak flame, brought to life.
///
/// On a live streak it layers four cheap effects, all intensifying with the
/// streak length ([_heat]):
///  * a **shimmer** — a hot band sweeping up the glyph via a moving gradient;
///  * a **breathing** halo whose blur/alpha swell and ebb;
///  * a candle-like **flicker** — a tiny irregular scale jitter;
///  * a one-shot **burst** — a bright pop whenever the user climbs a rank.
///
/// It falls back to a still, softly-lit flame when there is no streak
/// ([streak] == 0) or the platform asks for reduced motion, so it costs nothing
/// when there's nothing to celebrate.
class AnimatedFlameIcon extends StatefulWidget {
  const AnimatedFlameIcon({
    super.key,
    required this.streak,
    required this.rankTier,
    this.size = 20,
  });

  /// A flame that is simply alight — near full heat, no streak or rank
  /// behind it. For places that borrow the glyph as decoration (the modes
  /// screen's ember row) rather than as the streak indicator.
  const AnimatedFlameIcon.lit({super.key, this.size = 20})
    : streak = 30,
      rankTier = 0;

  /// Current streak length. 0 renders the muted, static flame.
  final int streak;

  /// Current rank tier; an increase (while the streak is live) fires the burst.
  final int rankTier;

  final double size;

  bool get active => streak > 0;

  @override
  State<AnimatedFlameIcon> createState() => _AnimatedFlameIconState();
}

class _AnimatedFlameIconState extends State<AnimatedFlameIcon>
    with TickerProviderStateMixin {
  /// One looping clock drives the shimmer, breathing and flicker. Every effect
  /// is phrased as an *integer* number of cycles over this period, so the loop
  /// is seamless at the wrap (no visible jump when value resets 1 → 0).
  static const Duration _period = Duration(milliseconds: 3000);

  late final AnimationController _loop;
  late final AnimationController _burst;

  @override
  void initState() {
    super.initState();
    _loop = AnimationController(vsync: this, duration: _period);
    _burst = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced-motion can flip at runtime; re-evaluate whether the loop runs.
    _syncRunning();
  }

  @override
  void didUpdateWidget(AnimatedFlameIcon old) {
    super.didUpdateWidget(old);
    _syncRunning();
    // Climbed a rank while the streak is alive → celebrate (unless motion off).
    if (widget.active && widget.rankTier > old.rankTier && !_reduceMotion) {
      _burst.forward(from: 0);
    }
  }

  bool get _reduceMotion => MediaQuery.of(context).disableAnimations;

  /// Run the looping clock only when there's a live streak and motion is
  /// allowed; otherwise stop it so the widget is free when idle.
  void _syncRunning() {
    final shouldRun = widget.active && !_reduceMotion;
    if (shouldRun && !_loop.isAnimating) {
      _loop.repeat();
    } else if (!shouldRun && _loop.isAnimating) {
      _loop.stop();
    }
  }

  /// 0..1 "heat": ramps quickly over the first days then saturates around a
  /// month, loosely tracking the rank ladder (3/7/14/30…). Drives palette
  /// warmth, glow strength and flicker amplitude.
  double get _heat => (1 - math.exp(-widget.streak / 18)).clamp(0.0, 1.0);

  @override
  void dispose() {
    _loop.dispose();
    _burst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active || _reduceMotion) {
      return _StillFlame(size: widget.size, active: widget.active);
    }

    final heat = _heat;
    const twoPi = 2 * math.pi;

    // On a light canvas the flame's near-white tips and white burst wash out, so
    // the glyph reads as blank. Keep the glowing-on-black palette for dark mode,
    // but on light themes hold the tips and burst at saturated amber/orange so
    // the flame stays clearly visible against the off-white background.
    final isLight = Theme.of(context).brightness == Brightness.light;

    return AnimatedBuilder(
      animation: Listenable.merge([_loop, _burst]),
      builder: (context, _) {
        final p = _loop.value; // 0..1 loop phase
        final burst = Curves.easeOut.transform(_burst.value); // 0..1

        // Flicker: a few incommensurate (but integer-cycle) sines sum into an
        // irregular wobble that still wraps cleanly. Roughly -1..1.
        final flick =
            0.5 * math.sin(twoPi * 7 * p) +
            0.3 * math.sin(twoPi * 11 * p + 1.7) +
            0.2 * math.sin(twoPi * 13 * p + 3.1);

        // Breathing: one slow swell over the whole loop. 0..1.
        final breath = 0.5 + 0.5 * math.sin(twoPi * p);

        // Scale: subtle flicker jitter (a little stronger as it heats up) times
        // a celebratory pop that peaks mid-burst.
        final flickerScale = 1 + flick * (0.015 + 0.02 * heat);
        final burstScale = 1 + math.sin(math.pi * burst) * 0.28;
        final scale = flickerScale * burstScale;

        // Glow: breathes, grows with heat, flares on a burst.
        final glowAlpha = (0.35 + 0.25 * breath + 0.35 * heat + 0.6 * burst)
            .clamp(0.0, 1.0);
        final glowBlur =
            widget.size * (0.5 + 0.25 * breath + 0.4 * heat + 0.8 * burst);

        // Palette: cooler amber at low streaks; pushes toward a deep-orange core
        // and bright tips as it heats. A burst momentarily blows it brighter.
        // The hot tip and burst target stay saturated on light themes (where
        // near-white would vanish) and reach toward white on dark themes.
        final tip = isLight
            ? Color.lerp(
                const Color(0xFFFB923C),
                const Color(0xFFFBBF24),
                heat,
              )!
            : Color.lerp(
                const Color(0xFFFFD27D),
                const Color(0xFFFFF3C4),
                heat,
              )!;
        final flare = isLight ? const Color(0xFFFDE047) : Colors.white;
        var cool = Color.lerp(
          isLight ? kFlameLight : kFlame,
          const Color(0xFFEA580C),
          heat,
        )!;
        var hot = tip;
        if (burst > 0) {
          cool = Color.lerp(cool, flare, 0.5 * burst)!;
          hot = Color.lerp(hot, flare, 0.7 * burst)!;
        }

        return Transform.scale(
          scale: scale,
          child: ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (rect) => LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [cool, hot, cool],
              tileMode: TileMode.repeated,
              // Slide the hot band up by exactly one rect-height over the loop;
              // with repeated tiling the cool→hot→cool cycle reads as a flame
              // licking upward and wraps seamlessly.
              transform: _GradientShift(dy: -p),
            ).createShader(rect),
            child: Icon(
              Icons.local_fire_department_rounded,
              size: widget.size,
              color: Colors.white,
              shadows: [
                Shadow(
                  color: cool.withValues(alpha: glowAlpha),
                  blurRadius: glowBlur,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Translates a gradient's shader vertically by a fraction of its bounds — used
/// to sweep the flame's shimmer band upward.
class _GradientShift extends GradientTransform {
  const _GradientShift({required this.dy});

  final double dy;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(0, bounds.height * dy, 0);
}

/// The non-animated flame: muted grey at streak 0, warm amber with a soft fixed
/// halo when there's a streak but motion is disabled.
class _StillFlame extends StatelessWidget {
  const _StillFlame({required this.size, required this.active});

  final double size;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? flameColor(context) : context.colors.subtle;
    return Icon(
      Icons.local_fire_department_rounded,
      size: size,
      color: color,
      shadows: active
          ? [
              Shadow(
                color: color.withValues(alpha: 0.6),
                blurRadius: size * 0.6,
              ),
            ]
          : null,
    );
  }
}
