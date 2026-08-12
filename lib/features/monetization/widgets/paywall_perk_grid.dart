import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// One PRO perk as it appears on the paywall: a tinted round icon with a short
/// label under it. Deliberately label-only — the grid sells the *shape* of what
/// PRO contains at a glance; the long argument is the headline above it.
class PaywallPerk {
  const PaywallPerk({
    required this.icon,
    required this.label,
    required this.tint,
  });

  final IconData icon;
  final String label;

  /// The perk's own accent. Each tile gets a different hue so the grid reads
  /// as a set of distinct things rather than one repeated row.
  final Color tint;
}

/// The perk grid: three tiles per row, filling the sheet's width.
///
/// Replaces the old stacked benefit rows — the same perks scanned in a glance
/// instead of a paragraph each, which is what keeps the whole paywall (perks,
/// plans, CTA and fine print) on one screen without scrolling.
class PaywallPerkGrid extends StatelessWidget {
  const PaywallPerkGrid({super.key, required this.perks, this.columns = 3});

  final List<PaywallPerk> perks;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var start = 0; start < perks.length; start += columns) {
      final end = (start + columns).clamp(0, perks.length);
      final row = perks.sublist(start, end);
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 18));
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < columns; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              // The trailing slots of a short last row stay empty so the tiles
              // keep their column width instead of stretching.
              Expanded(
                child: i < row.length
                    ? _PerkTile(perk: row[i])
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      );
    }
    return Column(children: rows);
  }
}

class _PerkTile extends StatelessWidget {
  const _PerkTile({required this.perk});

  final PaywallPerk perk;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: perk.tint.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(perk.icon, color: perk.tint, size: 26),
        ),
        const SizedBox(height: 8),
        Text(
          perk.label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.colors.ink,
            fontSize: 12,
            height: 1.25,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
