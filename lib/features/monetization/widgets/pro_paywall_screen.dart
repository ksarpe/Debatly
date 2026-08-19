import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show Package;

import '../../../core/layout/content_width.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/analytics.dart';
import '../../../services/purchases_service.dart' show PurchaseOutcome;
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

class _ProPaywallScreenState extends ConsumerState<ProPaywallScreen> {
  /// Mirrors the content's in-flight purchase/restore state so the close
  /// button locks alongside the CTA — dismissing mid-purchase is confusing.
  bool _busy = false;

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
                  onBusyChanged: (busy) => setState(() => _busy = busy),
                  // Nothing to await: the pop unmounts the content, which is
                  // exactly the "the owner handled it" signal it looks for.
                  onEntitled: () async => Navigator.of(context).pop(true),
                ),
              ),
            ),
          ),
          // Close affordance floating over the scrollable content.
          Positioned(
            top: MediaQuery.paddingOf(context).top + 4,
            right: 8,
            child: IconButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
              icon: Icon(Icons.close_rounded, color: context.colors.subtle),
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            ),
          ),
        ],
      ),
    );
  }
}
