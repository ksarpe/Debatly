import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_typography.dart';

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
    required this.voteYesInk,
    required this.voteNoInk,
    required this.sparkInk,
    required this.voteInkFades,
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

  /// The TAK green as *foreground* — the colour a label, percentage or check
  /// mark is painted in on top of a green-tinted tile.
  ///
  /// Not the same value as [AppTheme.yes], which is the FILL hue and was picked
  /// against the black canvas. Painting that hue as text over its own light
  /// tint left the community split at 1.5:1 on the light canvas — pale green on
  /// pale green. The fill still carries the side; the ink only has to be
  /// readable.
  final Color voteYesInk;

  /// The NIE red as foreground — see [voteYesInk].
  final Color voteNoInk;

  /// The spark accent as foreground, for small labels sitting on a
  /// spark-tinted surface (the "NOWE" pill).
  final Color sparkInk;

  /// Whether a vote-side ink may be faded with alpha to de-emphasise the side
  /// the user did *not* pick.
  ///
  /// True on the dark canvas, where fading a bright ink toward a near-black
  /// tile reads as "quieter" and stays legible. False on the light canvas: the
  /// ink there is a dark green/red and fading it toward the pale tile is
  /// exactly what made the unpicked side unreadable, so the weaker fill carries
  /// the de-emphasis on its own. See [voteInkMuted].
  final bool voteInkFades;

  /// The ink the TAK/NIE label and percentage are painted in.
  Color voteInk(bool isYes) => isYes ? voteYesInk : voteNoInk;

  /// [voteInk] de-emphasised for the side the user did not pick — faded to
  /// [alpha] where the canvas allows it ([voteInkFades]), solid where it does
  /// not.
  Color voteInkMuted(bool isYes, double alpha) =>
      voteInkFades ? voteInk(isYes).withValues(alpha: alpha) : voteInk(isYes);

  /// Dark theme — the original "pure black canvas", high-contrast and
  /// distraction-free. Ink is a warm cream (#FFE9DC), not pure white — the
  /// brand text-on-dark colour.
  static const AppColors dark = AppColors(
    background: Color(0xFF000000),
    ink: Color(0xFFFFE9DC),
    // Warm grey from the type spec's SUPPORT role — pairs with the cream ink.
    subtle: Color(0xFF9B938A),
    accent: Color(0xFF2A2A2A),
    cardSurface: Color(0xFF131318),
    hairline: Color(0xFF26262E),
    // On black the fill hues are already the high-contrast choice: the TAK
    // percentage on its own tile measures 4.0:1, so ink == fill here.
    voteYesInk: AppTheme.yes,
    voteNoInk: AppTheme.no,
    sparkInk: AppTheme.spark,
    voteInkFades: true,
  );

  /// Light theme — a soft off-white canvas with white cards floating above it,
  /// near-black ink and a darker grey for secondary text so small labels keep
  /// their contrast on a light background.
  static const AppColors light = AppColors(
    background: Color(0xFFF6F6F9),
    ink: Color(0xFF15161A),
    // Warm grey from the type spec's SUPPORT role (light-canvas variant).
    subtle: Color(0xFF6F6760),
    accent: Color(0xFFE7E7EE),
    cardSurface: Color(0xFFFFFFFF),
    hairline: Color(0xFFE2E2EA),
    // Darkened to clear 4.5:1 against the side's OWN tint, which is the worst
    // case (the picked side fills at 42% alpha): green-800 measures 4.7:1 on
    // #9DE1B8, red-800 4.9:1 on #F6B7B7, and the burnt spark 5.1:1 on #F4E0D4.
    // The bright fill hues sat at 1.5-2.5:1 there.
    voteYesInk: Color(0xFF166534),
    voteNoInk: Color(0xFF991B1B),
    sparkInk: Color(0xFF9A4409),
    voteInkFades: false,
  );

  @override
  AppColors copyWith({
    Color? background,
    Color? ink,
    Color? subtle,
    Color? accent,
    Color? cardSurface,
    Color? hairline,
    Color? voteYesInk,
    Color? voteNoInk,
    Color? sparkInk,
    bool? voteInkFades,
  }) {
    return AppColors(
      background: background ?? this.background,
      ink: ink ?? this.ink,
      subtle: subtle ?? this.subtle,
      accent: accent ?? this.accent,
      cardSurface: cardSurface ?? this.cardSurface,
      hairline: hairline ?? this.hairline,
      voteYesInk: voteYesInk ?? this.voteYesInk,
      voteNoInk: voteNoInk ?? this.voteNoInk,
      sparkInk: sparkInk ?? this.sparkInk,
      voteInkFades: voteInkFades ?? this.voteInkFades,
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
      voteYesInk: Color.lerp(voteYesInk, other.voteYesInk, t)!,
      voteNoInk: Color.lerp(voteNoInk, other.voteNoInk, t)!,
      sparkInk: Color.lerp(sparkInk, other.sparkInk, t)!,
      // A bool has no midpoint: it snaps with the rest of the palette.
      voteInkFades: t < 0.5 ? voteInkFades : other.voteInkFades,
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
  ///
  /// These are FILL hues, picked against the black canvas. Anything painting
  /// text or an icon on top of one of these tints reads its foreground from
  /// [AppColors.voteInk] instead — on the light canvas the fill hue is far too
  /// pale to be its own label.
  static const Color yes = Color(0xFF22C55E);
  // Lifted from the tailwind red-500 (#EF4444): at the low fill alphas the
  // result panels use, that shade sank into the dark background.
  static const Color no = Color(0xFFF7615C);

  /// [no] darkened until WHITE text on it clears WCAG AA (4.6:1, against the
  /// 2.9:1 the plain fill hue managed). For the few surfaces that use the
  /// "no" red as a SOLID background carrying white type — the offline banner
  /// — rather than as a low-alpha tint behind [AppColors.voteInk]. Same hue
  /// family, so the two read as the same red.
  static const Color noOnWhiteText = Color(0xFFD2403A);

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
      // Manrope is the app-wide text face; Barlow Condensed is reserved for
      // UPPERCASE headlines and numerals via AppTypography.
      fontFamily: AppTypography.sans,
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
        // The app runs edge-to-edge (enforced on Android 15+, opted into on
        // older versions in main.dart), so both system bars must stay fully
        // transparent. Without this the AppBar falls back to Flutter's
        // brightness presets, whose nav-bar colour is an opaque black/white
        // slab on Android <15. Icon brightness is the inverse of the canvas.
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: brightness == Brightness.dark
              ? Brightness.light
              : Brightness.dark,
          // iOS reads the bar style from the *background* brightness instead.
          statusBarBrightness: brightness,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: brightness == Brightness.dark
              ? Brightness.light
              : Brightness.dark,
          systemNavigationBarContrastEnforced: false,
        ),
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

  /// Base geometry for the question text — the DISPLAY role (Barlow Condensed
  /// 800, UPPERCASE). Colour/stroke are applied per-layer in
  /// [QuestionTextStyles], so this only carries family, size, weight and
  /// spacing. The size is the *largest* used; long questions shrink it via
  /// [QuestionTextStyles.fontSizeFor] so they don't become a wall of text.
  static final TextStyle questionBase = AppTypography.display(42);
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
  /// Based on the DISPLAY role directly (not `questionBase.copyWith`) so the
  /// em-relative tracking rescales with the fitted size.
  static TextStyle strokeFor(double fontSize) =>
      AppTypography.display(fontSize).copyWith(
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
      AppTypography.display(fontSize).copyWith(color: Colors.white);
}
