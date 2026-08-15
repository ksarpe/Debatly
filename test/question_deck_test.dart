import 'package:debatly/data/models/question.dart';
import 'package:debatly/data/repositories/question_repository.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Deck composition under the hard paywall: the deck is the daily plus the
/// whole catalog, in a stable seeded order that survives a refetch, with
/// unseen questions surfaced before the seen archive — plus the gate on the
/// catalog fetch itself, which only an entitled session may trigger.
void main() {
  Question q(String id) => Question(
    id: id,
    category: id.toUpperCase(),
    questionText: 'Question $id?',
  );

  Future<ProviderContainer> deckContainer({
    required Question daily,
    required List<Question> pool,
    bool premium = true,
  }) async {
    final container = ProviderContainer(
      overrides: [
        questionsProvider.overrideWith((ref) async => pool),
        todaysDailyQuestionProvider.overrideWith((ref) async => daily),
        isPremiumProvider.overrideWithValue(premium),
        deckShuffleSeedProvider.overrideWithValue(1),
      ],
    );
    addTearDown(container.dispose);
    await container.read(questionsProvider.future);
    await container.read(todaysDailyQuestionProvider.future);
    return container;
  }

  test('premium deck is the daily plus the whole catalog', () async {
    final daily = q('daily');
    final pool = [daily, q('a'), q('b'), q('c')];

    final container = await deckContainer(
      daily: daily,
      pool: pool,
      premium: true,
    );
    final deck = container.read(questionDeckProvider);

    expect(deck, hasLength(4));
    expect(deck.first.id, 'daily');
    expect(deck.map((e) => e.id).toSet(), {'daily', 'a', 'b', 'c'});
  });

  test(
    'premium deck order is stable across a pool refetch (seeded shuffle)',
    () async {
      final daily = q('daily');
      final pool = [daily, for (var i = 0; i < 8; i++) q('q$i')];

      final container = await deckContainer(
        daily: daily,
        pool: pool,
        premium: true,
      );
      final firstOrder = container
          .read(questionDeckProvider)
          .map((e) => e.id)
          .toList();

      container.invalidate(questionsProvider);
      await container.read(questionsProvider.future);

      final secondOrder = container
          .read(questionDeckProvider)
          .map((e) => e.id)
          .toList();
      expect(secondOrder, firstOrder);
    },
  );

  test('premium deck puts UNSEEN questions before the seen archive', () async {
    final daily = q('daily');
    Question seen(String id) =>
        Question(id: id, category: id, questionText: 'Q $id?', seen: true);

    // Catalog mixes seen and unseen; the deck must front-load the unseen ones.
    final pool = [daily, seen('s1'), q('u1'), seen('s2'), q('u2'), q('u3')];

    final container = await deckContainer(
      daily: daily,
      pool: pool,
      premium: true,
    );
    final deck = container.read(questionDeckProvider).map((e) => e.id).toList();

    expect(deck.first, 'daily');
    // The three unseen questions come first (in some shuffled order), then the
    // two seen ones — never a seen question ahead of an unseen one.
    expect(deck.sublist(1, 4).toSet(), {'u1', 'u2', 'u3'});
    expect(deck.sublist(4).toSet(), {'s1', 's2'});
  });

  test('the current index survives a pool refetch (premium)', () async {
    final daily = q('daily');
    final pool = [daily, for (var i = 0; i < 8; i++) q('q$i')];

    final container = await deckContainer(
      daily: daily,
      pool: pool,
      premium: true,
    );

    final index = container.read(questionIndexProvider.notifier);
    index.next();
    index.next();
    expect(container.read(questionIndexProvider), 2);

    container.invalidate(questionsProvider);
    await container.read(questionsProvider.future);

    expect(container.read(questionIndexProvider), 2);
  });

  /// Who is even allowed to load the catalog. The server withholds it from a
  /// non-entitled user anyway (RLS), but the client must not ask: a walled
  /// user pulling ~1000 rows (and jsonEncode-ing them into the cache) on every
  /// launch is bandwidth and battery spent on content they cannot see.
  group('catalog gating', () {
    ProviderContainer poolContainer(
      _CountingRepo repo,
      SessionNotifier session,
    ) {
      final container = ProviderContainer(
        overrides: [
          questionRepositoryProvider.overrideWithValue(repo),
          sessionProvider.overrideWith(() => session),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('a non-premium session never asks for the catalog', () async {
      final repo = _CountingRepo();
      final container = poolContainer(repo, FakeSession(guestSession()));
      await container.read(sessionProvider.future);

      expect(await container.read(questionsProvider.future), isEmpty);
      expect(repo.fetches, 0, reason: 'nothing is fetched behind the wall');
    });

    test('an entitled session loads it exactly once', () async {
      final repo = _CountingRepo();
      final container = poolContainer(
        repo,
        FakeSession(guestSession(isPremium: true)),
      );
      await container.read(sessionProvider.future);

      expect(await container.read(questionsProvider.future), hasLength(2));
      expect(repo.fetches, 1);
    });

    test('buying PRO loads the catalog without a relaunch', () async {
      // The moment the entitlement flips, the home gate swaps the wall for the
      // feed — the pool has to follow it, or the buyer lands on an empty deck
      // and has to kill the app to see what they paid for.
      final repo = _CountingRepo();
      final session = _MutableSession(guestSession());
      final container = poolContainer(repo, session);
      await container.read(sessionProvider.future);
      expect(await container.read(questionsProvider.future), isEmpty);

      session.emit(guestSession(isPremium: true));

      expect(await container.read(questionsProvider.future), hasLength(2));
      expect(repo.fetches, 1);
    });
  });
}

/// Counts how often the catalog was actually fetched.
class _CountingRepo extends MockQuestionRepository {
  int fetches = 0;

  @override
  Future<List<Question>> fetchQuestions() async {
    fetches++;
    return [
      Question(id: 'a', category: 'A', questionText: 'Q a?'),
      Question(id: 'b', category: 'B', questionText: 'Q b?'),
    ];
  }
}

/// A [SessionNotifier] whose state the test drives directly.
class _MutableSession extends SessionNotifier {
  _MutableSession(this._initial);

  final SessionState _initial;

  @override
  Future<SessionState> build() async => _initial;

  void emit(SessionState next) => state = AsyncValue.data(next);
}
