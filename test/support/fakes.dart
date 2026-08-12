import 'package:debatly/features/account/providers/session_providers.dart';

/// A [SessionNotifier] pinned to a fixed [SessionState] — no Supabase, no
/// RevenueCat, no auth subscriptions. Override with:
///
/// ```dart
/// sessionProvider.overrideWith(() => FakeSession(guestSession()))
/// ```
///
/// (Several older suites still carry a private copy of this; new tests should
/// use this one.)
class FakeSession extends SessionNotifier {
  FakeSession(this._state);

  final SessionState _state;

  @override
  Future<SessionState> build() async => _state;
}

/// An anonymous guest — signed in, no account.
SessionState guestSession({bool isPremium = false}) =>
    SessionState(userId: 'guest-1', isAnonymous: true, isPremium: isPremium);

/// A signed-in account holder.
SessionState accountSession({bool isPremium = false}) => SessionState(
  userId: 'user-1',
  email: 'user@example.com',
  isAnonymous: false,
  isPremium: isPremium,
);
