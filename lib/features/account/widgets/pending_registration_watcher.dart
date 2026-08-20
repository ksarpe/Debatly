import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feedback/app_toast.dart';
import '../../../core/locale/l10n_extension.dart';
import '../../../services/supabase_service.dart';
import '../providers/session_providers.dart';

/// Converges the running app on a registration that was confirmed OUTSIDE it.
///
/// Registering upgrades the anonymous user in place, which GoTrue serves
/// through its `email_change` path: `is_anonymous` stays true until the link in
/// the mail is clicked, and that link opens a WEB page with no route back into
/// the app. Nothing in the running client re-asks the server who it is — a
/// token refresh isn't treated as an identity change (correctly: normally it
/// carries none) — so the app went on believing it was talking to a guest.
/// Settings kept saying "guest session" and offering "Secure your account", and
/// the streak nudge kept pitching an account to someone who had just made one,
/// until the app was killed and relaunched. The reasonable conclusion for a
/// user is that registration failed, so they try again.
///
/// The only moment that can have changed is a return to the foreground (the
/// confirmation happens in the browser), and the only session worth spending a
/// call on is one with a registration actually pending — see
/// [SupabaseService.hasPendingRegistration]. Everyone else pays nothing.
///
/// Wraps the app rather than sitting on one screen: the user can be anywhere
/// when they come back from the mail.
class PendingRegistrationWatcher extends ConsumerStatefulWidget {
  const PendingRegistrationWatcher({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PendingRegistrationWatcher> createState() =>
      _PendingRegistrationWatcherState();
}

class _PendingRegistrationWatcherState
    extends ConsumerState<PendingRegistrationWatcher>
    with WidgetsBindingObserver {
  /// A check is in flight — resumes can arrive in bursts (the notification
  /// shade, the app switcher), and each converge is a token refresh.
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Also on launch: a cold start restores the stored session as-is, so an
    // app killed while the mail was still unread comes back up on the same
    // stale "anonymous" claim.
    WidgetsBinding.instance.addPostFrameCallback((_) => _converge());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _converge();
  }

  void _converge() => unawaited(_convergeOnIdentity());

  Future<void> _convergeOnIdentity() async {
    if (_checking || !SupabaseService.hasPendingRegistration) return;
    _checking = true;
    try {
      final user = await SupabaseService.reloadIdentity();
      // Still a guest: the link hasn't been clicked yet (or the refresh
      // failed). Nothing changed, so nothing to say and nothing to reload.
      if (user == null || user.isAnonymous) return;
      if (!mounted) return;
      await ref.read(sessionProvider.notifier).refresh();
      // Say it out loud: the confirmation happened on a web page the app never
      // saw, so without this the only evidence is a Settings row the user has
      // no reason to go and look at.
      if (mounted) AppToast.success(context, context.l10n.authAccountCreated);
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
