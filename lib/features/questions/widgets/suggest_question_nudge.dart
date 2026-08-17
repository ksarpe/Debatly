import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/feedback/app_toast.dart';
import '../../../core/locale/app_locale.dart' show sharedPreferencesProvider;
import '../../../core/locale/l10n_extension.dart';
import 'suggest_question_sheet.dart';

/// SharedPreferences key: how many votes this install has successfully cast.
/// Counted locally — the nudge is about "you've now played enough to get it",
/// which the local install knows without a server round-trip.
const String _kVotesCastKey = 'suggest_question_votes_cast';

/// SharedPreferences key: whether the one-time nudge has already been shown.
const String _kPromptedKey = 'suggest_question_nudge_shown';

/// The vote on which the nudge becomes due. After the second vote the user has
/// felt the loop (vote → split → smaczki) at least twice, so "you could write
/// one of these" lands; after the first it would read as noise.
const int kSuggestQuestionNudgeAfterVotes = 2;

/// Pure decision: should the suggest-a-question nudge show right now?
///
/// Kept free of prefs/context so it can be unit-tested directly: once ever
/// (the Settings card is the durable path afterwards), and only once the
/// install has [kSuggestQuestionNudgeAfterVotes] votes behind it. `>=` rather
/// than `==` on purpose — when another prompt owns the trigger vote's moment
/// (e.g. secure-streak), the nudge fires on the next vote instead of never.
bool shouldPromptSuggestQuestion({
  required int votesCast,
  required bool alreadyPrompted,
}) {
  if (alreadyPrompted) return false;
  return votesCast >= kSuggestQuestionNudgeAfterVotes;
}

/// Counts one successful vote toward the nudge trigger. Call on every vote,
/// before any prompt decides to own the moment — the counter must reflect the
/// vote either way. Returns the new total.
Future<int> recordVoteForSuggestQuestionNudge(SharedPreferences prefs) async {
  final votes = (prefs.getInt(_kVotesCastKey) ?? 0) + 1;
  await prefs.setInt(_kVotesCastKey, votes);
  return votes;
}

/// After a successful vote, shows the one-time "got an idea? send it in" toast
/// with a tap-through into the suggestion sheet.
///
/// No-ops (returns false) unless [shouldPromptSuggestQuestion] says it's due,
/// so callers can fire it unconditionally. Marks the nudge shown BEFORE
/// showing, so a dismissed toast still counts as the one ask. Returns whether
/// it showed, letting the caller skip stacking another prompt on top.
Future<bool> maybePromptSuggestQuestion(
  BuildContext context,
  WidgetRef ref,
) async {
  final prefs = ref.read(sharedPreferencesProvider);
  if (!shouldPromptSuggestQuestion(
    votesCast: prefs.getInt(_kVotesCastKey) ?? 0,
    alreadyPrompted: prefs.getBool(_kPromptedKey) ?? false,
  )) {
    return false;
  }

  await prefs.setBool(_kPromptedKey, true);
  if (!context.mounted) return false;

  // The toast outlives this widget (root overlay), so its action must too:
  // resolve the ROOT navigator's state now — it lives as long as the app —
  // and open the sheet from its context, not from the (possibly long
  // unmounted) vote panel's.
  final navigator = Navigator.of(context, rootNavigator: true);
  AppToast.show(
    context,
    context.l10n.suggestQuestionNudge,
    icon: Icons.lightbulb_outline_rounded,
    // Longer than the default hold: this one carries an action and a pitch,
    // and it never comes back.
    duration: const Duration(seconds: 8),
    action: (
      label: context.l10n.suggestQuestionNudgeAction,
      onPressed: () => showSuggestQuestionSheet(navigator.context),
    ),
  );
  return true;
}
