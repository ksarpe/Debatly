import 'package:debatly/data/models/vote_history_entry.dart';
import 'package:debatly/data/repositories/question_repository.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:debatly/features/questions/screens/history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/localized_test_app.dart';

/// The PRO voting record. Release guarantees:
///   * free users hit the PRO upsell, never the data;
///   * premium sees each voted question with its community split and own side;
///   * error and empty states are handled (with a working retry).
void main() {
  VoteHistoryEntry entry({
    String id = 'q-1',
    String text = 'Czy kara śmierci powinna istnieć?',
    int yes = 7,
    int no = 3,
    int? myChoice = 1,
  }) => VoteHistoryEntry.fromJson({
    'question_id': id,
    'category': 'Ethics',
    'question_text': text,
    'voted_at': '2026-07-10T18:42:07+00:00',
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

  testWidgets('a free user gets the PRO upsell and no history data', (
    tester,
  ) async {
    final repo = await pumpHistory(tester, premium: false, entries: [entry()]);

    expect(find.text('Historia to funkcja PRO'), findsOneWidget);
    expect(find.text('Przejdź na PRO'), findsOneWidget);
    // The gate must short-circuit BEFORE any data renders or is even fetched.
    expect(find.text('Czy kara śmierci powinna istnieć?'), findsNothing);
    expect(repo.fetchCalls, 0, reason: 'free users must not fetch history');
  });

  testWidgets(
    'premium sees the voted question, the split and a check on their side',
    (tester) async {
      await pumpHistory(tester, premium: true, entries: [entry()]);

      expect(find.text('Czy kara śmierci powinna istnieć?'), findsOneWidget);
      // 7 yes / 3 no → 70% / 30%, labeled TAK / NIE.
      expect(find.text('70%'), findsOneWidget);
      expect(find.text('30%'), findsOneWidget);
      expect(find.text('TAK'), findsOneWidget);
      expect(find.text('NIE'), findsOneWidget);
      // Voted yes → exactly one "my side" check.
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      // The row's date renders in the short PL format.
      expect(find.text('10 lip 2026'), findsOneWidget);
      // No upsell for premium.
      expect(find.text('Historia to funkcja PRO'), findsNothing);
    },
  );

  testWidgets('an entry nobody voted on collapses to the quiet no-votes line', (
    tester,
  ) async {
    await pumpHistory(
      tester,
      premium: true,
      entries: [entry(yes: 0, no: 0, myChoice: null)],
    );

    expect(find.text('Brak głosów'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('premium with no votes yet gets the empty state', (tester) async {
    await pumpHistory(tester, premium: true);

    expect(find.text('Brak historii'), findsOneWidget);
  });

  testWidgets(
    'a long history grows a search field that filters accent-insensitively',
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

      // The clear button restores the full list.
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Czy kara śmierci powinna istnieć?'), findsOneWidget);
      expect(find.text('Czy pieniądze dają szczęście?'), findsOneWidget);
    },
  );

  testWidgets('a short history stays search-free', (tester) async {
    await pumpHistory(tester, premium: true, entries: [entry()]);

    expect(find.byType(TextField), findsNothing);
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
