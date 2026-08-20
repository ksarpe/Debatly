import 'package:clock/clock.dart';
import 'package:debatly/data/models/smaczek.dart';
import 'package:debatly/data/models/vote_result.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/questions/providers/challenge_providers.dart';
import 'package:debatly/features/questions/widgets/challenge_session_watcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// The per-session valve on the argument gate, and the memory of what it did.
///
/// Both were entirely uncovered, and both fail silently when they break. A cap
/// that never re-arms means the arguments simply stop appearing after ten votes
/// and never come back — the user would report it as "the app stopped showing
/// them", with nothing in the logs. A record that outlives its owner means the
/// next person to use the phone is told they have already read an argument they
/// have never seen.
void main() {
  ChallengeSessionNotifier sessionOf(ProviderContainer c) =>
      c.read(challengeSessionProvider.notifier);

  group('the gate cap', () {
    test('counts up to the cap and then holds the line', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final session = sessionOf(c);

      expect(
        session.capReached,
        isFalse,
        reason: 'a fresh session owes nothing',
      );
      for (var i = 0; i < kChallengeSessionCap; i++) {
        expect(
          session.capReached,
          isFalse,
          reason:
              'gate ${i + 1} of $kChallengeSessionCap must still be allowed',
        );
        session.recordShown();
      }
      expect(session.capReached, isTrue);
    });

    test('only the FIRST gate of a session gets the full beat', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final session = sessionOf(c);

      expect(
        session.nextIsCompact,
        isFalse,
        reason: 'gate 1 falls word by word',
      );
      session.recordShown();
      expect(
        session.nextIsCompact,
        isTrue,
        reason: 'gate 2 onwards is compact',
      );
      session.recordShown();
      expect(session.nextIsCompact, isTrue);
    });
  });

  group('the 30-minute background reset', () {
    /// Runs [body] with a clock the test moves by hand, so the reset is
    /// asserted on the RULE rather than on how long the suite happens to take.
    void atFixedTime(void Function(void Function(Duration) advance) body) {
      var now = DateTime.utc(2026, 8, 20, 12);
      withClock(Clock(() => now), () => body((d) => now = now.add(d)));
    }

    test('long enough away re-arms the cap', () {
      atFixedTime((advance) {
        final c = ProviderContainer();
        addTearDown(c.dispose);
        final session = sessionOf(c);

        for (var i = 0; i < kChallengeSessionCap; i++) {
          session.recordShown();
        }
        expect(session.capReached, isTrue);

        session.markBackgrounded();
        advance(kChallengeSessionResetAfter);
        session.maybeResetOnResume();

        expect(
          session.capReached,
          isFalse,
          reason: 'coming back after a real break is a new session',
        );
        expect(
          session.nextIsCompact,
          isFalse,
          reason: 'and the first gate of it earns the full beat again',
        );
      });
    });

    test(
      'a shorter trip does NOT re-arm it — the valve would be pointless',
      () {
        atFixedTime((advance) {
          final c = ProviderContainer();
          addTearDown(c.dispose);
          final session = sessionOf(c);

          for (var i = 0; i < kChallengeSessionCap; i++) {
            session.recordShown();
          }

          session.markBackgrounded();
          advance(kChallengeSessionResetAfter - const Duration(seconds: 1));
          session.maybeResetOnResume();

          expect(
            session.capReached,
            isTrue,
            reason: 'checking a notification is not a new session',
          );
        });
      },
    );

    test('only the first pause of a stretch counts, so flapping through '
        'inactive cannot stretch the measured time', () {
      atFixedTime((advance) {
        final c = ProviderContainer();
        addTearDown(c.dispose);
        final session = sessionOf(c);
        session.recordShown();

        session.markBackgrounded();
        advance(const Duration(minutes: 20));
        // A second pause with no resume in between must not restart the clock,
        // or a user who peeks at the shade every few minutes would never be
        // credited with the time they were actually away.
        session.markBackgrounded();
        advance(const Duration(minutes: 15));
        session.maybeResetOnResume();

        expect(
          c.read(challengeSessionProvider),
          0,
          reason: '35 minutes away is 35 minutes away',
        );
      });
    });

    test('a resume with no preceding pause changes nothing', () {
      atFixedTime((advance) {
        final c = ProviderContainer();
        addTearDown(c.dispose);
        final session = sessionOf(c);
        session.recordShown();

        session.maybeResetOnResume();
        advance(const Duration(hours: 3));
        session.maybeResetOnResume();

        expect(
          c.read(challengeSessionProvider),
          1,
          reason: 'never left, never came back',
        );
      });
    });
  });

  group('what the gate remembers', () {
    ChallengeRecord recordFor(int choice) => ChallengeRecord(
      outcome: ChallengeOutcome.held,
      smaczekPosition: 1,
      smaczekTagged: true,
      choice: choice,
    );

    test('a dismissed gate is remembered, but never as READ', () {
      // The distinction the free tier rides on: a back press inside the first
      // second is a mis-tap, and it must not spend the one readable argument
      // that question will ever offer.
      const dismissed = ChallengeRecord(
        outcome: ChallengeOutcome.dismissed,
        smaczekPosition: 1,
        smaczekTagged: true,
        choice: VoteResult.yes,
      );
      expect(dismissed.wasRead, isFalse);

      for (final outcome in [ChallengeOutcome.held, ChallengeOutcome.moved]) {
        expect(
          ChallengeRecord(
            outcome: outcome,
            smaczekPosition: 1,
            smaczekTagged: true,
            choice: VoteResult.yes,
          ).wasRead,
          isTrue,
          reason: '$outcome means they answered, which means they read it',
        );
      }
    });

    test(
      'signing in as somebody else forgets what the last user read',
      () async {
        final session = _SwitchableSession();
        final c = ProviderContainer(
          overrides: [sessionProvider.overrideWith(() => session)],
        );
        addTearDown(c.dispose);
        // Let the guest resolve first: the records only mean anything once there
        // is an identity to own them.
        await c.read(sessionProvider.future);

        c
            .read(challengeRecordsProvider.notifier)
            .record('q1', recordFor(VoteResult.yes));
        expect(c.read(challengeRecordsProvider).containsKey('q1'), isTrue);

        session.switchTo(
          const SessionState(userId: 'somebody-else', isAnonymous: true),
        );

        expect(
          c.read(challengeRecordsProvider),
          isEmpty,
          reason: 'a fresh identity has not read anything on this phone',
        );
      },
    );

    test('the same user staying put keeps theirs', () async {
      final session = _SwitchableSession();
      final c = ProviderContainer(
        overrides: [sessionProvider.overrideWith(() => session)],
      );
      addTearDown(c.dispose);
      await c.read(sessionProvider.future);

      c
          .read(challengeRecordsProvider.notifier)
          .record('q1', recordFor(VoteResult.no));
      // A refresh that resolves to the SAME id is not an identity change, and
      // wiping on it would re-offer an argument they just finished reading.
      session.switchTo(guestSession());

      expect(c.read(challengeRecordsProvider).containsKey('q1'), isTrue);
    });
  });
  group('the OS lifecycle wiring', () {
    // The notifier above is only half the mechanic: something has to TELL it
    // the app went away and came back. If that wiring breaks, the cap is
    // reached once and never re-armed — the arguments stop appearing for good,
    // with nothing on screen and nothing in the logs to say why.
    Future<ProviderContainer> pumpWatcher(WidgetTester tester) async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(home: ChallengeSessionWatcher()),
        ),
      );
      return c;
    }

    testWidgets('a real trip to the background re-arms the cap', (
      tester,
    ) async {
      var now = DateTime.utc(2026, 8, 20, 12);
      await withClock(Clock(() => now), () async {
        final c = await pumpWatcher(tester);
        final session = sessionOf(c);
        for (var i = 0; i < kChallengeSessionCap; i++) {
          session.recordShown();
        }

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        now = now.add(kChallengeSessionResetAfter);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();

        expect(c.read(challengeSessionProvider), 0);
      });
    });

    testWidgets('a shade peek is not a trip — inactive must not start the '
        'clock', (tester) async {
      var now = DateTime.utc(2026, 8, 20, 12);
      await withClock(Clock(() => now), () async {
        final c = await pumpWatcher(tester);
        final session = sessionOf(c);
        session.recordShown();

        // `inactive` fires for the notification shade and the app switcher.
        // Counting it would let a user farm a fresh session by swiping down.
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        now = now.add(const Duration(hours: 2));
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();

        expect(
          c.read(challengeSessionProvider),
          1,
          reason: 'never actually backgrounded, so nothing to reset',
        );
      });
    });

    testWidgets('the observer is removed on dispose', (tester) async {
      await pumpWatcher(tester);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      // A leaked observer would keep answering lifecycle events against a dead
      // ref; reaching here without a throw is the assertion.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    });
  });
}

class _SwitchableSession extends SessionNotifier {
  @override
  Future<SessionState> build() async => guestSession();

  void switchTo(SessionState next) => state = AsyncData(next);
}
