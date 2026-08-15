import 'package:debatly/data/models/user_stats.dart';
import 'package:debatly/data/repositories/question_repository.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/account/providers/stats_providers.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the user-stats layer that backs the streak chip and the rank
/// sheet. The streak math lives in the SQL RPC; here we pin the CLIENT
/// contract: who triggers the sync, who is skipped, and how the derived
/// providers read the result.
void main() {
  const stats = UserStats(
    currentStreak: 4,
    longestStreak: 9,
    rankTier: 1,
    rankName: 'Prowokator',
    nextRankStreak: 7,
  );

  ProviderContainer container({
    required SessionState session,
    required _CountingRepo repo,
  }) {
    final c = ProviderContainer(
      overrides: [
        sessionProvider.overrideWith(() => _FakeSession(session)),
        questionRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('UserStats.fromJson parses the RPC row', () {
    final s = UserStats.fromJson(const {
      'current_streak': 4,
      'longest_streak': 9,
      'rank_tier': 1,
      'rank_name': 'Prowokator',
      'next_rank_streak': 7,
      'is_premium': false,
    });
    expect(s.currentStreak, 4);
    expect(s.longestStreak, 9);
    expect(s.rankName, 'Prowokator');
    expect(s.nextRankStreak, 7);
    expect(s.graceDaysLeft, isNull);
    expect(s.isPremium, false);
  });

  test('legacy credit/ad-cap fields in the RPC row are ignored', () {
    // The server still returns these for older app versions; the hard-paywall
    // client must parse the row without choking on (or exposing) them.
    final s = UserStats.fromJson(const {
      'current_streak': 4,
      'longest_streak': 9,
      'free_unlock_credits': 1,
      'ad_reveals_left_today': 0,
      'rank_tier': 1,
      'rank_name': 'Prowokator',
      'next_rank_streak': 7,
      'is_premium': false,
    });
    expect(s.currentStreak, 4);
    expect(s.rankName, 'Prowokator');
  });

  test('grace_days_left parses when the streak freeze is counting down', () {
    final s = UserStats.fromJson(const {
      'current_streak': 7,
      'longest_streak': 14,
      'rank_tier': 2,
      'rank_name': 'Podżegacz',
      'next_rank_streak': 14,
      'grace_days_left': 2,
      'is_premium': false,
    });
    expect(s.graceDaysLeft, 2);
  });

  test('null next_rank_streak (top rank) parses to null', () {
    final s = UserStats.fromJson(const {
      'current_streak': 100,
      'longest_streak': 100,
      'rank_tier': 6,
      'rank_name': 'Legenda kontrowersji',
      'next_rank_streak': null,
      'is_premium': false,
    });
    expect(s.nextRankStreak, isNull);
  });

  test('toJson round-trips through fromJson (offline stats snapshot)', () {
    final restored = UserStats.fromJson(stats.toJson());
    expect(restored.currentStreak, stats.currentStreak);
    expect(restored.longestStreak, stats.longestStreak);
    expect(restored.rankTier, stats.rankTier);
    expect(restored.rankName, stats.rankName);
    expect(restored.nextRankStreak, stats.nextRankStreak);
  });

  test('a signed-in user syncs state once', () async {
    final repo = _CountingRepo(stats);
    final c = container(
      session: const SessionState(userId: 'u1', isAnonymous: false),
      repo: repo,
    );

    await c.read(sessionProvider.future);
    final result = await c.read(userStatsProvider.future);

    expect(repo.syncCalls, 1);
    expect(result?.currentStreak, 4);
  });

  test('an anonymous guest still syncs (signed in server-side)', () async {
    final repo = _CountingRepo(stats);
    final c = container(
      session: const SessionState(userId: 'guest', isAnonymous: true),
      repo: repo,
    );

    await c.read(sessionProvider.future);
    await c.read(userStatsProvider.future);

    expect(repo.syncCalls, 1);
  });

  test('a not-yet-signed-in session does not sync', () async {
    final repo = _CountingRepo(stats);
    final c = container(session: const SessionState(), repo: repo);

    await c.read(sessionProvider.future);
    final result = await c.read(userStatsProvider.future);

    expect(repo.syncCalls, 0);
    expect(result, isNull);
  });

  test('currentStreakProvider reflects the synced streak', () async {
    final repo = _CountingRepo(stats);
    final c = container(
      session: const SessionState(userId: 'u1', isAnonymous: false),
      repo: repo,
    );

    await c.read(sessionProvider.future);
    await c.read(userStatsProvider.future);

    expect(c.read(currentStreakProvider), 4);
  });
}

/// A session fixed to a known state, so stats gating can be exercised without
/// touching Supabase/RevenueCat.
class _FakeSession extends SessionNotifier {
  _FakeSession(this._state);

  final SessionState _state;

  @override
  Future<SessionState> build() async => _state;
}

/// Mock repo that counts sync calls; everything else inherits the offline mock.
class _CountingRepo extends MockQuestionRepository {
  _CountingRepo(this._stats);

  final UserStats? _stats;
  int syncCalls = 0;

  @override
  Future<UserStats?> syncUserState() async {
    syncCalls++;
    return _stats;
  }
}
