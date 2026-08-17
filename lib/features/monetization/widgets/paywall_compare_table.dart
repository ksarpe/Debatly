import 'package:flutter/material.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';

/// The Free-vs-PRO comparison table on the paywall sheet. One glance answers
/// "what am I actually paying for" — the daily-limit row says more than any
/// benefit list. Free's real perks (community results, streak & ranks) are
/// shown as kept on purpose: an honest Free column is what makes the PRO
/// column credible.
class PaywallCompareTable extends StatelessWidget {
  const PaywallCompareTable({super.key});

  /// Width of the FREE / PRO value columns. Wide enough for the short text
  /// values ("1 pytanie", "Bez limitu") to wrap at most once.
  static const double _kValueWidth = 82;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;

    final rows = <TableRow>[
      _row(
        context,
        label: l10n.paywallCompareRowDaily,
        free: _text(context, l10n.paywallCompareRowDailyFree),
        pro: _text(context, l10n.paywallCompareRowDailyPro, pro: true),
      ),
      _row(
        context,
        label: l10n.paywallCompareRowSmaczki,
        free: _text(context, l10n.paywallCompareRowSmaczkiFree),
        pro: _text(context, l10n.paywallCompareRowSmaczkiPro, pro: true),
      ),
      _row(
        context,
        label: l10n.paywallCompareRowSplit,
        free: _check(context, included: true, pro: false),
        pro: _check(context, included: true, pro: true),
      ),
      _row(
        context,
        label: l10n.paywallCompareRowStreak,
        free: _check(context, included: true, pro: false),
        pro: _check(context, included: true, pro: true),
      ),
      _row(
        context,
        label: l10n.paywallCompareRowHistory,
        free: _check(context, included: false, pro: false),
        pro: _check(context, included: true, pro: true),
      ),
      _row(
        context,
        label: l10n.paywallCompareRowOffline,
        free: _check(context, included: false, pro: false),
        pro: _check(context, included: true, pro: true),
      ),
    ];

    final headerStyle = TextStyle(
      color: colors.subtle,
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.2,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.hairline, width: 1.4),
      ),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(),
          1: FixedColumnWidth(_kValueWidth),
          2: FixedColumnWidth(_kValueWidth),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            children: [
              const SizedBox.shrink(),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  l10n.paywallCompareFree,
                  textAlign: TextAlign.center,
                  style: headerStyle,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  l10n.paywallComparePro,
                  textAlign: TextAlign.center,
                  style: headerStyle.copyWith(color: AppTheme.spark),
                ),
              ),
            ],
          ),
          ...rows,
        ],
      ),
    );
  }

  TableRow _row(
    BuildContext context, {
    required String label,
    required Widget free,
    required Widget pro,
  }) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Text(
            label,
            style: TextStyle(
              color: context.colors.ink,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ),
        Center(child: free),
        Center(child: pro),
      ],
    );
  }

  Widget _text(BuildContext context, String value, {bool pro = false}) {
    return Text(
      value,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: pro ? AppTheme.spark : context.colors.subtle,
        fontSize: 12.5,
        fontWeight: pro ? FontWeight.w800 : FontWeight.w600,
        height: 1.2,
      ),
    );
  }

  /// A check for "included", a quiet dash for "not included" — with semantic
  /// labels so the table reads correctly to a screen reader.
  Widget _check(
    BuildContext context, {
    required bool included,
    required bool pro,
  }) {
    final l10n = context.l10n;
    if (!included) {
      return Icon(
        Icons.remove_rounded,
        size: 18,
        color: context.colors.subtle.withValues(alpha: 0.55),
        semanticLabel: l10n.paywallCompareExcluded,
      );
    }
    return Icon(
      Icons.check_rounded,
      size: 18,
      color: pro ? AppTheme.spark : context.colors.subtle,
      semanticLabel: l10n.paywallCompareIncluded,
    );
  }
}
