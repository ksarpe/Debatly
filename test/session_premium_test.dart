import 'package:debatly/core/locale/app_locale.dart'
    show sharedPreferencesProvider;
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/test_prefs.dart';

/// Premium is tied to the *identity* (the Supabase UUID every user gets at
/// launch via anonymous sign-in), NOT to having a real account. These tests pin
/// down that decoupling so the "a guest can hold PRO" / "restore doesn't log you
/// in" guarantees don't silently regress.
void main() {
  // A signed-in-but-anonymous guest: has a stable UUID, no email, isAnonymous.
  SessionState guest({bool isPremium = false}) => SessionState(
    userId: 'anon-uuid',
    isAnonymous: true,
    isPremium: isPremium,
  );

  // A real account: anonymous identity upgraded to email/password or Google.
  SessionState account({bool isPremium = false}) => SessionState(
    userId: 'anon-uuid',
    email: 'user@example.com',
    isAnonymous: false,
    isPremium: isPremium,
  );

  group('identity vs account', () {
    test('a guest is signed in but has no account', () {
      final s = guest();
      expect(s.isSignedIn, isTrue, reason: 'every user gets a UUID at launch');
      expect(s.hasAccount, isFalse, reason: 'anonymous == no real account');
    });

    test('an upgraded user has an account', () {
      expect(account().hasAccount, isTrue);
    });

    test(
      'a still-loading session (null userId) is neither signed in nor an account',
      () {
        const s = SessionState();
        expect(s.isSignedIn, isFalse);
        expect(s.hasAccount, isFalse);
      },
    );
  });

  group('premium is independent of having an account', () {
    test('a guest can hold PRO', () {
      final s = guest(isPremium: true);
      expect(s.isPremium, isTrue);
      expect(
        s.hasAccount,
        isFalse,
        reason: 'PRO must not require a real account',
      );
    });

    test('an account without PRO is possible', () {
      expect(account(isPremium: false).isPremium, isFalse);
    });
  });

  group('restore does not change the identity', () {
    test('restoring PRO leaves a guest a guest (no login happens)', () {
      final before = guest();
      // restorePurchases() only re-reads the entitlement; the session is then
      // refreshed. Model that as flipping isPremium and nothing else.
      final after = before.copyWith(isPremium: true);

      expect(after.isPremium, isTrue, reason: 'entitlement restored');
      expect(after.isAnonymous, isTrue, reason: 'still anonymous');
      expect(after.hasAccount, isFalse, reason: 'restore is not a login');
      expect(after.userId, before.userId, reason: 'same identity');
    });
  });

  // The auth listener converges the session on out-of-band identity changes.
  // Widening this set silently would turn a token refresh into a reload storm
  // (and trip the QuestionScreen identity listener); narrowing it would leave a
  // zombie UI after a silent sign-out. Pin exactly which events act.
  group('isIdentityChangingAuthEvent', () {
    test('a silent sign-out reloads (mint a fresh guest)', () {
      expect(isIdentityChangingAuthEvent(AuthChangeEvent.signedOut), isTrue);
    });

    test('an anonymous→email upgrade reloads', () {
      expect(isIdentityChangingAuthEvent(AuthChangeEvent.userUpdated), isTrue);
    });

    test('the initial session / sign-in / token refresh do NOT reload', () {
      expect(
        isIdentityChangingAuthEvent(AuthChangeEvent.initialSession),
        isFalse,
      );
      expect(isIdentityChangingAuthEvent(AuthChangeEvent.signedIn), isFalse);
      expect(
        isIdentityChangingAuthEvent(AuthChangeEvent.tokenRefreshed),
        isFalse,
      );
    });
  });

  // Keyless development (and the whole widget-test suite) runs with neither
  // Supabase nor RevenueCat configured. Under the hard paywall a free session
  // there would wall the app off behind a purchase that CANNOT be made — no
  // store, no entitlement, no way through. So a keyless session resolves
  // premium; anything else makes the mock data unreachable.
  group('mock mode (no backend keys)', () {
    test(
      'resolves a premium session, so the keyless app is never walled',
      () async {
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(
              await mockSharedPreferences(),
            ),
          ],
        );
        addTearDown(container.dispose);

        final session = await container.read(sessionProvider.future);

        expect(session.isPremium, isTrue, reason: 'the feed must be reachable');
        expect(
          container.read(isPremiumProvider),
          isTrue,
          reason: 'the home gate reads this flag, not the state directly',
        );
        // The entitlement is granted WITHOUT inventing an identity: there is
        // no backend to mint a UUID against, and nothing may pretend there is.
        expect(session.isSignedIn, isFalse);
      },
    );
  });

  // The effective-premium precedence is the gate the whole app reads. The order
  // matters (a promo grant with no purchase must still unlock) AND the
  // short-circuit matters (a resolved sync must not fire the other two
  // network/SDK calls).
  group('resolveEffectivePremium', () {
    test('the reconciled store↔DB sync wins when it resolves', () async {
      var profileCalls = 0;
      var storeCalls = 0;
      final result = await resolveEffectivePremium(
        sync: () async => true,
        profile: () async {
          profileCalls++;
          return false;
        },
        store: () async {
          storeCalls++;
          return false;
        },
      );
      expect(result, isTrue);
      expect(profileCalls, 0, reason: 'sync resolved — must not hit profile');
      expect(storeCalls, 0, reason: 'sync resolved — must not hit store');
    });

    test(
      'falls through to the profile flag when sync is null (promo grant)',
      () async {
        var storeCalls = 0;
        final result = await resolveEffectivePremium(
          sync: () async => null,
          profile: () async => true,
          store: () async {
            storeCalls++;
            return false;
          },
        );
        expect(
          result,
          isTrue,
          reason: 'a promo/admin grant unlocks with no buy',
        );
        expect(storeCalls, 0, reason: 'profile resolved — must not hit store');
      },
    );

    test('falls through to the store cache only when both are null', () async {
      final result = await resolveEffectivePremium(
        sync: () async => null,
        profile: () async => null,
        store: () async => true,
      );
      expect(result, isTrue);
    });

    test('is free when every source declines', () async {
      final result = await resolveEffectivePremium(
        sync: () async => null,
        profile: () async => null,
        store: () async => false,
      );
      expect(result, isFalse);
    });

    test(
      'a false from sync settles the DB side — the profile is not re-read',
      () async {
        // A resolved `false` is a real answer about the database (lapsed), not
        // "unknown"; only null means "couldn't reconcile, try the next source".
        var profileCalls = 0;
        final result = await resolveEffectivePremium(
          sync: () async => false,
          profile: () async {
            profileCalls++;
            return true;
          },
          store: () async => false,
        );
        expect(result, isFalse);
        expect(profileCalls, 0);
      },
    );

    test('the device receipt outranks a server that says no', () async {
      // The whole app sits behind the paywall, so every way the server can
      // wrongly answer "no" — a 502 from sync-entitlement, a webhook that
      // hasn't landed — is a paying user staring at a wall. RevenueCat holding
      // an ACTIVE entitlement on the device means they really did pay.
      expect(
        await resolveEffectivePremium(
          sync: () async => false,
          profile: () async => false,
          store: () async => true,
        ),
        isTrue,
        reason: 'a reconciled "no" must not lock out a receipt on the device',
      );
      expect(
        await resolveEffectivePremium(
          sync: () async => null,
          profile: () async => false,
          store: () async => true,
        ),
        isTrue,
        reason: 'nor a profile row the webhook has not reached yet',
      );
    });
  });
}
