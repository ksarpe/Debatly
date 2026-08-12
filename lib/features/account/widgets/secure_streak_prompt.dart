import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/app_locale.dart' show sharedPreferencesProvider;
import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../questions/widgets/animated_flame_icon.dart' show flameColor;
import '../providers/session_providers.dart';
import '../screens/auth_screen.dart';

/// SharedPreferences key: the local "epoch day" we last showed the
/// secure-your-streak nudge. Absent until the first ask; stored as a day index
/// so the cooldown is plain integer subtraction (same scheme as the review ask).
const String _kLastPromptedDayKey = 'secure_streak_last_prompted_day';

/// The streak that first makes the nudge land: with three days on the line the
/// guest has something concrete to lose, so "don't lose it" reads as help, not
/// as a sign-up wall. Below it the ask would be premature.
const int kSecureStreakFirstMilestone = 3;

/// Minimum days between asks. A guest who dismissed the nudge keeps voting
/// undisturbed for a week; each repeat then argues with a strictly bigger
/// streak, so the ask gets stronger, not just louder.
const int kSecureStreakCooldownDays = 7;

/// The device-local date as a day index (days since the Unix epoch). The nudge
/// rides an engagement moment the user feels in local time, and the cooldown is
/// intentionally coarse, so local midnight is the right boundary.
int _todayEpochDay() {
  final now = DateTime.now();
  return DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime.utc(1970)).inDays;
}

/// Pure decision: should the secure-your-streak nudge show right now?
///
/// Kept free of platform/prefs/clock so it can be unit-tested exhaustively:
///   * anyone with a real account → never (nothing left to secure);
///   * below the streak milestone → never (nothing worth protecting yet);
///   * on a promotion day → never — the rank-up celebration (confetti + share
///     card) owns that moment; the nudge comes around on the next eligible day;
///   * otherwise → on the first eligible day, then on the weekly cooldown.
bool shouldPromptToSecureStreak({
  required bool hasAccount,
  required int streak,
  required bool isPromotionDay,
  required int? lastPromptedDay,
  required int todayDay,
}) {
  if (hasAccount) return false;
  if (streak < kSecureStreakFirstMilestone) return false;
  if (isPromotionDay) return false;
  if (lastPromptedDay == null) return true;
  return todayDay - lastPromptedDay >= kSecureStreakCooldownDays;
}

/// After a guest's vote moves their streak, nudges them to attach it to a real
/// account.
///
/// A guest's streak (and votes, favourites, PRO) ride on the anonymous Supabase
/// identity, which is lost on reinstall or a new phone. Registering upgrades the
/// anonymous user in place — same UUID, so everything is kept. The moment right
/// after a vote is the loss-aversion high point: the streak just grew, so
/// "secure it" beats any generic "create an account" pitch.
///
/// No-ops (returns false) unless [shouldPromptToSecureStreak] says it's due, so
/// callers can fire it unconditionally after any successful vote. Records the
/// ask BEFORE showing, so a dismissed dialog still arms the cooldown. Returns
/// whether the dialog was actually shown, letting the caller skip stacking
/// another prompt (e.g. the OS review sheet) on top of it.
Future<bool> maybePromptSecureStreak(
  BuildContext context,
  WidgetRef ref, {
  required int streak,
  required bool isPromotionDay,
}) async {
  final session = ref.read(sessionProvider).value;
  final prefs = ref.read(sharedPreferencesProvider);

  if (!shouldPromptToSecureStreak(
    hasAccount: session?.hasAccount ?? false,
    streak: streak,
    isPromotionDay: isPromotionDay,
    lastPromptedDay: prefs.getInt(_kLastPromptedDayKey),
    todayDay: _todayEpochDay(),
  )) {
    return false;
  }

  await prefs.setInt(_kLastPromptedDayKey, _todayEpochDay());
  if (!context.mounted) return false;

  final flame = flameColor(context);
  final wantsAccount = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.62),
    builder: (dialogContext) => AlertDialog(
      backgroundColor: context.colors.cardSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 10),
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: flame.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.local_fire_department_rounded,
              color: flame,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              context.l10n.secureStreakTitle,
              style: TextStyle(
                color: context.colors.ink,
                fontSize: 19,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      content: Text(
        context.l10n.secureStreakBody(streak),
        style: TextStyle(
          color: context.colors.subtle,
          height: 1.4,
          fontSize: 14.5,
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          style: TextButton.styleFrom(foregroundColor: context.colors.subtle),
          child: Text(context.l10n.later),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: TextButton.styleFrom(foregroundColor: AppTheme.spark),
          child: Text(
            context.l10n.createAccount,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

  if (wantsAccount == true && context.mounted) {
    await showAuthSheet(context);
  }
  return true;
}
