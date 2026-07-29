import 'dart:async' show unawaited;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/locale/app_locale.dart' show kLocalePrefKey;
import 'supabase_service.dart';

/// SharedPreferences key holding this install's pseudonymous analytics id.
/// Minted once on first launch and never rotated, so funnels can be stitched
/// together BEFORE any Supabase session exists (onboarding runs pre-sign-in).
const String kInstallIdPrefKey = 'analytics_install_id';

/// Centralised product-analytics facade, mirroring [Monitoring]'s shape: the
/// rest of the app only ever calls `Analytics.log(...)` so the backend can be
/// swapped (or a second sink added) in one file.
///
/// Events land in the first-party `app_events` table via the Supabase client —
/// no extra SDK, no new privacy-policy vendor. The table is append-only for
/// client roles (insert-only RLS; reads are server-side), and rows carry the
/// pseudonymous [kInstallIdPrefKey] UUID plus the Supabase user id when a
/// session exists (null during onboarding).
///
/// Every call is fire-and-forget and swallow-on-error: analytics must never
/// block or break a user flow, and a dropped event on a flaky network is an
/// acceptable loss. Without Supabase configured (dev / mock mode) events are
/// just printed.
class Analytics {
  Analytics._();

  static SharedPreferences? _prefs;
  static String? _installId;

  /// Resolves (or mints) the install id. Called once from `main()` right after
  /// SharedPreferences is available; synchronous so it can't delay startup.
  static void init(SharedPreferences prefs) {
    _prefs = prefs;
    final existing = prefs.getString(kInstallIdPrefKey);
    if (existing != null) {
      _installId = existing;
      return;
    }
    final minted = _uuidV4();
    _installId = minted;
    // Fire-and-forget: a failed persist just means a fresh id next launch.
    unawaited(prefs.setString(kInstallIdPrefKey, minted));
  }

  /// Records one product event, optionally with a small property map (kept
  /// lean — the server caps the jsonb at 2 KB). Safe to call from anywhere,
  /// anytime: no-ops without [init] or Supabase, never throws, never awaited.
  static void log(String event, [Map<String, Object?> properties = const {}]) {
    unawaited(tryLog(event, properties));
  }

  /// Same as [log] but reports whether the insert actually landed. Still never
  /// throws. For the rare events that must not be lost (e.g. the one-shot
  /// `install_attributed` from [InstallReferrerService]) the caller can retry
  /// on a later launch until this returns true; everything else should keep
  /// using the fire-and-forget [log].
  static Future<bool> tryLog(
    String event, [
    Map<String, Object?> properties = const {},
  ]) async {
    final installId = _installId;
    if (installId == null || !SupabaseService.isInitialised) {
      debugPrint('Analytics (not sent): $event $properties');
      return false;
    }

    final row = <String, Object?>{
      'install_id': installId,
      'user_id': SupabaseService.currentUser?.id,
      'event': event,
      if (properties.isNotEmpty) 'properties': properties,
      // The persisted UI language (device-detected on first launch may not be
      // stamped yet — null then), so funnels can be split per locale.
      'app_locale': _prefs?.getString(kLocalePrefKey),
    };

    try {
      await SupabaseService.client.from('app_events').insert(row);
      return true;
    } catch (e) {
      // Losing an event (offline, RLS hiccup) is fine; losing the user's
      // flow over analytics is not.
      debugPrint('Analytics.log("$event") failed: $e');
      return false;
    }
  }

  /// Random (version 4) UUID from a CSPRNG — matches the `uuid` column type
  /// server-side without pulling in a package for one id.
  static String _uuidV4() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
