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
///
/// The multi-pulse patterns ([blocked], [celebrate]) are the only ones that
/// schedule anything; they run off short timers that outlive nothing but
/// themselves, so a widget disposed mid-pattern costs at most one stray buzz.
class Haptics {
  Haptics._();

  /// The lightest tick, for something small settling into place — one word of a
  /// falling sentence landing, or a selection changing (the paywall's plan
  /// cards).
  static void tick() => HapticFeedback.selectionClick().ignore();

  /// A soft single bump for an edge the user just met but is free to cross —
  /// the feed springing back at the daily, the deck ending at the day wall.
  /// Deliberately quieter than [blocked]: nothing was refused here.
  static void nudge() => HapticFeedback.lightImpact().ignore();

  /// Something hit: the argument landing on the answer the user just gave, the
  /// streak flame striking the chip in the app bar.
  static void impact() => HapticFeedback.heavyImpact().ignore();

  /// A deliberate choice registered — the vote cast, the user holding their
  /// ground or changing their mind, a question starred.
  static void confirm() => HapticFeedback.mediumImpact().ignore();

  /// "Not yours yet": a locked smaczek, the star on a free account, the
  /// history vault, the smaczki pill before the vote. Two quick light taps —
  /// a refusal reads as a *pattern*, which a single pulse (however strong)
  /// never does; it would just feel like an ordinary press.
  static void blocked() => _pattern(const [
    (0, HapticFeedback.lightImpact),
    (90, HapticFeedback.lightImpact),
  ]);

  /// The rare good news — a rank promotion, money actually landing. A rising
  /// roll (light → medium → heavy) so the biggest moments in the app are the
  /// only ones that feel like this.
  static void celebrate() => _pattern(const [
    (0, HapticFeedback.lightImpact),
    (70, HapticFeedback.mediumImpact),
    (150, HapticFeedback.heavyImpact),
  ]);

  /// Fires each `(delayMs, primitive)` pair relative to now. The first pulse of
  /// a pattern is played synchronously so the feedback is never a frame late on
  /// the tap that caused it.
  static void _pattern(List<(int, Future<void> Function())> steps) {
    for (final (delayMs, fire) in steps) {
      if (delayMs == 0) {
        fire().ignore();
      } else {
        Future<void>.delayed(Duration(milliseconds: delayMs), fire).ignore();
      }
    }
  }
}
