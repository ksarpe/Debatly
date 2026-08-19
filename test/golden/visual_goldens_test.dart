import 'dart:io';

import 'package:debatly/core/theme/app_theme.dart';
import 'package:debatly/data/models/conformity_stats.dart';
import 'package:debatly/data/models/debate_profile.dart';
import 'package:debatly/data/models/vote_result.dart';
import 'package:debatly/data/repositories/question_repository.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:debatly/features/questions/widgets/conformity_panel.dart';
import 'package:debatly/features/questions/widgets/rank_share_card.dart';
import 'package:debatly/features/questions/widgets/styled_question_text.dart';
import 'package:debatly/features/questions/widgets/vote_visuals.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/localized_test_app.dart';

/// Golden (pixel) coverage for the app's highest-value visual widgets — the ones
/// whose whole point is how they look, so a string/`takeException` test can't
/// catch a regression:
///   * [StyledQuestionText] — the signature white-fill / black-stroke headline,
///     including the length-driven font shrink;
///   * [RankShareCard] — the share-ready rank-promotion poster;
///   * [VoteResultsRow] — the daily TAK/NIE community split bars;
///   * [ConformityPanel]'s axis — five multi-word rung names sharing one row,
///     the case where "it fits" and "it is readable" are not the same thing.
///
/// Everything is pinned for determinism: locale fixed to Polish via
/// [LocalizedTestApp], the dark [AppTheme] explicitly applied, fixed fake data
/// (no providers, no network), real fonts loaded by `flutter_test_config.dart`,
/// and a fixed surface + 1× pixel ratio. Regenerate after an intentional visual
/// change with `flutter test test/golden --update-goldens` and commit the PNGs.
///
/// Determinism stops at the host, though: text rasterisation (hinting,
/// subpixel layout, shaping) differs per operating system, so the very same
/// widget legitimately paints different pixels on Windows and on Linux. The
/// committed PNGs are the Windows dev machine's, so the *pixel comparison*
/// only runs there — see [_comparesPixels]. Everywhere else (Linux CI) the
/// scenes are still pumped and asserted, just not diffed against a bitmap.
void main() {
  // A repaint boundary wrapping each scene so the golden captures exactly this
  // frame — including drop shadows — instead of a child's tight bounds.
  const sceneKey = ValueKey('golden_scene');

  Future<void> pumpScene(
    WidgetTester tester, {
    required Widget child,
    required Size surface,
  }) async {
    // 1× so golden pixels equal logical pixels (smaller, stable files); the
    // fixed surface keeps layout independent of the host's screen.
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      LocalizedTestApp(
        home: Theme(
          data: AppTheme.dark,
          child: Scaffold(
            backgroundColor: AppColors.dark.background,
            // Point default-family text (everything not in Anton) at the real
            // Roboto loaded by flutter_test_config; sits below Scaffold's own
            // Material/DefaultTextStyle so it actually wins. In production these
            // styles inherit the platform default (Roboto on Android), so this
            // mirrors the shipping look rather than altering it.
            body: DefaultTextStyle.merge(
              style: const TextStyle(fontFamily: 'Roboto'),
              child: Center(
                child: RepaintBoundary(key: sceneKey, child: child),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> expectGolden(WidgetTester tester, String name) async {
    // Off the golden host the scene has still been built, laid out and pumped
    // (so an overflow or a thrown exception fails the test as usual) — only the
    // bitmap diff, which would compare foreign rasterisation, is skipped.
    if (!_comparesPixels) return;
    await expectLater(
      find.byKey(sceneKey),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  group('StyledQuestionText', () {
    testWidgets('a short question renders at the full display size', (
      tester,
    ) async {
      await pumpScene(
        tester,
        surface: const Size(420, 320),
        child: Container(
          width: 360,
          color: AppColors.dark.background,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
          child: const StyledQuestionText('Czy zdrada myślami jest zdradą?'),
        ),
      );
      await expectGolden(tester, 'styled_question_text_short');
    });

    testWidgets('a long question shrinks to the minimum size and wraps', (
      tester,
    ) async {
      const long =
          'Czy państwo ma prawo zmuszać obywateli do szczepień w imię '
          'zdrowia publicznego, nawet wbrew ich woli i głęboko zakorzenionym '
          'przekonaniom?';
      await pumpScene(
        tester,
        surface: const Size(420, 520),
        child: Container(
          width: 360,
          color: AppColors.dark.background,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
          child: const StyledQuestionText(long),
        ),
      );
      await expectGolden(tester, 'styled_question_text_long');
    });
  });

  testWidgets('RankShareCard renders the promotion poster', (tester) async {
    await pumpScene(
      tester,
      surface: const Size(400, 720),
      child: const RankShareCard(
        rankName: 'Adwokat diabła',
        headline: 'Moja nowa ranga',
        streakLine: '14 dni z rzędu',
        tagline: 'Jedno przewrotne pytanie dziennie',
        iconKey: 'mask',
      ),
    );
    await expectGolden(tester, 'rank_share_card');
  });

  // A fixed 63/37 split keeps the bars and percentages deterministic.
  group('VoteResultsRow', () {
    testWidgets('the split with TAK as my side', (tester) async {
      await pumpScene(
        tester,
        surface: const Size(420, 200),
        child: Container(
          color: AppColors.dark.background,
          padding: const EdgeInsets.all(20),
          child: const VoteResultsRow(
            result: VoteResult(
              yesCount: 63,
              noCount: 37,
              myChoice: VoteResult.yes,
            ),
          ),
        ),
      );
      await expectGolden(tester, 'vote_result_bars_tak');
    });

    testWidgets('the split with NIE as my side', (tester) async {
      await pumpScene(
        tester,
        surface: const Size(420, 200),
        child: Container(
          color: AppColors.dark.background,
          padding: const EdgeInsets.all(20),
          child: const VoteResultsRow(
            result: VoteResult(
              yesCount: 63,
              noCount: 37,
              myChoice: VoteResult.no,
            ),
          ),
        ),
      );
      await expectGolden(tester, 'vote_result_bars_nie');
    });
  });

  // The conformity axis is the one place where five multi-word labels share a
  // single row, so it is also the one place where a layout that technically
  // fits can still be unreadable — the rung names once shrank to a ~4px smudge
  // here. The two hostile cases: the narrowest phone, and a large system font.
  group('ConformityPanel axis', () {
    Future<void> pumpPanel(
      WidgetTester tester, {
      required Size surface,
      double textScale = 1.0,
    }) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.binding.setSurfaceSize(surface);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = ProviderContainer(
        // The debate profile below the axis fails on purpose: the section then
        // renders nothing, keeping this golden about the axis alone (it has
        // its own tests). No retry, so the failure is immediate and stable.
        retry: (retryCount, error) => null,
        overrides: [questionRepositoryProvider.overrideWithValue(_AxisRepo())],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: LocalizedTestApp(
            home: Theme(
              data: AppTheme.dark,
              child: Scaffold(
                backgroundColor: AppColors.dark.background,
                body: const RepaintBoundary(
                  key: sceneKey,
                  child: ConformityPanel(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('every rung name stays whole on a 320dp screen', (
      tester,
    ) async {
      await pumpPanel(tester, surface: const Size(320, 260));
      expect(tester.takeException(), isNull);
      await expectGolden(tester, 'conformity_axis_narrow');
    });

    testWidgets('and at a 1.6x system font', (tester) async {
      await pumpPanel(tester, surface: const Size(360, 260), textScale: 1.6);
      expect(tester.takeException(), isNull);
      await expectGolden(tester, 'conformity_axis_large_font');
    });
  });
}

/// Whether this host is the one the committed PNGs were rasterised on.
///
/// Regenerate them with `flutter test test/golden --update-goldens` on
/// Windows; moving the golden host means flipping this check and
/// regenerating every PNG in one commit.
final _comparesPixels = Platform.isWindows;

/// 15 of 44 decided votes with the majority ≈ 34% → "Częściej pod prąd", the
/// middle-ish rung whose badge sits over the axis rather than clamped to an
/// edge.
class _AxisRepo extends MockQuestionRepository {
  @override
  Future<ConformityStats> fetchConformityStats() async => const ConformityStats(
    totalVotes: 47,
    majorityVotes: 15,
    minorityVotes: 29,
  );

  @override
  Future<DebateProfile> fetchDebateProfile() async =>
      throw Exception('no profile in this golden');
}
