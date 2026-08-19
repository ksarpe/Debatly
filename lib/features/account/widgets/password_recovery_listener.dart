import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/feedback/app_toast.dart';
import '../../../core/locale/l10n_extension.dart';
import '../../../core/monitoring/monitoring.dart';
import '../../../services/supabase_service.dart';
import '../screens/set_new_password_screen.dart';

/// Turns a tapped password-reset link into the "set a new password" sheet.
///
/// The chain: the mail points at a deep link
/// ([AppConfig.passwordResetRedirectUrl]) → the OS hands it to the app →
/// `supabase_flutter`'s own deep-link observer redeems the `code` → gotrue
/// emits [AuthChangeEvent.passwordRecovery]. Nothing in that chain shows any
/// UI, so without this widget the user lands on the feed, silently signed in,
/// with no way to type the new password they were promised.
///
/// Wraps the app's first widget rather than living on a screen because the link
/// can arrive at ANY moment — including a cold start, where it is delivered
/// while the splash is still up.
class PasswordRecoveryListener extends StatefulWidget {
  const PasswordRecoveryListener({super.key, required this.child});

  final Widget child;

  @override
  State<PasswordRecoveryListener> createState() =>
      _PasswordRecoveryListenerState();
}

class _PasswordRecoveryListenerState extends State<PasswordRecoveryListener> {
  StreamSubscription<AuthState>? _sub;

  /// One sheet at a time. `onAuthStateChange` is a BehaviorSubject, so a late or
  /// re-established subscription replays the last event — which is what makes
  /// the cold-start case work, and what would otherwise re-open the sheet.
  bool _sheetOpen = false;

  @override
  void initState() {
    super.initState();
    if (!SupabaseService.isInitialised) return;
    _sub = SupabaseService.client.auth.onAuthStateChange.listen(
      (state) {
        if (state.event != AuthChangeEvent.passwordRecovery) return;
        _open();
      },
      // A link that expired, was already used, or whose PKCE verifier belongs to
      // another install surfaces here (the SDK reports it, then does nothing).
      // Saying so beats a tap that visibly achieves nothing.
      onError: (Object error) {
        Monitoring.addBreadcrumb(
          'Password recovery deep link rejected',
          category: 'auth',
        );
        if (!mounted) return;
        AppToast.error(context, context.l10n.authRecoveryLinkInvalid);
      },
    );
  }

  void _open() {
    if (_sheetOpen || !mounted) return;
    _sheetOpen = true;
    Monitoring.addBreadcrumb(
      'Password recovery sheet opened',
      category: 'auth',
    );
    // The event can land mid-frame (and mid-splash on a cold start); pushing a
    // route from inside a build is illegal, so wait for the frame to settle.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _sheetOpen = false;
        return;
      }
      try {
        await showSetNewPasswordSheet(context);
      } finally {
        _sheetOpen = false;
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
