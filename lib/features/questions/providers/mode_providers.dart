import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/app_locale.dart' show sharedPreferencesProvider;
import '../../../data/models/question_mode.dart';
import '../../../data/repositories/question_repository.dart' show dateOnlyKey;
import '../../../l10n/gen/app_localizations.dart';

/// Localized tile / badge name of a mode.
String questionModeName(AppLocalizations l10n, QuestionMode mode) =>
    switch (mode) {
      QuestionMode.intimacy => l10n.modeIntimacy,
      QuestionMode.relationships => l10n.modeRelationships,
      QuestionMode.family => l10n.modeFamily,
      QuestionMode.moneyWork => l10n.modeMoneyWork,
      QuestionMode.society => l10n.modeSociety,
    };

/// The three-word line under a mode's name on the modes screen.
String questionModeDescription(AppLocalizations l10n, QuestionMode mode) =>
    switch (mode) {
      QuestionMode.intimacy => l10n.modeIntimacyDescription,
      QuestionMode.relationships => l10n.modeRelationshipsDescription,
      QuestionMode.family => l10n.modeFamilyDescription,
      QuestionMode.moneyWork => l10n.modeMoneyWorkDescription,
      QuestionMode.society => l10n.modeSocietyDescription,
    };

/// The post-vote hint's label: "Więcej o związkach" for a daily whose
/// category belongs to a mode, the generic "Zobacz tryby" otherwise.
String questionModesHintLabel(AppLocalizations l10n, QuestionMode? mode) =>
    switch (mode) {
      // Never reached in practice (the category never becomes the daily),
      // but the switch must be total.
      QuestionMode.intimacy => l10n.modesHintIntimacy,
      QuestionMode.relationships => l10n.modesHintRelationships,
      QuestionMode.family => l10n.modesHintFamily,
      QuestionMode.moneyWork => l10n.modesHintMoneyWork,
      QuestionMode.society => l10n.modesHintSociety,
      null => l10n.modesHintGeneric,
    };

/// SharedPreferences key for the once-per-install modes hint under the voted
/// daily. Absent = never shown; a `yyyy-MM-dd` = first shown that day (and
/// shown again only that day); [kModesHintDone] = tapped, never again.
const String kModesHintPrefKey = 'modes_hint';
const String kModesHintDone = 'done';

/// The state of the "Więcej o związkach →" link under the voted daily — the
/// one quiet pointer at the modes screen the first session gets, instead of a
/// pitch card in the middle of the vote → argument → split loop.
///
/// Shown on the daily only after its vote, for the rest of the local day it
/// first appeared on, then never again; a tap retires it at once. Both tiers
/// see it: for PRO it is discovery, for free it leads to the locked tiles
/// (and from there to the paywall), the same "tap a locked feature" rule as
/// the star or the history panel.
class ModesHintNotifier extends Notifier<String?> {
  @override
  String? build() =>
      ref.watch(sharedPreferencesProvider).getString(kModesHintPrefKey);

  /// Whether the hint may render right now.
  bool get eligible {
    final stamp = state;
    return stamp == null || stamp == dateOnlyKey(DateTime.now());
  }

  /// Stamps today as the hint's day, the first time it renders. A no-op once
  /// any stamp exists.
  Future<void> markShown() async {
    if (state != null) return;
    final today = dateOnlyKey(DateTime.now());
    state = today;
    await ref
        .read(sharedPreferencesProvider)
        .setString(kModesHintPrefKey, today);
  }

  /// Retires the hint for good — the user followed it.
  Future<void> dismiss() async {
    if (state == kModesHintDone) return;
    state = kModesHintDone;
    await ref
        .read(sharedPreferencesProvider)
        .setString(kModesHintPrefKey, kModesHintDone);
  }
}

final modesHintProvider = NotifierProvider<ModesHintNotifier, String?>(
  ModesHintNotifier.new,
);
