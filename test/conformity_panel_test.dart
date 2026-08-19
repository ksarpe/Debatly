import 'package:debatly/data/models/conformity_stats.dart';
import 'package:debatly/data/models/debate_profile.dart';
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

  testWidgets('the icon opens the panel with axis, rung and progress card', (
    tester,
  ) async {
    // 15/44 decided ≈ 34% with the majority → "Częściej pod prąd". The rungs
    // are positional PHRASES (the 2×2 grid keeps the nouns), so the axis can
    // never collide with a profile-type name again.
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
    // The active rung appears twice: the badge over the axis + its label row.
    expect(find.text('CZĘŚCIEJ POD PRĄD'), findsNWidgets(2));
    // Neighbouring rungs only once, in the label row.
    expect(find.text('PÓŁ NA PÓŁ'), findsOneWidget);
    expect(find.text('ZAWSZE Z TŁUMEM'), findsOneWidget);
    // The old noun rungs are gone — SAMOTNY WILK is a 2×2 type, not a rung.
    expect(find.textContaining('SAMOTNY WILK'), findsNothing);
    expect(find.text('BUNTOWNIK'), findsNothing);
    // The next-tier card: 5 more majority votes lift 34% over the 40% bound.
    expect(find.text('Do stopnia «Pół na pół»'), findsOneWidget);
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
/// latency, so the panel resolves within a single pumpAndSettle. The debate
/// profile is pinned LOCKED so these tests stay about the axis — the profile
/// section has its own test file (debate_profile_section_test.dart).
class _ConformityRepo extends MockQuestionRepository {
  _ConformityRepo({this.stats, this.fail = false});

  final ConformityStats? stats;
  final bool fail;

  @override
  Future<ConformityStats> fetchConformityStats() async {
    if (fail) throw Exception('boom');
    return stats ?? ConformityStats.empty;
  }

  @override
  Future<DebateProfile> fetchDebateProfile() async => DebateProfile.empty;
}
