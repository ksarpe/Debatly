import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/content_width.dart';
import '../../../core/locale/app_locale.dart' show sharedPreferencesProvider;
import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/fit_or_scroll.dart';
import '../../../data/repositories/question_repository.dart' show dateOnlyKey;
import '../../../services/analytics.dart';
import '../../account/providers/stats_providers.dart';
import '../../onboarding/providers/onboarding_providers.dart'
    show installDayNumber;
import '../../questions/providers/question_providers.dart';
import '../../questions/widgets/vote_visuals.dart'
    show VoteButtonsRow, voteRowMaxHeight;
import 'paywall_cta_button.dart';
import 'pro_paywall_screen.dart';
import 'purchase_settlement.dart';

/// SharedPreferences key: the local `yyyy-MM-dd` date the wall last opened the
/// paywall automatically — the "at most once a day" latch. Absent until
/// the first automatic open.
const String kWallAutoPaywallDatePrefKey = 'wall_auto_paywall_date';

/// A slow, deliberate back-drag commits past this many logical pixels even
/// with ~zero release velocity — same threshold as the feed's swipe.
const double _kSwipeCommitDistance = 64;

/// Smallest height worth giving the blurred question. Higher than the feed's
/// own 56, because the preview is two stacked blocks (the readable teaser and
/// the blurred continuation) plus the room the blur needs to fade out in.
const double _kMinQuestionHeight = 120;

/// The shortest the wall's three bands (ring · question group · CTA) are laid
/// out in: the ring at full size, the feed's minimum question group (question +
/// 28 gap + the vote row at this text scale) and a CTA that grows with the
/// system font. Under this the wall scrolls rather than squeezing — and it has
/// to be generous, because everything but the middle band is a fixed height
/// that an undersized floor would simply overflow.
double _minWallHeight(BuildContext context) {
  final scale = math.max(1.0, MediaQuery.textScalerOf(context).scale(1));
  return 12 +
      _CountdownRing.maxDiameter +
      _kMinQuestionHeight +
      28 +
      voteRowMaxHeight(context) +
      62 * scale +
      20;
}

/// The free tier's day wall — the screen a free user lands on when they swipe
/// forward past today's daily, and the model's main conversion surface.
///
/// It shows, top to bottom: a circular countdown to the user's LOCAL midnight
/// (when the next free question arrives) with the live HH:MM:SS set inside the
/// ring; then the feed's own centred group — a blurred teaser of the next
/// question (the first few words, from the read-only `peek_next_question`) with
/// an equally blurred, inert TAK/NIE row under it, at the feed's widths, gap
/// and type sizes, so the wall reads as the next question screen behind
/// frosted glass; and at the bottom the unlock CTA (opens the paywall,
/// always). The streak lives in the app-bar chip — the wall never repeats it.
/// The way back to today's daily is a rightward swipe — the same gesture that
/// browses the feed — or the system back gesture/button, which the wall
/// intercepts so it never exits the app ("never a trap").
///
/// On arrival it logs `wall_reached` and — at most once per local day, and
/// only after today's daily has been voted on — opens the paywall
/// automatically. Every later arrival that day shows just the wall; the
/// paywall then opens only from the CTA.
class DayWallView extends ConsumerStatefulWidget {
  const DayWallView({super.key});

  @override
  ConsumerState<DayWallView> createState() => _DayWallViewState();
}

class _DayWallViewState extends ConsumerState<DayWallView> {
  Timer? _ticker;
  Duration _left = Duration.zero;
  Duration _dayLength = const Duration(days: 1);

  /// Accumulated horizontal finger travel of the drag in progress.
  double _dragDx = 0;

  /// Guards against stacking a tapped sheet on top of the automatic one.
  bool _sheetOpen = false;

  @override
  void initState() {
    super.initState();
    _left = _untilLocalMidnight();
    _dayLength = _localDayLength();
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

  /// How long *today* is locally — 24h except on the two DST switch days, when
  /// it is 23 or 25. The ring divides by this, so its arc keeps reading as
  /// "the slice of the day that is left" on those days too.
  static Duration _localDayLength() {
    final now = DateTime.now();
    return DateTime(
      now.year,
      now.month,
      now.day + 1,
    ).difference(DateTime(now.year, now.month, now.day));
  }

  void _tick() {
    if (!mounted) return;
    // Once midnight passes, the fetch-day comparison trips and the feed rolls
    // over to the new daily — the wall then unmounts on its own (the visible
    // flag watches the daily provider), so there is no manual hide here.
    maybeRolloverDaily(ref);
    if (!mounted) return;
    setState(() {
      _left = _untilLocalMidnight();
      _dayLength = _localDayLength();
    });
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
    // Latched BEFORE the paywall resolves, so even an instantly-dismissed
    // paywall spends the day's automatic open.
    await prefs.setString(kWallAutoPaywallDatePrefKey, today);
    if (!mounted) return;
    await _openPaywall(trigger: 'auto');
  }

  /// Opens the paywall and, if money changed hands, settles what the user sees.
  ///
  /// The result used to be discarded here — the one place in the app where it
  /// was. The happy path limped along on the RevenueCat listener flipping
  /// `isPremium`, but a `PurchaseOutcome.pending` (paid, entitlement not
  /// visible yet) fires no listener, so nothing re-read the session and the
  /// person who had just paid was returned to the same countdown with no
  /// acknowledgement at all. On the tier's main conversion surface.
  Future<void> _openPaywall({required String trigger}) async {
    if (_sheetOpen) return;
    _sheetOpen = true;
    try {
      // True for `pending` as well as `entitled` — both mean the money left
      // their account, and the reconcile below is what decides which it was.
      final purchased = await showProPaywall(
        context,
        source: PaywallSource.wall,
        trigger: trigger,
      );
      if (!purchased || !mounted) return;
      // Says which one it actually was. Claiming "Premium active" over a
      // still-pending purchase would be a lie the wall itself contradicts —
      // it only hides once the entitlement really lands.
      await settleProPurchase(context, ref);
    } finally {
      _sheetOpen = false;
    }
  }

  /// Back to today's daily — the back swipe's and system back's target.
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final teaser = ref.watch(wallTeaserProvider).asData?.value;

    return PopScope(
      // System back returns to today's daily instead of leaving the app — the
      // wall is a fork, never a trap. Once hidden, this scope unmounts and
      // back behaves normally again.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _backToDaily();
      },
      child: GestureDetector(
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
          // Three bands, deliberately the feed's own geometry with the ring
          // added on top: the countdown sits high, just under the app bar's
          // streak chip; the middle band is the feed's centred group — the
          // question with the vote row 28px under it, both blurred — laid out
          // by the same widths, gap and fit rules, so the wall reads as the
          // next question screen behind frosted glass rather than as a
          // different screen; the CTA rides the bottom edge of the safe area,
          // where the feed's action bar is. Below [_minWallHeight] (landscape,
          // a split-screen column) the whole thing scrolls instead of
          // overflowing — an overflowed CTA is painted but untouchable.
          child: FitOrScroll(
            minContentHeight: _minWallHeight(context),
            child: Column(
              children: [
                const SizedBox(height: 12),
                _CountdownRing(
                  left: _left,
                  dayLength: _dayLength,
                  caption: l10n.wallCountdownCaption,
                ),
                Expanded(
                  child: Padding(
                    // The feed's own side margins, so the blurred question
                    // wraps its lines exactly where the real one does.
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: kReadingMaxWidth,
                        ),
                        // The feed's own group: question and vote row centred
                        // together, the question flexing against a box that
                        // [FitOrScroll] keeps from ever shrinking past the
                        // floor (below which the preview would be laid out in
                        // less height than its smallest type needs, and an
                        // overflowing Column paints where nothing hit-tests).
                        child: FitOrScroll(
                          minContentHeight:
                              _kMinQuestionHeight +
                              28 +
                              voteRowMaxHeight(context),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (teaser != null) ...[
                                Flexible(child: _TeaserPreview(teaser: teaser)),
                                const SizedBox(height: 28),
                              ],
                              const _BlurredVoteRow(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: kReadingMaxWidth,
                      ),
                      // The pill wraps its label, so without a width of its
                      // own it would shrink to its own text in the middle of
                      // the screen instead of spanning the column.
                      child: SizedBox(
                        width: double.infinity,
                        child: PaywallCtaButton(
                          label: l10n.wallCtaUnlock,
                          caption: l10n.wallCtaCaption,
                          busy: false,
                          onTap: () => _openPaywall(trigger: 'tap'),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The countdown as a ring: a spark-coloured arc that shrinks clockwise from
/// twelve o'clock as the day burns down, with the live HH:MM:SS and its
/// caption set inside it.
///
/// The digits are the biggest type on the screen and "23:59:59" cannot break
/// (a colon is class IS in UAX #14), so they are fitted down rather than
/// allowed to run past the ring at a large system text size.
class _CountdownRing extends StatelessWidget {
  const _CountdownRing({
    required this.left,
    required this.dayLength,
    required this.caption,
  });

  final Duration left;
  final Duration dayLength;
  final String caption;

  /// Outer diameter on a comfortable phone; a narrower column scales it down.
  /// Deliberately compact: every pixel it takes is a pixel the question below
  /// it doesn't get, and the question is what the wall is selling.
  static const double maxDiameter = 168;
  static const double _stroke = 9;

  static String _formatLeft(Duration d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final total = dayLength.inSeconds;
    final progress = total <= 0
        ? 0.0
        : (left.inSeconds / total).clamp(0.0, 1.0).toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        final diameter = constraints.maxWidth.isFinite
            ? math.min(maxDiameter, constraints.maxWidth)
            : maxDiameter;
        return Center(
          child: SizedBox.square(
            dimension: diameter,
            child: CustomPaint(
              painter: _RingPainter(
                progress: progress,
                track: colors.accent,
                stroke: _stroke,
              ),
              // Clear of the stroke and its glow, so the digits never touch
              // the ring.
              child: Padding(
                padding: EdgeInsets.all(_stroke + diameter * 0.10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _formatLeft(left),
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        style: AppTypography.numeric(34).copyWith(
                          color: colors.ink,
                          // Fixed-width digits so the ticking clock doesn't
                          // wobble the line.
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        caption.toUpperCase(),
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        style: AppTypography.eyebrow(
                          fontSize: 10.5,
                        ).copyWith(color: colors.subtle),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Paints the ring: a full quiet circle, then the remaining slice of the day
/// as a glowing spark arc running clockwise from twelve o'clock.
class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.track,
    required this.stroke,
  });

  /// 1 at local midnight, 0 as the next one lands.
  final double progress;
  final Color track;
  final double stroke;

  static const double _startAngle = -math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - stroke) / 2;
    if (radius <= 0) return;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );

    if (progress <= 0) return;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweep = 2 * math.pi * progress;

    // The halo first, so the crisp arc sits on top of its own glow.
    canvas.drawArc(
      rect,
      _startAngle,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = AppTheme.sparkGlow.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawArc(
      rect,
      _startAngle,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = const SweepGradient(
          colors: [AppTheme.spark, AppTheme.sparkGlow, AppTheme.spark],
          transform: GradientRotation(_startAngle),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.track != track || old.stroke != stroke;
}

/// The bait: the next question's first words readable, the rest blurred —
/// laid out exactly like a real question, because that is what it is pretending
/// to be. Same uppercase Barlow, same white-fill-over-black-stroke, same
/// length-then-fit sizing as the feed ([QuestionTextStyles.fitFontSize]), so
/// the blurred block lands where the next question's text will land.
///
/// Only the teaser ever reaches the client (`peek_next_question` cuts it
/// server-side); the blurred continuation is a fixed placeholder string, so
/// removing the blur reveals nothing — same trick as the locked smaczki cards.
/// The blur is deliberately left unclipped and given room to bleed into: the
/// [ClipRect] that used to wrap it sheared the soft edges flat and cut the
/// second line mid-glyph, which reads as a rendering bug rather than as
/// something withheld.
class _TeaserPreview extends StatelessWidget {
  const _TeaserPreview({required this.teaser});

  final String teaser;

  /// Stands in for the rest of the question: enough words to read as one or
  /// two more lines under the teaser, not a paragraph — a real question is
  /// two or three lines all in.
  static const _placeholder = 'blablabla blabla blablabla';

  /// Room around the blurred block for the blur to fade out in, instead of
  /// being cut off against its neighbours.
  static const double _bleed = 12;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Sized as if teaser + hidden continuation were one question: the
        // length picks the nominal size, the box it was handed shrinks it
        // further if it has to — the same two steps, in the same order, as the
        // question on the feed.
        final fontSize = QuestionTextStyles.fitFontSize(
          '$teaser… $_placeholder',
          maxWidth: constraints.maxWidth,
          maxHeight: constraints.maxHeight - _bleed * 2,
          textScaler: MediaQuery.textScalerOf(context),
        );

        Widget styled(String text) {
          final upper = text.toUpperCase();
          Text layer(TextStyle style) =>
              Text(upper, textAlign: TextAlign.center, style: style);
          return Stack(
            alignment: Alignment.center,
            children: [
              layer(QuestionTextStyles.strokeFor(fontSize)),
              layer(QuestionTextStyles.fillFor(fontSize)),
            ],
          );
        }

        // The size above is picked by the feed's simulator, which models one
        // block of falling words — close, but this preview is two stacked
        // blocks with a gap, so it can still come out a line taller than the
        // band. Scaling the assembled preview down covers that difference and
        // makes overflow impossible; at the sizes it actually gets, the scale
        // is 1 and nothing is scaled at all.
        // One node for the whole preview: the teaser, announced once and
        // WITHOUT the placeholder. Every layer under it is silenced —
        // "blablabla blabla blablabla" is scrambled art standing in for text
        // nobody is allowed to read, and a screen reader was reading it out.
        // The stroke/fill pairs would double the teaser on top of that.
        return Semantics(
          label: '$teaser…',
          container: true,
          child: ExcludeSemantics(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(
                // Fixed to the band's width, so the lines wrap where they
                // would unscaled instead of stretching into one long line.
                width: constraints.maxWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    styled('$teaser…'),
                    Padding(
                      padding: const EdgeInsets.only(
                        top: _bleed,
                        bottom: _bleed,
                      ),
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
                        child: styled(_placeholder),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The TAK / NIE buttons of the question that isn't unlocked yet — the real
/// [VoteButtonsRow], blurred and inert.
///
/// It carries no state and casts nothing; it is there because a question with
/// no vote row under it doesn't read as a question screen, and the wall's whole
/// argument is "this is the next one, you just can't reach it yet". Blur plus
/// [IgnorePointer]: a tap lands on the wall's swipe surface, never on a vote.
class _BlurredVoteRow extends StatelessWidget {
  const _BlurredVoteRow();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Padding(
        // Room for the blur to fade out in, as above.
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Opacity(
          opacity: 0.75,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: VoteButtonsRow(busy: false, onVote: (_) {}),
          ),
        ),
      ),
    );
  }
}
