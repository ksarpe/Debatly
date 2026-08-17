import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show Package;

import '../../../core/theme/app_theme.dart';
import '../../../services/analytics.dart';
import '../../../services/purchases_service.dart' show PurchaseOutcome;
import 'paywall_content.dart';

export 'paywall_content.dart' show PaywallSource;

/// Opens the PRO paywall as a modal sheet and reports whether the user ended
/// up with the premium entitlement (bought or restored).
///
/// THE paywall surface of the freemium model: the day wall opens it (once a
/// day automatically, and on every "unlock" tap), and so do the bridge, the
/// locked features and Settings. Always dismissible — drag down, tap outside,
/// or the floating X — and a dismissal lands the user back where they were,
/// never out of the app. Packages and localized prices come live from the
/// current RevenueCat offering; [source] picks the headline.
///
/// [trigger] is `'auto'` only for the day wall's once-a-day automatic open;
/// every user-initiated open is `'tap'`.
///
/// A dismissed sheet is a quiet `false`, so call sites keep their "purchase
/// not completed" handling unchanged.
Future<bool> showProPaywall(
  BuildContext context, {
  PaywallSource source = PaywallSource.general,
  String trigger = 'tap',
}) async {
  final openedAt = DateTime.now();
  final result = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: context.colors.background,
    isScrollControlled: true,
    useSafeArea: true,
    // The standard grabber, same as the app's other sheets — dismissed by
    // dragging it down or tapping outside, plus the floating close "X".
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => ProPaywallSheet(source: source, trigger: trigger),
  );
  final purchased = result ?? false;
  // The funnel exit: closed without ending up entitled (close button, swipe
  // down, or gave up after a cancelled purchase). Purchases and restores log
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

/// The sheet chrome around [ProPaywallContent]: a scrollable body with the
/// bottom safe-area inset and a floating close button. Pops `true` the moment
/// the user is entitled (bought or restored).
///
/// [loadPackages]/[buy] are the test seams, passed straight through.
class ProPaywallSheet extends ConsumerStatefulWidget {
  const ProPaywallSheet({
    super.key,
    this.source = PaywallSource.general,
    this.trigger = 'tap',
    this.loadPackages,
    this.buy,
  });

  final PaywallSource source;
  final String trigger;
  final Future<List<Package>> Function()? loadPackages;
  final Future<PurchaseOutcome> Function(Package package)? buy;

  @override
  ConsumerState<ProPaywallSheet> createState() => _ProPaywallSheetState();
}

class _ProPaywallSheetState extends ConsumerState<ProPaywallSheet> {
  /// Mirrors the content's in-flight purchase/restore state so the close
  /// button locks alongside the CTA — dismissing mid-purchase is confusing.
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    // `useSafeArea: true` on the route is `SafeArea(bottom: false)` — it keeps
    // the sheet below the status bar but leaves the BOTTOM inset to the
    // content, whose sticky CTA bar pads itself past the Android gesture bar.
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      child: Stack(
        children: [
          // The route's drag handle sits above this content, which owns its
          // own scrolling: the pitch scrolls under the pinned CTA bar.
          ProPaywallContent(
            source: widget.source,
            trigger: widget.trigger,
            loadPackages: widget.loadPackages,
            buy: widget.buy,
            // The auth sheet is sign-in-only pre-purchase, so this link is how
            // a returning buyer reaches the account their PRO actually sits on.
            showSignInLink: true,
            onBusyChanged: (busy) => setState(() => _busy = busy),
            // Nothing to await: the pop unmounts the content, which is exactly
            // the "the owner handled it" signal it looks for.
            onEntitled: () async => Navigator.of(context).pop(true),
          ),
          // Close affordance floating over the scrollable content.
          Positioned(
            top: 0,
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
