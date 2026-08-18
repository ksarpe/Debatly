import 'package:debatly/data/models/conformity_stats.dart';
import 'package:debatly/data/repositories/question_repository.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:debatly/features/questions/widgets/conformity_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/localized_test_app.dart';

/// The conformity-axis panel. Release guarantees:
///   * the top-bar icon opens the slide-down panel with the fetched stats:
///     percentage line, the current tier lit on the axis, and the exact
///     next-tier progress card;
///   * a user with no decided votes gets the empty-state copy, never a marker;
///   * a failed fetch degrades to the load-error line;
///   * tapping the barrier closes the panel (never a trap).
void main() {
  Future<void> pumpPanelOpener(
    WidgetTester tester, {
    ConformityStats? stats,
    bool fail = false,
  }) async {
    final container = ProviderContainer(
      // Riverpod auto-retries failed providers with backoff; disable it so the
      // error state is deterministic.
      retry: (retryCount, error) => null,
      overrides: [
        questionRepositoryProvider.overrideWithValue(
          _ConformityRepo(stats: stats, fail: fail),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const LocalizedTestApp(
          home: Scaffold(body: Center(child: ConformityAxisButton())),
        ),
      ),
    );
    await tester.tap(find.byType(ConformityAxisButton));
    await tester.pumpAndSettle();
  }

  testWidgets('the icon opens the panel with axis, tier and progress card', (
    tester,
  ) async {
    // 15/44 decided ≈ 34% with the majority → Buntownik.
    await pumpPanelOpener(
      tester,
      stats: const ConformityStats(
        totalVotes: 47,
        majorityVotes: 15,
        minorityVotes: 29,
      ),
    );

    expect(find.text('OŚ ZGODNOŚCI'), findsOneWidget);
    expect(find.text('34% z większością'), findsOneWidget);
    // The active tier appears twice: the badge over the axis + its label row.
    expect(find.text('BUNTOWNIK'), findsNWidgets(2));
    // Neighbouring tiers only once, in the label row.
    expect(find.text('NIEZALEŻNY'), findsOneWidget);
    expect(find.text('GŁOS TŁUMU'), findsOneWidget);
    // The next-tier card: 5 more majority votes lift 34% over the 40% bound.
    expect(find.text('Do stopnia «Niezależny»'), findsOneWidget);
    expect(find.text('5 głosów z większością'), findsOneWidget);
    expect(find.text('+6%'), findsOneWidget);
  });

  testWidgets('no decided votes → the empty state, no marker or progress', (
    tester,
  ) async {
    await pumpPanelOpener(tester, stats: ConformityStats.empty);

    expect(
      find.text(
        'Zagłosuj na kilka pytań, a zobaczysz, po której stronie '
        'zwykle jesteś.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('%'), findsNothing);
    expect(find.textContaining('Do stopnia'), findsNothing);
  });

  testWidgets('a failed fetch shows the load-error line', (tester) async {
    await pumpPanelOpener(tester, fail: true);

    expect(
      find.text('Nie udało się załadować osi — spróbuj za chwilę.'),
      findsOneWidget,
    );
  });

  testWidgets('tapping the barrier dismisses the panel', (tester) async {
    await pumpPanelOpener(
      tester,
      stats: const ConformityStats(
        totalVotes: 10,
        majorityVotes: 7,
        minorityVotes: 3,
      ),
    );
    expect(find.byType(ConformityPanel), findsOneWidget);

    // The panel hugs the top third — the bottom of the screen is barrier.
    await tester.tapAt(
      tester.getBottomLeft(find.byType(LocalizedTestApp)) -
          const Offset(-20, 20),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ConformityPanel), findsNothing);
  });
}

/// Mock repo with a canned (or failing) conformity aggregate and no simulated
/// latency, so the panel resolves within a single pumpAndSettle.
class _ConformityRepo extends MockQuestionRepository {
  _ConformityRepo({this.stats, this.fail = false});

  final ConformityStats? stats;
  final bool fail;

  @override
  Future<ConformityStats> fetchConformityStats() async {
    if (fail) throw Exception('boom');
    return stats ?? ConformityStats.empty;
  }
}
