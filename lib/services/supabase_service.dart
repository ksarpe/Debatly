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
  /// registration — and for an anonymous guest the "create" half upgrades
  /// their existing user in place (see [signInWithIdTokenOn]).
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

    // Same nonce dance as Apple: Google gets the SHA-256 hash (echoed
    // verbatim into the ID token's `nonce` claim), Supabase gets the raw
    // value and re-hashes it to compare. Without this, a token that arrives
    // with a nonce claim (newer Google SDKs add one on their own) is
    // rejected by GoTrue with "Passed nonce and nonce in id_token should
    // either both exist or not".
    final rawNonce = _generateNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

    final googleSignIn = GoogleSignIn.instance;
    // initialize() is idempotent — safe to call on every sign-in attempt,
    // which also swaps in this attempt's fresh nonce.
    await googleSignIn.initialize(
      serverClientId: AppConfig.googleServerClientId,
      nonce: hashedNonce,
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

    return signInWithIdTokenOn(
      client.auth,
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: authorization?.accessToken,
      nonce: rawNonce,
    );
  }

  /// Signs in with Apple via the native iOS/macOS sheet, then exchanges Apple's
  /// identity token for a Supabase session. Returns null if the user cancels.
  ///
  /// First sign-in creates the account, so this covers both login and
  /// registration — for an anonymous guest via an in-place upgrade, see
  /// [signInWithIdTokenOn]. A cryptographic nonce ties Apple's token to this request:
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

    return signInWithIdTokenOn(
      client.auth,
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );
  }

  /// GoTrue's error code for "this Google/Apple identity is already linked to
  /// another user" — the expected outcome when an existing user signs back in
  /// on a fresh install or a new phone.
  static const String _kIdentityAlreadyExists = 'identity_already_exists';

  /// The id-token exchange itself, on an injectable auth client: an anonymous
  /// CURRENT user links the identity IN PLACE (`linkIdentityWithIdToken` keeps
  /// the same UUID, so the guest's streak, votes and favourites survive — the
  /// social twin of [registerWithPasswordOn]). Only when that identity already
  /// belongs to another Supabase account does it fall back to
  /// `signInWithIdToken` and switch to that account — a genuine "sign back
  /// in", where abandoning the throwaway guest is what the user asked for.
  /// With no anonymous session it signs in directly. Extracted so the "don't
  /// lose a guest's progress" rule is pinned by a unit test.
  ///
  /// Requires "allow manual linking" to be enabled in the project's Auth
  /// settings. Any unexpected link failure (that flag being off included)
  /// still falls back to a plain sign-in — a working login on a fresh uid
  /// beats a dead button — but is reported, because silently minting new users
  /// for guests is exactly the lost-progress bug this branch exists to fix.
  @visibleForTesting
  static Future<User?> signInWithIdTokenOn(
    GoTrueClient auth, {
    required OAuthProvider provider,
    required String idToken,
    String? accessToken,
    String? nonce,
  }) async {
    if (auth.currentUser?.isAnonymous == true) {
      try {
        final response = await auth.linkIdentityWithIdToken(
          provider: provider,
          idToken: idToken,
          accessToken: accessToken,
          nonce: nonce,
        );
        return response.user;
      } on AuthException catch (e, st) {
        if (e.code == _kIdentityAlreadyExists) {
          Monitoring.addBreadcrumb(
            'Social identity already linked to another account; '
            'signing into it instead of upgrading the guest',
            category: 'auth',
          );
        } else {
          await Monitoring.captureException(e, stackTrace: st, feature: 'auth');
        }
      }
    }

    final response = await auth.signInWithIdToken(
      provider: provider,
      idToken: idToken,
      accessToken: accessToken,
      nonce: nonce,
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

  /// Decides what submitting the register form would actually DO to the
  /// current session, so the UI can refuse the surprising cases up front.
  ///
  /// Because registration upgrades the current user in place, the form is only
  /// a "create account" for a fresh guest. For anyone else `updateUser` would
  /// quietly rewrite the account they already have: a signed-in user
  /// "registering" again gets `same_password` errors, and typing a different
  /// email would silently re-point their existing account at it (a pending
  /// email change) instead of creating anything.
  static RegisterPrecheck registerPrecheck(String email) =>
      registerPrecheckFor(currentUser, email);

  /// The decision itself, on injectable state so a unit test can pin it.
  @visibleForTesting
  static RegisterPrecheck registerPrecheckFor(User? current, String email) {
    if (current != null && !current.isAnonymous) {
      return RegisterPrecheck.alreadySignedIn;
    }
    final attached = current?.email?.trim() ?? '';
    if (attached.isEmpty) return RegisterPrecheck.ok;
    final sameEmail = attached.toLowerCase() == email.trim().toLowerCase();
    // Same address = a retry of the registration that already happened
    // (resend the mail, or set the password they meant) — allowed.
    return sameEmail ? RegisterPrecheck.ok : RegisterPrecheck.pendingOtherEmail;
  }

  /// Creates a permanent email/password account.
  ///
  /// When the current user is anonymous we update that same Supabase user
  /// instead of creating a separate account, preserving any progress attached to
  /// their anonymous UUID.
  ///
  /// [locale] is the app's current language code; it rides along as user
  /// metadata so the `send-auth-email` hook can write the confirmation mail in
  /// the right language. It has to travel with THIS call — the mail goes out the
  /// moment the account exists, long before anything else could record a
  /// preference server-side.
  static Future<User?> registerWithPassword({
    required String email,
    required String password,
    required String locale,
  }) async {
    if (!_initialised) {
      throw StateError('Supabase is not configured.');
    }
    return registerWithPasswordOn(
      client.auth,
      email: email,
      password: password,
      locale: locale,
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
    required String locale,
  }) async {
    final data = {'locale': locale};
    final current = auth.currentUser;
    if (current?.isAnonymous == true) {
      // `emailRedirectTo` is a method argument here, not a `UserAttributes`
      // field — it steers the confirmation link to the "email confirmed" page
      // instead of the project's bare Site URL.
      try {
        final response = await auth.updateUser(
          UserAttributes(email: email.trim(), password: password, data: data),
          emailRedirectTo: AppConfig.emailConfirmedUrl,
        );
        return response.user;
      } on AuthException catch (error) {
        // A registration retry: the upgrade already succeeded earlier in this
        // session, and GoTrue refuses to "change" a password to the value it
        // already has. The password half is therefore already done — redo just
        // the email half so the retry still lands (and resends the
        // confirmation) instead of dying on an error about a password the
        // user never asked to change.
        if (error.code != 'same_password') rethrow;
        final response = await auth.updateUser(
          UserAttributes(email: email.trim(), data: data),
          emailRedirectTo: AppConfig.emailConfirmedUrl,
        );
        return response.user;
      }
    }

    final response = await auth.signUp(
      email: email.trim(),
      password: password,
      data: data,
      emailRedirectTo: AppConfig.emailConfirmedUrl,
    );
    return response.user;
  }

  /// Records the app's language on the user's profile so the auth emails
  /// (`send-auth-email` edge function) are written in it.
  ///
  /// Goes through the `set_profile_locale` RPC rather than `updateUser`
  /// metadata on purpose: a metadata write emits `userUpdated`, which
  /// [SessionNotifier] answers with a full session reload and an entitlement
  /// reconcile. Switching the UI language must not cost a premium re-check.
  ///
  /// Best-effort and silent — nobody's language preference is worth failing a
  /// launch or a settings tap over, and the value is re-sent on the next launch
  /// anyway. No-ops without a backend or a session.
  static Future<void> syncProfileLocale(String locale) async {
    if (!_initialised || client.auth.currentUser == null) return;
    try {
      await client.rpc('set_profile_locale', params: {'p_locale': locale});
    } catch (e) {
      debugPrint('SupabaseService.syncProfileLocale failed: $e');
      Monitoring.addBreadcrumb(
        'Profile locale sync failed; auth emails may use the previous language',
        category: 'auth',
      );
    }
  }

  /// The all-time TAK/NIE tally for [questionId] — the onboarding taste card's
  /// live community split.
  ///
  /// Reuses the `get_daily_vote_state` RPC (granted to `authenticated`, which
  /// covers anonymous guests), so a guest is minted first when none exists yet —
  /// harmless, the session reload right after onboarding does the same. Returns
  /// null when Supabase isn't configured (mock mode), no session could be
  /// established (offline first launch) or the RPC fails — the caller then keeps
  /// its curated fallback split.
  static Future<({int yes, int no})?> fetchVoteSplit(String questionId) async {
    if (!_initialised) return null;
    try {
      if (await ensureSignedIn() == null) return null;
      final data = await client.rpc(
        'get_daily_vote_state',
        params: {'p_question_id': questionId},
      );
      final rows = (data as List).cast<Map<String, dynamic>>();
      if (rows.isEmpty) return null;
      int asInt(Object? v) => v is int ? v : int.tryParse('$v') ?? 0;
      return (
        yes: asInt(rows.first['yes_count']),
        no: asInt(rows.first['no_count']),
      );
    } catch (e) {
      debugPrint('SupabaseService.fetchVoteSplit failed: $e');
      // Best-effort: the onboarding reveal simply keeps its fallback split.
      Monitoring.addBreadcrumb(
        'Taste vote split fetch failed; onboarding shows the fallback 50/50',
        category: 'onboarding',
      );
      return null;
    }
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
  /// How long the entitlement reconcile may hold up a session reload. The
  /// function caps its own RevenueCat call at 6 s and degrades to the DB
  /// truth, so a healthy round trip always answers well within this; past it
  /// the caller's fallback chain (profile flag, then the device receipt)
  /// reaches the same answer without pinning the UI on a slow store API —
  /// observed at 30–40 s per call, which read as a frozen spinner.
  static const _syncEntitlementTimeout = Duration(seconds: 10);

  static Future<bool?> syncEntitlement() async {
    if (!_initialised || client.auth.currentUser == null) return null;
    try {
      final res = await client.functions
          .invoke('sync-entitlement')
          .timeout(_syncEntitlementTimeout);
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

/// Outcome of [SupabaseService.registerPrecheck]: whether submitting the
/// register form would create/retry a registration ([ok]) or quietly rewrite
/// an account that already exists (the other two — the UI refuses those).
enum RegisterPrecheck {
  ok,

  /// The current user already has a full (non-anonymous) account.
  alreadySignedIn,

  /// The current guest already registered with a DIFFERENT address (still
  /// awaiting confirmation); proceeding would re-point that registration.
  pendingOtherEmail,
}
