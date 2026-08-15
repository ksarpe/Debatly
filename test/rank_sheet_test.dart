import 'package:debatly/data/models/rank.dart';
import 'package:debatly/data/models/user_stats.dart';
import 'package:debatly/data/repositories/question_repository.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:debatly/features/questions/widgets/rank_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/localized_test_app.dart';

/// The rank sheet: current rank + progress + the full ladder. Release
/// guarantees:
///   * the current rank is derived from the streak against the LADDER data
///     (not trusted from a stale client field);
///   * reached ranks show as unlocked, future ones as locked;
///   * the top rank swaps the progress bar for the respect line;
///   * the grace warning appears exactly when the server flags it.
void main() {
  const ladder = [
    Rank(tier: 0, minStreak: 0, namePl: 'Nowicjusz', nameEn: 'Novice'),
    Rank(tier: 1, minStreak: 2, namePl: 'Adept', nameEn: 'Adept'),
    Rank(tier: 2, minStreak: 4, namePl: 'Weteran', nameEn: 'Veteran'),
    Rank(tier: 3, minStreak: 7, namePl: 'Legenda', nameEn: 'Legend'),
  ];

  UserStats stats({int streak = 5, int longest = 9, int? graceDaysLeft}) =>
      UserStats(
        currentStreak: streak,
        longestStreak: longest,
        rankTier: 0,
        rankName: '',
        graceDaysLeft: graceDaysLeft,
      );

  Future<void> pumpSheet(
    WidgetTester tester, {
    required UserStats stats,
  }) async {
    final container = ProviderContainer(
      overrides: [
        sessionProvider.overrideWith(_FakeSession.new),
        questionRepositoryProvider.overrideWithValue(
          _RankRepo(ranks: ladder, stats: stats),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LocalizedTestApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showRankSheet(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'streak 5 on a 0/2/4/7 ladder: current rank is the highest reached, '
    'progress points at the next one, reached ranks unlocked',
    (tester) async {
      await pumpSheet(tester, stats: stats(streak: 5));

      expect(find.text('TWOJA RANGA'), findsOneWidget);
      // Weteran (minStreak 4) is the highest tier a 5-day streak reaches:
      // once in the header, once as its ladder row.
      expect(find.text('Weteran'), findsNWidgets(2));
      // The streak itself, and the longest-streak secondary stat.
      expect(find.text('Seria: 5 dni'), findsOneWidget);
      expect(find.textContaining('Najdłuższa seria: 9 dni'), findsOneWidget);
      // Progress towards the next rank (minStreak 7): 2 days to go — and the
      // line must NOT name it, the promotion stays a surprise.
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Jeszcze 2 dni do kolejnej rangi'), findsOneWidget);
      expect(find.textContaining('Legenda'), findsOneWidget);
      // The full ladder renders with its thresholds…
      expect(find.text('od 0'), findsOneWidget);
      expect(find.text('od 2'), findsOneWidget);
      expect(find.text('od 4'), findsOneWidget);
      expect(find.text('od 7'), findsOneWidget);
      // …tiers 0-2 reached (check), tier 3 still locked.
      expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(3));
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    },
  );

  testWidgets('every locked rank is blurred — including the very next one', (
    tester,
  ) async {
    await pumpSheet(tester, stats: stats(streak: 5));

    // The single locked row (Legenda) has both its icon and its name blurred,
    // so the coming promotion stays a surprise…
    expect(
      find.ancestor(
        of: find.text('Legenda'),
        matching: find.byType(ImageFiltered),
      ),
      findsOneWidget,
    );
    expect(find.byType(ImageFiltered), findsNWidgets(2));
    // …while the ranks already earned stay readable.
    expect(
      find.ancestor(
        of: find.text('Adept'),
        matching: find.byType(ImageFiltered),
      ),
      findsNothing,
    );
  });

  testWidgets('at the top rank the progress bar yields to the respect line', (
    tester,
  ) async {
    await pumpSheet(tester, stats: stats(streak: 10));

    expect(find.text('Legenda'), findsNWidgets(2));
    expect(find.textContaining('szacun'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
    // Nothing left to hide once the whole ladder is unlocked.
    expect(find.byType(ImageFiltered), findsNothing);
  });

  testWidgets('a server-flagged grace period surfaces the warning banner', (
    tester,
  ) async {
    await pumpSheet(tester, stats: stats(streak: 5, graceDaysLeft: 1));

    expect(find.textContaining('potem ranga spadnie'), findsOneWidget);
  });

  testWidgets('no grace flag, no warning', (tester) async {
    await pumpSheet(tester, stats: stats(streak: 5));

    expect(find.textContaining('potem ranga spadnie'), findsNothing);
  });
}

/// A signed-in session so [userStatsProvider] performs its sync.
class _FakeSession extends SessionNotifier {
  @override
  Future<SessionState> build() async =>
      const SessionState(userId: 'u1', isAnonymous: false);
}

/// Repo serving a fixed ladder + stats snapshot (the server's view).
class _RankRepo extends MockQuestionRepository {
  _RankRepo({required this.ranks, required this.stats});

  final List<Rank> ranks;
  final UserStats stats;

  @override
  Future<List<Rank>> fetchRanks() async => ranks;

  @override
  Future<UserStats?> syncUserState() async => stats;
}
