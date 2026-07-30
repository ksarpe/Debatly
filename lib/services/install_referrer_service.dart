import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:play_install_referrer/play_install_referrer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'analytics.dart';

/// SharedPreferences flag set once the `install_attributed` event has landed
/// in `app_events` — the whole service is a no-op from then on.
const String kReferrerLoggedPrefKey = 'install_referrer_logged';

/// SharedPreferences key caching the event properties between launches, so the
/// referrer is READ from Play exactly once but DELIVERED at-least-once (a
/// first launch with no network must not lose the attribution forever).
const String kReferrerPayloadPrefKey = 'install_referrer_payload';

/// SharedPreferences counter of failed referrer reads across launches.
const String kReferrerAttemptsPrefKey = 'install_referrer_attempts';

/// One-shot install attribution via the Play Install Referrer API.
///
/// Play Console only counts installs; the `referrer` parameter of the store
/// link (`utm_source=...`) also reaches the app itself through the Install
/// Referrer API. This service reads it on first launch and logs it as a single
/// `install_attributed` event to `app_events`, keyed by the same install id as
/// every other analytics event — so one SQL join answers what Play Console
/// can't: do installs from a given source finish onboarding, vote, or buy
/// premium? (See the `acquisition_funnel` view.)
///
/// Delivery contract:
///   * The referrer is FETCHED at most [kMaxFetchAttempts] times (once per
///     launch), then cached — Google recommends reading it once, and it
///     expires 90 days after install anyway. A device without Play services
///     (sideload, emulator) burns its attempts and is recorded as
///     `status: unavailable`, so every install still gets exactly one row.
///   * The event is SENT at-least-once: the cached payload is retried on every
///     launch until one insert is confirmed, then the flag stops everything.
///     (A confirmed-but-lost response can duplicate the row; the funnel view
///     counts `distinct install_id`, so duplicates are harmless.)
///   * Never throws, never blocks the UI — it runs from the post-`runApp`
///     background phase of startup, and the platform-channel read carries its
///     own timeout (an R8-stripped native handler must not hang the service;
///     see the Play Install Referrer keep in proguard-rules.pro).
///
/// Existing installs updating to this build also log one row (the API keeps
/// returning the original referrer within its 90-day window); their event
/// `created_at` is the update day, while `install_begin_ts` in the properties
/// holds the true install time.
class InstallReferrerService {
  InstallReferrerService._();

  /// Launches worth of failed reads before giving up and recording the install
  /// as unattributable.
  static const int kMaxFetchAttempts = 3;

  /// Bound on the platform-channel read, mirroring [kInitTimeout]'s rationale:
  /// a stripped/hung native handler never replies on its own.
  static const Duration _fetchTimeout = Duration(seconds: 8);

  /// Reads the referrer (or the cached payload from a previous launch) and
  /// logs `install_attributed`, honouring the delivery contract above.
  ///
  /// [fetch] and [send] exist for tests only; production callers pass none.
  static Future<void> reportIfNeeded(
    SharedPreferences prefs, {
    Future<ReferrerDetails> Function()? fetch,
    Future<bool> Function(String event, Map<String, Object?> properties)? send,
  }) async {
    if (prefs.getBool(kReferrerLoggedPrefKey) ?? false) return;
    // The Install Referrer API is a Play-store concept — nothing to read on
    // iOS (the plugin throws there by design), so don't burn attempts on it.
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    var properties = _cachedProperties(prefs);
    if (properties == null) {
      try {
        final details = await (fetch ?? _fetchFromPlay)().timeout(
          _fetchTimeout,
        );
        properties = propertiesFrom(details);
      } catch (e) {
        final attempts = (prefs.getInt(kReferrerAttemptsPrefKey) ?? 0) + 1;
        if (attempts < kMaxFetchAttempts) {
          debugPrint(
            'InstallReferrer: read failed (attempt $attempts/'
            '$kMaxFetchAttempts), retrying next launch — $e',
          );
          await prefs.setInt(kReferrerAttemptsPrefKey, attempts);
          return;
        }
        // Definitive: no Play services / sideload / broken channel. Record the
        // install anyway so the funnel has a row for it, with the reason.
        properties = <String, Object?>{
          'status': 'unavailable',
          'error': _truncate('$e', 200),
        };
      }
      await prefs.setString(kReferrerPayloadPrefKey, jsonEncode(properties));
    }

    final Future<bool> Function(String, Map<String, Object?>) deliver =
        send ?? Analytics.tryLog;
    final sent = await deliver('install_attributed', properties);
    if (!sent) return; // offline / Supabase down — cached payload retries.

    await prefs.setBool(kReferrerLoggedPrefKey, true);
    await prefs.remove(kReferrerPayloadPrefKey);
    await prefs.remove(kReferrerAttemptsPrefKey);
  }

  static Future<ReferrerDetails> _fetchFromPlay() =>
      PlayInstallReferrer.installReferrer;

  /// Maps the raw [ReferrerDetails] to lean event properties (the server caps
  /// the jsonb at 2 KB, hence the truncations). Organic Play installs come
  /// through as `utm_source=google-play&utm_medium=organic`, so a null
  /// `utm_source` in SQL means "referrer present but not UTM-tagged".
  @visibleForTesting
  static Map<String, Object?> propertiesFrom(ReferrerDetails details) {
    final raw = details.installReferrer;
    return <String, Object?>{
      'status': 'ok',
      if (raw != null && raw.isNotEmpty) 'referrer': _truncate(raw, 600),
      ...parseUtm(raw),
      'referrer_click_ts': details.referrerClickTimestampSeconds,
      'install_begin_ts': details.installBeginTimestampSeconds,
      'install_version': ?details.installVersion,
      if (details.googlePlayInstantParam) 'google_play_instant': true,
    };
  }

  /// Extracts the five standard `utm_*` parameters from the referrer string.
  /// Tolerates the referrer arriving URL-encoded one level too deep
  /// (`utm_source%3Dtiktok%26...` — common when the store link was built by
  /// hand) and never throws on garbage: no UTMs is a valid outcome.
  @visibleForTesting
  static Map<String, String> parseUtm(String? raw) {
    if (raw == null || raw.isEmpty) return const {};

    final direct = _utmFrom(_splitQuery(raw));
    if (direct.isNotEmpty) return direct;

    // A doubly-encoded referrer collapses into ONE decoded mega-key with no
    // value ({'utm_source=tiktok&…': ''}), so "did we extract anything" — not
    // the raw shape — is what decides whether to decode a level and retry.
    try {
      final decoded = Uri.decodeComponent(raw);
      if (decoded != raw) return _utmFrom(_splitQuery(decoded));
    } on ArgumentError {
      // Malformed percent-escapes — nothing more to be extracted.
    }
    return direct;
  }

  static Map<String, String> _splitQuery(String source) {
    try {
      return Uri.splitQueryString(source);
    } catch (_) {
      return const {}; // Undecodable garbage is a valid (empty) referrer.
    }
  }

  static Map<String, String> _utmFrom(Map<String, String> query) {
    const keys = [
      'utm_source',
      'utm_medium',
      'utm_campaign',
      'utm_term',
      'utm_content',
    ];
    return <String, String>{
      for (final key in keys)
        if (query[key] case final value? when value.isNotEmpty)
          key: _truncate(value, 200),
    };
  }

  /// The payload cached by a previous launch whose insert didn't go through,
  /// or null when there is none (or it doesn't decode — then it's dropped so
  /// the next launch re-reads the referrer instead of looping on bad data).
  static Map<String, Object?>? _cachedProperties(SharedPreferences prefs) {
    final cached = prefs.getString(kReferrerPayloadPrefKey);
    if (cached == null) return null;
    try {
      return (jsonDecode(cached) as Map).cast<String, Object?>();
    } catch (_) {
      unawaited(prefs.remove(kReferrerPayloadPrefKey));
      return null;
    }
  }

  static String _truncate(String value, int max) =>
      value.length <= max ? value : value.substring(0, max);
}
