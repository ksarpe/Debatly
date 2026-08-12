import 'package:debatly/data/models/question.dart';
import 'package:debatly/data/repositories/question_repository.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:debatly/features/settings/screens/favorites_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/localized_test_app.dart';

/// The favorites screen backs the PRO "readable forever" promise. Release
/// guarantees:
///   * saved questions render with their full text (nothing locked here);
///   * removing a star drops the card instantly (optimistic, no refetch);
///   * an empty list and a failed fetch both fall back to the nudge, never a
///     blocking error.
void main() {
  Question q(String id, String text) =>
      Question(id: id, category: 'Ethics', questionText: text);

  Future<_FavoritesRepo> pumpFavorites(
    WidgetTester tester, {
    required List<Question> favorites,
    bool failFetch = false,
  }) async {
    final repo = _FavoritesRepo(favorites: favorites, failFetch: failFetch);
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        sessionProvider.overrideWith(_FakeSession.new),
        questionRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const LocalizedTestApp(home: FavoritesScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('saved questions render as readable cards', (tester) async {
    await pumpFavorites(
      tester,
      favorites: [
        q('q1', 'Czy pieniądze dają szczęście?'),
        q('q2', 'Czy sztuka musi być piękna?'),
      ],
    );

    expect(find.text('Ulubione'), findsOneWidget);
    expect(find.text('Czy pieniądze dają szczęście?'), findsOneWidget);
    expect(find.text('Czy sztuka musi być piękna?'), findsOneWidget);
    // One removal star per card.
    expect(find.byIcon(Icons.star_rounded), findsNWidgets(2));
  });

  testWidgets('tapping the star removes the card instantly', (tester) async {
    final repo = await pumpFavorites(
      tester,
      favorites: [
        q('q1', 'Czy pieniądze dają szczęście?'),
        q('q2', 'Czy sztuka musi być piękna?'),
      ],
    );

    final fetchesBeforeRemoval = repo.fetchQuestionsCalls;

    await tester.tap(find.byIcon(Icons.star_rounded).first);
    await tester.pumpAndSettle();

    // The card is gone without a refetch (live membership), the other stays.
    expect(repo.toggleCalls, ['q1']);
    expect(find.text('Czy pieniądze dają szczęście?'), findsNothing);
    expect(find.text('Czy sztuka musi być piękna?'), findsOneWidget);
    expect(
      repo.fetchQuestionsCalls,
      fetchesBeforeRemoval,
      reason: 'removal must not re-hit the server for the list',
    );
  });

  testWidgets('removing the last favorite lands on the empty nudge', (
    tester,
  ) async {
    await pumpFavorites(
      tester,
      favorites: [q('q1', 'Czy pieniądze dają szczęście?')],
    );

    await tester.tap(find.byIcon(Icons.star_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Brak ulubionych'), findsOneWidget);
  });

  testWidgets('a long favorites list grows a search field that filters cards', (
    tester,
  ) async {
    await pumpFavorites(
      tester,
      favorites: [
        q('q1', 'Czy pieniądze dają szczęście?'),
        q('q2', 'Czy sztuka musi być piękna?'),
        q('q3', 'Czy praca zdalna jest lepsza?'),
        q('q4', 'Czy warto studiować?'),
        q('q5', 'Czy kara śmierci powinna istnieć?'),
        q('q6', 'Czy żołnierz może odmówić rozkazu?'),
      ],
    );

    expect(find.byType(TextField), findsOneWidget);

    // Accent-insensitive: "szczescie" finds "szczęście".
    await tester.enterText(find.byType(TextField), 'szczescie');
    await tester.pumpAndSettle();
    expect(find.text('Czy pieniądze dają szczęście?'), findsOneWidget);
    expect(find.text('Czy sztuka musi być piękna?'), findsNothing);

    // No match → the no-results state, not an empty hole.
    await tester.enterText(find.byType(TextField), 'xyz nie ma');
    await tester.pumpAndSettle();
    expect(find.text('Brak wyników'), findsOneWidget);
  });

  testWidgets('a short favorites list stays search-free', (tester) async {
    await pumpFavorites(
      tester,
      favorites: [q('q1', 'Czy pieniądze dają szczęście?')],
    );

    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('removing a card while searching keeps the search field', (
    tester,
  ) async {
    await pumpFavorites(
      tester,
      favorites: [
        q('q1', 'Czy pieniądze dają szczęście?'),
        q('q2', 'Czy sztuka musi być piękna?'),
        q('q3', 'Czy praca zdalna jest lepsza?'),
        q('q4', 'Czy warto studiować?'),
        q('q5', 'Czy kara śmierci powinna istnieć?'),
        q('q6', 'Czy żołnierz może odmówić rozkazu?'),
      ],
    );

    await tester.enterText(find.byType(TextField), 'sztuka');
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.star_rounded));
    await tester.pumpAndSettle();

    // The card is gone, but the field (with its query) survives the removal.
    expect(find.text('Czy sztuka musi być piękna?'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Brak wyników'), findsOneWidget);
  });

  testWidgets('no favorites yet shows the nudge toward the home star', (
    tester,
  ) async {
    await pumpFavorites(tester, favorites: const []);

    expect(find.text('Brak ulubionych'), findsOneWidget);
  });

  testWidgets('a failed fetch degrades to the empty state, not a crash', (
    tester,
  ) async {
    await pumpFavorites(tester, favorites: const [], failFetch: true);

    expect(find.text('Brak ulubionych'), findsOneWidget);
  });
}

/// A signed-in session so the favorites providers resolve an identity.
class _FakeSession extends SessionNotifier {
  @override
  Future<SessionState> build() async =>
      const SessionState(userId: 'u1', isAnonymous: false);
}

/// Repo with a scripted favorites list; toggling always succeeds and reports
/// the question as no longer favorited (a removal).
class _FavoritesRepo extends MockQuestionRepository {
  _FavoritesRepo({required this.favorites, this.failFetch = false});

  final List<Question> favorites;
  final bool failFetch;
  final List<String> toggleCalls = [];
  int fetchQuestionsCalls = 0;

  @override
  Future<Set<String>> fetchFavoriteIds() async =>
      favorites.map((q) => q.id).toSet();

  @override
  Future<List<Question>> fetchFavoriteQuestions() async {
    fetchQuestionsCalls++;
    if (failFetch) throw Exception('offline');
    return favorites;
  }

  @override
  Future<bool> toggleFavorite(String questionId) async {
    toggleCalls.add(questionId);
    return false; // removed
  }
}
