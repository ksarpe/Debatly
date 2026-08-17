import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/app_locale.dart' show sharedPreferencesProvider;
import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/question_repository.dart' show dateOnlyKey;
import '../../../services/analytics.dart';
import '../../account/providers/stats_providers.dart';
import '../../onboarding/providers/onboarding_providers.dart'
    show installDayNumber;
import '../../questions/providers/question_providers.dart';
import 'paywall_cta_button.dart';
import 'pro_paywall_sheet.dart';

/// SharedPreferences key: the local `yyyy-MM-dd` date the wall last opened the
/// paywall sheet automatically — the "at most once a day" latch. Absent until
/// the first automatic open.
const String kWallAutoPaywallDatePrefKey = 'wall_auto_paywall_date';

/// A slow, deliberate back-drag commits past this many logical pixels even
/// with ~zero release velocity — same threshold as the feed's swipe.
const double _kSwipeCommitDistance = 64;

/// The free tier's day wall — the screen a free user lands on when they swipe
/// forward past today's daily, and the model's main conversion surface.
///
/// It shows, in order: a blurred teaser of the next question (the first few
/// words, from the read-only `peek_next_question`), a live countdown to the
/// user's LOCAL midnight (when the next free question arrives), the streak
/// they'd lose by not coming back, the unlock CTA (opens the paywall sheet,
/// always), and a real, tappable "or come back tomorrow" exit. The wall is an
/// honest fork — pay or wait — never a trap: the exit button and a back swipe
/// both return to today's daily.
///
/// On arrival it logs `wall_reached` and — at most once per local day, and
/// only after today's daily has been voted on — opens the paywall sheet
/// automatically. Every later arrival that day shows just the wall; the sheet
/// then opens only from the CTA.
class DayWallView extends ConsumerStatefulWidget {
  const DayWallView({super.key});

  @override
  ConsumerState<DayWallView> createState() => _DayWallViewState();
}

class _DayWallViewState extends ConsumerState<DayWallView> {
  Timer? _ticker;
  Duration _left = Duration.zero;

  /// Accumulated horizontal finger travel of the drag in progress.
  double _dragDx = 0;

  /// Guards against stacking a tapped sheet on top of the automatic one.
  bool _sheetOpen = false;

  @override
  void initState() {
    super.initState();
    _left = _untilLocalMidnight();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    WidgetsBinding.instance.addPostFrameCallback((_) => _onArrived());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  static Duration _untilLocalMidnight() {
    final now = DateTime.now();
    // Day arithmetic (not +24h) so DST switch days count to the actual
    // midnight, mirroring the reminder scheduler.
    return DateTime(now.year, now.month, now.day + 1).difference(now);
  }

  void _tick() {
    if (!mounted) return;
    // Once midnight passes, the fetch-day comparison trips and the feed rolls
    // over to the new daily — the wall then unmounts on its own (the visible
    // flag watches the daily provider), so there is no manual hide here.
    maybeRolloverDaily(ref);
    if (!mounted) return;
    setState(() => _left = _untilLocalMidnight());
  }

  /// One-shot per arrival: the funnel event, then maybe the once-a-day
  /// automatic sheet.
  Future<void> _onArrived() async {
    if (!mounted) return;
    final prefs = ref.read(sharedPreferencesProvider);
    Analytics.log('wall_reached', {
      'streak': ref.read(currentStreakProvider),
      'day_number': installDayNumber(prefs),
    });

    // The automatic open: at most once per LOCAL day, and never before the
    // user has voted on today's daily — the wall must not be the first thing
    // that asks for money.
    final daily = ref.read(todaysDailyQuestionProvider).asData?.value;
    final voted =
        daily != null &&
        (ref.read(dailyVoteStateProvider(daily.id)).asData?.value.hasVoted ??
            false);
    final today = dateOnlyKey(DateTime.now());
    if (!voted || prefs.getString(kWallAutoPaywallDatePrefKey) == today) {
      return;
    }
    // Latched BEFORE the sheet resolves, so even an instantly-dismissed sheet
    // spends the day's automatic open.
    await prefs.setString(kWallAutoPaywallDatePrefKey, today);
    if (!mounted) return;
    await _openPaywall(trigger: 'auto');
  }

  Future<void> _openPaywall({required String trigger}) async {
    if (_sheetOpen) return;
    _sheetOpen = true;
    try {
      await showProPaywall(
        context,
        source: PaywallSource.wall,
        trigger: trigger,
      );
    } finally {
      _sheetOpen = false;
    }
  }

  /// The honest exit — back to today's daily (also the back swipe's target).
  void _backToDaily() {
    ref.read(dayWallVisibleProvider.notifier).hide();
  }

  void _onDragStart(DragStartDetails details) => _dragDx = 0;

  void _onDragUpdate(DragUpdateDetails details) => _dragDx += details.delta.dx;

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    // Rightward flick or slow rightward drag = back. Leftward is ignored —
    // there is nothing further forward for a free user.
    if (velocity > 100 ||
        (velocity.abs() <= 100 && _dragDx > _kSwipeCommitDistance)) {
      _backToDaily();
    }
  }

  String _formatLeft(Duration d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    final streak = ref.watch(currentStreakProvider);
    final teaser = ref.watch(wallTeaserProvider).asData?.value;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: Padding(
        // The transparent app bar floats over the body; reserve its band so
        // the wall centres in the visible area, like the feed does.
        padding: EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top + kToolbarHeight,
        ),
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (teaser != null) ...[
                      _TeaserPreview(teaser: teaser),
                      const SizedBox(height: 30),
                    ],
                    Text(
                      l10n.wallCountdown(_formatLeft(_left)),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        // Fixed-width digits so the ticking clock doesn't
                        // wobble the line.
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (streak > 0) ...[
                      const SizedBox(height: 10),
                      Text(
                        '🔥 ${l10n.wallStreak(streak)}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.subtle,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    PaywallCtaButton(
                      label: l10n.wallCtaUnlock,
                      busy: false,
                      onTap: () => _openPaywall(trigger: 'tap'),
                    ),
                    const SizedBox(height: 10),
                    // A real button, not a resigned caption — the wall is a
                    // fork, not a trap.
                    TextButton(
                      onPressed: _backToDaily,
                      style: TextButton.styleFrom(
                        foregroundColor: colors.subtle,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      child: Text(
                        l10n.wallCtaTomorrow,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The bait: the next question's first words readable, the rest blurred.
///
/// Only the teaser ever reaches the client (`peek_next_question` cuts it
/// server-side); the blurred continuation is a fixed dummy string, so removing
/// the blur reveals nothing — same trick as the locked smaczki cards.
class _TeaserPreview extends StatelessWidget {
  const _TeaserPreview({required this.teaser});

  final String teaser;

  static const _dummy =
      'aaabbbbaaabbb aaabbbbaaabbb aaabbbbaaabbb '
      'aaabbbbaaabbb aaabbbbaaabbb aaabbbbaaabbb';

  @override
  Widget build(BuildContext context) {
    final questionStyle = TextStyle(
      color: context.colors.ink,
      fontSize: 24,
      fontWeight: FontWeight.w800,
      height: 1.3,
    );

    return Column(
      children: [
        Text('$teaser…', textAlign: TextAlign.center, style: questionStyle),
        const SizedBox(height: 8),
        ClipRect(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
            child: Text(
              _dummy,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.clip,
              style: questionStyle.copyWith(color: context.colors.subtle),
            ),
          ),
        ),
      ],
    );
  }
}
