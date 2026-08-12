import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/providers/session_providers.dart';

/// Tester accounts that see the DEV section in settings even in RELEASE builds
/// (TestFlight / internal testing). Lowercase e-mails only — the check
/// lowercases the signed-in address before comparing.
///
/// Store builds ship with this list too, so keep it to trusted testers: anyone
/// signing in with a listed e-mail gets the DEV tools. The tools only preview
/// UI and pin questions locally — no server-side privileges are attached.
const Set<String> kDevToolsTesterEmails = {
  '229kasper@gmail.com',
  'justkasperr@gmail.com',
  'kasper@aknsoftware.com',
  'alicjaszcz00@wp.pl',
  'janowskicorp@gmail.com',
};

/// Whether the DEV section in settings is visible.
///
/// True in any debug build, in builds compiled with
/// `--dart-define=DEV_TOOLS=true` (e.g. a dedicated TestFlight build where every
/// tester should see the tools without signing in to a listed account), or when
/// the signed-in e-mail is in [kDevToolsTesterEmails].
final devToolsEnabledProvider = Provider<bool>((ref) {
  if (kDebugMode) return true;
  if (const bool.fromEnvironment('DEV_TOOLS')) return true;
  final email = ref
      .watch(sessionProvider.select((s) => s.value?.email))
      ?.toLowerCase();
  return email != null && kDevToolsTesterEmails.contains(email);
});
