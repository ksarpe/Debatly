import 'package:debatly/data/models/vote_history_entry.dart';
import 'package:debatly/data/repositories/question_repository.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/monetization/widgets/pro_paywall_screen.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:debatly/features/questions/screens/history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/localized_test_app.dart';

/// The voting record. Release guarantees:
///   * free users see only today's card(s) — older history sits behind the
///     locked panel, and tapping it opens the paywall;
///   * premium sees every voted question as a card with their side and the
///     community split, grouped under day headers;
///   * error and empty states are handled (with a working retry).
void main() {
  VoteHistoryEntry entry({
    String id = 'q-1',
    String text = 'Czy kara śmierci powinna istnieć?',
    int yes = 7,
    int no = 3,
    int? myChoice = 1,
    String votedAt = '2026-07-10T18:42:07+00:00',
  }) => VoteHistoryEntry.fromJson({
    'question_id': id,
    'category': 'Ethics',
    'question_text': text,
    'voted_at': votedAt,
    'yes_count': yes,
    'no_count': no,
    'my_choice': myChoice,
  });

  Future<_HistoryRepo> pumpHistory(
    WidgetTester tester, {
    required bool premium,
    List<VoteHistoryEntry> entries = const [],
    int failFirst = 0,
  }) async {
    final repo = _HistoryRepo(entries: entries, failFirst: failFirst);
    final container = ProviderContainer(
      // Riverpod 3 auto-retries failed providers with backoff; disable it so
      // the error state is deterministic and the retry BUTTON is what reloads.
      retry: (retryCount, error) => null,
      overrides: [
        isPremiumProvider.overrideWithValue(premium),
        questionRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const LocalizedTestApp(home: HistoryScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('a free user sees today only, older history stays locked', (
    tester,
  ) async {
    final repo = await pumpHistory(
      tester,
      premium: false,
      entries: [
        entry(
          id: 'q-today',
          text: 'Czy pytanie dnia jest darmowe?',
          votedAt: DateTime.now().toUtc().toIso8601String(),
        ),
        entry(id: 'q-old', text: 'Czy kara śmierci powinna istnieć?'),
      ],
    );

    // No auto-paywall on open — the free view has content of its own now.
    expect(find.byType(ProPaywallScreen), findsNothing);
    expect(repo.fetchCalls, 1);

    // Today's vote renders as a card; the older one hides behind the lock.
    expect(find.text('Czy pytanie dnia jest darmowe?'), findsOneWidget);
    expect(find.text('Czy kara śmierci powinna istnieć?'), findsNothing);
    expect(find.text('Odblokuj pełną historię'), findsOneWidget);
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);

    // Tapping the locked panel opens the paywall…
    await tester.tap(find.text('Odblokuj pełną historię'));
    await tester.pumpAndSettle();
    expect(find.byType(ProPaywallScreen), findsOneWidget);

    // …and dismissing it lands back on the history, never out of the screen.
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(ProPaywallScreen), findsNothing);
    expect(find.text('Czy pytanie dnia jest darmowe?'), findsOneWidget);
  });

  testWidgets(
    'premium sees the card: own side, corner split and the day header',
    (tester) async {
      await pumpHistory(tester, premium: true, entries: [entry()]);

      expect(find.text('Czy kara śmierci powinna istnieć?'), findsOneWidget);
      // Voted yes → "TY: TAK" chip in the card.
      expect(find.text('TY: TAK'), findsOneWidget);
      // 7 yes / 3 no → corner split "70 vs 30", the user's side first.
      expect(find.text('70'), findsOneWidget);
      expect(find.text('vs'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);
      // Grouped under its local-day header.
      expect(find.textContaining('10 LIP'), findsOneWidget);
      // The lifetime answered count (from the conformity stats mock).
      expect(find.text('Odpowiedziano na 47 pytań'), findsOneWidget);
      // No lock and no paywall for premium.
      expect(find.text('Odblokuj pełną historię'), findsNothing);
      expect(find.byIcon(Icons.lock_rounded), findsNothing);
    },
  );

  testWidgets('a NIE vote leads the corner split with its own side', (
    tester,
  ) async {
    await pumpHistory(
      tester,
      premium: true,
      entries: [entry(yes: 7, no: 3, myChoice: 2)],
    );

    expect(find.text('TY: NIE'), findsOneWidget);
    // The user's side (30%) leads, the other side follows.
    expect(find.text('30'), findsOneWidget);
    expect(find.text('70'), findsOneWidget);
  });

  testWidgets('an entry nobody voted on collapses to the quiet no-votes note', (
    tester,
  ) async {
    await pumpHistory(
      tester,
      premium: true,
      entries: [entry(yes: 0, no: 0, myChoice: null)],
    );

    expect(find.text('Brak głosów'), findsOneWidget);
    expect(find.text('vs'), findsNothing);
  });

  testWidgets('premium with no votes yet gets the empty state', (tester) async {
    await pumpHistory(tester, premium: true);

    expect(find.text('Brak historii'), findsOneWidget);
  });

  testWidgets(
    'a long history grows a magnifier that expands into the filter field',
    (tester) async {
      await pumpHistory(
        tester,
        premium: true,
        entries: [
          entry(id: 'q-1', text: 'Czy kara śmierci powinna istnieć?'),
          entry(id: 'q-2', text: 'Czy pieniądze dają szczęście?'),
          entry(id: 'q-3', text: 'Czy sztuka musi być piękna?'),
          entry(id: 'q-4', text: 'Czy praca zdalna jest lepsza?'),
          entry(id: 'q-5', text: 'Czy warto studiować?'),
          entry(id: 'q-6', text: 'Czy żołnierz może odmówić rozkazu?'),
        ],
      );

      // Collapsed: a bare magnifier, no text field yet.
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);

      // Plain-letter query finds the diacritic text: "smierc" → "śmierci".
      await tester.enterText(find.byType(TextField), 'smierc');
      await tester.pumpAndSettle();
      expect(find.text('Czy kara śmierci powinna istnieć?'), findsOneWidget);
      expect(find.text('Czy pieniądze dają szczęście?'), findsNothing);

      // A query nothing matches lands on the no-results state.
      await tester.enterText(find.byType(TextField), 'xyz nie ma');
      await tester.pumpAndSettle();
      expect(find.text('Brak wyników'), findsOneWidget);

      // First X tap clears the text and restores the full list…
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Czy kara śmierci powinna istnieć?'), findsOneWidget);
      expect(find.text('Czy pieniądze dają szczęście?'), findsOneWidget);

      // …the second collapses the field back to the count row.
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Czy kara śmierci powinna istnieć?'), findsOneWidget);
    },
  );

  testWidgets('a long history pages: 30 cards, then "load more" reveals rest', (
    tester,
  ) async {
    await pumpHistory(
      tester,
      premium: true,
      entries: [
        for (var i = 1; i <= 34; i++)
          entry(id: 'q-$i', text: 'Czy pytanie numer $i jest ciekawe?'),
      ],
    );

    // The first page builds, the 31st card doesn't exist yet.
    expect(find.text('Czy pytanie numer 30 jest ciekawe?'), findsOneWidget);
    expect(find.text('Czy pytanie numer 31 jest ciekawe?'), findsNothing);

    // The pill names the exact hidden count; tapping reveals the rest.
    final loadMore = find.text('Załaduj jeszcze 4');
    expect(loadMore, findsOneWidget);
    await tester.ensureVisible(loadMore);
    await tester.tap(loadMore);
    await tester.pumpAndSettle();

    expect(find.text('Czy pytanie numer 34 jest ciekawe?'), findsOneWidget);
    expect(find.textContaining('Załaduj jeszcze'), findsNothing);
  });

  testWidgets('a new search query restarts paging from the first page', (
    tester,
  ) async {
    await pumpHistory(
      tester,
      premium: true,
      entries: [
        for (var i = 1; i <= 40; i++)
          entry(id: 'q-$i', text: 'Czy pytanie numer $i jest ciekawe?'),
      ],
    );

    // Reveal everything…
    final loadMore = find.text('Załaduj jeszcze 10');
    await tester.ensureVisible(loadMore);
    await tester.tap(loadMore);
    await tester.pumpAndSettle();
    expect(find.textContaining('Załaduj jeszcze'), findsNothing);

    // …then type a query. Scroll all the way back first — near-but-not-at the
    // top the floating close button still hovers over the magnifier's corner.
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, 5000),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ciekawe');
    await tester.pumpAndSettle();

    // All 40 match the query, so paging is back at page one: 30 cards + pill.
    expect(find.text('Czy pytanie numer 31 jest ciekawe?'), findsNothing);
    expect(find.text('Załaduj jeszcze 10'), findsOneWidget);
  });

  testWidgets('a short history stays search-free', (tester) async {
    await pumpHistory(tester, premium: true, entries: [entry()]);

    expect(find.byType(TextField), findsNothing);
    expect(find.byIcon(Icons.search_rounded), findsNothing);
  });

  testWidgets('a failed fetch offers retry, and retry actually reloads', (
    tester,
  ) async {
    final repo = await pumpHistory(
      tester,
      premium: true,
      entries: [entry()],
      failFirst: 1,
    );

    expect(find.text('Nie udało się wczytać historii.'), findsOneWidget);

    await tester.tap(find.text('Spróbuj ponownie'));
    await tester.pumpAndSettle();

    expect(repo.fetchCalls, 2);
    expect(find.text('Czy kara śmierci powinna istnieć?'), findsOneWidget);
  });
}

/// Repo with a scripted history: optionally fails the first [failFirst]
/// fetches (to drive the error + retry path), then serves [entries].
class _HistoryRepo extends MockQuestionRepository {
  _HistoryRepo({required this.entries, this.failFirst = 0});

  final List<VoteHistoryEntry> entries;
  final int failFirst;
  int fetchCalls = 0;

  @override
  Future<List<VoteHistoryEntry>> fetchVoteHistory() async {
    fetchCalls++;
    if (fetchCalls <= failFirst) throw Exception('offline');
    return entries;
  }
}
