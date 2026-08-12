import 'dart:ui';

/// Tokens of an SVG path-data string: a command letter, or a number.
///
/// Exporters pack numbers as tightly as the grammar allows (`c-.4.6.8-1.2`,
/// `3.2.6`), so the data can't be split on whitespace or commas — it has to be
/// scanned. The number branch tries `.5` / `1.5` before the bare-integer form so
/// `3.2` is one token rather than `3.` followed by `2`.
final RegExp _svgPathToken = RegExp(
  r'[MmLlHhVvCcSsQqTtZzAa]|[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?',
);

/// Converts an SVG path-data string (the `d` attribute) into a [Path].
///
/// Exists so brand marks that are only ever shipped as vector artwork — the
/// Apple logo, the Google "G" — can be drawn from their original path data
/// instead of being approximated with Material icons or baked into a bitmap
/// that goes soft on a 3x screen. It covers the subset those marks use:
/// move / line / horizontal / vertical / cubic / quadratic / smooth / close, in
/// both absolute and relative form, including implicit repetition of the last
/// command. Elliptical arcs (`A` / `a`) are rejected rather than silently
/// approximated, so a path using them fails loudly at parse time.
///
/// Throws a [FormatException] on anything it can't represent faithfully.
Path parseSvgPath(String d) {
  final path = Path();
  final tokens = _svgPathToken
      .allMatches(d)
      .map((match) => match[0]!)
      .toList(growable: false);

  var index = 0;
  var current = Offset.zero; // where the pen is
  var subpathStart = Offset.zero; // where the current subpath began
  Offset? lastCubicControl; // 2nd control point of the previous cubic (for S)
  Offset? lastQuadControl; // control point of the previous quadratic (for T)
  String? command;

  double readNumber() {
    if (index >= tokens.length) {
      throw FormatException('SVG path ended mid-command', d);
    }
    final token = tokens[index++];
    final value = double.tryParse(token);
    if (value == null) {
      throw FormatException('Expected a number, found "$token"', d);
    }
    return value;
  }

  // Relative points are all measured from the pen position at the START of the
  // command, so callers must read every point of a command before moving it.
  Offset readPoint({required bool relative}) {
    final x = readNumber();
    final y = readNumber();
    return relative ? current + Offset(x, y) : Offset(x, y);
  }

  Offset reflect(Offset? previousControl) =>
      previousControl == null ? current : current * 2 - previousControl;

  while (index < tokens.length) {
    final startsWithLetter = double.tryParse(tokens[index]) == null;
    if (startsWithLetter) {
      command = tokens[index++];
    } else if (command == null) {
      throw FormatException('SVG path does not start with a command', d);
    } else if (command == 'M') {
      command = 'L'; // extra coordinate pairs after a moveto are linetos
    } else if (command == 'm') {
      command = 'l';
    }

    final cmd = command;
    // Without this guard a stray number after a closepath would re-enter the
    // `Z` branch forever, since that branch consumes no tokens.
    if (!startsWithLetter && cmd.toUpperCase() == 'Z') {
      throw FormatException('Stray number after a closepath', d);
    }
    final relative = cmd == cmd.toLowerCase();

    switch (cmd.toUpperCase()) {
      case 'M':
        current = readPoint(relative: relative);
        subpathStart = current;
        path.moveTo(current.dx, current.dy);
        lastCubicControl = null;
        lastQuadControl = null;
      case 'L':
        current = readPoint(relative: relative);
        path.lineTo(current.dx, current.dy);
        lastCubicControl = null;
        lastQuadControl = null;
      case 'H':
        final x = readNumber();
        current = Offset(relative ? current.dx + x : x, current.dy);
        path.lineTo(current.dx, current.dy);
        lastCubicControl = null;
        lastQuadControl = null;
      case 'V':
        final y = readNumber();
        current = Offset(current.dx, relative ? current.dy + y : y);
        path.lineTo(current.dx, current.dy);
        lastCubicControl = null;
        lastQuadControl = null;
      case 'C':
        final control1 = readPoint(relative: relative);
        final control2 = readPoint(relative: relative);
        final end = readPoint(relative: relative);
        path.cubicTo(
          control1.dx,
          control1.dy,
          control2.dx,
          control2.dy,
          end.dx,
          end.dy,
        );
        current = end;
        lastCubicControl = control2;
        lastQuadControl = null;
      case 'S':
        final control2 = readPoint(relative: relative);
        final end = readPoint(relative: relative);
        final control1 = reflect(lastCubicControl);
        path.cubicTo(
          control1.dx,
          control1.dy,
          control2.dx,
          control2.dy,
          end.dx,
          end.dy,
        );
        current = end;
        lastCubicControl = control2;
        lastQuadControl = null;
      case 'Q':
        final control = readPoint(relative: relative);
        final end = readPoint(relative: relative);
        path.quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
        current = end;
        lastCubicControl = null;
        lastQuadControl = control;
      case 'T':
        final end = readPoint(relative: relative);
        final control = reflect(lastQuadControl);
        path.quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
        current = end;
        lastCubicControl = null;
        lastQuadControl = control;
      case 'Z':
        path.close();
        current = subpathStart;
        lastCubicControl = null;
        lastQuadControl = null;
      default:
        throw FormatException('Unsupported SVG path command "$cmd"', d);
    }
  }

  return path;
}
