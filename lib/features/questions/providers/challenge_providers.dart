import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/smaczek.dart';
import '../../account/providers/session_providers.dart';

/// How many post-vote gates a single session may show. The gate solves the
/// FREE user's problem (one question a day — the argument IS the product); a
/// PRO user bought the unlimited catalog, i.e. speed, and must not pay for it
/// with an endless run of full-screen interruptions. Free users never feel
/// this cap.
///
/// Raised 3 → 10 on 2026-08-20: the arguments ARE the reason to sit in the
/// feed, and cutting them off at the third vote was throttling the one thing
/// a PRO session is worth reading. Gates 2+ are already compact (the
/// word-by-word fall is dropped), so ten of them cost far less attention than
/// ten of the first one. The cap stays a cap — a valve against the
/// hundred-vote binge, not a per-session budget the normal user should ever
/// meet.
const int kChallengeSessionCap = 10;

/// How long the app must sit in the background before the next resume starts
/// a fresh session (and re-arms the gate cap).
const Duration kChallengeSessionResetAfter = Duration(minutes: 30);

/// Counts the gates shown since cold start — the app's one notion of a usage
/// session. A [Notifier] lives with the ProviderContainer, so a cold start is
/// a fresh zero for free; the 30-minutes-in-background reset is driven by the
/// lifecycle watcher on the question screen ([ChallengeSessionWatcher]).
class ChallengeSessionNotifier extends Notifier<int> {
  DateTime? _backgroundedAt;

  @override
  int build() => 0;

  /// Whether the NEXT gate may still show. Read (not watched) at vote time.
  bool get capReached => state >= kChallengeSessionCap;

  /// Whether the next gate is a shortened one — every gate after the first in
  /// a session drops the word-by-word fall and keeps only the hit.
  bool get nextIsCompact => state >= 1;

  void recordShown() => state = state + 1;

  /// Called when the app leaves the foreground. Only the FIRST pause of a
  /// stretch counts — a resume clears it — so flapping through inactive states
  /// can't stretch the measured background time.
  void markBackgrounded() => _backgroundedAt ??= clock.now();

  /// Called on resume: away long enough means a fresh session.
  void maybeResetOnResume() {
    final away = _backgroundedAt;
    _backgroundedAt = null;
    if (away != null &&
        clock.now().difference(away) >= kChallengeSessionResetAfter) {
      state = 0;
    }
  }
}

final challengeSessionProvider =
    NotifierProvider<ChallengeSessionNotifier, int>(
      ChallengeSessionNotifier.new,
    );

/// What the post-vote gate did on one question — kept so the surfaces AROUND
/// the gate can tell the truth afterwards: the bottom bar's label and the free
/// tier's smaczki sheet (which must not repeat the argument already read).
class ChallengeRecord {
  const ChallengeRecord({
    required this.outcome,
    required this.smaczekPosition,
    required this.smaczekTagged,
    required this.choice,
  });

  final ChallengeOutcome outcome;

  /// Position of the smaczek the gate served — the sheet hides exactly this
  /// card for a free user instead of guessing "the readable one".
  final int smaczekPosition;

  /// Whether that smaczek carried a `side` tag. Untagged means no "against
  /// you" promise can be kept, and the bar label follows.
  final bool smaczekTagged;

  /// The side the user had voted ([VoteResult.yes] / [VoteResult.no]) when the
  /// gate ran. The free sheet needs it to tell which locked cards DEFEND that
  /// answer — its header sells "attack → defense", and may only do so when a
  /// defense really waits behind the paywall.
  final int choice;

  /// Whether the argument was actually READ, i.e. the user answered the gate
  /// instead of leaving through system back.
  ///
  /// A [ChallengeOutcome.dismissed] gate is recorded like any other (the
  /// statistic wants to know), but nothing was delivered: a back press inside
  /// the first second — a mis-tap, a notification, a change of mind — must not
  /// spend the FREE tier's one readable argument on this question. Every
  /// surface that speaks in the past tense about the gate ("Pierwszy masz za
  /// sobą", the bottom bar's post-gate label, the sheet's hidden card) checks
  /// this first and otherwise keeps its pre-gate promise.
  bool get wasRead => outcome != ChallengeOutcome.dismissed;
}

/// The gates run this session, keyed by question id. In-memory on purpose:
/// after a restart the vote panel shows the bars straight away (no gate), so
/// stale records have nothing to mislabel. Reset on an identity switch — a
/// fresh user hasn't read anything.
class ChallengeRecordsNotifier extends Notifier<Map<String, ChallengeRecord>> {
  @override
  Map<String, ChallengeRecord> build() {
    ref.watch(sessionProvider.select((s) => s.value?.userId));
    return const {};
  }

  void record(String questionId, ChallengeRecord record) {
    state = {...state, questionId: record};
  }
}

final challengeRecordsProvider =
    NotifierProvider<ChallengeRecordsNotifier, Map<String, ChallengeRecord>>(
      ChallengeRecordsNotifier.new,
    );
