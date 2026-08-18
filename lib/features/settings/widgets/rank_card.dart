import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../account/providers/stats_providers.dart';
import '../../questions/widgets/rank_sheet.dart';
import 'stat_card_shell.dart';

class RankCard extends ConsumerWidget {
  const RankCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(userStatsValueProvider);
    final rankName = stats.rankName.isEmpty
        ? '—'
        : stats.rankName.toUpperCase();
    final next = stats.nextRankStreak;
    // Progress toward the next rank. Without the current rank's floor we
    // approximate against the next threshold — good enough for the profile card;
    // the rank sheet shows the precise ladder.
    final progress = (next != null && next > 0)
        ? (stats.currentStreak / next).clamp(0.0, 1.0)
        : 1.0;
    final remaining = next == null ? 0 : next - stats.currentStreak;
    final subtitle = next == null
        ? context.l10n.rankCardTopRank
        : (remaining > 0
              ? context.l10n.rankCardDaysToPromotion(remaining)
              : context.l10n.rankCardPromotionReady);

    return StatCardShell(
      // Tapping the rank card opens the same rank sheet as tapping the streak
      // flame on the main screen — the full ladder, progress and freeze state.
      onTap: () => showRankSheet(context),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.emoji_events_outlined,
            color: AppTheme.spark,
            size: 28,
          ),
          const SizedBox(height: 8),
          _RankName(rankName),
          const SizedBox(height: 4),
          Text(
            context.l10n.rankLabel.toUpperCase(),
            style: AppTypography.eyebrow(
              fontSize: 11,
            ).copyWith(color: context.colors.subtle),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: context.colors.hairline,
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.spark),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: AppTypography.support(
              fontSize: 11,
            ).copyWith(color: context.colors.subtle),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          // Nothing else on this card says it opens anything, so spell the
          // affordance out — the ladder of ranks is easy to miss otherwise.
          const _TapHint(),
        ],
      ),
    );
  }
}

/// Small "KLIKNIJ ›" pill at the foot of the rank card.
class _TapHint extends StatelessWidget {
  const _TapHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: AppTheme.spark.withValues(alpha: 0.12),
        border: Border.all(color: AppTheme.spark.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              context.l10n.rankCardTapHint.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.eyebrow(
                fontSize: 10,
              ).copyWith(color: AppTheme.spark),
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: AppTheme.spark,
            size: 14,
          ),
        ],
      ),
    );
  }
}

/// The rank name, shrunk to fit at most two lines of this half-width card.
///
/// Names come from the `ranks` table and vary a lot in length — the longest
/// ones ("AMATOR KONTROWERSJI") broke onto a third line with a dangling
/// syllable at a fixed size. Rather than truncate a name the user just earned,
/// step the type down until it fits — from the TITLE size (30) to Barlow's
/// floor (20; below that the condensed caps stop reading as a headline).
///
/// Implemented as a render object (not a [LayoutBuilder]) because the stats row
/// sits inside an [IntrinsicHeight]: intrinsic sizing must be answerable, and a
/// [LayoutBuilder] throws when asked for it.
class _RankName extends LeafRenderObjectWidget {
  const _RankName(this.name);

  final String name;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderRankName(
    name,
    DefaultTextStyle.of(context).style,
    MediaQuery.textScalerOf(context),
    Directionality.of(context),
  );

  @override
  void updateRenderObject(BuildContext context, _RenderRankName renderObject) {
    renderObject
      ..name = name
      ..baseStyle = DefaultTextStyle.of(context).style
      ..textScaler = MediaQuery.textScalerOf(context)
      ..textDirection = Directionality.of(context);
  }
}

class _RenderRankName extends RenderBox {
  _RenderRankName(
    this._name,
    this._baseStyle,
    this._textScaler,
    this._textDirection,
  );

  static const double _maxFontSize = 30;
  static const double _minFontSize = 20;
  static const double _step = 0.5;
  static const int _maxLines = 2;

  String _name;
  set name(String value) {
    if (_name == value) return;
    _name = value;
    markNeedsLayout();
  }

  TextStyle _baseStyle;
  set baseStyle(TextStyle value) {
    if (_baseStyle == value) return;
    _baseStyle = value;
    markNeedsLayout();
  }

  TextScaler _textScaler;
  set textScaler(TextScaler value) {
    if (_textScaler == value) return;
    _textScaler = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  /// Painter kept from [performLayout] so [paint] draws the exact laid-out text.
  TextPainter? _painter;

  static TextStyle _styleFor(double fontSize) =>
      AppTypography.title(fontSize: fontSize).copyWith(color: AppTheme.spark);

  TextPainter _layoutPainter(double fontSize, double maxWidth) => TextPainter(
    text: TextSpan(text: _name, style: _baseStyle.merge(_styleFor(fontSize))),
    textAlign: TextAlign.center,
    textDirection: _textDirection,
    textScaler: _textScaler,
    maxLines: _maxLines,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth);

  /// Steps the font down from [_maxFontSize] until the name fits two lines of
  /// [maxWidth] (or [_minFontSize] is reached), returning the fitted painter.
  TextPainter _fit(double maxWidth) {
    var fontSize = _maxFontSize;
    var painter = _layoutPainter(fontSize, maxWidth);
    while (fontSize > _minFontSize && painter.didExceedMaxLines) {
      fontSize -= _step;
      painter.dispose();
      painter = _layoutPainter(fontSize, maxWidth);
    }
    return painter;
  }

  @override
  void performLayout() {
    _painter?.dispose();
    final painter = _fit(constraints.maxWidth);
    _painter = painter;
    size = constraints.constrain(Size(painter.width, painter.height));
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    final painter = _layoutPainter(_minFontSize, double.infinity);
    final width = painter.minIntrinsicWidth;
    painter.dispose();
    return width;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    final painter = _layoutPainter(_maxFontSize, double.infinity);
    final width = painter.maxIntrinsicWidth;
    painter.dispose();
    return width;
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      computeMaxIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) {
    final painter = _fit(width);
    final height = painter.height;
    painter.dispose();
    return height;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final painter = _painter;
    if (painter == null) return;
    // Centre horizontally when constrained wider than the text itself.
    final dx = (size.width - painter.width) / 2;
    painter.paint(context.canvas, offset + Offset(dx, 0));
  }

  @override
  void dispose() {
    _painter?.dispose();
    _painter = null;
    super.dispose();
  }
}
