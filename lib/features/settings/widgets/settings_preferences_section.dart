import 'package:flutter/material.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../questions/screens/history_screen.dart';
import 'offline_download_row.dart';
import 'settings_nav_row.dart';
import 'settings_primitives.dart';
import 'settings_toggle_row.dart';

/// The "App settings" card: the daily-reminder toggle (and time row when on),
/// the language and appearance pickers, the premium offline download, the
/// favorites list and the history of the user's votes.
///
/// The owning [SettingsScreen] keeps the reminder/picker state and logic; this
/// widget is the visual section and forwards taps back up through its callbacks.
class SettingsPreferencesSection extends StatelessWidget {
  const SettingsPreferencesSection({
    super.key,
    required this.reminderEnabled,
    required this.reminderTimeLabel,
    required this.languageLabel,
    required this.appearanceIcon,
    required this.appearanceLabel,
    required this.localeCode,
    required this.isPremium,
    required this.showFavorites,
    required this.favoriteCount,
    required this.onReminderToggled,
    required this.onReminderTime,
    required this.onLanguage,
    required this.onAppearance,
    required this.onFavorites,
  });

  final bool reminderEnabled;
  final String reminderTimeLabel;
  final String languageLabel;
  final IconData appearanceIcon;
  final String appearanceLabel;
  final String localeCode;
  final bool isPremium;
  final bool showFavorites;
  final int favoriteCount;
  final ValueChanged<bool> onReminderToggled;
  final VoidCallback onReminderTime;
  final VoidCallback onLanguage;
  final VoidCallback onAppearance;
  final VoidCallback onFavorites;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---- App settings -----------------------------------
        SettingsSectionLabel(context.l10n.settingsSectionApp),
        const SizedBox(height: 12),
        SettingsCard(
          children: [
            SettingsToggleRow(
              icon: Icons.notifications_none_rounded,
              title: context.l10n.settingsReminders,
              subtitle: context.l10n.settingsRemindersSubtitle,
              value: reminderEnabled,
              onChanged: onReminderToggled,
            ),
            if (reminderEnabled) ...[
              const SettingsRowDivider(),
              SettingsNavRow(
                icon: Icons.schedule_rounded,
                title: context.l10n.settingsReminderTime,
                trailingText: reminderTimeLabel,
                onTap: onReminderTime,
              ),
            ],

            const SettingsRowDivider(),
            SettingsNavRow(
              icon: Icons.language_rounded,
              title: context.l10n.settingsLanguage,
              trailingText: languageLabel,
              onTap: onLanguage,
            ),

            const SettingsRowDivider(),
            SettingsNavRow(
              icon: appearanceIcon,
              title: context.l10n.settingsAppearance,
              trailingText: appearanceLabel,
              onTap: onAppearance,
            ),

            // Premium-only: pull the whole (legitimately-readable)
            // catalog + smaczki onto the device so it stays
            // readable offline. Free users only get the daily +
            // their reveals, so the action is meaningless for them.
            if (isPremium) ...[
              const SettingsRowDivider(),
              OfflineDownloadRow(localeCode: localeCode),
            ],

            if (showFavorites) ...[
              const SettingsRowDivider(),
              SettingsNavRow(
                icon: Icons.star_rounded,
                iconColor: kGold,
                title: context.l10n.settingsFavorites,
                trailingText: favoriteCount > 0 ? '$favoriteCount' : null,
                onTap: onFavorites,
              ),
            ],

            // The PRO history of the user's votes + how people voted.
            // Shown to everyone; the screen gates premium itself,
            // so a free user lands on the PRO upsell inside it.
            const SettingsRowDivider(),
            SettingsNavRow(
              icon: Icons.history_rounded,
              title: context.l10n.historyTitle,
              onTap: () => openHistory(context),
            ),
          ],
        ),
      ],
    );
  }
}
