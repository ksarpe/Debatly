import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debatly/services/supabase_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The auth flows that guard a user's progress and their way out:
///
///  * `signInWithIdToken` (social) — the Google/Apple buttons, which since the
///    sheet went social-only (2026-09-05) are also how an account is CREATED:
///    an anonymous session LINKS the identity in place
///    (`linkIdentityWithIdToken`, same UUID → the guest's streak/votes/PRO
///    survive); only an identity that already belongs to another account
///    falls back to a plain sign-in, switching to that account. Losing the
///    link branch silently orphans every guest who "registers".
///  * `linkIdentityWithIdTokenOn` — Settings' "link Apple / Google" for the
///    legacy email/password accounts: the same in-place link onto a
///    signed-in, NON-anonymous user, with NO sign-in fallback — a refused link
///    must never quietly switch an account holder onto someone else's account.
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

  group('linkIdentityWithIdTokenOn (Settings: link Apple / Google)', () {
    bool isIdTokenGrant(http.Request r) =>
        r.url.path.endsWith('/auth/v1/token') &&
        r.url.queryParameters['grant_type'] == 'id_token';
    bool isLink(http.Request r) =>
        isIdTokenGrant(r) &&
        (jsonDecode(r.body) as Map<String, dynamic>)['link_identity'] == true;
    bool isPasswordGrant(http.Request r) =>
        r.url.path.endsWith('/auth/v1/token') &&
        r.url.queryParameters['grant_type'] == 'password';

    test('a signed-in email account gains the identity in place — same UUID, '
        'never a plain sign-in', () async {
      final owner = userJson(
        id: 'owner-1',
        email: 'user@gmail.com',
        anonymous: false,
      );
      final linked = userJson(
        id: 'owner-1',
        email: 'user@gmail.com',
        anonymous: false,
      );
      final log = <http.Request>[];
      final client = buildClient(log, (request) {
        if (isPasswordGrant(request)) {
          return http.Response(
            sessionJson(owner),
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

      await client.auth.signInWithPassword(
        email: 'user@gmail.com',
        password: 'secret123',
      );
      expect(client.auth.currentUser?.isAnonymous, isFalse);

      final user = await SupabaseService.linkIdentityWithIdTokenOn(
        client.auth,
        provider: OAuthProvider.google,
        idToken: 'google-id-token',
      );

      expect(user?.id, 'owner-1', reason: 'the account is kept, not swapped');
      final grants = log.where(isIdTokenGrant).toList();
      expect(grants, hasLength(1));
      expect(isLink(grants.single), isTrue);
    });

    test(
      'an identity owned by another account is REFUSED — no sign-in fallback',
      () async {
        final owner = userJson(
          id: 'owner-1',
          email: 'user@outlook.com',
          anonymous: false,
        );
        final log = <http.Request>[];
        final client = buildClient(log, (request) {
          if (isPasswordGrant(request)) {
            return http.Response(
              sessionJson(owner),
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
          return null;
        });

        await client.auth.signInWithPassword(
          email: 'user@outlook.com',
          password: 'secret123',
        );

        Object? thrown;
        try {
          await SupabaseService.linkIdentityWithIdTokenOn(
            client.auth,
            provider: OAuthProvider.google,
            idToken: 'google-id-token',
          );
        } catch (e) {
          thrown = e;
        }

        expect(thrown, isA<AuthException>());
        expect(
          SupabaseService.isIdentityAlreadyLinked(thrown!),
          isTrue,
          reason: 'the sheet explains this one specifically',
        );
        expect(
          client.auth.currentUser?.id,
          'owner-1',
          reason: 'the account holder stays on their own account',
        );
        final grants = log.where(isIdTokenGrant).toList();
        expect(
          grants,
          hasLength(1),
          reason: 'the link attempt and nothing else',
        );
        expect(isLink(grants.single), isTrue);
      },
    );

    test('with no session there is nothing to link into', () async {
      final client = buildClient(<http.Request>[], (_) => null);
      expect(
        () => SupabaseService.linkIdentityWithIdTokenOn(
          client.auth,
          provider: OAuthProvider.apple,
          idToken: 'apple-id-token',
        ),
        throwsStateError,
      );
    });
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

  group('deleteAccount', () {
    // Which failures may clear the on-device session. A guest's anonymous UUID
    // is their ONLY identity — there are no credentials to sign back in with —
    // so clearing it after a delete that did NOT happen orphans their streak,
    // votes, favourites and profile for good. Deletion is offered to guests,
    // who are most of the install base, which is what makes this rule load-
    // bearing rather than tidy.
    test(
      'a refusal the server SPOKE is unambiguous — the account still lives',
      () {
        for (final status in [400, 401, 403, 500]) {
          expect(
            SupabaseService.deleteOutcomeIsAmbiguous(
              FunctionException(status: status),
            ),
            isFalse,
            reason: 'HTTP $status is an answer, not a lost response',
          );
        }
      },
    );

    test(
      'a lost or unreadable response is ambiguous — the delete may have run',
      () {
        final unknown = <Object>[
          TimeoutException('no response'),
          const SocketException('connection closed'),
          Exception('Account deletion did not complete.'),
        ];
        for (final error in unknown) {
          expect(
            SupabaseService.deleteOutcomeIsAmbiguous(error),
            isTrue,
            reason: '$error leaves the fate of the account unknown',
          );
        }
      },
    );
  });
}
