import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/app_locale.dart' show sharedPreferencesProvider;
import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/spark_cta_button.dart';
import '../../../services/analytics.dart';
import '../../account/providers/session_providers.dart';
import '../screens/modes_screen.dart';

/// The app bar's modes icon (see `QuestionScreen`), so the showcase can find
/// it on screen and cut its spotlight around it. Unmounted whenever the feed
/// is not the visible route — which is also the showcase's guard.
final GlobalKey modesIconKey = GlobalKey(debugLabel: 'modes_icon');

/// SharedPreferences key: the one-time modes showcase has been shown on this
/// install. Set BEFORE the overlay opens, so a crash or a swipe mid-showcase
/// never turns it into a repeat.
const String kModesShowcaseSeenPrefKey = 'modes_showcase_seen';

/// What the user did with the showcase.
enum ModesShowcaseAction { open, close }

/// The one-time "Nowość: tryby" showcase (2026-09-02): after a vote, once
/// per install — a new install's first vote, an updated install's next one —
/// the feed dims, a spotlight is cut around the app bar's modes icon, and a
/// card under it says what the modes are, with "Zobacz tryby" and "Zamknij".
///
/// Returns whether it showed (so the caller keeps its one-prompt-per-vote
/// rule). Skips, without spending the once, whenever the modes icon is not
/// on screen — the feed is not the visible route, or a widget test pumps the
/// vote panel on its own — because a spotlight with nothing to point at is
/// just a dimmed screen.
///
/// This is the ONE modal the feed shows after a vote by design (owner's
/// call): the loop vote → argument → split stays whole, the showcase comes
/// after the bars, and it happens exactly once.
Future<bool> maybeShowModesShowcase(BuildContext context, WidgetRef ref) async {
  final prefs = ref.read(sharedPreferencesProvider);
  if (prefs.getBool(kModesShowcaseSeenPrefKey) ?? false) return false;
  final rect = modesIconRect();
  if (rect == null) return false;

  final premium = ref.read(isPremiumProvider);
  await prefs.setBool(kModesShowcaseSeenPrefKey, true);
  Analytics.log('modes_showcase_shown', {'premium': premium});
  if (!context.mounted) return true;

  final action = await showModesShowcase(
    context,
    iconRect: rect,
    premium: premium,
  );
  Analytics.log('modes_showcase_closed', {
    'action': (action ?? ModesShowcaseAction.close).name,
  });
  if (action == ModesShowcaseAction.open && context.mounted) {
    await openModes(context);
  }
  return true;
}

/// The modes icon's rect in global (overlay) coordinates, or null when it is
/// not laid out on screen.
Rect? modesIconRect() {
  final object = modesIconKey.currentContext?.findRenderObject();
  if (object is! RenderBox || !object.attached || !object.hasSize) return null;
  return object.localToGlobal(Offset.zero) & object.size;
}

/// Opens the showcase over the current route. Exposed for the widget test;
/// production goes through [maybeShowModesShowcase].
Future<ModesShowcaseAction?> showModesShowcase(
  BuildContext context, {
  required Rect iconRect,
  required bool premium,
}) {
  return showGeneralDialog<ModesShowcaseAction>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    barrierLabel: 'modes showcase',
    transitionDuration: const Duration(milliseconds: 280),
    // A general dialog gives its page no Material — every Text on the card
    // would render with the "missing Material" yellow underline.
    pageBuilder: (_, _, _) => Material(
      type: MaterialType.transparency,
      child: _ModesShowcase(iconRect: iconRect, premium: premium),
    ),
    transitionBuilder: (_, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    ),
  );
}

/// The overlay: a scrim with a round hole over the icon and a pulsing spark
/// ring around the hole, a caret pointing up at it, and the card. A tap on
/// the scrim closes; a tap inside the hole counts as "open".
class _ModesShowcase extends StatefulWidget {
  const _ModesShowcase({required this.iconRect, required this.premium});

  final Rect iconRect;
  final bool premium;

  @override
  State<_ModesShowcase> createState() => _ModesShowcaseState();
}

class _ModesShowcaseState extends State<_ModesShowcase>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_reduceMotion && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (_reduceMotion && _pulse.isAnimating) {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _finish(ModesShowcaseAction action) => Navigator.of(context).pop(action);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    final rect = widget.iconRect;
    final holeRadius = math.max(rect.width, rect.height) / 2 + 8;

    return LayoutBuilder(
      builder: (context, constraints) {
        // The card is capped at the sub-screens' width and centred; the caret
        // sits under the icon, clamped so it never leaves the card.
        final width = constraints.maxWidth;
        final cardWidth = math.min(480.0, width - 40);
        final cardLeft = (width - cardWidth) / 2;
        final caretLeft = (rect.center.dx - cardLeft - 8).clamp(
          16.0,
          cardWidth - 32,
        );
        final cardTop = rect.bottom + holeRadius - rect.height / 2 + 14;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Scrim + hole + ring. The scrim tap closes.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _finish(ModesShowcaseAction.close),
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) => CustomPaint(
                  painter: _SpotlightPainter(
                    center: rect.center,
                    radius: holeRadius,
                    pulse: _reduceMotion
                        ? 0.5
                        : Curves.easeInOut.transform(_pulse.value),
                  ),
                ),
              ),
            ),
            // The hole itself: a tap on the icon is "open".
            Positioned(
              left: rect.center.dx - holeRadius,
              top: rect.center.dy - holeRadius,
              width: holeRadius * 2,
              height: holeRadius * 2,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _finish(ModesShowcaseAction.open),
              ),
            ),
            Positioned(
              left: cardLeft,
              top: cardTop,
              width: cardWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The caret: a rotated square that overlaps the card's top
                  // edge, so the two read as one shape.
                  Padding(
                    padding: EdgeInsets.only(left: caretLeft),
                    child: Transform.translate(
                      offset: const Offset(0, 8),
                      child: Transform.rotate(
                        angle: math.pi / 4,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: colors.cardSurface,
                            border: Border.all(color: AppTheme.spark),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
                    decoration: BoxDecoration(
                      color: colors.cardSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.spark),
                      boxShadow: AppTheme.ctaGlow,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l10n.modesShowcaseEyebrow.toUpperCase(),
                          style: AppTypography.eyebrow(
                            fontSize: 11,
                          ).copyWith(color: AppTheme.spark),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          l10n.modesShowcaseTitle.toUpperCase(),
                          style: AppTypography.display(
                            30,
                          ).copyWith(color: colors.ink),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          widget.premium
                              ? l10n.modesShowcaseBodyPro
                              : l10n.modesShowcaseBodyFree,
                          style: AppTypography.body(
                            fontSize: 14.5,
                            height: 1.4,
                          ).copyWith(color: colors.subtle),
                        ),
                        const SizedBox(height: 18),
                        SparkCtaButton(
                          label: l10n.modesShowcaseCta,
                          icon: Icons.grid_view_rounded,
                          expand: true,
                          onTap: () => _finish(ModesShowcaseAction.open),
                        ),
                        const SizedBox(height: 4),
                        TextButton(
                          onPressed: () => _finish(ModesShowcaseAction.close),
                          style: TextButton.styleFrom(
                            foregroundColor: colors.subtle,
                          ),
                          child: Text(
                            l10n.modesShowcaseClose.toUpperCase(),
                            style: AppTypography.action(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Paints the dim scrim with a round hole over the icon and a spark ring
/// around the hole that swells and fades with [pulse] (0..1).
class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter({
    required this.center,
    required this.radius,
    required this.pulse,
  });

  final Offset center;
  final double radius;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Path()..addRect(Offset.zero & size);
    final hole = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    canvas.drawPath(
      Path.combine(PathOperation.difference, scrim, hole),
      Paint()..color = Colors.black.withValues(alpha: 0.8),
    );
    // The ring: crisp at rest, breathing outward and fading as it goes.
    canvas.drawCircle(
      center,
      radius + 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppTheme.spark,
    );
    canvas.drawCircle(
      center,
      radius + 4 + 10 * pulse,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppTheme.sparkGlow.withValues(alpha: 0.55 * (1 - pulse))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.center != center || old.radius != radius || old.pulse != pulse;
}
