import 'package:flutter/material.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';

/// A slim "you're offline" strip, designed to ride in an [AppBar]'s `bottom`
/// slot (it's a [PreferredSizeWidget]) so it grows the bar instead of overlaying
/// the status chips. The host shows it only while offline — `bottom: online ?
/// null : const OfflineBanner()` — so it reserves no space when connected.
///
/// It's a HINT surface, not a blocker: the cached daily/catalog still render
/// underneath (see the caching repository). It just sets expectations — votes
/// and reveals won't go through until the connection is back.
class OfflineBanner extends StatelessWidget implements PreferredSizeWidget {
  const OfflineBanner({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(26);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: preferredSize.height,
      alignment: Alignment.center,
      color: AppTheme.no.withValues(alpha: 0.92),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 15, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            context.l10n.offlineBannerLabel,
            style: AppTypography.support(
              fontSize: 12.5,
            ).copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}
