import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/network/network_error.dart';

/// Localises what an auth flow can realistically get back from GoTrue — shared
/// by the sign-in sheet and the "link Apple / Google" sheet so the two never
/// drift apart on the same error code.
///
/// Offline is checked FIRST: gotrue wraps a dropped connection in an
/// `AuthException` subclass whose message is a raw `SocketException` /
/// "Failed host lookup" dump, so without this an airplane-mode tap showed a
/// Polish user an English stack-trace fragment. An unrecognised code still
/// falls back to the server's message — more actionable than a mute failure.
String authErrorText(BuildContext context, Object error) {
  final l10n = context.l10n;
  if (isOfflineError(error)) return l10n.noConnection;
  // Not from GoTrue at all — a GoogleSignInException, a
  // SignInWithAppleAuthorizationException, a StateError from a build with no
  // keys. Their `toString()` is developer text ("Bad state: ...") and used to
  // go straight into a Polish user's toast.
  if (error is! AuthException) return l10n.authErrorGeneric;
  return switch (error.code) {
    'invalid_credentials' => l10n.authErrorInvalidCredentials,
    'email_not_confirmed' => l10n.authErrorEmailNotConfirmed,
    'validation_failed' => l10n.authEnterValidEmail,
    'over_request_rate_limit' ||
    'over_email_send_rate_limit' => l10n.authErrorTooManyRequests,
    _ => error.message,
  };
}
