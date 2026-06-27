// Batch-exports branded question posters as PNGs for the store listing.
//
// It reuses the exact same [QuestionShareCard] + [renderWidgetToPng] that the
// in-app share button uses, so the screenshots and the share image are one and
// the same art (the ASO "card doubles as store screenshots" point).
//
// Run it like a test (it uses the test harness only to get a FlutterView and to
// load fonts head-less — it is NOT part of the normal suite because it lives
// outside test/ and isn't named *_test.dart):
//
//   flutter test tool/export_store_screenshots.dart
//
// Output → build/store_screenshots/<locale>/01.png, 02.png, …  (1080×1920)
// build/ is git-ignored/ephemeral; copy any poster you want to keep into the
// committed store-art home at marketing/screenshots/ (see marketing/README.md).
//
// Edit the question lists in tool/store_screenshots/questions.<locale>.txt
// (one question per line). See tool/README.md.
//
// Optional overrides (OS env vars):
//   SCREENSHOT_LOCALES      comma list, default "pl,en"
//   SCREENSHOT_OUT_DIR      default "build/store_screenshots"
//   SCREENSHOT_PIXEL_RATIO  default "3"  (3 ⇒ 360×640 logical ⇒ 1080×1920 px)
import 'dart:io';

import 'package:debatly/core/share/widget_to_image.dart';
import 'package:debatly/features/questions/widgets/share_question_card.dart';
import 'package:debatly/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _logicalSize = Size(360, 640);

void main() {
  // Fonts must be loaded OUTSIDE the testWidgets fake-async zone — FontLoader
  // does real platform-channel async the fake clock never pumps (awaiting it
  // inside the test body hangs).
  setUpAll(_loadFonts);

  testWidgets('export store screenshots', (tester) async {
    final locales = (Platform.environment['SCREENSHOT_LOCALES'] ?? 'pl,en')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final outRoot =
        Platform.environment['SCREENSHOT_OUT_DIR'] ?? 'build/store_screenshots';
    final pixelRatio =
        double.tryParse(Platform.environment['SCREENSHOT_PIXEL_RATIO'] ?? '') ??
        3;

    var total = 0;
    for (final code in locales) {
      final questions = _readQuestions(code);
      if (questions.isEmpty) {
        stderr.writeln('• $code: no questions file/lines — skipped');
        continue;
      }
      final l10n = await AppLocalizations.delegate.load(Locale(code));
      final dir = Directory('$outRoot/$code');
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      dir.createSync(recursive: true);

      for (var i = 0; i < questions.length; i++) {
        // Run the off-screen raster outside the fake-async test zone.
        late final List<int> png;
        await tester.runAsync(() async {
          final bytes = await renderWidgetToPng(
            child: QuestionShareCard(
              questionText: questions[i],
              tagline: l10n.shareCardTagline,
            ),
            logicalSize: _logicalSize,
            view: tester.view,
            pixelRatio: pixelRatio,
          );
          png = bytes!;
        });
        final name = '${(i + 1).toString().padLeft(2, '0')}.png';
        File('${dir.path}/$name').writeAsBytesSync(png);
        total++;
      }
      final px = _logicalSize * pixelRatio;
      stderr.writeln(
        '✓ $code: ${questions.length} screenshot(s) '
        '@ ${px.width.toInt()}×${px.height.toInt()} → ${dir.path}',
      );
    }
    stderr.writeln('Done — $total PNG(s) written under $outRoot/.');
    expect(
      total,
      greaterThan(0),
      reason: 'no screenshots were produced; check the questions files',
    );
  });
}

/// Reads `tool/store_screenshots/questions.<locale>.txt`, falling back to the
/// locale-agnostic `questions.txt`. Blank lines and `#` comments are ignored.
List<String> _readQuestions(String locale) {
  const base = 'tool/store_screenshots';
  for (final path in ['$base/questions.$locale.txt', '$base/questions.txt']) {
    final file = File(path);
    if (!file.existsSync()) continue;
    return file
        .readAsLinesSync()
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('#'))
        .toList();
  }
  return const [];
}

/// Loads the fonts the card needs into the head-less render: the bundled
/// `Anton` display face (project asset) plus `MaterialIcons` (the ⚡ bolt) and
/// `Roboto` (the tagline) from the Flutter SDK's cached font artifacts.
Future<void> _loadFonts() async {
  await _load('Anton', 'assets/fonts/Anton-Regular.ttf');
  final materialFonts = '${_flutterRoot()}/bin/cache/artifacts/material_fonts';
  await _load('MaterialIcons', '$materialFonts/materialicons-regular.otf');
  await _load('Roboto', '$materialFonts/roboto-regular.ttf');
}

Future<void> _load(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('⚠ font not found, glyphs may be blank: $path');
    return;
  }
  final loader = FontLoader(family)
    ..addFont(file.readAsBytes().then((b) => b.buffer.asByteData()));
  await loader.load();
}

/// Locates the Flutter SDK root: prefers $FLUTTER_ROOT, else walks up from the
/// test runner executable to the dir that contains `bin/cache`.
String _flutterRoot() {
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && env.isNotEmpty) return env.replaceAll(r'\', '/');
  var dir = File(Platform.resolvedExecutable).parent;
  while (dir.path != dir.parent.path) {
    if (Directory('${dir.path}/bin/cache').existsSync()) {
      return dir.path.replaceAll(r'\', '/');
    }
    dir = dir.parent;
  }
  throw StateError(
    'Could not locate the Flutter SDK; set FLUTTER_ROOT and retry.',
  );
}
