import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_config.dart';
import '../core/monitoring/monitoring.dart';

/// Thin wrapper around the Supabase client lifecycle.
///
/// Initialised once from `main()` before `runApp`. If no credentials are
/// supplied (see [AppConfig]) initialisation is skipped so the app still runs
/// against mock data during early development.
class SupabaseService {
  SupabaseService._();

  static bool _initialised = false;
  static bool get isInitialised => _initialised;

  static Future<void> initialise() async {
    if (!AppConfig.hasSupabaseCredentials) {
      debugPrint(
        'SupabaseService: no credentials provided — skipping init. '
        'Pass --dart-define=SUPABASE_URL/SUPABASE_ANON_KEY to enable.',
      );
      return;
    }

    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      // Supabase renamed the anon key to "publishable key"; the env var keeps
      // the familiar SUPABASE_ANON_KEY name.
      publishableKey: AppConfig.supabaseAnonKey,
    );
    _initialised = true;
  }

  /// Convenience accessor; throws if used before [initialise] succeeded.
  static SupabaseClient get client => Supabase.instance.client;

  // ---- Auth ------------------------------------------------------------------

  /// Ensures there is a signed-in user, creating an anonymous one on first
  /// launch. Returns the user's UUID, or `null` when Supabase is not configured
  /// (development / mock mode).
  ///
  /// Every user — even guests — gets a stable UUID so their progress can be
  /// tracked server-side without ever asking for an email or password.
  static Future<String?> ensureSignedIn() async {
    if (!_initialised) return null;

    final existing = client.auth.currentUser;
    if (existing != null) return existing.id;

    try {
      final response = await client.auth.signInAnonymously();
      return response.user?.id;
    } catch (e, st) {
      debugPrint('SupabaseService.ensureSignedIn failed: $e');
      // Failing to mint a guest means the whole app falls back to a sign-in-less
      // state (every RPC 401s) — a real, non-offline failure worth surfacing.
      await Monitoring.captureException(e, stackTrace: st, feature: 'auth');
      return null;
    }
  }

  /// Signs the user out. A default (global) sign-out revokes the refresh token
  /// server-side, which needs the network — so if that fails (e.g. offline) we
  /// fall back to a LOCAL sign-out, which just clears the on-device session.
  /// Either way the app ends up logged out and the auth listener converges on a
  /// fresh guest; a stale refresh token left behind expires server-side and is
  /// harmless. This makes "Sign out" work even with no connection instead of
  /// throwing and leaving the user stuck signed in.
  static Future<void> signOut() async {
    if (!_initialised) return;
    await signOutOn(client.auth);
  }

  /// The fallback rule itself, on an injectable auth client so the offline
  /// contract ("Sign out never throws, the device session is always cleared")
  /// is pinned by a unit test.
  @visibleForTesting
  static Future<void> signOutOn(GoTrueClient auth) async {
    try {
      await auth.signOut();
    } catch (e) {
      debugPrint(
        'SupabaseService.signOut: global sign-out failed ($e); '
        'falling back to local.',
      );
      // Recovered (local sign-out still logs the user out), so just leave a trail
      // for context rather than raising an issue.
      Monitoring.addBreadcrumb(
        'Global sign-out failed; fell back to local',
        category: 'auth',
      );
      await auth.signOut(scope: SignOutScope.local);
    }
  }

  static Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    if (!_initialised) {
      throw StateError('Supabase is not configured.');
    }

    await client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Signs in with Google via the native account picker, then exchanges the
  /// Google ID token for a Supabase session. Returns null if the user cancels.
  ///
  /// First sign-in creates the account, so this covers both login and
  /// registration.
  ///
  /// Uses the google_sign_in v7 API: a singleton initialised once with the
  /// "Web" OAuth client id (so Google mints an ID token Supabase will accept),
  /// then [GoogleSignIn.authenticate] for the native picker. Supabase only needs
  /// the ID token; the access token is fetched best-effort and passed when
  /// available.
  static Future<User?> signInWithGoogle() async {
    if (!_initialised) {
      throw StateError('Supabase is not configured.');
    }
    if (AppConfig.googleServerClientId.isEmpty) {
      throw StateError(
        'Missing GOOGLE_SERVER_CLIENT_ID (the Google "Web" OAuth client id).',
      );
    }

    final googleSignIn = GoogleSignIn.instance;
    // initialize() is idempotent — safe to call on every sign-in attempt.
    await googleSignIn.initialize(
      serverClientId: AppConfig.googleServerClientId,
    );

    final GoogleSignInAccount account;
    try {
      account = await googleSignIn.authenticate(scopeHint: const ['email']);
    } on GoogleSignInException catch (e) {
      // The user dismissing the picker is not an error to surface.
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }

    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const AuthException('Google did not return an ID token.');
    }

    // Access tokens now come from the authorization client, separately from
    // authentication. Supabase treats it as optional, so grab it without
    // forcing a second consent prompt and fall back to null.
    final authorization = await account.authorizationClient
        .authorizationForScopes(const ['email']);

    final response = await client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: authorization?.accessToken,
    );
    return response.user;
  }

  /// Signs in with Apple via the native iOS/macOS sheet, then exchanges Apple's
  /// identity token for a Supabase session. Returns null if the user cancels.
  ///
  /// First sign-in creates the account, so this covers both login and
  /// registration. A cryptographic nonce ties Apple's token to this request:
  /// we hand Apple the SHA-256 hash and Supabase the raw value, which it
  /// re-hashes and compares to reject replayed tokens.
  ///
  /// Only offered on Apple platforms (the UI hides it elsewhere); on Android it
  /// would need a web redirect + Service ID we deliberately don't set up.
  static Future<User?> signInWithApple() async {
    if (!_initialised) {
      throw StateError('Supabase is not configured.');
    }

    final rawNonce = _generateNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

    final AuthorizationCredentialAppleID credential;
    try {
      credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      // The user dismissing the sheet is not an error to surface.
      if (e.code == AuthorizationErrorCode.canceled) return null;
      rethrow;
    }

    final idToken = credential.identityToken;
    if (idToken == null) {
      throw const AuthException('Apple did not return an identity token.');
    }

    final response = await client.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );
    return response.user;
  }

  /// Cryptographically secure random string used as the Apple sign-in nonce.
  static String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  /// Sends a password-reset email so a user who forgot their password can set a
  /// new one. Supabase emails a recovery link out of the box; the link's target
  /// is the project's configured Site URL (no client-side deep link required).
  ///
  /// Note: Supabase deliberately returns success even for an unknown email so
  /// the endpoint can't be used to probe which addresses have accounts, so the
  /// caller should phrase the confirmation as "if an account exists…".
  static Future<void> resetPasswordForEmail(String email) async {
    if (!_initialised) {
      throw StateError('Supabase is not configured.');
    }
    await client.auth.resetPasswordForEmail(email.trim());
  }

  /// Creates a permanent email/password account.
  ///
  /// When the current user is anonymous we update that same Supabase user
  /// instead of creating a separate account, preserving any progress attached to
  /// their anonymous UUID.
  static Future<User?> registerWithPassword({
    required String email,
    required String password,
  }) async {
    if (!_initialised) {
      throw StateError('Supabase is not configured.');
    }
    return registerWithPasswordOn(
      client.auth,
      email: email,
      password: password,
    );
  }

  /// The branch itself, on an injectable auth client: an anonymous CURRENT user
  /// is upgraded in place (`updateUser` keeps the same UUID, so their streak,
  /// votes and reveals survive); only with no anonymous session does a fresh
  /// `signUp` mint a separate account. Extracted so the "don't lose a guest's
  /// progress" rule is pinned by a unit test.
  @visibleForTesting
  static Future<User?> registerWithPasswordOn(
    GoTrueClient auth, {
    required String email,
    required String password,
  }) async {
    final current = auth.currentUser;
    if (current?.isAnonymous == true) {
      final response = await auth.updateUser(
        UserAttributes(email: email.trim(), password: password),
      );
      return response.user;
    }

    final response = await auth.signUp(email: email.trim(), password: password);
    return response.user;
  }

  /// Reconciles the STORE side of premium against RevenueCat for the current
  /// identity and returns the resulting EFFECTIVE `is_premium` — the same flag
  /// the server gate enforces, merging store subscriptions with promotional /
  /// admin grants. Returns null only when the call couldn't run (no backend, no
  /// session, network error); the function itself no longer fails when the store
  /// key is unset — it then returns the DB truth without reconciling.
  ///
  /// This is the PULL counterpart to the inbound `revenue-cat-webhook`: the app
  /// calls it on launch and right after a purchase/restore so the gate
  /// (`profiles.is_premium`, read by every question/smaczki RPC) matches what the
  /// device knows, without waiting on — or depending on — the async webhook ever
  /// landing.
  static Future<bool?> syncEntitlement() async {
    if (!_initialised || client.auth.currentUser == null) return null;
    try {
      final res = await client.functions.invoke('sync-entitlement');
      final data = res.data;
      if (data is Map && data['is_premium'] is bool) {
        return data['is_premium'] as bool;
      }
      return null;
    } catch (e, st) {
      debugPrint('SupabaseService.syncEntitlement failed: $e');
      // The caller falls back to the DB/store flag, but a failing reconcile can
      // mean "bought PRO, sees nothing" — report it (offline is filtered out).
      await Monitoring.captureException(
        e,
        stackTrace: st,
        feature: 'entitlement',
      );
      return null;
    }
  }

  /// Reads the current identity's EFFECTIVE premium straight from `profiles`
  /// (the very flag the server gate enforces, via the `read own profile` RLS
  /// policy). Used as the source of truth for the UI when [syncEntitlement]
  /// can't run, so a promotional / admin grant — which has no RevenueCat
  /// purchase behind it — still unlocks the app. Honours `premium_until` so an
  /// expired grant reads as non-premium. Returns null only with no backend /
  /// session or on a read error (the caller then falls back to the on-device
  /// store cache).
  static Future<bool?> fetchIsPremium() async {
    if (!_initialised) return null;
    final user = client.auth.currentUser;
    if (user == null) return null;
    try {
      final row = await client
          .from('profiles')
          .select('is_premium, premium_until')
          .eq('id', user.id)
          .maybeSingle();
      if (row == null) return null;
      if (row['is_premium'] != true) return false;
      final until = row['premium_until'];
      if (until == null) return true; // lifetime / non-expiring
      final expiry = DateTime.tryParse(until as String);
      // isAfter compares absolute instants, so a UTC expiry vs local now is fine.
      return expiry == null || expiry.isAfter(DateTime.now());
    } catch (e, st) {
      debugPrint('SupabaseService.fetchIsPremium failed: $e');
      await Monitoring.captureException(
        e,
        stackTrace: st,
        feature: 'entitlement',
      );
      return null;
    }
  }

  /// Permanently deletes the current account and all associated data via the
  /// `delete-account` edge function (service-role; a client can't delete its own
  /// `auth.users` row). Deleting the auth user cascades across every user-owned
  /// table, so this removes/anonymizes all personal data server-side.
  ///
  /// On success the local session is torn down so the app falls back to a fresh
  /// anonymous guest on the next [ensureSignedIn]. Throws when there is no
  /// backend / no signed-in user, or the function fails, so the caller can
  /// surface an error instead of a silent no-op.
  ///
  /// Note: this does NOT cancel an active store subscription — the UI tells the
  /// user to do that in the App Store / Play Store.
  static Future<void> deleteAccount() async {
    if (!_initialised) {
      throw StateError('Supabase is not configured.');
    }
    if (client.auth.currentUser == null) {
      throw StateError('No signed-in user to delete.');
    }

    // Throws FunctionException on a non-2xx response; let it propagate.
    final res = await client.functions.invoke('delete-account');
    final data = res.data;
    if (!(data is Map && data['deleted'] == true)) {
      throw Exception('Account deletion did not complete.');
    }

    // The server-side user is gone, so its JWT is now invalid — a global
    // sign-out would try to revoke it and fail. Clear the session locally only.
    try {
      await client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      // Best-effort: the account is already deleted; a stale local token is
      // harmless and gets replaced by a fresh guest on next launch.
    }
  }

  static User? get currentUser => _initialised ? client.auth.currentUser : null;

  static bool get currentUserHasAccount {
    final user = currentUser;
    return user != null && !user.isAnonymous;
  }
}
