import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/startup/supabase_init_provider.dart';
import '../../../services/supabase_service.dart';

/// The force-update gate (v2.1.0+): compares the installed app's SEMANTIC
/// version (pubspec `version:` — NOT the Codemagic build counter, which
/// auto-increments and is nothing the owner tracks) against the server's
/// `app_update_gate.min_version` for this platform. Older → [HomeGate] swaps
/// the feed for the blocking update screen.
///
/// FAIL-OPEN everywhere: mock mode, a backend that is down, an RPC error, an
/// unparsable version — the app simply runs. Being locked out by a network
/// blip would be strictly worse than any stale build; the gate exists for the
/// owner to retire versions deliberately, not for the network to do it by
/// accident.

/// The installed build's version name, e.g. '2.1.0'. Empty string when the
/// platform plugin is unavailable (widget tests) — [isVersionBelow] reads
/// that as unparsable and fails open. Never throws: under Riverpod 3 a
/// throwing provider is retried with backoff, which would leave the gate
/// check hanging instead of failing open.
final currentAppVersionProvider = FutureProvider<String>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  } catch (_) {
    return '';
  }
});

/// The minimum version the backend still supports for THIS platform, or null
/// when there is no gate to consult (mock mode, backend down, RPC failure).
final minSupportedVersionProvider = FutureProvider<String?>((ref) async {
  // Watching the status (not reading) makes the gate re-check when a backend
  // that came up late flips to ready — same pattern as the session reload.
  if (ref.watch(supabaseInitProvider) != SupabaseInitStatus.ready) return null;
  final platform = defaultTargetPlatform == TargetPlatform.iOS
      ? 'ios'
      : 'android';
  return SupabaseService.fetchMinSupportedVersion(platform);
});

/// True when this build is below the server's minimum and must update.
final updateRequiredProvider = FutureProvider<bool>((ref) async {
  try {
    final min = await ref.watch(minSupportedVersionProvider.future);
    if (min == null) return false;
    final current = await ref.watch(currentAppVersionProvider.future);
    return isVersionBelow(current, min);
  } catch (_) {
    // Includes PackageInfo being unavailable (widget tests) — fail open.
    return false;
  }
});

/// Numeric dotted-version comparison: true only when [current] < [min].
///
/// Segments compare as integers ('2.10.0' > '2.9.0'); a missing segment is 0
/// ('2.1' == '2.1.0'); trailing junk inside a segment is ignored past its
/// leading digits ('2.1.0-beta' → 2.1.0). Anything unparsable — on either
/// side — fails OPEN (false): a typo in the gate row must never brick every
/// install in the field.
bool isVersionBelow(String current, String min) {
  List<int>? parse(String v) {
    final nums = <int>[];
    for (final part in v.trim().split('.')) {
      final digits = RegExp(r'^\d+').firstMatch(part.trim());
      if (digits == null) break;
      nums.add(int.parse(digits.group(0)!));
    }
    return nums.isEmpty ? null : nums;
  }

  final c = parse(current);
  final m = parse(min);
  if (c == null || m == null) return false;
  final len = c.length > m.length ? c.length : m.length;
  for (var i = 0; i < len; i++) {
    final a = i < c.length ? c[i] : 0;
    final b = i < m.length ? m[i] : 0;
    if (a != b) return a < b;
  }
  return false;
}
