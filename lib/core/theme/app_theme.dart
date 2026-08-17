import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The semantic, brightness-dependent colours — everything that must flip
/// between the light and dark themes lives here as a [ThemeExtension], so a
/// widget reads the *current* value via `context.colors.x` instead of a fixed
/// constant. The brand accents that stay the same in both themes ([AppTheme.spark],
/// [AppTheme.yes], [AppTheme.no]) deliberately stay on [AppTheme] as plain
/// constants.
///
/// Read it with the [BuildContextColors] extension: `context.colors.background`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.ink,
    required this.subtle,
    required this.accent,
    required this.cardSurface,
    required this.hairline,
  });

  /// App canvas / scaffold background.
  final Color background;

  /// Primary foreground (text + icons).
  final Color ink;

  /// Muted secondary text and quiet icons.
  final Color subtle;

  /// Raised/accent surfaces on the canvas (buttons, dividers, snackbars).
  final Color accent;

  /// A card surface that reads as a distinct layer above [background]
  /// (settings cards, bottom sheets, the auth sheet).
  final Color cardSurface;

  /// Hairline borders/dividers separating rows inside a card.
  final Color hairline;

  /// Dark theme — the original "pure black canvas", high-contrast and
  /// distraction-free. Ink is a warm cream (#FFE9DC), not pure white — the
  /// brand text-on-dark colour.
  static const AppColors dark = AppColors(
    background: Color(0xFF000000),
    ink: Color(0xFFFFE9DC),
    subtle: Color(0xFF8A8A8A),
    accent: Color(0xFF2A2A2A),
    cardSurface: Color(0xFF131318),
    hairline: Color(0xFF26262E),
  );

  /// Light theme — a soft off-white canvas with white cards floating above it,
  /// near-black ink and a darker grey for secondary text so small labels keep
  /// their contrast on a light background.
  static const AppColors light = AppColors(
    background: Color(0xFFF6F6F9),
    ink: Color(0xFF15161A),
    subtle: Color(0xFF5E5E66),
    accent: Color(0xFFE7E7EE),
    cardSurface: Color(0xFFFFFFFF),
    hairline: Color(0xFFE2E2EA),
  );

  @override
  AppColors copyWith({
    Color? background,
    Color? ink,
    Color? subtle,
    Color? accent,
    Color? cardSurface,
    Color? hairline,
  }) {
    return AppColors(
      background: background ?? this.background,
      ink: ink ?? this.ink,
      subtle: subtle ?? this.subtle,
      accent: accent ?? this.accent,
      cardSurface: cardSurface ?? this.cardSurface,
      hairline: hairline ?? this.hairline,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      subtle: Color.lerp(subtle, other.subtle, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      cardSurface: Color.lerp(cardSurface, other.cardSurface, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
    );
  }
}

/// `context.colors.background` etc. — the active [AppColors] for the current
/// theme. Falls back to the dark palette if (somehow) no extension is
/// registered, so a lookup never throws.
extension BuildContextColors on BuildContext {
  AppColors get colors =>
      Theme.of(this).extension<AppColors>() ?? AppColors.dark;
}

/// The smallest touch target the app holds itself to: Material's 48dp, which
/// also clears Apple's 44pt guidance.
///
/// Anything a finger is meant to hit is sized against this. Two controls used to
/// fall short — the share / history pills at 42, and "forgot password?" at the
/// 19pt height of its own glyphs — and a target that small is missed often
/// enough to read as "the app didn't react".
const double kMinTouchTarget = 48;

/// Central place for the brand accents, the global [ThemeData] (light + dark),
/// and the signature "outlined + shadowed" text styling used for the question.
///
/// Brightness-dependent colours live on [AppColors] (read via `context.colors`);
/// only the theme-independent brand accents stay here.
class AppTheme {
  AppTheme._();

  /// Orange "spark" accent — the glowing "go deeper" affordance. Shared by both
  /// themes.
  // Toned down from tailwind orange-500 (#F97316): at full brightness white
  // labels on the spark gradient washed out on the onboarding choice card.
  static const Color spark = Color(0xFFEA6A12);

  /// The hue every orange glow is painted in (#FF6A1A) — a touch brighter than
  /// [spark] so halos read as light, not as a solid orange surface. Callers
  /// apply their own alpha; the canonical CTA value lives in [ctaGlow]
  /// (rgba(255,106,26,.28)).
  static const Color sparkGlow = Color(0xFFFF6A1A);

  /// Semantic vote colours: green for TAK, red for NIE. Used by the daily
  /// vote panel for the buttons' side hints and the post-vote split. Shared by
  /// both themes.
  static const Color yes = Color(0xFF22C55E);
  // Lifted from the tailwind red-500 (#EF4444): at the low fill alphas the
  // result panels use, that shade sank into the dark background.
  static const Color no = Color(0xFFF7615C);

  /// The dark theme — the app's original look.
  static ThemeData get dark => _build(Brightness.dark, AppColors.dark);

  /// The light theme — same structure, light palette.
  static ThemeData get light => _build(Brightness.light, AppColors.light);

  /// Builds a [ThemeData] for [brightness] from the matching [AppColors]
  /// palette, so the two themes stay structurally identical and only the
  /// colours differ.
  static ThemeData _build(Brightness brightness, AppColors colors) {
    final base = ThemeData(
      useMaterial3: true,
      colorSchemeSeed: spark,
      scaffoldBackgroundColor: colors.background,
      brightness: brightness,
    );

    return base.copyWith(
      scaffoldBackgroundColor: colors.background,
      colorScheme: base.colorScheme.copyWith(
        surface: colors.background,
        primary: colors.subtle,
        secondary: colors.subtle,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: colors.ink,
      ),
      iconTheme: IconThemeData(color: colors.ink),
      dividerColor: colors.accent,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: colors.ink,
        ),
      ),
      // Snackbars carry the app's messages on the [accent] surface; pin the text
      // to [ink] so it contrasts in BOTH themes. Without this the Material 3
      // default text colour (onInverseSurface) is dark-on-dark on our overridden
      // accent background and the message reads as blank.
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.accent,
        contentTextStyle: TextStyle(color: colors.ink),
        actionTextColor: spark,
      ),
      extensions: [colors],
    );
  }

  /// The "premium" accent-CTA look shared by every orange primary button —
  /// the paywall CTA, onboarding "next", the auth submit and the settings
  /// "secure account" action: a full stadium pill carrying the spark gradient
  /// and an orange glow. Defined once so the buttons can't drift apart again.
  static const Gradient ctaGradient = LinearGradient(
    colors: [spark, Color(0xFFD9510B)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  /// Corner radius for the accent CTAs. A rounded rectangle, NOT a full
  /// stadium — the sides keep a clear straight run. Tune the look here —
  /// every accent button reads this.
  static const BorderRadius ctaRadius = BorderRadius.all(Radius.circular(14));

  /// The orange halo behind an *enabled* accent CTA — [sparkGlow] at 28%
  /// (rgba(255,106,26,.28)). Disabled buttons drop it (a dimmed button that
  /// still glows reads as tappable).
  static const List<BoxShadow> ctaGlow = [
    BoxShadow(color: Color(0x47FF6A1A), blurRadius: 22, spreadRadius: 1),
  ];

  /// Label/icon colour on the CTA gradient — a near-black warm brown
  /// (#170A02), not white: on the spark orange dark reads at ~7:1 contrast
  /// where white only manages ~3:1, and the brown keeps the warmth of the
  /// palette where pure black looked stamped-on.
  static const Color ctaForeground = Color(0xFF170A02);

  /// Base geometry for the question text. Colour/stroke are applied per-layer
  /// in [QuestionTextStyles], so this only carries size, weight and spacing.
  /// The size is the *largest* used; long questions shrink it via
  /// [QuestionTextStyles.fontSizeFor] so they don't become a wall of text.
  static const TextStyle questionBase = TextStyle(
    fontFamily: 'Anton',
    fontSize: 42,
    fontWeight: FontWeight.w400,
    height: 1.15,
    letterSpacing: 0.5,
  );
}

/// The two paint layers that produce the white-fill / black-stroke look.
///
/// Flutter cannot fill *and* stroke a single [Text] in one pass, so the
/// question is rendered as two stacked [Text] widgets sharing these styles.
/// The look is deliberately theme-independent — a white "sticker" with a black
/// outline reads on either a black or a light canvas.
class QuestionTextStyles {
  QuestionTextStyles._();

  /// Largest font size, used for short questions.
  static const double maxFontSize = 42;

  /// Smallest font size, used for very long questions.
  static const double minFontSize = 26;

  /// Length (in characters) up to which the text stays at [maxFontSize], and
  /// the length at/after which it bottoms out at [minFontSize]. Between them the
  /// size scales linearly so longer questions read as several tidy lines rather
  /// than an overflowing block.
  static const int _shortLen = 55;
  static const int _longLen = 150;

  /// Outline width relative to the font size, so the stroke stays proportional
  /// when the text shrinks (6px at the 42px base size).
  static const double _strokeRatio = 6 / 42;

  /// Picks a font size for [text] based on its length, clamped to
  /// [minFontSize]..[maxFontSize].
  static double fontSizeFor(String text) {
    final len = text.trim().length;
    if (len <= _shortLen) return maxFontSize;
    if (len >= _longLen) return minFontSize;
    final t = (len - _shortLen) / (_longLen - _shortLen);
    return maxFontSize - t * (maxFontSize - minFontSize);
  }

  /// Floor used when the length-based size genuinely does not fit the space it
  /// is given — a small screen, a large system font, or an unusually long
  /// question. [minFontSize] stays the *design* floor for a comfortable screen;
  /// this one only exists so the question shrinks rather than growing into the
  /// vote panel and the share / history pills below it.
  static const double hardMinFontSize = 18;

  /// Horizontal gap between two words on the same line, kept proportional to
  /// the (possibly reduced) size — 14px at the 42px base. Lives here so the
  /// `FallingWordsText` layout and [fitFontSize]'s simulation of it can never
  /// drift apart.
  static double wordSpacingFor(double fontSize) =>
      fontSize * (14 / maxFontSize);

  /// Vertical gap between two lines of the assembled question.
  static const double lineSpacing = 2;

  /// Step (in px) the fit search walks down by.
  static const double _fitStep = 1;

  /// Last few fit results, keyed by (text, box, text scale). The question is
  /// re-laid-out on every rebuild of the feed, and the search below costs a
  /// handful of [TextPainter] passes — with one question on screen at a time a
  /// tiny cache turns all but the first into a map lookup.
  static final Map<String, double> _fitCache = {};

  /// The largest size at or below [fontSizeFor] at which [text], laid out as
  /// centred words exactly the way `FallingWordsText` lays them out, still fits
  /// a [maxWidth] × [maxHeight] box — never going below [hardMinFontSize].
  ///
  /// [fontSizeFor] alone only knows the character count, so on a short screen
  /// (or with a large system font) a long question grew past the space it had
  /// and ran into the vote panel and the pills underneath. This keeps the
  /// length-based size as the intended look and only shrinks further when the
  /// box demands it. An unbounded box returns the length-based size unchanged.
  static double fitFontSize(
    String text, {
    required double maxWidth,
    required double maxHeight,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    final preferred = fontSizeFor(text);
    if (maxWidth <= 0 ||
        maxHeight <= 0 ||
        !maxWidth.isFinite ||
        !maxHeight.isFinite) {
      return preferred;
    }

    final key =
        '${maxWidth.round()}x${maxHeight.round()}'
        '@${textScaler.scale(100).round()}|$text';
    final cached = _fitCache[key];
    if (cached != null) return cached;

    final words = text.trim().split(RegExp(r'\s+'));
    var size = preferred;
    while (size > hardMinFontSize &&
        _blockHeight(words, size, maxWidth, textScaler) > maxHeight) {
      size = math.max(hardMinFontSize, size - _fitStep);
    }

    // Bounded so a long session of varied questions can't grow it forever.
    if (_fitCache.length >= 32) _fitCache.clear();
    return _fitCache[key] = size;
  }

  /// Height the assembled question occupies at [fontSize], replaying the greedy
  /// line-breaking of the `Wrap` that lays the words out.
  static double _blockHeight(
    List<String> words,
    double fontSize,
    double maxWidth,
    TextScaler textScaler,
  ) {
    final spacing = wordSpacingFor(fontSize);
    final style = fillFor(fontSize);
    var total = 0.0;
    var runWidth = 0.0;
    var runHeight = 0.0;

    void closeRun() {
      total += runHeight + (total > 0 ? lineSpacing : 0);
    }

    for (final word in words) {
      final size = _measure(word.toUpperCase(), style, textScaler);
      if (runWidth > 0 && runWidth + spacing + size.width > maxWidth) {
        closeRun();
        runWidth = size.width;
        runHeight = size.height;
      } else {
        runWidth = runWidth > 0 ? runWidth + spacing + size.width : size.width;
        runHeight = math.max(runHeight, size.height);
      }
    }
    if (runWidth > 0) closeRun();
    return total;
  }

  static Size _measure(String text, TextStyle style, TextScaler textScaler) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    final size = painter.size;
    painter.dispose();
    return size;
  }

  /// Bottom layer: the black outline, drawn slightly wider, with a drop shadow.
  static TextStyle strokeFor(double fontSize) => AppTheme.questionBase.copyWith(
    fontSize: fontSize,
    foreground: Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = fontSize * _strokeRatio
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.black,
    shadows: const [
      Shadow(color: Color(0x55000000), offset: Offset(0, 4), blurRadius: 6),
    ],
  );

  /// Top layer: the white fill sitting inside the outline.
  static TextStyle fillFor(double fontSize) =>
      AppTheme.questionBase.copyWith(fontSize: fontSize, color: Colors.white);
}
