import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feedback/app_toast.dart';
import '../../../core/locale/l10n_extension.dart';
import '../../../core/network/network_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../account/providers/session_providers.dart';
import '../../monetization/widgets/pro_paywall_screen.dart';
import '../providers/favorites_providers.dart';

/// Gold accent for the favorite star, matching the "go Premium" upsell elsewhere.
const Color _kGold = Color(0xFFFFC857);

/// A deeper gold for light themes: the bright [_kGold] all but vanishes against
/// the off-white canvas, so on light we drop to a richer amber-gold that keeps
/// the star clearly visible while still reading as "gold".
const Color _kGoldLight = Color(0xFFE0A100);

/// The top-left "save to favorites" star on the question screen.
///
/// Premium users get a gold outline star that fills — with a little pop + a
/// radial sparkle burst — when they save the question, and empties when they
/// un-save it. Free users get a muted star that, on tap, opens the paywall:
/// favorites are a premium feature, so the star doubles as an upsell hook rather
/// than being hidden.
///
/// State comes from [favoriteIdsProvider]; the toggle is optimistic there, so
/// the fill flips instantly and the animation isn't waiting on the network.
class FavoriteStarButton extends ConsumerStatefulWidget {
  const FavoriteStarButton({super.key, required this.questionId});

  /// The question currently on screen — the one the star saves/removes.
  final String questionId;

  @override
  ConsumerState<FavoriteStarButton> createState() => _FavoriteStarButtonState();
}

class _FavoriteStarButtonState extends ConsumerState<FavoriteStarButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop;

  /// True while the paywall round-trip is in flight, so a free user can't spam
  /// taps and stack paywalls.
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _pop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  bool get _reduceMotion => MediaQuery.of(context).disableAnimations;

  Future<void> _onTap() async {
    final isPremium = ref.read(isPremiumProvider);
    if (!isPremium) {
      await _openPaywall();
      return;
    }
    await _toggle();
  }

  Future<void> _toggle() async {
    final notifier = ref.read(favoriteIdsProvider.notifier);
    // All feedback fires NOW, off the optimistic flip — the burst and the toast
    // must not sit on the network round-trip. If the server later refuses, the
    // provider rolls the star back and the toast is retracted below.
    final adding = !notifier.isFavorite(widget.questionId);
    if (adding && !_reduceMotion) _pop.forward(from: 0);
    final toastId = adding
        ? AppToast.success(
            context,
            context.l10n.favoriteAdded,
            icon: Icons.star_rounded,
          )
        : AppToast.info(
            context,
            context.l10n.favoriteRemoved,
            icon: Icons.star_border_rounded,
          );
    try {
      await notifier.toggle(widget.questionId);
    } catch (e) {
      // Take the now-false confirmation down with the rollback.
      AppToast.dismiss(toastId);
      if (!mounted) return;
      // A premium gate the client didn't expect (e.g. lapsed mid-session) comes
      // back from the RPC as 'premium required' — route that to the paywall.
      // Offline gets the calmer "no connection" line; anything else is the
      // generic favorites error.
      if (e.toString().contains('premium')) {
        await _openPaywall();
      } else {
        AppToast.error(
          context,
          isOfflineError(e)
              ? context.l10n.noConnection
              : context.l10n.favoriteError,
        );
      }
    }
  }

  /// Shows the PRO paywall, then refreshes the session so a purchase
  /// flips premium immediately and the next tap actually saves.
  Future<void> _openPaywall() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final purchased = await showProPaywall(
        context,
        source: PaywallSource.favorites,
      );
      if (!mounted) return;
      if (purchased) {
        await ref.read(sessionProvider.notifier).refresh();
        if (!mounted) return;
        AppToast.success(context, context.l10n.settingsPremiumActiveToast);
      } else {
        AppToast.info(context, context.l10n.favoritesPremiumOnly);
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPremium = ref.watch(isPremiumProvider);
    final isFavorite = ref.watch(
      favoriteIdsProvider.select((s) => s.value?.contains(widget.questionId)),
    );
    final filled = isFavorite ?? false;

    // Gold for premium (active feature), muted for free (upsell). The outline
    // and the fill share the colour so the transition reads as one gesture. The
    // gold deepens on light themes so it doesn't wash out on the off-white bar.
    final gold = Theme.of(context).brightness == Brightness.light
        ? _kGoldLight
        : _kGold;
    final color = isPremium ? gold : context.colors.subtle;

    final tooltip = !isPremium
        ? context.l10n.favoritesPremiumOnly
        : filled
        ? context.l10n.favoriteRemoveTooltip
        : context.l10n.favoriteAddTooltip;

    return Semantics(
      button: true,
      toggled: filled,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: InkResponse(
          onTap: _opening ? null : _onTap,
          radius: 24,
          child: SizedBox(
            width: 48,
            height: 48,
            child: AnimatedBuilder(
              animation: _pop,
              builder: (context, _) {
                final t = _pop.value; // 0..1, only runs on a fresh "add"
                // A quick overshoot then settle — the satisfying "snap" of the
                // star locking in. Stays at 1.0 when idle.
                final pop = t == 0 ? 1.0 : 1.0 + math.sin(t * math.pi) * 0.35;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    if (t > 0 && t < 1)
                      CustomPaint(
                        size: const Size(48, 48),
                        painter: _BurstPainter(progress: t, color: color),
                      ),
                    Transform.scale(
                      scale: pop,
                      child: Icon(
                        filled ? Icons.star_rounded : Icons.star_border_rounded,
                        size: 26,
                        color: color,
                        shadows: filled
                            ? [
                                Shadow(
                                  color: color.withValues(alpha: 0.55),
                                  blurRadius: 12,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// A one-shot sparkle that fires when a question is saved: an expanding,
/// fading ring with a ring of little radiating dots — the celebratory pop that
/// makes saving feel rewarding without being loud.
class _BurstPainter extends CustomPainter {
  _BurstPainter({required this.progress, required this.color});

  /// 0..1 burst phase, driven by the pop controller.
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final eased = Curves.easeOut.transform(progress);
    final fade = (1 - progress).clamp(0.0, 1.0);

    // Expanding ring.
    final ringRadius = 8 + eased * 14;
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * fade
      ..color = color.withValues(alpha: 0.7 * fade);
    canvas.drawCircle(center, ringRadius, ringPaint);

    // Radiating sparkle dots.
    const count = 6;
    final dotDistance = 10 + eased * 12;
    final dotPaint = Paint()..color = color.withValues(alpha: fade);
    for (var i = 0; i < count; i++) {
      final angle = (i / count) * 2 * math.pi - math.pi / 2;
      final offset = Offset(
        center.dx + math.cos(angle) * dotDistance,
        center.dy + math.sin(angle) * dotDistance,
      );
      canvas.drawCircle(offset, 1.6 * fade, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) =>
      old.progress != progress || old.color != color;
}
