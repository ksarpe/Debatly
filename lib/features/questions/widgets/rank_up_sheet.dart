import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/share/widget_to_image.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/spark_cta_button.dart';
import '../../../data/models/rank.dart';
import '../../../data/models/user_stats.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../services/analytics.dart';
import '../../account/providers/rank_celebration_providers.dart';
import '../../account/providers/stats_providers.dart';
import '../../settings/providers/review_providers.dart';
import 'confetti_overlay.dart';
import 'rank_share_card.dart';
import 'rank_sheet.dart' show rankIcon;

/// The full-screen "you climbed a rank" celebration: confetti, the new rank's
/// badge scaling in inside a glowing ring, and the rank name + streak — with a
/// prominent **share** action that renders the moment as a [RankShareCard]
/// poster, plus a dismiss.
///
/// Presented as a branded dark takeover (the same dark, orange-tinted palette as the
/// share card) regardless of the app theme, so the in-app moment and the image
/// the user shares look like one thing. Not dismissible by tapping outside — the
/// user taps a button, so the share CTA is always seen.
Future<void> showRankUpCelebration(
  BuildContext context, {
  required Rank rank,
  required int streak,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'rank-up',
    barrierColor: Colors.black.withValues(alpha: 0.72),
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (_, _, _) => _RankUpView(rank: rank, streak: streak),
    transitionBuilder: (_, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(opacity: curved, child: child);
    },
  );
}

class _RankUpView extends StatefulWidget {
  const _RankUpView({required this.rank, required this.streak});

  final Rank rank;
  final int streak;

  @override
  State<_RankUpView> createState() => _RankUpViewState();
}

class _RankUpViewState extends State<_RankUpView>
    with TickerProviderStateMixin {
  late final AnimationController _entrance;
  late final AnimationController _glow;

  /// True while the poster is rendering / the share sheet is being prepared, so
  /// a second tap can't fire a parallel render.
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Honour reduced motion: jump the entrance to its resting state and keep the
    // glow still, so the celebration still appears — just calm.
    if (MediaQuery.of(context).disableAnimations) {
      _entrance.value = 1;
      _glow.value = 0.5;
    } else {
      if (_entrance.status == AnimationStatus.dismissed) _entrance.forward();
      if (!_glow.isAnimating) _glow.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    _glow.dispose();
    super.dispose();
  }

  String get _lang => Localizations.localeOf(context).languageCode;

  Future<void> _share() async {
    if (_sharing) return;
    final l10n = context.l10n;
    final rankName = widget.rank.nameFor(_lang);
    final ui.FlutterView view = View.of(context);
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;

    setState(() => _sharing = true);
    Analytics.log('share_card_opened', {'type': 'rank'});
    try {
      final params = await _buildShareParams(
        l10n: l10n,
        rankName: rankName,
        view: view,
        origin: origin,
      );
      await SharePlus.instance.share(params);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// Renders the [RankShareCard] poster and bundles it with the signoff text,
  /// degrading to text-only if the card can't be rendered/encoded — so the
  /// share button never dead-ends.
  Future<ShareParams> _buildShareParams({
    required AppLocalizations l10n,
    required String rankName,
    required ui.FlutterView view,
    required Rect? origin,
  }) async {
    final message = l10n.rankShareMessage(rankName);
    try {
      final png = await renderWidgetToPng(
        child: RankShareCard(
          rankName: rankName,
          headline: l10n.rankShareHeadline,
          streakLine: l10n.rankShareStreakLine(widget.streak),
          tagline: l10n.shareCardTagline,
          iconKey: widget.rank.icon,
        ),
        logicalSize: const Size(360, 640),
        view: view,
      );
      if (png != null) {
        return ShareParams(
          text: message,
          subject: l10n.rankShareSubject,
          sharePositionOrigin: origin,
          files: [
            XFile.fromData(png, mimeType: 'image/png', name: 'spark-rank.png'),
          ],
        );
      }
    } catch (e) {
      debugPrint('rank share card render failed, sharing text only: $e');
    }
    return ShareParams(
      text: message,
      subject: l10n.rankShareSubject,
      sharePositionOrigin: origin,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // An OPAQUE branded dark backdrop (same palette as the share card), so
          // the celebration is a true takeover — the app content behind is fully
          // hidden instead of bleeding through a translucent scrim and drowning
          // out the animation.
          const Positioned.fill(child: _RankUpBackdrop()),

          if (!reduceMotion) const Positioned.fill(child: ConfettiOverlay()),

          SafeArea(
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white70,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: FadeTransition(
                      opacity: CurvedAnimation(
                        parent: _entrance,
                        curve: const Interval(0.15, 1, curve: Curves.easeOut),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _AnimatedBadge(
                            iconKey: widget.rank.icon,
                            entrance: _entrance,
                            glow: _glow,
                          ),
                          const SizedBox(height: 28),
                          Text(
                            l10n.rankUpEyebrow,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppTheme.spark,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 3,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            widget.rank.nameFor(_lang),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'Anton',
                              fontSize: 40,
                              height: 1.05,
                              letterSpacing: 0.5,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 18),
                          _StreakChip(
                            text: l10n.rankUpStreakLine(widget.streak),
                          ),
                          const SizedBox(height: 40),
                          _ShareButton(busy: _sharing, onTap: _share),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white70,
                            ),
                            child: Text(
                              l10n.rankUpDismiss,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The rank badge: the glyph in a glowing spark ring, scaling in (elastic) on
/// entrance and breathing a soft glow.
class _AnimatedBadge extends StatelessWidget {
  const _AnimatedBadge({
    required this.iconKey,
    required this.entrance,
    required this.glow,
  });

  final String? iconKey;
  final AnimationController entrance;
  final AnimationController glow;

  @override
  Widget build(BuildContext context) {
    final scale = CurvedAnimation(parent: entrance, curve: Curves.elasticOut);
    return AnimatedBuilder(
      animation: Listenable.merge([entrance, glow]),
      builder: (context, child) {
        final g = glow.value; // 0..1 breathing
        return Transform.scale(
          scale: 0.4 + 0.6 * scale.value.clamp(0.0, 1.4),
          child: Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.spark.withValues(alpha: 0.16),
              border: Border.all(
                color: AppTheme.spark.withValues(alpha: 0.7),
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.sparkGlow.withValues(alpha: 0.35 + 0.35 * g),
                  blurRadius: 38 + 26 * g,
                  spreadRadius: 2 + 4 * g,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: Icon(rankIcon(iconKey), color: Colors.white, size: 64),
    );
  }
}

/// A pill showing the streak that earned the rank — flame + "N dni z rzędu".
class _StreakChip extends StatelessWidget {
  const _StreakChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.local_fire_department_rounded,
            color: Color(0xFFF59E0B),
            size: 18,
          ),
          const SizedBox(width: 7),
          Text(
            text,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// The primary share CTA — a glowing spark pill that shows a spinner while the
/// poster renders.
class _ShareButton extends StatelessWidget {
  const _ShareButton({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SparkCtaButton(
      label: context.l10n.shareLabel,
      icon: Icons.ios_share_rounded,
      busy: busy,
      onTap: onTap,
    );
  }
}

/// The full-screen, OPAQUE takeover background: the same dark orange-tinted
/// gradient as [RankShareCard], with a soft spark halo bleeding in from the top.
///
/// Opaque on purpose — it completely covers the app behind the celebration so
/// the badge, confetti and copy read against a clean dark canvas (the old
/// translucent scrim let the app content show through, swamping the animation),
/// and the in-app moment matches the poster the user shares.
class _RankUpBackdrop extends StatelessWidget {
  const _RankUpBackdrop();

  // Mirrors RankShareCard's fixed palette so the takeover and the shared image
  // look like one thing.
  static const Color _bgTop = Color(0xFF0C0A14);
  static const Color _bgBottom = Color(0xFF171124);

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_bgTop, _bgBottom],
        ),
      ),
      child: Align(
        alignment: const Alignment(0, -0.65),
        child: FractionallySizedBox(
          widthFactor: 1.15,
          heightFactor: 0.6,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppTheme.sparkGlow.withValues(alpha: 0.28),
                  AppTheme.sparkGlow.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Watches the synced [UserStats] and fires the one-shot [showRankUpCelebration]
/// whenever a promotion is detected. Mounts once, high in the screen tree, as a
/// zero-size widget — so a rank climb is caught both on launch (overnight streak
/// growth) and right after a daily vote, from a single place rather than every
/// call site that refreshes stats.
class RankCelebrationListener extends ConsumerStatefulWidget {
  const RankCelebrationListener({super.key});

  @override
  ConsumerState<RankCelebrationListener> createState() =>
      _RankCelebrationListenerState();
}

class _RankCelebrationListenerState
    extends ConsumerState<RankCelebrationListener> {
  /// Set synchronously before any await so two near-simultaneous stats updates
  /// (e.g. the initial value plus a listen callback) can't both open a dialog.
  bool _busy = false;
  bool _checkedInitial = false;

  @override
  Widget build(BuildContext context) {
    // Subsequent refreshes (post-vote invalidation, retries) flow through here.
    ref.listen<AsyncValue<UserStats?>>(userStatsProvider, (_, next) {
      final stats = next.value;
      if (stats != null) _maybeCelebrate(stats);
    });

    // Cover the case where stats already resolved before this listener mounted
    // (ref.listen only fires on change, not for an already-present value).
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
    _busy = true;
    try {
      final ladder = ref.read(ranksProvider).value ?? kDefaultRanks;
      final rank = await ref
          .read(rankCelebrationControllerProvider.notifier)
          .evaluate(stats, ladder);
      if (rank == null || !mounted) return;
      await showRankUpCelebration(
        context,
        rank: rank,
        streak: stats.currentStreak,
      );
      // The store-review ask rides right behind the closed celebration — the
      // moment of satisfaction. Only the 3-day-streak completion qualifies
      // (streak 3 IS a promotion day, so the celebration is guaranteed to
      // have just played); every other rank-up is a no-op inside.
      if (mounted) {
        await ref
            .read(reviewPromptControllerProvider.notifier)
            .maybePromptForStreak(stats.currentStreak);
      }
    } finally {
      _busy = false;
    }
  }
}
