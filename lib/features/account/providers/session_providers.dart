import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/locale/app_locale.dart';
import '../../../core/monitoring/monitoring.dart';
import '../../../services/purchases_service.dart';
import '../../../services/supabase_service.dart';

/// Whether [event] is an OUT-OF-BAND identity change the session must converge
/// on by reloading. A silent sign-out (a refresh-token failure / server-side
/// revocation) and an anonymous→email upgrade (`userUpdated`) both change who we
/// are; the initial session, a plain `signedIn`, and a token refresh carry no
/// identity change to act on and are deliberately ignored.
///
/// Extracted from [SessionNotifier] so the "which events trip a reload" rule —
/// easy to widen by accident into a reload storm — is pinned by a unit test.
@visibleForTesting
bool isIdentityChangingAuthEvent(AuthChangeEvent event) =>
    event == AuthChangeEvent.signedOut || event == AuthChangeEvent.userUpdated;

/// Resolves the EFFECTIVE premium flag from the three sources in strict
/// precedence: the reconciled store↔DB sync wins; else the raw profile flag (so
/// a promotional / admin grant with no purchase behind it still unlocks); else
/// the on-device store cache (only reached with no backend at all).
///
/// The sources are LAZY thunks, not values, so the short-circuit is preserved —
/// a successful [sync] must NOT fire [profile] or [store] (each is a network /
/// SDK call). Extracted so both the order and that no-redundant-call guarantee
/// are unit-tested without standing up the whole static service layer.
@visibleForTesting
Future<bool> resolveEffectivePremium({
  required Future<bool?> Function() sync,
  required Future<bool?> Function() profile,
  required Future<bool> Function() store,
}) async => await sync() ?? await profile() ?? await store();

/// Immutable snapshot of who the current user is and what they're entitled to.
///
/// [userId] is the Supabase anonymous UUID (null until silent sign-in resolves,
/// or in mock mode). [isPremium] reflects the active RevenueCat entitlement.
class SessionState {
  const SessionState({
    this.userId,
    this.email,
    this.displayName,
    this.createdAt,
    this.isAnonymous,
    this.isPremium = false,
  });

  final String? userId;
  final String? email;

  /// Human name from the auth provider (e.g. Google `full_name`), when present.
  /// Email/password accounts have none — the UI falls back to the email handle.
  final String? displayName;

  /// When the account was created — drives the "member since" badge.
  final DateTime? createdAt;

  final bool? isAnonymous;
  final bool isPremium;

  bool get isSignedIn => userId != null;
  bool get hasAccount => isSignedIn && isAnonymous != true;

  SessionState copyWith({
    String? userId,
    String? email,
    String? displayName,
    DateTime? createdAt,
    bool? isAnonymous,
    bool? isPremium,
  }) => SessionState(
    userId: userId ?? this.userId,
    email: email ?? this.email,
    displayName: displayName ?? this.displayName,
    createdAt: createdAt ?? this.createdAt,
    isAnonymous: isAnonymous ?? this.isAnonymous,
    isPremium: isPremium ?? this.isPremium,
  );
}

/// Owns the user session: silent anonymous auth on launch plus the premium
/// entitlement that gates the swipe.
///
/// Built lazily the first time something reads [sessionProvider]; the app reads
/// it at launch (see `QuestionScreen`) so anonymous sign-in happens up front.
class SessionNotifier extends AsyncNotifier<SessionState> {
  /// True while an IN-APP sign-out (Settings) drives its own reload, so the auth
  /// listener ignores the `signedOut` event it triggers. Without it the sign-out
  /// would reload twice — once here (awaited so we can leave Settings cleanly)
  /// and once from the listener — and hit the entitlement network on both. An
  /// OUT-OF-BAND sign-out (token revocation) leaves this false and is still
  /// converged by the listener.
  bool _selfDrivenSignOut = false;

  @override
  Future<SessionState> build() {
    _subscribeToAuthChanges();
    _subscribeToEntitlementChanges();
    _subscribeToLocaleChanges();
    return _load();
  }

  /// Keep the server's idea of the user's language in step with the app's, so
  /// the auth emails (`send-auth-email` edge function reads `profiles.locale`)
  /// follow someone who switches language in Settings. Fire-and-forget: the
  /// write is best-effort and must not stall the language switch itself.
  ///
  /// `fireImmediately` is deliberately off — the initial value is written by
  /// [_load] once there is a session to write it against, which on a cold start
  /// does not exist yet.
  void _subscribeToLocaleChanges() {
    ref.listen<Locale>(localeControllerProvider, (_, next) {
      unawaited(SupabaseService.syncProfileLocale(next.languageCode));
    });
  }

  /// Keep `isPremium` live when the entitlement changes OUTSIDE the in-app
  /// paywall — a renewal, an expiry, or a restore on another device. Without
  /// this the session reads premium once at launch and only `refresh()` (called
  /// after an in-app purchase) updates it, so an entitlement that lapses or is
  /// restored elsewhere is invisible until the app is killed and relaunched.
  /// Guarded on a real change so RevenueCat's immediate replay (and repeat
  /// pushes of identical info) don't trigger redundant reloads.
  void _subscribeToEntitlementChanges() {
    final listener = PurchasesService.addPremiumListener((isPremium) {
      if (state.hasValue && state.value!.isPremium != isPremium) refresh();
    });
    ref.onDispose(() => PurchasesService.removePremiumListener(listener));
  }

  /// Converge the app on the real identity whenever Supabase changes it OUTSIDE
  /// an in-app action — a refresh-token failure / server-side revocation fires
  /// `signedOut`, and an anonymous→email upgrade fires `userUpdated`. Without
  /// this the session is loaded once and a silent sign-out leaves a zombie UI
  /// (stale userId, every RPC 401-ing) recoverable only by an app restart.
  ///
  /// We reload via [refresh] (no loading flash) rather than `invalidateSelf` so
  /// the QuestionScreen identity listener isn't tripped by a transient null. A
  /// `signedOut` reload re-runs `ensureSignedIn`, minting a fresh guest so the
  /// app is never left sign-in-less. The initial-session / signedIn / token
  /// refresh events are ignored (no identity change to act on).
  void _subscribeToAuthChanges() {
    if (!SupabaseService.isInitialised) return;
    final sub = SupabaseService.client.auth.onAuthStateChange.listen((data) {
      if (!isIdentityChangingAuthEvent(data.event)) return;
      // An in-app sign-out owns its own reload (see [signOutAndReload]); don't
      // double up on the `signedOut` it emits.
      if (_selfDrivenSignOut && data.event == AuthChangeEvent.signedOut) return;
      refresh();
    });
    ref.onDispose(sub.cancel);
  }

  /// Signs the user out and reloads into a fresh guest, awaited end-to-end.
  ///
  /// The caller (Settings) can therefore leave the screen only once the home
  /// screen behind it already shows the guest — instead of popping onto the
  /// stale signed-in view that then visibly reloads in the background. Owns the
  /// reload itself (suppressing the auth listener's duplicate) so a sign-out
  /// costs exactly one entitlement reconcile, not two.
  Future<void> signOutAndReload() async {
    _selfDrivenSignOut = true;
    try {
      await SupabaseService.signOut();
      await refresh();
    } finally {
      _selfDrivenSignOut = false;
    }
  }

  Future<SessionState> _load() async {
    // 1. Make sure every user — even a brand-new guest — has a stable UUID.
    final userId = await SupabaseService.ensureSignedIn();
    final user = SupabaseService.currentUser;

    // 2. Tie the RevenueCat customer to that same identity, and record the app
    //    language against it. Guests get a locale too, so the value is already
    //    on the profile by the time one upgrades and the first mail goes out.
    if (userId != null) {
      await PurchasesService.identify(userId);
      unawaited(
        SupabaseService.syncProfileLocale(
          ref.read(localeControllerProvider).languageCode,
        ),
      );
    }

    // 3. Resolve the EFFECTIVE premium entitlement. The DATABASE is the source
    // of truth — it merges store subscriptions with promotional/admin grants and
    // the server-side question/smaczki gate enforces that same flag. We first
    // reconcile the STORE side against RevenueCat (sync-entitlement pulls this
    // identity's store entitlement and folds it in) and use the effective flag it
    // returns; this also closes the "bought PRO but see nothing" race before any
    // RPC fetches catalog text. If that call can't run we read the flag straight
    // from the profile, so a promotional grant with no purchase behind it still
    // unlocks the app. Only with no backend at all do we fall back to the
    // on-device RevenueCat cache.
    final isPremium = await resolveEffectivePremium(
      sync: SupabaseService.syncEntitlement,
      profile: SupabaseService.fetchIsPremium,
      store: PurchasesService.isPremium,
    );

    // 4. Pull the display name (social logins only) and the account's creation
    // date for the profile header.
    final metadata = user?.userMetadata;
    final displayName =
        (metadata?['full_name'] ?? metadata?['name']) as String?;
    final createdAt = user != null ? DateTime.tryParse(user.createdAt) : null;

    // Tag every Sentry event with the (pseudonymous) identity + tier, so a crash
    // report says WHO hit it and whether they were premium — without ever sending
    // an email/name. Re-runs on each reload, so a sign-out/switch keeps it fresh.
    await Monitoring.setUser(
      id: userId,
      isPremium: isPremium,
      isAnonymous: user?.isAnonymous ?? false,
    );

    return SessionState(
      userId: userId,
      email: user?.email,
      displayName: displayName,
      createdAt: createdAt,
      isAnonymous: user?.isAnonymous ?? false,
      isPremium: isPremium,
    );
  }

  /// Re-reads the premium entitlement, e.g. immediately after a purchase so the
  /// swipe gate sees the upgrade.
  ///
  /// Deliberately does NOT flip to `AsyncValue.loading()` first. Doing so nulls
  /// out `value` mid-reload, so `userId` momentarily reads null and the
  /// QuestionScreen identity listener fires on the guest→null→guest flicker —
  /// wiping the revealed feed, snapping back to the daily and flashing a
  /// full-screen spinner. That's the "freeze" a guest sees after buying PRO from
  /// the reveal-slot paywall (a logged-in user buys from Settings, so the flicker
  /// hides under that pushed route). Keeping the previous SessionState visible
  /// while `_load` runs means only `isPremium` changes, exactly once.
  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }
}

final sessionProvider = AsyncNotifierProvider<SessionNotifier, SessionState>(
  SessionNotifier.new,
);

/// Convenience: `true` only once the session has resolved to a premium user.
/// Treats the still-loading / errored states as non-premium (free tier).
final isPremiumProvider = Provider<bool>(
  (ref) => ref.watch(sessionProvider).value?.isPremium ?? false,
);

/// Details of the active premium subscription (renewal date, billing store,
/// management deep link) for the Manage-subscription screen. Re-fetched whenever
/// the premium entitlement flips, and only resolves to non-null while premium is
/// active; otherwise the SDK has nothing to report.
final premiumStatusProvider = FutureProvider.autoDispose<PremiumStatus?>((
  ref,
) async {
  if (!ref.watch(isPremiumProvider)) return null;
  return PurchasesService.premiumStatus();
});
