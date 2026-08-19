import 'package:debatly/core/theme/app_theme.dart';
import 'package:debatly/data/models/vote_result.dart';
import 'package:debatly/features/questions/widgets/rank_share_card.dart';
import 'package:debatly/features/questions/widgets/styled_question_text.dart';
import 'package:debatly/features/questions/widgets/vote_visuals.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/localized_test_app.dart';

/// Golden (pixel) coverage for the app's highest-value visual widgets — the ones
/// whose whole point is how they look, so a string/`takeException` test can't
/// catch a regression:
///   * [StyledQuestionText] — the signature white-fill / black-stroke headline,
///     including the length-driven font shrink;
///   * [RankShareCard] — the share-ready rank-promotion poster;
///   * [VoteResultsRow] — the daily TAK/NIE community split bars.
///
/// Everything is pinned for determinism: locale fixed to Polish via
/// [LocalizedTestApp], the dark [AppTheme] explicitly applied, fixed fake data
/// (no providers, no network), real fonts loaded by `flutter_test_config.dart`,
/// and a fixed surface + 1× pixel ratio. Regenerate after an intentional visual
/// change with `flutter test test/golden --update-goldens` and commit the PNGs.
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

  Future<void> expectGolden(WidgetTester tester, String name) {
    return expectLater(
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
}
