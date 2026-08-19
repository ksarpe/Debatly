import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Per-directory test bootstrap: `flutter test` runs this for every test under
/// `test/golden/` (it walks up to the nearest `flutter_test_config.dart`), and
/// nowhere else — so the font loading here is scoped to the golden suite and
/// leaves the rest of the test tree rendering with the default fallback.
///
/// flutter_test ships no real typefaces: text drawn with the bundled `Anton`
/// display face, every `Icons.*` glyph (Material Icons), and even ordinary body
/// text all render as empty placeholder boxes, which would make the goldens
/// meaningless. We load all three — Anton + Material Icons from the build's
/// asset bundle, and Roboto from the SDK for default-family text — so the
/// committed `.png`s look like the shipping app. Rendering stays deterministic:
/// the font files are fixed (Anton in the repo, Roboto pinned to the Flutter
/// SDK version).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await _loadBundledFonts();
  await _loadRobotoFallback();
  await testMain();
}

/// Loads every font declared in the build's `FontManifest.json` — the app's own
/// `Anton` face and Flutter's bundled `MaterialIcons` — into the test's font
/// collection.
Future<void> _loadBundledFonts() async {
  final manifest = await rootBundle.loadStructuredData<List<dynamic>>(
    'FontManifest.json',
    (data) async => json.decode(data) as List<dynamic>,
  );
  for (final entry in manifest) {
    final font = entry as Map<String, dynamic>;
    final loader = FontLoader(_familyOf(font['family'] as String));
    for (final asset in font['fonts'] as List<dynamic>) {
      final descriptor = asset as Map<String, dynamic>;
      loader.addFont(rootBundle.load(descriptor['asset'] as String));
    }
    await loader.load();
  }
}

/// flutter_test's default font renders every glyph as a placeholder box, so any
/// text in the default family (everything that isn't `Anton`) would be
/// unreadable in a golden. Register the real Roboto faces the SDK ships with —
/// resolved from `FLUTTER_ROOT`, which `flutter test` always sets — under the
/// `Roboto` family; the golden harness points default text at it. Degrades
/// gracefully (text falls back to boxes, tests still run) if the SDK layout
/// ever changes.
Future<void> _loadRobotoFallback() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return;

  final loader = FontLoader('Roboto');
  var added = false;
  for (final name in const [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
    'roboto-black.ttf',
    'roboto-italic.ttf',
  ]) {
    final file = File('${dir.path}/$name');
    if (file.existsSync()) {
      loader.addFont(
        file.readAsBytes().then((bytes) => ByteData.view(bytes.buffer)),
      );
      added = true;
    }
  }
  if (added) await loader.load();
}

/// Strips the `packages/<pkg>/` prefix the manifest uses for package-supplied
/// fonts so the family registers under the name widgets actually reference.
String _familyOf(String declared) =>
    declared.startsWith('packages/') ? declared.split('/').last : declared;
