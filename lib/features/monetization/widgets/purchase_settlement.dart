import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feedback/app_toast.dart';
import '../../../core/locale/l10n_extension.dart';
import '../../account/providers/session_providers.dart';

/// Settles a paywall that came back `true` — money changed hands — and tells
/// the user WHICH of the two things that covers actually happened.
///
/// `showProPaywall` returns true for `PurchaseOutcome.pending` as well as
/// `PurchaseOutcome.entitled`: the store took the payment, but the entitlement
/// isn't visible yet (a RevenueCat webhook still in flight, a failed
/// customer-info fetch, a payment that clears at a kiosk tomorrow).
/// Announcing "Premium active 🎉" over that is a claim the surface behind the
/// toast immediately contradicts — the star is still grey, the wall is still
/// up, the cards are still locked. So: reconcile first, then say what is true.
///
/// The day wall worked this out and documented it; every other entry point
/// claimed premium unconditionally. This is that branch, hoisted, so there is
/// one answer to "what do we say after a purchase" instead of six.
///
/// Returns whether the entitlement really landed, so a caller with its own
/// follow-up (refetching a premium-gated RPC) can branch on it. Safe to call
/// from a widget that may be disposed mid-reconcile: the toast is skipped if
/// [context] no longer is mounted, and the return value still holds.
Future<bool> settleProPurchase(BuildContext context, WidgetRef ref) async {
  // The reload's own return value, not a re-read of the provider: re-reading
  // is only reliable while something is still listening to the session, which
  // is not a guarantee a single screen can make about itself.
  final session = await ref.read(sessionProvider.notifier).refresh();
  final entitled = session?.isPremium ?? false;
  if (!context.mounted) return entitled;
  if (entitled) {
    AppToast.success(context, context.l10n.settingsPremiumActiveToast);
  } else {
    AppToast.info(context, context.l10n.purchaseSyncPending);
  }
  return entitled;
}
