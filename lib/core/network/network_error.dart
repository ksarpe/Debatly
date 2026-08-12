import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart'
    show FunctionException, PostgrestException;

/// Whether [error] looks like a loss of connectivity rather than a genuine
/// server-side rejection.
///
/// We classify transport-level failures — no socket, a DNS lookup that fails, a
/// timeout, a dropped HTTP connection — as "offline" so callers can fall back to
/// the local cache and the UI can show a calm "you're offline" message instead
/// of surfacing a raw `PostgrestException` / `ClientException`.
///
/// A real 4xx/5xx the server actually returned is deliberately NOT offline: the
/// request reached the backend, so the caller should treat it as a true error
/// (it carries a status/code, and its text won't match the transport keywords
/// below). When in doubt we err towards "not offline" so genuine errors are
/// never silently masked by stale cache.
bool isOfflineError(Object error) {
  if (error is SocketException) return true;
  if (error is TimeoutException) return true;
  if (error is HttpException) return true;

  // A typed PostgREST / edge-function error means the server actually
  // responded — the supabase clients rethrow transport failures raw and only
  // construct these from an HTTP response. Decide BEFORE the keyword scan: a
  // server-side "canceling statement due to statement timeout" (or a message
  // containing "retryable") would otherwise match below and be masked by cache.
  if (error is PostgrestException) return false;
  if (error is FunctionException) return false;

  // supabase_flutter surfaces transport failures as a `ClientException` from
  // package:http (and gotrue's `AuthRetryableFetchException`), neither of which
  // we want to depend on by type. Matching the message keeps this resilient
  // across package versions and covers both the dart:io and web (XHR) wordings.
  final text = error.toString().toLowerCase();
  return text.contains('socketexception') ||
      text.contains('clientexception') ||
      text.contains('failed host lookup') ||
      text.contains('connection closed') ||
      text.contains('connection refused') ||
      text.contains('connection reset') ||
      text.contains('connection terminated') ||
      text.contains('connection attempt failed') ||
      text.contains('software caused connection abort') ||
      text.contains('network is unreachable') ||
      text.contains('no address associated with hostname') ||
      text.contains('xmlhttprequest') ||
      text.contains('retryable') ||
      text.contains('timeout') ||
      text.contains('timed out');
}
