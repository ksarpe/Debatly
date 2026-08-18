import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';

// Shared building blocks for the settings hub and its sub-screens: the small
// layout primitives (section label, card, row divider), the accent colours that
// span several rows/sheets, and the locale-aware long-date formatter.

/// Gold accent for the "go Premium" upsell, matching the auth notice.
const Color kGold = Color(0xFFFFC857);

const Color kDanger = Color(0xFFFF6B6B);

/// Soft green used for the active-premium state, matching the original row.
const Color kPremiumGreen = Color(0xFF7CE38B);

class SettingsSectionLabel extends StatelessWidget {
  const SettingsSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          // EYEBROW demands uppercase; every current caller already passes
          // caps, so this is a belt-and-braces no-op that keeps it true.
          text.toUpperCase(),
          style: AppTypography.eyebrow(
            fontSize: 11,
          ).copyWith(color: AppTheme.spark),
        ),
      ),
    );
  }
}

/// Rounded card grouping a column of rows.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.cardSurface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.colors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// Hairline separator inset past the leading icon, like iOS grouped lists.
class SettingsRowDivider extends StatelessWidget {
  const SettingsRowDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: context.colors.hairline,
      indent: 56,
    );
  }
}

/// Full month names for the renewal/expiry date, hand-rolled per locale to
/// avoid pulling in `intl`'s date-symbol initialisation.
/// Polish months are in the genitive case ("21 lipca 2026"), as dates take it.
const List<String> _monthsEnFull = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const List<String> _monthsPlGenitive = [
  'stycznia',
  'lutego',
  'marca',
  'kwietnia',
  'maja',
  'czerwca',
  'lipca',
  'sierpnia',
  'września',
  'października',
  'listopada',
  'grudnia',
];

String formatLongDate(DateTime date, String localeCode) {
  final local = date.toLocal();
  final months = localeCode == 'pl' ? _monthsPlGenitive : _monthsEnFull;
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}
