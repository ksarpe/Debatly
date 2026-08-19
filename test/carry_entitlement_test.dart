import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:flutter_test/flutter_test.dart';

/// When a just-bought PRO has to be re-posted against the identity the user
/// signed into.
///
/// RevenueCat does not move purchases between two identified app user ids on
/// `logIn` alone, so a guest who buys PRO and then signs into an existing
/// account lands on a uid it has never seen: `sync-entitlement` 404s,
/// `isPremium` goes false, and the paywall shuts on somebody who paid a minute
/// ago. The rule lived inline in ONE branch of the auth screen, which is
/// exactly how the email/password branch ended up without it.
void main() {
  const guestPremium = SessionState(
    userId: 'guest-1',
    isAnonymous: true,
    isPremium: true,
  );

  group('shouldCarryEntitlement', () {
    test('a premium guest signing into another account carries PRO', () {
      // The case that was broken: signing in REPLACES the session, so the uid
      // always changes — this is not an edge case, it is every password login.
      expect(
        shouldCarryEntitlement(previous: guestPremium, next: 'account-9'),
        isTrue,
      );
    });

    test(
      'an in-place upgrade carries nothing — same uid, PRO already there',
      () {
        // Registering and linking a social identity keep the same UUID.
        expect(
          shouldCarryEntitlement(previous: guestPremium, next: 'guest-1'),
          isFalse,
        );
      },
    );

    test('a free user has no entitlement to move', () {
      const freeGuest = SessionState(
        userId: 'guest-1',
        isAnonymous: true,
        isPremium: false,
      );
      expect(
        shouldCarryEntitlement(previous: freeGuest, next: 'account-9'),
        isFalse,
      );
    });

    test('an unresolved session on either side is left alone', () {
      expect(
        shouldCarryEntitlement(previous: null, next: 'account-9'),
        isFalse,
      );
      expect(
        shouldCarryEntitlement(previous: guestPremium, next: null),
        isFalse,
      );
      expect(
        shouldCarryEntitlement(
          previous: const SessionState(isPremium: true),
          next: 'account-9',
        ),
        isFalse,
      );
    });
  });
}
