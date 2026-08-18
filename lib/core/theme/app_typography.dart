import 'package:flutter/material.dart';

/// The Debatly type system — two families, seven roles.
///
/// * **Barlow Condensed** (600/700/800 bundled) — headlines and numerals only,
///   always UPPERCASE. Lowercase Barlow reads as a mistake; callers must pass
///   already-uppercased strings (Flutter has no CSS-style text-transform).
/// * **Manrope** (400–800 bundled) — everything else: body copy, labels,
///   buttons, meta text. Also the [ThemeData] default family, so any [Text]
///   without an explicit style already renders in Manrope.
///
/// Both families ship as static latin + latin-ext files, so Polish diacritics
/// (ą ć ę ł ń ó ś ź ż) render natively with no fallback font.
///
/// Every role is expressed as a method returning the *geometry* of the role
/// (family, weight, size, tracking, leading). Colour is the caller's job —
/// apply it with `copyWith(color: …)` from `context.colors` so the styles stay
/// theme-independent.
///
/// House rules the roles encode:
/// 1. Barlow only for UPPERCASE text and numerals.
/// 2. Nothing below 10px; caps labels 10–11, running text no smaller than 13.
/// 3. One weight per role — never 700 next to 800 on the same line.
class AppTypography {
  AppTypography._();

  /// Headline/numeral family. UPPERCASE only.
  static const String condensed = 'BarlowCondensed';

  /// Text/UI family — the app-wide default.
  static const String sans = 'Manrope';

  /// 1. DISPLAY — the question itself, the rank name, a screen title.
  /// Barlow Condensed 800, 40–46 nominal (fit logic may shrink long
  /// questions), leading .98, tracking −.005em. UPPERCASE.
  static TextStyle display(double fontSize) => TextStyle(
    fontFamily: condensed,
    fontWeight: FontWeight.w800,
    fontSize: fontSize,
    height: 0.98,
    letterSpacing: fontSize * -0.005,
  );

  /// 2. TITLE — panel, sheet and section headlines.
  /// Barlow Condensed 800, 30–34. UPPERCASE.
  static TextStyle title({double fontSize = 32}) => TextStyle(
    fontFamily: condensed,
    fontWeight: FontWeight.w800,
    fontSize: fontSize,
    height: 1.0,
    letterSpacing: fontSize * -0.005,
  );

  /// 3. NUMERIC — percentages, vote counts, tile values. Barlow Condensed 800,
  /// 20–86, leading .8–1. Big numbers are never set in Manrope.
  static TextStyle numeric(double fontSize, {double height = 1.0}) => TextStyle(
    fontFamily: condensed,
    fontWeight: FontWeight.w800,
    fontSize: fontSize,
    height: height,
    // Numerals sit alone; a hair of positive tracking keeps digit pairs
    // (11, 74) from touching at heavy weights.
    letterSpacing: 0,
  );

  /// 4. BODY — arguments, history rows, card copy.
  /// Manrope 600, 14–15, leading 1.32–1.4.
  static TextStyle body({double fontSize = 14.5, double height = 1.36}) =>
      TextStyle(
        fontFamily: sans,
        fontWeight: FontWeight.w600,
        fontSize: fontSize,
        height: height,
      );

  /// 5. SUPPORT — captions, meta, fine print. Manrope 500, 11–13. Colour is
  /// the caller's job (normally `context.colors.subtle`).
  static TextStyle support({double fontSize = 12, double height = 1.35}) =>
      TextStyle(
        fontFamily: sans,
        fontWeight: FontWeight.w500,
        fontSize: fontSize,
        height: height,
      );

  /// 6. EYEBROW — small-caps labels: "YOU: YES", day headers, section tags.
  /// Manrope 800 (NOT Barlow — condensed glyphs smear at cap sizes), 10–11,
  /// tracking .12–.20em. UPPERCASE.
  static TextStyle eyebrow({double fontSize = 10.5, double tracking = 0.16}) =>
      TextStyle(
        fontFamily: sans,
        fontWeight: FontWeight.w800,
        fontSize: fontSize,
        height: 1.2,
        letterSpacing: fontSize * tracking,
      );

  /// 7. ACTION — buttons and chips. Manrope 800, 11.5–14, tracking .06em.
  /// UPPERCASE. (One sanctioned exception: the rank pill in the header uses
  /// Barlow 800 / 15 — that's [numeric]-style, set it with [title]/[numeric].)
  static TextStyle action({double fontSize = 13}) => TextStyle(
    fontFamily: sans,
    fontWeight: FontWeight.w800,
    fontSize: fontSize,
    height: 1.2,
    letterSpacing: fontSize * 0.06,
  );
}
