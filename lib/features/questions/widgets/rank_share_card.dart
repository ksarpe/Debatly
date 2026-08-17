import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'rank_sheet.dart' show rankIcon;

/// A self-contained, share-ready poster announcing a rank promotion: the Debatly
/// wordmark, the new rank's badge in a glowing ring, an eyebrow, the rank name,
/// and the streak that earned it — on the same dark orange-tinted gradient as
/// [QuestionShareCard], so the in-app moment and the shared image read as one.
///
/// Deliberately **theme-independent** and string-injected: like
/// [QuestionShareCard] it reads no `context.colors` and no `context.l10n`, so it
/// renders identically in either theme and when drawn off-screen by
/// [renderWidgetToPng] (where neither an app theme nor Localizations is in
/// scope). All copy is passed in already-localized.
///
/// The default [size] is 9:16; captured at 3× it yields a 1080×1920 PNG.
class RankShareCard extends StatelessWidget {
  const RankShareCard({
    super.key,
    required this.rankName,
    required this.headline,
    required this.streakLine,
    required this.tagline,
    this.iconKey,
    this.size = const Size(360, 640),
  });

  /// The reached rank's display name, e.g. "Adwokat diabła".
  final String rankName;

  /// Eyebrow above the name, e.g. "MOJA NOWA RANGA".
  final String headline;

  /// The streak that earned it, e.g. "14 dni z rzędu".
  final String streakLine;

  /// Brand line in the footer (reuses the question card's tagline).
  final String tagline;

  /// Optional rank icon key (e.g. 'mask', 'crown') mapped to a glyph.
  final String? iconKey;

  /// Logical size of the poster. 9:16 by default.
  final Size size;

  // Fixed palette (not from AppColors) so the poster looks the same in either
  // theme and when rendered with no theme at all. Mirrors [QuestionShareCard].
  static const Color _bgTop = Color(0xFF0C0A14);
  static const Color _bgBottom = Color(0xFF171124);
  static const Color _taglineInk = Color(0xFFB9B4C6);

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
            // Soft orange halo bleeding in from the top, echoing the splash glow.
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
                  _Wordmark(fontSize: size.width * 0.085),
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _Badge(iconKey: iconKey, diameter: size.width * 0.34),
                          SizedBox(height: size.height * 0.045),
                          Text(
                            headline.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppTheme.spark,
                              fontSize: size.width * 0.045,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2.4,
                            ),
                          ),
                          SizedBox(height: size.height * 0.018),
                          // The hero: the rank name in the display font, scaled
                          // down only if pathologically long so it never wraps
                          // past the poster width.
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: SizedBox(
                              width: size.width * 0.82,
                              child: Text(
                                rankName,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Anton',
                                  fontSize: size.width * 0.13,
                                  height: 1.05,
                                  letterSpacing: 0.5,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: size.height * 0.024),
                          _StreakLine(
                            text: streakLine,
                            fontSize: size.width * 0.04,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _TaglineFooter(text: tagline, accentWidth: size.width * 0.14),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The rank glyph inside a glowing, spark-tinted ring — the poster's emblem.
class _Badge extends StatelessWidget {
  const _Badge({required this.iconKey, required this.diameter});

  final String? iconKey;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.spark.withValues(alpha: 0.16),
        border: Border.all(
          color: AppTheme.spark.withValues(alpha: 0.65),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.sparkGlow.withValues(alpha: 0.45),
            blurRadius: diameter * 0.4,
            spreadRadius: diameter * 0.02,
          ),
        ],
      ),
      child: Icon(rankIcon(iconKey), color: Colors.white, size: diameter * 0.5),
    );
  }
}

/// A small flame + the streak text, sitting under the rank name.
class _StreakLine extends StatelessWidget {
  const _StreakLine({required this.text, required this.fontSize});

  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.local_fire_department_rounded,
          color: const Color(0xFFF59E0B),
          size: fontSize * 1.3,
        ),
        SizedBox(width: fontSize * 0.3),
        Text(
          text,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.92),
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }
}

/// The static Debatly wordmark in the display font. Mirrors
/// [QuestionShareCard]'s wordmark so both posters match.
class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.fontSize});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      'Debatly',
      style: TextStyle(
        fontFamily: 'Anton',
        fontSize: fontSize,
        height: 1,
        letterSpacing: 1,
        color: Colors.white,
      ),
    );
  }
}

/// A short spark-coloured rule above a muted, letter-spaced tagline — the
/// poster's footer. Mirrors [QuestionShareCard]'s footer.
class _TaglineFooter extends StatelessWidget {
  const _TaglineFooter({required this.text, required this.accentWidth});

  final String text;
  final double accentWidth;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: accentWidth,
          height: 3,
          decoration: BoxDecoration(
            color: AppTheme.spark,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          text.toUpperCase(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: RankShareCard._taglineInk,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}
