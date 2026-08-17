import 'dart:convert';

import 'package:debatly/services/supabase_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The auth flows that guard a user's progress and their way out:
///
///  * `registerWithPassword` — an anonymous session is upgraded IN PLACE
///    (`updateUser`, same UUID → the guest's streak/votes/reveals survive);
///    only with no anonymous session does `signUp` mint a separate account.
///    Losing this branch silently orphans every guest who registers.
///  * `signInWithIdToken` (social) — the same rule for the Google/Apple
///    buttons: an anonymous session LINKS the identity in place
///    (`linkIdentityWithIdToken`, same UUID); only an identity that already
///    belongs to another account falls back to a plain sign-in, switching to
///    that account.
///  * `signOut` — the global sign-out revokes the refresh token server-side,
///    which needs the network; when that fails the LOCAL fallback must still
///    log the user out without throwing (sign-out has to work offline).
///
/// Run against a real [GoTrueClient] on a [MockClient] transport, like
/// supabase_question_repository_test does for the data path.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String b64(Map<String, dynamic> map) =>
      base64Url.encode(utf8.encode(jsonEncode(map))).replaceAll('=', '');

  // gotrue only decodes the payload (expiry), so an unsigned token is enough.
  String fakeJwt(String sub) =>
      '${b64({'alg': 'none', 'typ': 'JWT'})}.'
      '${b64({'sub': sub, 'exp': 4102444800, 'role': 'authenticated'})}.sig';

  Map<String, dynamic> userJson({
    required String id,
    String? email,
    required bool anonymous,
  }) => {
    'id': id,
    'aud': 'authenticated',
    'role': 'authenticated',
    'email': email,
    'phone': '',
    'created_at': '2026-01-01T00:00:00Z',
    'updated_at': '2026-01-01T00:00:00Z',
    'is_anonymous': anonymous,
    'app_metadata': <String, dynamic>{},
    'user_metadata': <String, dynamic>{},
    'identities': <dynamic>[],
  };

  String sessionJson(Map<String, dynamic> user) => jsonEncode({
    'access_token': fakeJwt(user['id'] as String),
    'token_type': 'bearer',
    'expires_in': 3600,
    'refresh_token': 'rt-1',
    'user': user,
  });

  const jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

  /// A Supabase client whose transport is [handler]; requests are recorded
  /// into [log].
  SupabaseClient buildClient(
    List<http.Request> log,
    http.Response? Function(http.Request request) handler,
  ) {
    final mock = MockClient((request) async {
      log.add(request);
      final response = handler(request);
      if (response != null) return response;
      return http.Response('{}', 404, request: request, headers: jsonHeaders);
    });
    final client = SupabaseClient(
      'https://test.supabase.co',
      'test-anon-key',
      httpClient: mock,
      // implicit: the default PKCE flow asserts on an asyncStorage the tests
      // don't have (and don't exercise).
      authOptions: const AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.implicit,
      ),
    );
    addTearDown(client.dispose);
    return client;
  }

  group('registerWithPassword', () {
    test(
      'an anonymous session upgrades in place — same UUID, no signUp',
      () async {
        final anon = userJson(id: 'anon-1', anonymous: true);
        final upgraded = userJson(
          id: 'anon-1',
          email: 'user@example.com',
          anonymous: false,
        );
        final log = <http.Request>[];
        final client = buildClient(log, (request) {
          if (request.url.path.endsWith('/auth/v1/signup')) {
            return http.Response(
              sessionJson(anon),
              200,
              request: request,
              headers: jsonHeaders,
            );
          }
          if (request.url.path.endsWith('/auth/v1/user')) {
            return http.Response(
              jsonEncode(upgraded),
              200,
              request: request,
              headers: jsonHeaders,
            );
          }
          return null;
        });

        await client.auth.signInAnonymously();
        expect(client.auth.currentUser?.isAnonymous, isTrue);

        final user = await SupabaseService.registerWithPasswordOn(
          client.auth,
          email: '  user@example.com  ',
          password: 'secret123',
          locale: 'pl',
        );

        final update = log.last;
        expect(update.method, 'PUT');
        expect(update.url.path, endsWith('/auth/v1/user'));
        final body = jsonDecode(update.body) as Map<String, dynamic>;
        expect(body['email'], 'user@example.com', reason: 'email is trimmed');
        expect(body['password'], 'secret123');
        expect(
          (body['data'] as Map<String, dynamic>)['locale'],
          'pl',
          reason: 'the send-auth-email hook reads this to pick the language',
        );

        expect(
          user?.id,
          'anon-1',
          reason: 'the UUID must not change — it carries the guest\'s progress',
        );
        expect(
          log.where((r) => r.url.path.endsWith('/auth/v1/signup')).length,
          1,
          reason: 'only the anonymous sign-in hit /signup — no second account',
        );
      },
    );

    test(
      'with no anonymous session a fresh signUp creates the account',
      () async {
        final fresh = userJson(
          id: 'new-1',
          email: 'user@example.com',
          anonymous: false,
        );
        final log = <http.Request>[];
        final client = buildClient(log, (request) {
          if (request.url.path.endsWith('/auth/v1/signup')) {
            return http.Response(
              sessionJson(fresh),
              200,
              request: request,
              headers: jsonHeaders,
            );
          }
          return null;
        });

        final user = await SupabaseService.registerWithPasswordOn(
          client.auth,
          email: 'user@example.com',
          password: 'secret123',
          locale: 'en',
        );

        expect(log, hasLength(1));
        expect(log.single.method, 'POST');
        expect(log.single.url.path, endsWith('/auth/v1/signup'));
        final body = jsonDecode(log.single.body) as Map<String, dynamic>;
        expect(body['email'], 'user@example.com');
        expect(
          (body['data'] as Map<String, dynamic>)['locale'],
          'en',
          reason: 'the send-auth-email hook reads this to pick the language',
        );
        expect(user?.id, 'new-1');
      },
    );
  });

  group('signInWithIdToken (social)', () {
    /// Requests to the id-token grant endpoint, split by intent: linking
    /// carries `link_identity: true` in the body, a plain sign-in doesn't.
    bool isIdTokenGrant(http.Request r) =>
        r.url.path.endsWith('/auth/v1/token') &&
        r.url.queryParameters['grant_type'] == 'id_token';
    bool isLink(http.Request r) =>
        isIdTokenGrant(r) &&
        (jsonDecode(r.body) as Map<String, dynamic>)['link_identity'] == true;

    test('an anonymous session links the identity in place — same UUID, '
        'no plain sign-in', () async {
      final anon = userJson(id: 'anon-1', anonymous: true);
      final linked = userJson(
        id: 'anon-1',
        email: 'user@gmail.com',
        anonymous: false,
      );
      final log = <http.Request>[];
      final client = buildClient(log, (request) {
        if (request.url.path.endsWith('/auth/v1/signup')) {
          return http.Response(
            sessionJson(anon),
            200,
            request: request,
            headers: jsonHeaders,
          );
        }
        if (isLink(request)) {
          return http.Response(
            sessionJson(linked),
            200,
            request: request,
            headers: jsonHeaders,
          );
        }
        return null;
      });

      await client.auth.signInAnonymously();
      expect(client.auth.currentUser?.isAnonymous, isTrue);

      final user = await SupabaseService.signInWithIdTokenOn(
        client.auth,
        provider: OAuthProvider.google,
        idToken: 'google-id-token',
      );

      expect(
        user?.id,
        'anon-1',
        reason: 'the UUID must not change — it carries the guest\'s progress',
      );
      final grants = log.where(isIdTokenGrant).toList();
      expect(grants, hasLength(1), reason: 'link only — no fallback needed');
      expect(isLink(grants.single), isTrue);
      expect(
        (jsonDecode(grants.single.body) as Map<String, dynamic>)['id_token'],
        'google-id-token',
      );
    });

    test(
      'an identity already on another account falls back to signing into it',
      () async {
        final anon = userJson(id: 'anon-1', anonymous: true);
        final owner = userJson(
          id: 'owner-1',
          email: 'user@gmail.com',
          anonymous: false,
        );
        final log = <http.Request>[];
        final client = buildClient(log, (request) {
          if (request.url.path.endsWith('/auth/v1/signup')) {
            return http.Response(
              sessionJson(anon),
              200,
              request: request,
              headers: jsonHeaders,
            );
          }
          if (isLink(request)) {
            return http.Response(
              jsonEncode({
                'error_code': 'identity_already_exists',
                'msg': 'Identity is already linked to another user',
              }),
              422,
              request: request,
              headers: jsonHeaders,
            );
          }
          if (isIdTokenGrant(request)) {
            return http.Response(
              sessionJson(owner),
              200,
              request: request,
              headers: jsonHeaders,
            );
          }
          return null;
        });

        await client.auth.signInAnonymously();

        final user = await SupabaseService.signInWithIdTokenOn(
          client.auth,
          provider: OAuthProvider.google,
          idToken: 'google-id-token',
        );

        expect(
          user?.id,
          'owner-1',
          reason: 'the existing account wins — this is a "sign back in"',
        );
        expect(client.auth.currentUser?.id, 'owner-1');
        final grants = log.where(isIdTokenGrant).toList();
        expect(grants, hasLength(2), reason: 'link attempt, then sign-in');
        expect(isLink(grants.first), isTrue);
        expect(isLink(grants.last), isFalse);
      },
    );

    test(
      'with no session a plain sign-in runs directly — no link attempt',
      () async {
        final owner = userJson(
          id: 'owner-1',
          email: 'user@gmail.com',
          anonymous: false,
        );
        final log = <http.Request>[];
        final client = buildClient(log, (request) {
          if (isIdTokenGrant(request)) {
            return http.Response(
              sessionJson(owner),
              200,
              request: request,
              headers: jsonHeaders,
            );
          }
          return null;
        });

        final user = await SupabaseService.signInWithIdTokenOn(
          client.auth,
          provider: OAuthProvider.google,
          idToken: 'google-id-token',
        );

        expect(user?.id, 'owner-1');
        final grants = log.where(isIdTokenGrant).toList();
        expect(grants, hasLength(1));
        expect(isLink(grants.single), isFalse);
      },
    );
  });

  group('signOut', () {
    test(
      'a failed server revocation falls back to local — never throws',
      () async {
        final anon = userJson(id: 'anon-1', anonymous: true);
        final log = <http.Request>[];
        final client = buildClient(log, (request) {
          if (request.url.path.endsWith('/auth/v1/signup')) {
            return http.Response(
              sessionJson(anon),
              200,
              request: request,
              headers: jsonHeaders,
            );
          }
          if (request.url.path.endsWith('/auth/v1/logout')) {
            // Offline / server error: the global revocation cannot complete.
            return http.Response(
              '{"error":"unreachable"}',
              500,
              request: request,
              headers: jsonHeaders,
            );
          }
          return null;
        });

        await client.auth.signInAnonymously();
        expect(client.auth.currentSession, isNotNull);

        // Must complete without throwing, leaving the device signed out.
        await SupabaseService.signOutOn(client.auth);
        expect(client.auth.currentSession, isNull);
      },
    );

    test('the happy path signs out with a single server revocation', () async {
      final anon = userJson(id: 'anon-1', anonymous: true);
      final log = <http.Request>[];
      final client = buildClient(log, (request) {
        if (request.url.path.endsWith('/auth/v1/signup')) {
          return http.Response(
            sessionJson(anon),
            200,
            request: request,
            headers: jsonHeaders,
          );
        }
        if (request.url.path.endsWith('/auth/v1/logout')) {
          return http.Response('', 204, request: request, headers: jsonHeaders);
        }
        return null;
      });

      await client.auth.signInAnonymously();
      await SupabaseService.signOutOn(client.auth);

      expect(client.auth.currentSession, isNull);
      expect(
        log.where((r) => r.url.path.endsWith('/auth/v1/logout')).length,
        1,
      );
    });
  });
}
