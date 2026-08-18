import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import 'styled_question_text.dart';

/// A self-contained, share-ready poster of a single question: the Debatly
/// logo, the question rendered in the app's signature white-fill /
/// black-outline "sticker" style, and a hook line above the `debatly.app`
/// call-to-action, on a dark orange-tinted gradient.
///
/// Deliberately **theme-independent** — it reads no `context.colors`, so it
/// renders identically whether the app is in light or dark mode (and when drawn
/// off-screen by [renderWidgetToPng], where no app theme is in scope). That same
/// fixed dark look is what makes the render double as App Store / Play
/// screenshot source art, not just a chat-share image.
///
/// The default [size] is 9:16; captured at a 3× pixel ratio it yields a
/// 1080×1920 PNG.
class QuestionShareCard extends StatelessWidget {
  const QuestionShareCard({
    super.key,
    required this.questionText,
    required this.tagline,
    this.logo,
    this.size = const Size(360, 640),
  });

  /// The full question text to feature (rendered uppercased, like on screen).
  final String questionText;

  /// Short hook shown above the `debatly.app` URL, e.g. "A Ty? TAK czy NIE?".
  /// Passed in (not hard-coded) so it stays localized.
  final String tagline;

  /// Pre-decoded brand logo painted at the top of the poster. It must be
  /// **already decoded** (see [loadLogo]) because [renderWidgetToPng] captures
  /// in a single synchronous paint pass with no frame loop to deliver an async
  /// `Image.asset`. When null the poster falls back to the text wordmark so it
  /// never renders a blank badge (and keeps widget tests theme-free).
  final ui.Image? logo;

  /// Logical size of the poster. 9:16 by default.
  final Size size;

  // Fixed palette (not from AppColors) so the poster looks the same in either
  // theme and when rendered with no theme at all.
  static const Color _bgTop = Color(0xFF0C0A14);
  static const Color _bgBottom = Color(0xFF171124);
  static const Color _taglineInk = Color(0xFFB9B4C6);

  /// Decodes the brand logo asset into a paint-ready [ui.Image] for [logo].
  ///
  /// Callers do this once, before [renderWidgetToPng], so the mark is present in
  /// the single synchronous capture pass. Returns null on any failure; the card
  /// then falls back to the text wordmark rather than dead-ending the share.
  static Future<ui.Image?> loadLogo() async {
    try {
      final data = await rootBundle.load('assets/images/logo.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

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
                  _Brandmark(logo: logo, fontSize: size.width * 0.085),
                  // The hero: the question in the signature stacked stroke+fill
                  // style, centred in the band between the logo and the
                  // footer. QuestionTextStyles already picks a font size from
                  // the length; the FittedBox is a backstop that scales a
                  // pathologically long question down so it can never overflow
                  // the fixed-height poster (normal lengths fit and aren't
                  // scaled).
                  Expanded(
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SizedBox(
                          width: size.width * 0.82,
                          child: StyledQuestionText(questionText),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _BrandFooter(hook: tagline, accentWidth: size.width * 0.14),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The poster's top mark: the real brand [logo] when one was pre-decoded, else
/// the static "Debatly" wordmark. A non-animated sibling of the
/// splash/onboarding `SparkLogo`, safe to paint in a one-shot off-screen render.
class _Brandmark extends StatelessWidget {
  const _Brandmark({required this.logo, required this.fontSize});

  final ui.Image? logo;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final logo = this.logo;
    if (logo == null) return _Wordmark(fontSize: fontSize);
    // The logo is square art; ~1.9× the wordmark cap-height reads as a badge.
    final dim = fontSize * 1.9;
    return RawImage(
      image: logo,
      width: dim,
      height: dim,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
  }
}

/// The static Debatly wordmark, set in the display font — the fallback mark used
/// when no decoded [_Brandmark.logo] is available (e.g. widget tests).
class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.fontSize});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      'DEBATLY',
      style: AppTypography.display(
        fontSize,
      ).copyWith(height: 1, color: Colors.white),
    );
  }
}

/// A short spark-coloured rule over a muted, letter-spaced [hook], with the
/// `debatly.app` URL set in the display font beneath it as the call-to-action —
/// the poster's footer.
class _BrandFooter extends StatelessWidget {
  const _BrandFooter({required this.hook, required this.accentWidth});

  final String hook;
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
          hook.toUpperCase(),
          textAlign: TextAlign.center,
          style: AppTypography.eyebrow(
            fontSize: 11,
          ).copyWith(color: QuestionShareCard._taglineInk, height: 1.3),
        ),
        const SizedBox(height: 8),
        // The URL rides in the condensed display face, so it goes uppercase —
        // Barlow is never set in lowercase.
        Text(
          'DEBATLY.APP',
          textAlign: TextAlign.center,
          style: AppTypography.title(
            fontSize: 22,
          ).copyWith(color: AppTheme.spark, height: 1),
        ),
      ],
    );
  }
}
