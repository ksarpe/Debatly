import 'dart:async';

/// How long any single Supabase call may hang before it is treated as a failure.
///
/// Generous on purpose — a slow train connection should still succeed, and
/// Supabase RPCs normally answer well under a second. This is not a latency
/// budget; it is the difference between "eventually fails" and "never returns".
///
/// Without it there is no ceiling at all: a captive-portal Wi-Fi, a blocked
/// route or a silently dropped TCP connection produces neither a response nor
/// an error, so the future never completes. Every guard downstream — the cache
/// fallback, the retry, the "you're offline" copy — is reached by an EXCEPTION,
/// so a call that simply never answers reaches none of them and the UI waits
/// forever.
const Duration kNetworkCallTimeout = Duration(seconds: 15);

extension NetworkTimeout<T> on Future<T> {
  /// Fails this call with a [TimeoutException] once [kNetworkCallTimeout] is up.
  ///
  /// [TimeoutException] is deliberately classified as offline by
  /// `isOfflineError`, so a timed-out read falls back to the cache and shows the
  /// calm "no connection" line rather than a technical error — the same
  /// treatment a dropped socket already gets.
  Future<T> withNetworkTimeout() => timeout(kNetworkCallTimeout);
}
