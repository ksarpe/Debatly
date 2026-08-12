import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shortest side (in logical pixels) at or above which a device counts as a
/// tablet. The conventional Material breakpoint, and the one Android itself
/// uses for `sw600dp` resources.
const double kTabletShortestSide = 600;

/// Pins phones to portrait, and leaves tablets free to rotate.
///
/// The feed is one full-bleed question with the vote row, the share / history
/// pills and the bottom overlay stacked beneath it. A phone in landscape offers
/// ~375pt of height for roughly 500pt of that chrome, so something always had to
/// give: the reveal wall's bottom links ("restore purchase") ended up below the
/// fold, painted but out of reach. The app has advertised
/// landscape on iPhone since 1.0 without a single layout designed for it.
///
/// Tablets keep all four orientations — they have the room, and iPadOS
/// multitasking expects an app to rotate. The layouts underneath are size-driven
/// (see `FitOrScroll`), so a Split View or Slide Over column still behaves.
///
/// The decision follows the physical display, not the window: an iPad in Slide
/// Over hands out a phone-shaped window, and that must not be mistaken for a
/// phone.
class OrientationLock extends StatefulWidget {
  const OrientationLock({super.key, required this.child});

  final Widget child;

  @override
  State<OrientationLock> createState() => _OrientationLockState();
}

class _OrientationLockState extends State<OrientationLock> {
  /// The last value pushed to the platform, so a rebuild (a theme change, a
  /// rotation on a tablet) doesn't re-cross the channel for no reason.
  bool? _lockedToPortrait;

  static const _portrait = [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ];

  static const _all = [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];

  @override
  Widget build(BuildContext context) {
    final isMobile =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
    if (isMobile) {
      final display = View.of(context).display;
      final logical = display.size / display.devicePixelRatio;
      final lock = logical.shortestSide < kTabletShortestSide;
      if (lock != _lockedToPortrait) {
        _lockedToPortrait = lock;
        SystemChrome.setPreferredOrientations(lock ? _portrait : _all);
      }
    }
    return widget.child;
  }
}
