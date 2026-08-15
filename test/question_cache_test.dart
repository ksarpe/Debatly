import 'package:debatly/data/models/question.dart';
import 'package:debatly/data/models/rank.dart';
import 'package:debatly/data/models/smaczek.dart';
import 'package:debatly/data/models/user_stats.dart';
import 'package:debatly/services/question_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The on-device cache must round-trip every content type, key by locale, tell
/// today's daily from a stale one, and wipe cleanly on a premium lapse.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late QuestionCache cache;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cache = QuestionCache(await SharedPreferences.getInstance());
  });

  Question q(String id, {bool locked = false, String? teaser}) => Question(
    id: id,
    category: 'CAT_$id',
    questionText: 'Question $id?',
    isLocked: locked,
    teaser: teaser,
  );

  test('catalog round-trips preserving locked/teaser fields', () async {
    final catalog = [q('a'), q('b', locked: true, teaser: 'Czy miliarderzy')];
    await cache.writeCatalog('pl', catalog);

    final read = cache.readCatalog('pl');
    expect(read, isNotNull);
    expect(read!.map((e) => e.id), ['a', 'b']);
    expect(read[1].isLocked, isTrue);
    expect(read[1].teaser, 'Czy miliarderzy');
  });

  test('catalog is keyed by locale', () async {
    await cache.writeCatalog('pl', [q('pl1')]);
    expect(cache.readCatalog('pl'), isNotNull);
    expect(cache.readCatalog('en'), isNull);
  });

  test('readCatalog returns null when nothing was cached', () {
    expect(cache.readCatalog('pl'), isNull);
  });

  test('daily: exact-date read matches only the same day', () async {
    await cache.writeDaily('pl', '2026-06-23', q('d'));

    expect(cache.readDaily('pl', '2026-06-23')?.id, 'd');
    // A different day must NOT come back through the exact path.
    expect(cache.readDaily('pl', '2026-06-24'), isNull);
  });

  test(
    'readLatestDaily returns the last cached daily regardless of date',
    () async {
      await cache.writeDaily('pl', '2026-06-23', q('d1'));
      final latest = cache.readLatestDaily('pl');
      expect(latest?.question.id, 'd1');
      expect(latest?.date, '2026-06-23');

      // Writing a newer day overwrites the single per-locale slot.
      await cache.writeDaily('pl', '2026-06-24', q('d2'));
      expect(cache.readLatestDaily('pl')?.question.id, 'd2');
    },
  );

  test('smaczki round-trip and key by locale + question id', () async {
    final smaczki = [
      const Smaczek(position: 1, isLocked: false, text: 'Hot take?'),
      const Smaczek(position: 2, isLocked: true),
    ];
    await cache.writeSmaczki('pl', 'q1', smaczki);

    final read = cache.readSmaczki('pl', 'q1');
    expect(read, hasLength(2));
    expect(read![0].text, 'Hot take?');
    expect(read[1].isLocked, isTrue);
    expect(read[1].text, isNull);

    // Different question id / locale → miss.
    expect(cache.readSmaczki('pl', 'q2'), isNull);
    expect(cache.readSmaczki('en', 'q1'), isNull);
  });

  test('favorites (ids + questions) round-trip', () async {
    await cache.writeFavoriteIds('pl', {'a', 'b'});
    expect(cache.readFavoriteIds('pl'), {'a', 'b'});

    await cache.writeFavoriteQuestions('pl', [q('a'), q('b')]);
    expect(cache.readFavoriteQuestions('pl')!.map((e) => e.id), ['a', 'b']);
  });

  test('stats round-trip preserving streak + credits', () async {
    const stats = UserStats(
      currentStreak: 5,
      longestStreak: 9,
      rankTier: 2,
      rankName: 'Podżegacz',
      nextRankStreak: 7,
    );
    await cache.writeStats(stats);

    final read = cache.readStats();
    expect(read?.currentStreak, 5);
    expect(read?.rankName, 'Podżegacz');
  });

  test('ranks round-trip', () async {
    await cache.writeRanks(kDefaultRanks);
    final read = cache.readRanks();
    expect(read, hasLength(kDefaultRanks.length));
    expect(read!.first.tier, 0);
  });

  test('cachedAsPremium and lastSyncAt meta persist', () async {
    expect(cache.cachedAsPremium, isFalse);
    expect(cache.lastSyncAt, isNull);

    await cache.setCachedAsPremium(true);
    await cache.markSynced(DateTime.utc(2026, 6, 23, 12));

    expect(cache.cachedAsPremium, isTrue);
    expect(cache.lastSyncAt, DateTime.utc(2026, 6, 23, 12));
  });

  test('clearContent wipes every cached entry and the premium tag', () async {
    await cache.writeCatalog('pl', [q('a')]);
    await cache.writeDaily('pl', '2026-06-23', q('d'));
    await cache.writeSmaczki('pl', 'q1', const [
      Smaczek(position: 1, isLocked: false),
    ]);
    await cache.writeFavoriteIds('pl', {'a'});
    await cache.writeStats(UserStats.empty);
    await cache.writeRanks(kDefaultRanks);
    await cache.setCachedAsPremium(true);

    await cache.clearContent();

    expect(cache.readCatalog('pl'), isNull);
    expect(cache.readLatestDaily('pl'), isNull);
    expect(cache.readSmaczki('pl', 'q1'), isNull);
    expect(cache.readFavoriteIds('pl'), isNull);
    expect(cache.readStats(), isNull);
    expect(cache.readRanks(), isNull);
    expect(cache.cachedAsPremium, isFalse);
  });
}
