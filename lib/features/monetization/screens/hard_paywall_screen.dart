import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show Package;

import '../../../core/feedback/app_toast.dart';
import '../../../core/locale/l10n_extension.dart';
import '../../account/providers/session_providers.dart';
import '../widgets/paywall_content.dart';

/// Widest the centred paywall column is allowed to get — matches the feed's
/// tablet cap so the two screens share a silhouette.
const double _kPaywallMaxWidth = 560;

/// The hard paywall: the full-screen gate every non-PRO user lands on after
/// onboarding (and on every launch until they are entitled). There is no way
/// past it into the feed — Debatly's content is PRO-only.
///
/// The wall is the SAME for everyone, signed in or not. Debatly's model is
/// "buy PRO to play; an account only secures a purchase you already made", so
/// there is no profile to reach from here — accounts don't exist before the
/// purchase, and nothing in Settings is anyone's yet. That keeps this screen a
/// single decision with no side doors (the superwall pattern).
///
/// What it must still offer besides the purchase itself, all in the content's
/// sticky footer:
///   * restore — a store requirement, and the recovery path for a guest whose
///     PRO lives in this device's purchase history,
///   * sign-in — the recovery path for someone whose PRO rides on an account
///     they secured earlier (a reinstall, a new phone),
///   * terms + privacy, which must not sit behind a purchase.
///
/// There is no close button by design. On a completed purchase / restore the
/// session refresh flips `isPremium` and the home gate (see `AppEntry`) swaps
/// this screen for the feed — the paywall never dismisses itself.
class HardPaywallScreen extends ConsumerWidget {
  const HardPaywallScreen({super.key, this.loadPackages, this.buy});

  /// Test seams, passed straight through to [ProPaywallContent].
  final Future<List<Package>> Function()? loadPackages;
  final Future<bool> Function(Package package)? buy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // No app bar: with the profile entry gone there is nothing to put in one,
    // and the ~56dp it reserved is worth more to the pitch — especially at
    // large system font sizes, where the sticky CTA bar and the scrolling
    // benefit list are already competing for a short screen.
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kPaywallMaxWidth),
            // The content owns its scrolling: the pitch scrolls while the CTA
            // bar stays pinned to the bottom of the screen (fillHeight).
            child: ProPaywallContent(
              source: PaywallSource.hardWall,
              showSignInLink: true,
              fillHeight: true,
              loadPackages: loadPackages,
              buy: buy,
              // The refresh re-reconciles the entitlement; once `isPremium`
              // flips, the home gate replaces this screen with the feed (and
              // fires the guest save-your-PRO nudge from its own, surviving
              // context).
              //
              // Awaited, because this screen is the one surface that does NOT
              // dismiss itself: if the reconcile fails (a 502 from
              // `sync-entitlement`, a webhook still in flight) we are still
              // here, still walling off the app — from someone who has just
              // paid. Say so and point at restore rather than silently showing
              // them the paywall again.
              onEntitled: () async {
                // The outcome comes back from the reload itself: this screen
                // does not watch the session (the home gate above it does), so
                // re-reading the provider here would be asking a question
                // nothing in this subtree is subscribed to.
                final reloaded = await ref
                    .read(sessionProvider.notifier)
                    .refresh();
                if (!context.mounted) return;
                if (reloaded?.isPremium ?? false) return;
                AppToast.info(context, context.l10n.purchaseSyncPending);
              },
            ),
          ),
        ),
      ),
    );
  }
}
