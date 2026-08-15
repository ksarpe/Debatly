import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/rank.dart';
import '../../../data/models/user_stats.dart';
import '../../questions/providers/question_providers.dart';
import 'session_providers.dart';

/// Syncs and exposes the user's engagement state (streak, rank) once the
/// session resolves.
///
/// Skipped until the user is signed in; anonymous guests are signed in
/// server-side, so they get stats too.
final userStatsProvider = FutureProvider<UserStats?>((ref) async {
  final session = ref.watch(sessionProvider).value;
  if (session == null || !session.isSignedIn) return null;

  final repo = ref.watch(questionRepositoryProvider);
  return repo.syncUserState();
});

/// The resolved stats, or [UserStats.empty] while loading / signed out.
final userStatsValueProvider = Provider<UserStats>(
  (ref) => ref.watch(userStatsProvider).value ?? UserStats.empty,
);

/// The current streak length (decayed server-side by the streak "freeze": one
/// rank per 3 missed days, instead of snapping to 0).
final currentStreakProvider = Provider<int>(
  (ref) => ref.watch(userStatsValueProvider).currentStreak,
);

/// The full rank ladder (ordered by tier) for the rank sheet.
final ranksProvider = FutureProvider<List<Rank>>((ref) async {
  final repo = ref.watch(questionRepositoryProvider);
  return repo.fetchRanks();
});
