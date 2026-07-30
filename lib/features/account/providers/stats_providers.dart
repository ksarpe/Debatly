import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/rank.dart';
import '../../../data/models/user_stats.dart';
import '../../questions/providers/question_providers.dart';
import 'session_providers.dart';

/// Syncs and exposes the user's engagement state (streak, free-unlock credits,
/// rank) once the session resolves.
///
/// Calling `syncUserState` here on launch is ALSO what tops up today's free
/// credit (server-side, once per UTC day, capped at 1) — this is what replaced
/// the old random-bonus claim. Skipped until the user is signed in; anonymous
/// guests are signed in server-side, so they get stats too.
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

/// Free unlock credits available to spend.
///
/// Forced to 0 for premium users (who don't use the credit system) — both
/// server-side and here, so the chip hides immediately on a premium session
/// without waiting for the next sync.
final freeUnlockCreditsProvider = Provider<int>((ref) {
  if (ref.watch(sessionProvider).value?.isPremium ?? false) return 0;
  return ref.watch(userStatsValueProvider).freeUnlockCredits;
});

/// Whether today's ad-reveal cap is exhausted (server-synced, UTC day).
///
/// False while unknown (premium, pre-sync, offline snapshot from an older
/// server) — the paywall then keeps its ad button and the reveal RPC stays the
/// authority. The server enforces the cap regardless; this only decides
/// whether the "watch an ad" button is even offered.
final adCapReachedProvider = Provider<bool>((ref) {
  if (ref.watch(sessionProvider).value?.isPremium ?? false) return false;
  final left = ref.watch(userStatsValueProvider).adRevealsLeftToday;
  return left != null && left <= 0;
});

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
