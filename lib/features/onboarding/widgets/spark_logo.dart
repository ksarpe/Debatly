import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// The app's logo, shown on the launch splash and the onboarding welcome. It
/// plays a soft fade + scale entrance on mount.
///
/// Prefers real brand art at `assets/images/logo.png`. Until that file exists
/// it falls back to a code-drawn wordmark — a glowing orange bolt beside
/// "Debatly" in the display font, with a slow breathing glow — so the splash
/// never shows a broken image. Swapping in the real art is just dropping the
/// PNG; nothing outside this file reaches into its internals.
class SparkLogo extends StatefulWidget {
  const SparkLogo({super.key, this.size = 56});

  /// Cap-height of the wordmark glyphs in logical pixels.
  final double size;

  @override
  State<SparkLogo> createState() => _SparkLogoState();
}

class _SparkLogoState extends State<SparkLogo> with TickerProviderStateMixin {
  late final AnimationController _entrance;
  late final AnimationController _glow;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion: settle straight to the resting frame and don't loop.
    if (MediaQuery.of(context).disableAnimations) {
      _entrance.value = 1;
      _glow.stop();
    } else {
      if (!_entrance.isCompleted) _entrance.forward();
      if (!_glow.isAnimating) _glow.repeat();
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_entrance, _glow]),
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_entrance.value);
        // A little overshoot so the mark "pops" into place.
        final scale =
            Curves.easeOutBack.transform(_entrance.value) * 0.18 + 0.82;
        // Slow swell 0..1 used to breathe the halo strength.
        final breath = 0.5 + 0.5 * math.sin(2 * math.pi * _glow.value);
        final glowAlpha = 0.30 + 0.30 * breath;
        final glowBlur = widget.size * (0.45 + 0.25 * breath);

        return Opacity(
          opacity: t,
          child: Transform.scale(
            scale: scale,
            child: Image.asset(
              'assets/images/logo.png',
              height: widget.size * 1.5,
              fit: BoxFit.contain,
              // No real logo dropped in yet → show the code-drawn wordmark so
              // the splash/onboarding never render a broken-image box.
              errorBuilder: (context, error, stackTrace) =>
                  _wordmark(context, glowAlpha, glowBlur),
            ),
          ),
        );
      },
    );
  }

  /// The fallback brand mark: a glowing bolt beside "Debatly". Used until a real
  /// `assets/images/logo.png` exists. [glowAlpha]/[glowBlur] drive the breathing
  /// halo, handed down from the animation frame in [build].
  Widget _wordmark(BuildContext context, double glowAlpha, double glowBlur) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          Icons.bolt,
          size: widget.size * 1.12,
          color: AppTheme.spark,
          shadows: [
            Shadow(
              color: AppTheme.sparkGlow.withValues(alpha: glowAlpha),
              blurRadius: glowBlur,
            ),
          ],
        ),
        SizedBox(width: widget.size * 0.06),
        Text(
          'Debatly',
          style: TextStyle(
            fontFamily: 'Anton',
            fontSize: widget.size,
            color: context.colors.ink,
            letterSpacing: 1,
            height: 1,
            shadows: [
              Shadow(
                color: AppTheme.sparkGlow.withValues(alpha: glowAlpha * 0.7),
                blurRadius: glowBlur,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
