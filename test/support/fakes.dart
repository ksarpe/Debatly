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

/// A signed-in account holder — with a social identity, so Settings has no
/// "link Apple / Google" row to offer them.
SessionState accountSession({
  bool isPremium = false,
  List<String> linkedProviders = const ['google'],
}) => SessionState(
  userId: 'user-1',
  email: 'user@example.com',
  isAnonymous: false,
  isPremium: isPremium,
  linkedProviders: linkedProviders,
);

/// A legacy email/password account: signed in, no Google / Apple identity.
/// The one `SessionState.canLinkSocial` holds for.
SessionState passwordOnlyAccountSession({bool isPremium = false}) =>
    accountSession(isPremium: isPremium, linkedProviders: const ['email']);
