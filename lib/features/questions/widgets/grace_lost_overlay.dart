import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feedback/haptics.dart';
import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/models/user_stats.dart';
import '../../account/providers/grace_providers.dart';
import '../../account/providers/stats_providers.dart';
import 'animated_flame_icon.dart' show graceColor;

/// Watches the synced [UserStats] and, on the first sync that shows a grace
/// was spent (a missed day ate one of the streak's three forgiven days), plays
/// the "a grace is gone" moment: a heart cracks in half mid-screen, with the
/// count of graces still standing and the way out (vote today).
///
/// Mounts once, high in the screen tree, as a zero-size widget — the same
/// shape as `StreakCelebrationListener`. The decision (and its once-per-lost-
/// grace memory) lives in [GraceLostController]; this only shows it. It fires
/// on launch by construction: the countdown only moves overnight, so the
/// stats sync that reveals it is the first one of the day.
class GraceLostListener extends ConsumerStatefulWidget {
  const GraceLostListener({super.key});

  @override
  ConsumerState<GraceLostListener> createState() => _GraceLostListenerState();
}

class _GraceLostListenerState extends ConsumerState<GraceLostListener> {
  /// Held from the decision until the overlay removes itself, so two
  /// near-simultaneous stats updates can't stack two hearts.
  bool _busy = false;
  bool _checkedInitial = false;

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<UserStats?>>(userStatsProvider, (_, next) {
      final stats = next.value;
      if (stats != null) _maybeShow(stats);
    });

    // Stats may have resolved before this listener mounted (ref.listen only
    // fires on change) — the launch case, which is exactly the one that matters.
    if (!_checkedInitial) {
      final initial = ref.read(userStatsProvider).value;
      if (initial != null) {
        _checkedInitial = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _maybeShow(initial);
        });
      }
    }

    return const SizedBox.shrink();
  }

  Future<void> _maybeShow(UserStats stats) async {
    if (_busy) return;
    _busy = true;
    var willShow = false;
    try {
      final left = await ref
          .read(graceLostControllerProvider.notifier)
          .evaluate(stats);
      if (left == null || !mounted) return;
      willShow = true;
      showGraceLostOverlay(
        context,
        gracesLeft: left,
        onDone: () {
          _busy = false;
        },
      );
    } finally {
      if (!willShow) _busy = false;
    }
  }
}

/// Inserts the one-shot cracking-heart moment into the root overlay (so it
/// sits above the app bar and any sheet) and tears it down when it finishes
/// or is tapped away. [onDone] runs once, after removal. Also the DEV tools'
/// preview entry point.
void showGraceLostOverlay(
  BuildContext context, {
  required int gracesLeft,
  VoidCallback? onDone,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _GraceLostMoment(
      gracesLeft: gracesLeft,
      onDone: () {
        entry.remove();
        onDone?.call();
      },
    ),
  );
  overlay.insert(entry);
}

/// The moment itself: the canvas dims, a grace-blue heart pops in, trembles,
/// then cracks along a jagged seam — the halves drift apart and lose their
/// colour — while the message settles in underneath. Tap anywhere to close
/// early; otherwise it fades out on its own after a beat. The crack is the one
/// point the user is meant to *feel* ([Haptics.impact]); under reduced motion
/// the final frame is shown at once and nothing buzzes.
class _GraceLostMoment extends StatefulWidget {
  const _GraceLostMoment({required this.gracesLeft, required this.onDone});

  final int gracesLeft;
  final VoidCallback onDone;

  @override
  State<_GraceLostMoment> createState() => _GraceLostMomentState();
}

class _GraceLostMomentState extends State<_GraceLostMoment>
    with TickerProviderStateMixin {
  late final AnimationController _c;
  late final AnimationController _fade;
  Timer? _autoClose;

  /// Timeline points (fractions of [_c]). Shared by the frame builder and the
  /// haptic listener so the buzz can never drift off the pixels that cause it.
  static const double _trembleAt = 0.22;
  static const double _crackAt = 0.36;
  static const double _textAt = 0.48;

  /// How long the finished frame holds before the overlay fades itself out.
  static const Duration _hold = Duration(milliseconds: 2200);

  bool _ticked = false;
  bool _cracked = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      value: 1,
    );
    _c.addListener(_onTick);
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        _autoClose = Timer(_hold, _close);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.of(context).disableAnimations) {
        // Jump straight to the settled frame: no motion, no haptics.
        _ticked = true;
        _cracked = true;
        _c.value = 1;
        _autoClose = Timer(_hold, _close);
      } else {
        _c.forward();
      }
    });
  }

  void _onTick() {
    if (!_ticked && _c.value >= _trembleAt) {
      _ticked = true;
      Haptics.tick();
    }
    if (!_cracked && _c.value >= _crackAt) {
      _cracked = true;
      Haptics.impact();
    }
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _autoClose?.cancel();
    if (!MediaQuery.of(context).disableAnimations) {
      await _fade.reverse();
    }
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    _autoClose?.cancel();
    _c.removeListener(_onTick);
    _c.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final grace = graceColor(context);
    final l10n = context.l10n;

    return FadeTransition(
      opacity: _fade,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _close,
        child: Material(
          type: MaterialType.transparency,
          child: ColoredBox(
            color: colors.background.withValues(alpha: 0.86),
            child: SafeArea(
              child: Center(
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) {
                    final t = _c.value;

                    // Entrance: an elastic pop + fade-in.
                    final appear = Curves.easeOut.transform(
                      (t / 0.16).clamp(0.0, 1.0),
                    );
                    final pop = Curves.elasticOut.transform(
                      (t / 0.30).clamp(0.0, 1.0),
                    );

                    // Tremble: a quickening shiver in the beat before the
                    // crack, gone the instant it breaks.
                    final trembleRaw =
                        ((t - _trembleAt) / (_crackAt - _trembleAt)).clamp(
                          0.0,
                          1.0,
                        );
                    final tremble = t < _crackAt
                        ? math.sin(trembleRaw * math.pi * 9) * 0.06 * trembleRaw
                        : 0.0;

                    // The crack: halves drift apart and tilt, colour drains.
                    final crack = Curves.easeOutCubic.transform(
                      ((t - _crackAt) / (0.70 - _crackAt)).clamp(0.0, 1.0),
                    );
                    final flash = t < _crackAt
                        ? 0.0
                        : (1 - ((t - _crackAt) / 0.18).clamp(0.0, 1.0));

                    final textIn = Curves.easeOut.transform(
                      ((t - _textAt) / (1 - _textAt)).clamp(0.0, 1.0),
                    );

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Opacity(
                          opacity: appear,
                          child: Transform.rotate(
                            angle: tremble,
                            child: Transform.scale(
                              scale: pop,
                              child: _CrackedHeart(
                                size: 128,
                                color: grace,
                                faded: colors.subtle,
                                crack: crack,
                                flash: flash,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        Opacity(
                          opacity: textIn,
                          child: Transform.translate(
                            offset: Offset(0, 14 * (1 - textIn)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32,
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    l10n.graceLostTitle.toUpperCase(),
                                    textAlign: TextAlign.center,
                                    style: AppTypography.title(
                                      fontSize: 30,
                                    ).copyWith(color: colors.ink),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    l10n.graceLostBody(widget.gracesLeft),
                                    textAlign: TextAlign.center,
                                    style: AppTypography.body(
                                      fontSize: 17,
                                    ).copyWith(color: grace),
                                  ),
                                  const SizedBox(height: 18),
                                  Text(
                                    l10n.graceLostHint,
                                    textAlign: TextAlign.center,
                                    style: AppTypography.support(
                                      fontSize: 13,
                                    ).copyWith(color: colors.subtle),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A heart drawn as two halves split along a jagged seam. At [crack] = 0 the
/// halves sit flush and read as one whole heart in [color]; as it rises they
/// drift apart, tilt outward and lerp toward [faded]. [flash] briefly lights
/// the seam white at the moment of the break.
class _CrackedHeart extends StatelessWidget {
  const _CrackedHeart({
    required this.size,
    required this.color,
    required this.faded,
    required this.crack,
    required this.flash,
  });

  final double size;
  final Color color;
  final Color faded;
  final double crack;
  final double flash;

  @override
  Widget build(BuildContext context) {
    final tint = Color.lerp(color, faded, crack * 0.75)!;
    final glow = color.withValues(alpha: (1 - crack) * 0.55);
    final drift = size * 0.09 * crack;
    final drop = size * 0.06 * crack;
    final tilt = 0.14 * crack;

    Widget half({required bool left}) {
      return Transform.translate(
        offset: Offset(left ? -drift : drift, drop),
        child: Transform.rotate(
          angle: left ? -tilt : tilt,
          alignment: left ? Alignment.bottomRight : Alignment.bottomLeft,
          child: ClipPath(
            clipper: _HalfHeartClipper(left: left),
            child: Icon(Icons.favorite_rounded, size: size, color: tint),
          ),
        ),
      );
    }

    return SizedBox(
      width: size * 1.4,
      height: size * 1.2,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The halo lives on its own unclipped layer: a shadow inside the
          // clipped halves gets cut along the clip's bounding box and reads
          // as a faint rectangle behind the heart.
          if (glow.a > 0)
            Icon(
              Icons.favorite_rounded,
              size: size,
              color: Colors.transparent,
              shadows: [Shadow(color: glow, blurRadius: size * 0.35)],
            ),
          half(left: true),
          half(left: false),
          if (flash > 0)
            IgnorePointer(
              child: CustomPaint(
                size: Size(size, size),
                painter: _SeamFlashPainter(opacity: flash, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

/// The seam, top to bottom, as fractions of the heart's box — the same
/// polyline both halves and the flash share so the pieces fit like a puzzle.
/// The first and last points sit on the box edges so the clip closes
/// cleanly; the glyph itself spans roughly 0.16–0.86 of the box, which is
/// why the flash only lights the seam between [_kSeamGlyphTop] and
/// [_kSeamGlyphBottom].
const List<Offset> _kSeam = [
  Offset(0.50, 0.00),
  Offset(0.44, 0.24),
  Offset(0.57, 0.44),
  Offset(0.46, 0.64),
  Offset(0.54, 0.82),
  Offset(0.50, 1.00),
];
const double _kSeamGlyphTop = 0.19;
const double _kSeamGlyphBottom = 0.85;

/// [_kSeam] trimmed to the glyph's vertical extent, interpolating the end
/// points so the flash starts and ends on the heart's outline, not the box.
List<Offset> _seamWithinGlyph() {
  Offset at(double y) {
    for (var i = 1; i < _kSeam.length; i++) {
      final a = _kSeam[i - 1];
      final b = _kSeam[i];
      if (y >= a.dy && y <= b.dy) {
        final t = (y - a.dy) / (b.dy - a.dy);
        return Offset(a.dx + (b.dx - a.dx) * t, y);
      }
    }
    return _kSeam.last;
  }

  return [
    at(_kSeamGlyphTop),
    ..._kSeam.where((p) => p.dy > _kSeamGlyphTop && p.dy < _kSeamGlyphBottom),
    at(_kSeamGlyphBottom),
  ];
}

class _HalfHeartClipper extends CustomClipper<Path> {
  const _HalfHeartClipper({required this.left});

  final bool left;

  @override
  Path getClip(Size size) {
    final path = Path();
    final w = size.width;
    final h = size.height;
    // Walk the seam downward, then close around the outer edge of this half.
    path.moveTo(_kSeam.first.dx * w, _kSeam.first.dy * h);
    for (final p in _kSeam.skip(1)) {
      path.lineTo(p.dx * w, p.dy * h);
    }
    if (left) {
      path.lineTo(0, h);
      path.lineTo(0, 0);
    } else {
      path.lineTo(w, h);
      path.lineTo(w, 0);
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_HalfHeartClipper old) => old.left != left;
}

class _SeamFlashPainter extends CustomPainter {
  const _SeamFlashPainter({required this.opacity, required this.color});

  final double opacity;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    final seam = _seamWithinGlyph();
    final path = Path()
      ..moveTo(seam.first.dx * size.width, seam.first.dy * size.height);
    for (final p in seam.skip(1)) {
      path.lineTo(p.dx * size.width, p.dy * size.height);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SeamFlashPainter old) =>
      old.opacity != opacity || old.color != color;
}
