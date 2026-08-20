import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';

/// Base height of the strip at the default text scale.
const double _kBannerHeight = 26;

/// How far the strip follows the system font before it stops growing. Past
/// this it would start eating the app bar it hangs under; the label is clamped
/// to the same factor so the two can never disagree.
const double _kBannerMaxTextScale = 1.6;

/// A slim "you're offline" strip, designed to ride in an [AppBar]'s `bottom`
/// slot (it's a [PreferredSizeWidget]) so it grows the bar instead of overlaying
/// the status chips. The host shows it only while offline — `bottom: online ?
/// null : OfflineBanner(textScale: ...)` — so it reserves no space when
/// connected.
///
/// It's a HINT surface, not a blocker: the cached daily/catalog still render
/// underneath (see the caching repository). It just sets expectations — votes
/// and reveals won't go through until the connection is back.
///
/// [textScale] is passed in rather than read from a [MediaQuery], because
/// [preferredSize] is queried without a [BuildContext] — and an [AppBar] gives
/// its `bottom` exactly the height that getter names. A hard-coded 26 therefore
/// overflowed the moment the system font grew: the label had no room and the
/// strip had no way to ask for more.
class OfflineBanner extends StatelessWidget implements PreferredSizeWidget {
  const OfflineBanner({super.key, this.textScale = 1});

  /// The host's text scale factor, e.g.
  /// `MediaQuery.textScalerOf(context).scale(1)`.
  final double textScale;

  double get _scale => math.min(_kBannerMaxTextScale, math.max(1, textScale));

  @override
  Size get preferredSize => Size.fromHeight(_kBannerHeight * _scale);

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: _kBannerMaxTextScale,
      child: Container(
        width: double.infinity,
        // A minimum, not a fixed height: if the strip is ever handed more room
        // than it asked for, the label centres in it instead of clipping.
        constraints: BoxConstraints(minHeight: preferredSize.height),
        alignment: Alignment.center,
        // The darkened red, not the fill hue: this is one of the few places
        // that puts WHITE type on a SOLID "no" background, where the fill hue
        // measured 2.9:1 — below AA for 12.5pt text.
        color: AppTheme.noOnWhiteText,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 15, color: Colors.white),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                context.l10n.offlineBannerLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.support(
                  fontSize: 12.5,
                ).copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
