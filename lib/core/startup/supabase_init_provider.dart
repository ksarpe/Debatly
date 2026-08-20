import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/supabase_service.dart';

/// The backend-availability signal, as a provider so the UI rebuilds on it.
///
/// Exists because the answer is not static. It starts as whatever
/// `main()`'s init left behind, but a client that came up LATE — after
/// [SupabaseService.initialise] gave up waiting on it — flips this to
/// [SupabaseInitStatus.ready] on its own, and the error state's retry can
/// re-run the init through [SupabaseInitNotifier.retry]. Everything that used
/// to ask `SupabaseService.isInitialised` once, at first build, and then live
/// with the answer forever should watch this instead.
final supabaseInitProvider =
    NotifierProvider<SupabaseInitNotifier, SupabaseInitStatus>(
      SupabaseInitNotifier.new,
    );

class SupabaseInitNotifier extends Notifier<SupabaseInitStatus> {
  @override
  SupabaseInitStatus build() {
    final listener = SupabaseService.addStatusListener(() {
      state = SupabaseService.status;
    });
    ref.onDispose(() => SupabaseService.removeStatusListener(listener));
    return SupabaseService.status;
  }

  /// Re-attempts the init — what the error state's retry button runs.
  ///
  /// Waits on the original attempt rather than starting a new one (see
  /// `SupabaseService._initFuture`). After a timeout that is usually quick and
  /// usually succeeds: the first attempt was still running and just needed
  /// longer. After a genuine failure it reports failure again — deliberately,
  /// because the SDK will not redo the session restore, and reporting success
  /// there would hand the user a fresh anonymous account in place of their own.
  Future<void> retry() async {
    state = await SupabaseService.initialise();
  }
}
