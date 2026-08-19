import 'package:flutter/widgets.dart';

/// Widest a single column of content is allowed to get.
///
/// Phones never reach it; it exists for tablets, foldables and iPad
/// multitasking, where an uncapped column turns one line of text into an
/// unreadable ribbon (a question on an 11" iPad stretches past 1100pt). Every
/// full-width reading surface — the feed, the day wall, the paywall, the modal
/// sheets — shares this number so they cannot drift apart and look like screens
/// from different apps sitting next to each other.
///
/// Denser surfaces keep their own tighter caps: settings / history lists at 520,
/// the auth forms at 480, the vote row at 320.
const double kReadingMaxWidth = 560;

/// Cap for the auth forms (sign in / register, set a new password). Tighter than
/// [kReadingMaxWidth] because a row of short labelled fields stretched wide
/// reads worse than prose does, and it matches the card inside those sheets so
/// the sheet background hugs the form instead of framing empty space.
const double kFormMaxWidth = 480;

/// Empty space on ONE side once the content is capped at [maxWidth] and centred.
///
/// Zero on any screen narrower than the cap, so phone layouts are untouched. Use
/// it to pull edge-anchored chrome (app-bar icons) in towards the content column
/// instead of leaving it stranded at the screen edges while the content sits in
/// the middle.
double horizontalGutter(
  BuildContext context, {
  double maxWidth = kReadingMaxWidth,
}) {
  final width = MediaQuery.sizeOf(context).width;
  if (width <= maxWidth) return 0;
  return (width - maxWidth) / 2;
}
