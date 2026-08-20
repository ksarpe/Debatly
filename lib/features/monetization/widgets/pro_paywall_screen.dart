import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show Package;

import '../../../core/feedback/haptics.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/analytics.dart';
import '../../../services/purchases_service.dart' show PurchaseOutcome;
import '../../account/providers/session_providers.dart';
import 'paywall_content.dart';

export 'paywall_content.dart' show PaywallSource;

/// Opens the PRO paywall as a fullscreen dialog route and reports whether the
/// user ended up with the premium entitlement (bought or restored).
///
/// THE paywall surface of the freemium model: the day wall opens it (once a
/// day automatically, and on every "unlock" tap), and so do the bridge, the
/// locked features and Settings. Always dismissible — the floating X or the
/// system back — and a dismissal lands the user back where they were, never
/// out of the app. Packages and localized prices come live from the current
/// RevenueCat offering.
///
/// [trigger] is `'auto'` only for the day wall's once-a-day automatic open;
/// every user-initiated open is `'tap'`.
///
/// [headline] overrides the fixed slogan headline — the ONE sanctioned use is
/// the debate-profile entry, whose paywall talks about the user's portrait
/// ("{n} głosów. Zobacz, co mówią o Tobie."), not the catalog. Every other
/// entry point keeps the identical default copy; do not add more variants
/// without the owner's sign-off.
///
/// A dismissed paywall is a quiet `false`, so call sites keep their "purchase
/// not completed" handling unchanged.
Future<bool> showProPaywall(
  BuildContext context, {
  PaywallSource source = PaywallSource.general,
  String trigger = 'tap',
  String? headline,
}) async {
  final openedAt = DateTime.now();
  // Captured BEFORE the push: the caller's context can be gone by the time the
  // route pops (the smaczki sheet closes behind it), and the container is what
  // tells a confirmed purchase apart from a pending one afterwards.
  final container = ProviderScope.containerOf(context, listen: false);
  final result = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      fullscreenDialog: true,
      builder: (_) => ProPaywallScreen(
        source: source,
        trigger: trigger,
        headline: headline,
      ),
    ),
  );
  final purchased = result ?? false;
  // One place for every entry point: the moment the money actually landed (or
  // an old purchase was restored) is the other rising roll in the app.
  //
  // Gated on the entitlement being VISIBLE, not merely on `purchased`, which is
  // also true for [PurchaseOutcome.pending]. A Play-pending buyer used to get
  // the full celebratory roll and then a toast telling them the purchase could
  // not be confirmed yet — the haptic promising what the words took back.
  if (purchased && container.read(isPremiumProvider)) {
    Haptics.celebrate();
  }
  // The funnel exit: closed without ending up entitled (close button, system
  // back, or gave up after a cancelled purchase). Purchases and restores log
  // their own events inside the content. seconds_visible separates a bounce
  // ("saw it, closed it") from genuine consideration.
  if (!purchased) {
    Analytics.log('paywall_dismissed', {
      'source': source.name,
      'seconds_visible': DateTime.now().difference(openedAt).inSeconds,
    });
  }
  return purchased;
}

/// The fullscreen chrome around [ProPaywallContent]: the spark glow washing
/// down from the top of the screen, the scrollable body, and a floating close
/// button. Pops `true` the moment the user is entitled (bought or restored).
///
/// [loadPackages]/[buy] are the test seams, passed straight through.
class ProPaywallScreen extends ConsumerStatefulWidget {
  const ProPaywallScreen({
    super.key,
    this.source = PaywallSource.general,
    this.trigger = 'tap',
    this.headline,
    this.loadPackages,
    this.buy,
  });

  final PaywallSource source;
  final String trigger;

  /// Optional headline override (see [showProPaywall]); null = the slogan.
  final String? headline;
  final Future<List<Package>> Function()? loadPackages;
  final Future<PurchaseOutcome> Function(Package package)? buy;

  @override
  ConsumerState<ProPaywallScreen> createState() => _ProPaywallScreenState();
}

/// How long the close button may stay locked behind an in-flight purchase or
/// restore before it unlocks anyway.
///
/// Long enough to cover a normal store round trip (the sheet, Face ID, the
/// receipt) so nobody dismisses a purchase that was about to land, and short
/// enough that the screen can never become a room with no door. Neither
/// `Purchases.purchase` nor `restorePurchases` has a deadline of its own — a
/// store SDK that never calls back would otherwise leave the user with a
/// disabled X on a fullscreen route that has no edge-swipe back, i.e. the
/// "never a trap" rule broken on the exact screen App Review exercises
/// hardest, with the app kill as the only way out.
const Duration _kBusyExitGrace = Duration(seconds: 20);

class _ProPaywallScreenState extends ConsumerState<ProPaywallScreen> {
  /// Mirrors the content's in-flight purchase/restore state so the close
  /// button locks alongside the CTA — dismissing mid-purchase is confusing.
  bool _busy = false;

  /// Set once [_kBusyExitGrace] has passed with [_busy] still true: the exit
  /// comes back even though the purchase is nominally still running.
  bool _exitUnlocked = false;
  Timer? _graceTimer;

  void _onBusyChanged(bool busy) {
    _graceTimer?.cancel();
    if (busy) {
      _graceTimer = Timer(_kBusyExitGrace, () {
        if (mounted) setState(() => _exitUnlocked = true);
      });
    }
    setState(() {
      _busy = busy;
      // A finished attempt re-arms the full grace period for the next one.
      if (!busy) _exitUnlocked = false;
    });
  }

  @override
  void dispose() {
    _graceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: Stack(
        children: [
          // The spark glow washing down from the top edge, behind everything.
          Positioned(
            top: -160,
            left: -80,
            child: IgnorePointer(
              child: Container(
                width: 520,
                height: 440,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      AppTheme.sparkGlow.withValues(alpha: 0.28),
                      AppTheme.sparkGlow.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // The content owns its own scrolling (the pitch scrolls under the
          // pinned CTA bar) and pads its sticky bar past the bottom system
          // inset itself — so only the top inset is handled here.
          SafeArea(
            bottom: false,
            // Cap and centre the pitch. Uncapped, an iPad in landscape spread
            // the plan cards, the feature rows and the CTA across ~1320pt while
            // the day wall right next to it stayed at 560 — and this is the
            // surface App Review looks at on a tablet.
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: kReadingMaxWidth),
                child: ProPaywallContent(
                  source: widget.source,
                  trigger: widget.trigger,
                  headline: widget.headline,
                  loadPackages: widget.loadPackages,
                  buy: widget.buy,
                  // This link is how a returning buyer reaches the account their
                  // PRO actually sits on, instead of buying again.
                  showSignInLink: true,
                  onBusyChanged: _onBusyChanged,
                  // Pop only while this route is genuinely on top. `pop()`
                  // targets the topmost PRESENT route, and a route already
                  // animating out no longer counts as present — so a second
                  // hand-off during the exit transition (the entitlement can
                  // arrive from RevenueCat's own listener while `buy` is still
                  // returning) used to dismiss the smaczki sheet, the history
                  // screen or the feed sitting underneath. The same guard keeps
                  // it from swallowing the "save your PRO" dialog when that
                  // lands over the paywall first.
                  onEntitled: () async {
                    if (ModalRoute.of(context)?.isCurrent ?? false) {
                      Navigator.of(context).pop(true);
                    }
                  },
                ),
              ),
            ),
          ),
          // Close affordance floating over the scrollable content.
          Positioned(
            top: MediaQuery.paddingOf(context).top + 4,
            right: 8,
            child: IconButton(
              // Locked while a purchase is genuinely in flight, but never for
              // longer than [_kBusyExitGrace] — there is always a way out.
              onPressed: _busy && !_exitUnlocked
                  ? null
                  : () => Navigator.of(context).pop(false),
              icon: Icon(Icons.close_rounded, color: context.colors.subtle),
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            ),
          ),
        ],
      ),
    );
  }
}
