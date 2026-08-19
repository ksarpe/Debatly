import 'package:flutter/material.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';

/// Why the plan cards aren't there.
///
/// These are genuinely different situations and used to share one screen, which
/// told a user whose store lookup succeeded-but-empty to "check your connection"
/// and handed them a Try again that could not possibly work. Worse, an App
/// Review build submitted before its IAPs are approved lands on exactly that
/// state — a reviewer seeing a network error on the paywall is a rejection.
enum PaywallOfferProblem {
  /// The fetch failed: offline, a store outage, RevenueCat unreachable. Real
  /// blips, so a retry is worth offering.
  unreachable,

  /// The fetch SUCCEEDED and the offering was empty. A dashboard / store
  /// configuration state (products not approved yet, no current offering), so
  /// the same call returns the same nothing — no retry button, because a
  /// button that provably changes nothing is worse than no button.
  unavailable,
}

/// Stands in for the plan cards when there is no offer to show.
///
/// Only the offer section is replaced: the restore and legal links live in the
/// sticky bar below and stay reachable, which is what lets somebody who already
/// owns PRO get it back while the plans are missing.
class PaywallOfferError extends StatelessWidget {
  const PaywallOfferError({
    super.key,
    required this.problem,
    required this.onRetry,
  });

  final PaywallOfferProblem problem;

  /// Ignored for [PaywallOfferProblem.unavailable], which renders no button.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final unreachable = problem == PaywallOfferProblem.unreachable;
    // Min-height (not a fixed box): the section keeps its visual weight while
    // the offer is absent, but large accessibility text sizes may legitimately
    // need more room — a fixed 220 overflowed at 1.6x.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 220),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            unreachable ? Icons.wifi_off_rounded : Icons.storefront_outlined,
            color: colors.subtle,
            size: 32,
          ),
          const SizedBox(height: 12),
          Text(
            unreachable
                ? context.l10n.paywallLoadError
                : context.l10n.paywallOfferUnavailable,
            textAlign: TextAlign.center,
            style: AppTypography.body(
              fontSize: 14,
              height: 1.4,
            ).copyWith(color: colors.subtle),
          ),
          if (unreachable) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.spark,
                textStyle: AppTypography.action(),
              ),
              child: Text(context.l10n.tryAgain.toUpperCase()),
            ),
          ],
        ],
      ),
    );
  }
}
