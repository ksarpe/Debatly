import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/models/debate_profile.dart';

/// A share-ready poster announcing the user's debate-profile type: the Debatly
/// wordmark, a miniature of the 2×2 grid with the user's cell lit, the type
/// name as the hero, both axis stat lines, and the app URL — on the same dark
/// gradient as [QuestionShareCard] / [RankShareCard], designed to sit well on
/// a dark Stories background.
///
/// Deliberately **theme-independent** and string-injected, like its two
/// sibling posters: no `context.colors`, no `context.l10n`, so it renders
/// identically off-screen through `renderWidgetToPng` (no theme, no
/// Localizations in scope). All copy arrives already localized.
///
/// The default [size] is 9:16; captured at 3× it yields a 1080×1920 PNG.
class ProfileShareCard extends StatelessWidget {
  const ProfileShareCard({
    super.key,
    required this.type,
    required this.typeName,
    required this.headline,
    required this.questionsLine,
    required this.movedLine,
    required this.footer,
    this.provisionalTag,
    this.size = const Size(360, 640),
  });

  /// Which of the four grid cells to light up.
  final DebateProfileType type;

  /// The localized type name, e.g. "POSZUKIWACZ" — the poster's hero.
  final String typeName;

  /// Eyebrow above the name, e.g. "MÓJ TYP DEBATANTA".
  final String headline;

  /// First stat line, e.g. "47 pytań · przeciw tłumowi w 68%".
  final String questionsLine;

  /// Second stat line, e.g. "12 razy zmieniłem zdanie".
  final String movedLine;

  /// The app URL in the footer ("debatly.app").
  final String footer;

  /// Small note under the name for a 6–11-answer profile ("profil wstępny");
  /// null once the profile is full — the poster stays honest either way.
  final String? provisionalTag;

  final Size size;

  // Fixed palette (not from AppColors) so the poster looks the same in either
  // theme and when rendered with no theme at all. Mirrors [RankShareCard].
  static const Color _bgTop = Color(0xFF0C0A14);
  static const Color _bgBottom = Color(0xFF171124);
  static const Color _footerInk = Color(0xFFB9B4C6);

  @override
  Widget build(BuildContext context) {
    return SizedBox.fromSize(
      size: size,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bgTop, _bgBottom],
          ),
        ),
        child: Stack(
          children: [
            // Soft orange halo bleeding in from the top, echoing the splash
            // glow — same device as the sibling posters.
            Positioned(
              top: -size.height * 0.16,
              left: -size.width * 0.10,
              right: -size.width * 0.10,
              child: Center(
                child: Container(
                  width: size.width * 1.1,
                  height: size.width * 1.1,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppTheme.spark.withValues(alpha: 0.30),
                        AppTheme.spark.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: size.width * 0.09,
                vertical: size.height * 0.075,
              ),
              child: Column(
                children: [
                  Text(
                    'DEBATLY',
                    style: AppTypography.display(
                      size.width * 0.085,
                    ).copyWith(height: 1, color: Colors.white),
                  ),
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _MiniGrid(active: type, cell: size.width * 0.135),
                          SizedBox(height: size.height * 0.05),
                          Text(
                            headline.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: AppTypography.eyebrow(
                              fontSize: size.width * 0.042,
                              tracking: 0.18,
                            ).copyWith(color: AppTheme.spark),
                          ),
                          SizedBox(height: size.height * 0.018),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: SizedBox(
                              width: size.width * 0.82,
                              child: Text(
                                typeName.toUpperCase(),
                                textAlign: TextAlign.center,
                                style: AppTypography.display(
                                  size.width * 0.125,
                                ).copyWith(color: Colors.white),
                              ),
                            ),
                          ),
                          if (provisionalTag != null) ...[
                            SizedBox(height: size.height * 0.012),
                            Text(
                              provisionalTag!,
                              style: AppTypography.support(
                                fontSize: size.width * 0.036,
                              ).copyWith(color: _footerInk),
                            ),
                          ],
                          SizedBox(height: size.height * 0.03),
                          Text(
                            questionsLine,
                            textAlign: TextAlign.center,
                            style:
                                AppTypography.body(
                                  fontSize: size.width * 0.042,
                                ).copyWith(
                                  color: Colors.white.withValues(alpha: 0.92),
                                ),
                          ),
                          SizedBox(height: size.height * 0.008),
                          Text(
                            movedLine,
                            textAlign: TextAlign.center,
                            style:
                                AppTypography.body(
                                  fontSize: size.width * 0.042,
                                ).copyWith(
                                  color: Colors.white.withValues(alpha: 0.92),
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: size.width * 0.14,
                        height: 3,
                        decoration: BoxDecoration(
                          color: AppTheme.spark,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        footer,
                        textAlign: TextAlign.center,
                        style: AppTypography.eyebrow(
                          fontSize: 12,
                        ).copyWith(color: _footerInk, height: 1.3),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The poster's emblem: an abstract 2×2 grid with the user's cell filled and
/// glowing — instantly reads as "I landed HERE" without needing labels.
class _MiniGrid extends StatelessWidget {
  const _MiniGrid({required this.active, required this.cell});

  final DebateProfileType active;

  /// Side length of one cell.
  final double cell;

  static const List<List<DebateProfileType>> _layout = [
    [DebateProfileType.pillar, DebateProfileType.flow],
    [DebateProfileType.wolf, DebateProfileType.seeker],
  ];

  @override
  Widget build(BuildContext context) {
    final gap = cell * 0.14;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in _layout)
          Padding(
            padding: EdgeInsets.only(bottom: row == _layout.last ? 0 : gap),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final t in row)
                  Padding(
                    padding: EdgeInsets.only(right: t == row.last ? 0 : gap),
                    child: Container(
                      width: cell,
                      height: cell,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(cell * 0.22),
                        color: t == active
                            ? AppTheme.spark
                            : Colors.white.withValues(alpha: 0.08),
                        border: Border.all(
                          color: t == active
                              ? AppTheme.spark
                              : Colors.white.withValues(alpha: 0.22),
                          width: 1.5,
                        ),
                        boxShadow: t == active
                            ? [
                                BoxShadow(
                                  color: AppTheme.sparkGlow.withValues(
                                    alpha: 0.55,
                                  ),
                                  blurRadius: cell * 0.6,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
