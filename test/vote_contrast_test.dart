import 'package:debatly/core/theme/app_theme.dart';
import 'package:debatly/data/models/vote_result.dart';
import 'package:debatly/features/questions/widgets/vote_visuals.dart';
import 'package:debatly/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Contrast guards for the one surface that has to be readable on BOTH
/// canvases: the community split.
///
/// The split is a free-tier row and the payoff of every vote, and it is painted
/// as a coloured label sitting on a tint of its own hue — the exact shape that
/// silently collapses when the canvas flips. It did: [AppTheme.yes] /
/// [AppTheme.no] are fill hues chosen against black, and reused as text over
/// their own 42% tint on the light canvas they measured 1.5:1 and 1.8:1 — pale
/// green on pale green. Foregrounds now come from [AppColors.voteInk] instead.
///
/// The numbers below are WCAG 2.1 contrast ratios, taken against the
/// *composited* tile rather than the page background: the tile is what the
/// glyphs actually sit on, and it is always the tighter of the two.
void main() {
  /// The WCAG ratio between [text] and the tile it sits on — [fill] at
  /// [fillAlpha] flattened onto [canvas].
  double ratioOnTile(Color text, Color fill, double fillAlpha, Color canvas) {
    final tile = Color.alphaBlend(fill.withValues(alpha: fillAlpha), canvas);
    final ink = Color.alphaBlend(text, tile);
    final a = ink.computeLuminance();
    final b = tile.computeLuminance();
    final (hi, lo) = a > b ? (a, b) : (b, a);
    return (hi + 0.05) / (lo + 0.05);
  }

  /// The picked side's label, percentage and check mark — full-strength text on
  /// the strong 42% tint, the worst case on either canvas.
  void expectPickedSideReadable(AppColors colors, String canvas, double floor) {
    for (final isYes in [true, false]) {
      final side = isYes ? 'TAK' : 'NIE';
      final fill = isYes ? AppTheme.yes : AppTheme.no;
      expect(
        ratioOnTile(colors.voteInk(isYes), fill, 0.42, colors.background),
        greaterThanOrEqualTo(floor),
        reason: '$canvas: the picked $side panel, label + percentage',
      );
    }
  }

  /// The other side — the panel the user did not pick and the smaczek
  /// challenge's unlit tile. Both are de-emphasised on purpose, so they answer
  /// to [floor] rather than to the small-text bar.
  void expectOtherSideReadable(AppColors colors, String canvas, double floor) {
    for (final isYes in [true, false]) {
      final side = isYes ? 'TAK' : 'NIE';
      final fill = isYes ? AppTheme.yes : AppTheme.no;
      // The result panel's unpicked label (12% tint)...
      expect(
        ratioOnTile(
          colors.voteInkMuted(isYes, 0.6),
          fill,
          0.12,
          colors.background,
        ),
        greaterThanOrEqualTo(floor),
        reason: '$canvas: the unpicked $side panel, label',
      );
      // ...and the smaczek challenge's unlit tile (10% tint).
      expect(
        ratioOnTile(
          colors.voteInkMuted(isYes, 0.45),
          fill,
          0.10,
          colors.background,
        ),
        greaterThanOrEqualTo(floor),
        reason: '$canvas: the unlit $side vote tile, label',
      );
    }
  }

  group('the vote split stays legible', () {
    // The dark canvas is held to the 3:1 large-text / non-text floor rather
    // than 4.5: its ink IS the brand hue, and #22C55E measures 4.04:1 on its
    // own 42% tint — enough for the 26px percentage and the check mark, a
    // shade short for the 11px label. That gap predates the light canvas and
    // closing it means moving the brand green, which is a design call rather
    // than an accessibility patch.
    test('on the dark canvas', () {
      expectPickedSideReadable(AppColors.dark, 'dark', 3.0);
      // Dark's faded labels run 2.16-3.67:1 — dimmed twice over (a 10-12%
      // fill under a 45-60% ink), so the weakest of them (the unlit NIE tile)
      // sit well under 3:1. This floor is a ratchet pinning where dark stands
      // today, not a target; lifting them is a one-line alpha change per call
      // site and the same deliberate-dimming design call as the note above.
      expectOtherSideReadable(AppColors.dark, 'dark', 2.1);
    });

    // The light canvas carries no such constraint — its ink exists for exactly
    // this job — so it answers to the full small-text bar.
    test('on the light canvas', () {
      expectPickedSideReadable(AppColors.light, 'light', 4.5);
      expectOtherSideReadable(AppColors.light, 'light', 4.5);
    });
  });

  group('the NOWE badge stays legible', () {
    for (final (name, colors) in [
      ('dark', AppColors.dark),
      ('light', AppColors.light),
    ]) {
      test('on the $name canvas', () {
        expect(
          ratioOnTile(colors.sparkInk, AppTheme.spark, 0.16, colors.background),
          greaterThanOrEqualTo(4.5),
          reason: '$name: the badge label on its 16% spark tint',
        );
      });
    }
  });

  group('the history card and the toasts use the same ink', () {
    for (final (name, colors) in [
      ('dark', AppColors.dark),
      ('light', AppColors.light),
    ]) {
      test('on the $name canvas', () {
        for (final isYes in [true, false]) {
          final side = isYes ? 'TAK' : 'NIE';
          final fill = isYes ? AppTheme.yes : AppTheme.no;
          // The history card's "TY: TAK" eyebrow, on the card's own 10% tint.
          expect(
            ratioOnTile(colors.voteInk(isYes), fill, 0.10, colors.background),
            greaterThanOrEqualTo(name == 'dark' ? 3.0 : 4.5),
            reason: '$name: the history card’s $side label',
          );
          // The toast glyph, on its 16% disc over the CARD, not the canvas.
          expect(
            ratioOnTile(colors.voteInk(isYes), fill, 0.16, colors.cardSurface),
            greaterThanOrEqualTo(3.0),
            reason: '$name: the $side toast glyph on its disc',
          );
        }
        expect(
          ratioOnTile(
            colors.sparkInk,
            AppTheme.spark,
            0.16,
            colors.cardSurface,
          ),
          greaterThanOrEqualTo(3.0),
          reason: '$name: the info toast glyph on its disc',
        );
      });
    }
  });

  testWidgets('the rendered split really reads from the ink, not the fill', (
    tester,
  ) async {
    // The guards above pin the PALETTE. This one pins the WIRING: without it,
    // reverting vote_visuals.dart to `isYes ? AppTheme.yes : AppTheme.no` left
    // every ratio above passing while the light-canvas split went back to
    // 1.5:1 on screen. The goldens cannot cover it either — they render dark,
    // where ink and fill are the same colour by definition.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('pl'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: VoteResultsRow(
            result: VoteResult(
              yesCount: 61,
              noCount: 39,
              myChoice: VoteResult.yes,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pct = tester.widget<Text>(find.text('61%'));
    expect(
      pct.style?.color,
      AppColors.light.voteInk(true),
      reason: 'the picked percentage must be painted in the light ink',
    );
    expect(
      pct.style?.color,
      isNot(AppTheme.yes),
      reason: 'the fill hue is what measured 1.5:1 here',
    );
  });

  test('the fill hues are not their own foreground on the light canvas', () {
    // The regression itself, pinned. If a future palette ever makes these pass,
    // the split above has stopped guarding anything and should be revisited.
    expect(
      ratioOnTile(AppTheme.yes, AppTheme.yes, 0.42, AppColors.light.background),
      lessThan(3.0),
    );
    expect(
      ratioOnTile(AppTheme.no, AppTheme.no, 0.42, AppColors.light.background),
      lessThan(3.0),
    );
  });
}
