import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';

/// The glowing "wejdz glebiej" pill. Tapping it opens the "Smaczki" panel from
/// the bottom. Every few seconds it plays a short nudge — alternating between
/// a shake and a heartbeat pulse — as a reminder that there is more behind
/// the question.
class GoDeeperButton extends StatefulWidget {
  const GoDeeperButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  State<GoDeeperButton> createState() => _GoDeeperButtonState();
}

class _GoDeeperButtonState extends State<GoDeeperButton>
    with SingleTickerProviderStateMixin {
  static const _nudgeEvery = Duration(milliseconds: 4500);
  static const _shakeDuration = Duration(milliseconds: 600);
  static const _pulseDuration = Duration(milliseconds: 900);

  late final AnimationController _nudge = AnimationController(
    vsync: this,
    duration: _shakeDuration,
  );
  Timer? _reminder;

  /// Which variant the currently running (or next) nudge plays — the two
  /// alternate so the reminder doesn't get monotonous.
  bool _pulsing = false;

  @override
  void initState() {
    super.initState();
    _reminder = Timer.periodic(_nudgeEvery, (_) {
      if (!mounted || _nudge.isAnimating) return;
      // Honour the OS-level "reduce motion" setting.
      if (MediaQuery.disableAnimationsOf(context)) return;
      _pulsing = !_pulsing;
      _nudge.duration = _pulsing ? _pulseDuration : _shakeDuration;
      _nudge.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _reminder?.cancel();
    _nudge.dispose();
    super.dispose();
  }

  /// Damped side-to-side wiggle: a few oscillations that fade out.
  double _shakeOffset(double t) => math.sin(t * math.pi * 6) * 3 * (1 - t);

  /// Gentle grow-and-shrink riding the shake: peaks mid-animation, back to
  /// normal size by the end.
  double _shakeScale(double t) => 1 + 0.08 * math.sin(t * math.pi);

  /// The alternate variant: three quick heartbeat-style pulses, no movement.
  double _pulseScale(double t) => 1 + 0.08 * math.sin(t * math.pi * 3).abs();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.l10n.goDeeper,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _nudge,
          builder: (context, child) {
            final t = _nudge.value;
            return Transform.translate(
              offset: Offset(_pulsing ? 0 : _shakeOffset(t), 0),
              child: Transform.scale(
                scale: _pulsing ? _pulseScale(t) : _shakeScale(t),
                child: child,
              ),
            );
          },
          // The shared accent-CTA look (spark gradient pill + orange glow),
          // so the lit "go deeper" affordance reads the same as every other
          // premium button in BOTH themes. Sized to the shared touch-target
          // height and stretching to whatever width the action bar hands it,
          // so it lines up flush with the share / favorite pills beside it.
          child: const DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: AppTheme.ctaRadius,
              gradient: AppTheme.ctaGradient,
              boxShadow: AppTheme.ctaGlow,
            ),
            child: SizedBox(
              height: kMinTouchTarget,
              child: Center(child: _Label()),
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label();

  @override
  Widget build(BuildContext context) {
    return Text(
      context.l10n.goDeeper.toUpperCase(),
      textAlign: TextAlign.center,
      style: AppTypography.action(
        fontSize: 13,
      ).copyWith(color: AppTheme.ctaForeground),
    );
  }
}
