import 'dart:async';

import 'package:flutter/services.dart';

/// Named haptic intents, so the app asks for a *meaning* ("this landed", "you
/// held") instead of picking a platform primitive at every call site.
///
/// Mirrors the Monitoring / AppToast shape: one facade, one place to add a user
/// preference or a platform quirk later. Every call is fire-and-forget and
/// drops its own failure — a device without a vibrator (most tablets, every
/// simulator) must never turn a missing buzz into a broken flow.
///
/// The OS already honours the user's system-wide haptics setting, so nothing
/// here re-checks it. "Reduce motion" is deliberately NOT consulted: it is a
/// setting about movement on screen, and a caller that hides the animation is
/// expected to skip the matching haptic itself.
class Haptics {
  Haptics._();

  /// The lightest tick, for something small settling into place — one word of a
  /// falling sentence landing.
  static void tick() => HapticFeedback.selectionClick().ignore();

  /// Something hit: the argument landing on the answer the user just gave.
  static void impact() => HapticFeedback.heavyImpact().ignore();

  /// A deliberate choice registered — the user held their ground, or changed
  /// their mind.
  static void confirm() => HapticFeedback.mediumImpact().ignore();
}
