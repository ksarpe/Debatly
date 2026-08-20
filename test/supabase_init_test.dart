import 'dart:async';

import 'package:debatly/services/supabase_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The init contract, which exists because getting it wrong silently destroys
/// accounts.
///
/// `Supabase.initialize` runs `_init(...)` — setting its own internal "already
/// initialised" flag — to completion BEFORE it awaits `supabaseAuth.initialize`,
/// and THAT is the step that restores the persisted session. So calling it a
/// second time is not a retry: it returns instantly, successfully, having
/// restored nothing. The app then finds no current user and mints a fresh
/// anonymous UUID over the returning user's streak, votes, favourites and
/// entitlement, which are now on an identity with no credentials and no way
/// back.
///
/// Every assertion below is about that: the SDK call happens AT MOST ONCE, and
/// "ready" is only ever reported for an attempt that actually finished.
void main() {
  setUp(SupabaseService.resetInitForTest);
  tearDown(SupabaseService.resetInitForTest);

  test('a clean init reports ready and wakes the status listeners', () async {
    var woken = 0;
    SupabaseService.addStatusListener(() => woken++);

    final status = await SupabaseService.initialiseOn(() async {});

    expect(status, SupabaseInitStatus.ready);
    expect(SupabaseService.isInitialised, isTrue);
    expect(woken, 1, reason: 'the feed rebuilds off this');
  });

  test(
    'the SDK is asked exactly once, however many times we are called',
    () async {
      var starts = 0;
      Future<void> start() async => starts++;

      await SupabaseService.initialiseOn(start);
      await SupabaseService.initialiseOn(start);
      await SupabaseService.initialiseOn(start);

      expect(starts, 1);
    },
  );

  test('a retry after a FAILED init reports failure again — it does not '
      'declare a success the session restore never had', () async {
    var starts = 0;
    Future<void> start() {
      starts++;
      return Future<void>.error(StateError('local storage unreadable'));
    }

    expect(
      await SupabaseService.initialiseOn(start),
      SupabaseInitStatus.failed,
    );

    // THE regression. Restarting the SDK here returns ready in milliseconds,
    // because its own flag is already set — and the app would then sign the
    // user in as somebody new.
    expect(
      await SupabaseService.initialiseOn(start),
      SupabaseInitStatus.failed,
      reason: 'ready here means a fresh anonymous UUID over a real account',
    );
    expect(starts, 1, reason: 'the second attempt must not re-enter the SDK');
    expect(SupabaseService.isInitialised, isFalse);
  });

  test('a retry DURING a slow init waits on the original attempt and rides '
      'it to ready', () async {
    final slow = Completer<void>();
    var starts = 0;
    Future<void> start() {
      starts++;
      return slow.future;
    }

    // First attempt gives up waiting — the app shows its backend error screen.
    expect(
      await SupabaseService.initialiseOn(
        start,
        timeout: const Duration(milliseconds: 20),
      ),
      SupabaseInitStatus.failed,
    );
    expect(SupabaseService.isInitialised, isFalse);

    // The user taps retry while the first attempt is still in flight. This is
    // the case a retry can actually help with, and the one it must not fake.
    final retry = SupabaseService.initialiseOn(
      start,
      timeout: const Duration(seconds: 5),
    );
    slow.complete();

    expect(await retry, SupabaseInitStatus.ready);
    expect(starts, 1, reason: 'still one SDK call, not two');
    expect(SupabaseService.isInitialised, isTrue);
  });

  test(
    'an init that lands AFTER the app gave up still wakes the listeners',
    () async {
      final slow = Completer<void>();
      var woken = 0;
      SupabaseService.addStatusListener(() => woken++);

      expect(
        await SupabaseService.initialiseOn(
          () => slow.future,
          timeout: const Duration(milliseconds: 20),
        ),
        SupabaseInitStatus.failed,
      );
      expect(woken, 0);

      // No retry tap, no user action: the backend simply comes up late. The app
      // has to un-break itself, because the launch that gave up resolved with no
      // identity at all.
      slow.complete();
      await pumpEventQueue();

      expect(SupabaseService.status, SupabaseInitStatus.ready);
      expect(woken, 1);
    },
  );

  test(
    'the late-convergence hand-off is attached once, not once per retry',
    () async {
      final slow = Completer<void>();
      var woken = 0;
      SupabaseService.addStatusListener(() => woken++);

      const quick = Duration(milliseconds: 20);
      await SupabaseService.initialiseOn(() => slow.future, timeout: quick);
      await SupabaseService.initialiseOn(() => slow.future, timeout: quick);
      await SupabaseService.initialiseOn(() => slow.future, timeout: quick);

      slow.complete();
      await pumpEventQueue();

      expect(
        woken,
        1,
        reason: 'listeners fire on the transition, not per attempt',
      );
    },
  );

  group('statusFor — "no keys" and "keys that did not come up" are not the '
      'same thing', () {
    test('no credentials is mock mode', () {
      expect(
        SupabaseService.statusFor(configured: false, initialised: false),
        SupabaseInitStatus.notConfigured,
      );
    });

    test('credentials that failed is an ERROR, never mock mode', () {
      // Collapsing this into `!isInitialised` is what served real users
      // invented questions, a fabricated split, and votes thrown away.
      expect(
        SupabaseService.statusFor(configured: true, initialised: false),
        SupabaseInitStatus.failed,
      );
    });

    test('up is up, either way', () {
      for (final configured in [true, false]) {
        expect(
          SupabaseService.statusFor(configured: configured, initialised: true),
          SupabaseInitStatus.ready,
        );
      }
    });
  });
}
