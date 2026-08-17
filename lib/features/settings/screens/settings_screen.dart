import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feedback/app_toast.dart';
import '../../../core/locale/app_locale.dart';
import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/widgets/sub_screen_chrome.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../services/notification_service.dart';
import '../../../services/purchases_service.dart';
import '../../../services/reminder_scheduler.dart';
import '../../../services/supabase_service.dart';
import '../../account/providers/session_providers.dart';
import '../../account/screens/auth_screen.dart';
import '../../account/widgets/restore_sign_in_prompt.dart';
import '../../monetization/widgets/pro_paywall_screen.dart';
import '../../questions/providers/favorites_providers.dart';
import '../../questions/widgets/suggest_question_sheet.dart';
import '../providers/app_info_provider.dart';
import '../providers/dev_tools_providers.dart';
import '../providers/reminder_providers.dart';
import '../widgets/account_action_buttons.dart';
import '../widgets/manage_subscription_sheet.dart';
import '../widgets/profile_header.dart';
import '../widgets/rank_card.dart';
import '../widgets/settings_account_section.dart';
import '../widgets/settings_nav_row.dart';
import '../widgets/settings_preferences_section.dart';
import '../widgets/settings_primitives.dart';
import '../widgets/settings_session_actions.dart';
import '../widgets/streak_card.dart';
import '../widgets/suggest_question_card.dart';
import 'dev_tools_screen.dart';
import 'favorites_screen.dart';
import 'privacy_data_screen.dart';

/// The signed-in user's profile hub: identity, gamification stats, app
/// preferences, subscription and account actions — all on one scrollable page.
///
/// Reached by tapping the person icon in the top-right of [QuestionScreen].
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver {
  /// True while the user turned the reminder on but the OS hadn't granted the
  /// permission yet and we sent them to system settings. When they return with
  /// it granted, [_syncReminderToggle] finishes the enable without a second tap.
  bool _pendingEnable = false;

  /// True while a sign-out is in flight, so the button shows a spinner and
  /// can't be tapped twice (a slow global token revoke can take a moment).
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // After the first frame (context + providers ready), reconcile the stored
    // switch with the real OS permission — it may have been revoked elsewhere.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncReminderToggle());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check on return to the foreground — typically back from the system
    // notification settings the "Open settings" action opened.
    if (state == AppLifecycleState.resumed) _syncReminderToggle();
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(sessionProvider).value;
    final hasAccount = account?.hasAccount ?? false;
    final isPremium = account?.isPremium ?? false;
    final localeCode = ref.watch(localeControllerProvider).languageCode;
    final reminder = ref.watch(reminderControllerProvider);
    final themeMode = ref.watch(themeControllerProvider);
    final appInfo = ref.watch(appInfoProvider).value;

    // Favorites entry: shown to premium (the feature is theirs) and to anyone
    // who still has saved questions — a lapsed-premium user keeps access to the
    // list they built (favorites are readable forever).
    final favoriteCount = ref.watch(favoriteIdsProvider).value?.length ?? 0;
    final showFavorites = isPremium || favoriteCount > 0;

    return Scaffold(
      backgroundColor: context.colors.background,
      body: Stack(
        children: [
          // Faint orange glow bleeding down from the top, behind the header.
          const TopGlow(),
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                32 + MediaQuery.paddingOf(context).bottom,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ProfileHeader(
                        account: account,
                        hasAccount: hasAccount,
                        onClose: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(height: 24),

                      // A guest's single most important action lives at the
                      // top, right under the "guest session" identity it fixes:
                      // secure the anonymous account so the streak/votes/PRO
                      // survive a reinstall or a new phone.
                      if (!hasAccount) ...[
                        SecureAccountButton(onTap: _openAuth),
                        const SizedBox(height: 28),
                      ],

                      // ---- Stats (live from sync_user_state) --------------
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: const [
                            Expanded(child: StreakCard()),
                            SizedBox(width: 14),
                            Expanded(child: RankCard()),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // The one action that feeds the catalog back: pitch us a
                      // question. Sits with the engagement cards, above the
                      // preference plumbing, so it's visible without scrolling.
                      SuggestQuestionCard(onTap: _openSuggestQuestion),
                      const SizedBox(height: 28),

                      SettingsPreferencesSection(
                        reminderEnabled: reminder.enabled,
                        reminderTimeLabel: _formatTime(reminder.time),
                        languageLabel: _languageName(localeCode),
                        appearanceIcon: _themeModeIcon(themeMode),
                        appearanceLabel: _themeModeName(context, themeMode),
                        localeCode: localeCode,
                        isPremium: isPremium,
                        showFavorites: showFavorites,
                        favoriteCount: favoriteCount,
                        onReminderToggled: _onReminderToggled,
                        onReminderTime: _openReminderTimePicker,
                        onLanguage: _openLanguagePicker,
                        onAppearance: _openAppearancePicker,
                        onFavorites: _openFavorites,
                      ),
                      const SizedBox(height: 28),

                      SettingsAccountSection(
                        isPremium: isPremium,
                        localeCode: localeCode,
                        hasAccount: hasAccount,
                        signingOut: _signingOut,
                        onManageSubscription: _openManageSubscription,
                        onGoPremium: _openPaywall,
                        onPrivacy: _openPrivacyData,
                        onRestore: _restorePurchases,
                        onSignOut: _signOut,
                      ),

                      // Tester-only tools (onboarding replay, question pinning).
                      // Hidden for everyone else — see devToolsEnabledProvider.
                      if (ref.watch(devToolsEnabledProvider)) ...[
                        const SizedBox(height: 28),
                        const SettingsSectionLabel('DEV'),
                        const SizedBox(height: 12),
                        SettingsCard(
                          children: [
                            SettingsNavRow(
                              icon: Icons.bug_report_outlined,
                              title: 'Narzędzia testowe',
                              subtitle: 'Onboarding, pytania testowe',
                              onTap: _openDevTools,
                            ),
                          ],
                        ),
                      ],

                      SettingsSessionActions(
                        hasAccount: hasAccount,
                        appInfo: appInfo,
                        onDeleteAccount: _confirmDeleteAccount,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Actions ---------------------------------------------------------------

  /// Shows the PRO paywall, then refreshes the session so the gate sees
  /// the upgrade immediately.
  Future<void> _openPaywall() async {
    final purchased = await showProPaywall(context);
    if (!mounted) return;
    if (purchased) {
      await ref.read(sessionProvider.notifier).refresh();
      if (!mounted) return;
      _showMessage(
        context.l10n.settingsPremiumActiveToast,
        type: ToastType.success,
      );
    }
  }

  /// Opens the Manage-subscription sheet. The current entitlement details are
  /// already cached by [premiumStatusProvider]; the sheet refreshes them itself
  /// while it loads so a date that ticked over since open is still correct.
  Future<void> _openManageSubscription() async {
    final localeCode = ref.read(localeControllerProvider).languageCode;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.colors.cardSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ManageSubscriptionSheet(localeCode: localeCode),
    );
  }

  Future<void> _restorePurchases() async {
    // Settings is account-only today, so the guest chooser inside
    // confirmGuestRestore never fires here — the guard is a safety net in case
    // this screen ever opens for a guest (the paywall restore is the live path).
    if (!await confirmGuestRestore(context, ref)) return;
    if (!mounted) return;
    final outcome = await PurchasesService.restorePurchases();
    if (!mounted) return;
    if (outcome == RestoreOutcome.restored) {
      await ref.read(sessionProvider.notifier).refresh();
    }
    if (!mounted) return;
    // A store we never reached is not "you own nothing" — see [RestoreOutcome].
    _showMessage(
      switch (outcome) {
        RestoreOutcome.restored => context.l10n.purchaseRestored,
        RestoreOutcome.none => context.l10n.noPreviousPurchase,
        RestoreOutcome.failed => context.l10n.storeUnreachable,
      },
      type: switch (outcome) {
        RestoreOutcome.restored => ToastType.success,
        RestoreOutcome.none => ToastType.info,
        RestoreOutcome.failed => ToastType.error,
      },
    );
  }

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);

    // Await the FULL sign-out + reload-into-guest before leaving Settings, so we
    // pop onto a home screen that already shows the guest rather than the stale
    // signed-in view that then reloads in the background (the visible "double
    // reload" on sign-out). signOutAndReload owns the reload — re-running
    // ensureSignedIn to mint a fresh guest — and suppresses the auth listener's
    // duplicate refresh, so this is one clean transition with a single loader.
    // We deliberately do NOT `invalidate(sessionProvider)`: that flips the
    // session to AsyncValue.loading() (nulling userId mid-reload), tripping the
    // QuestionScreen identity listener on account→null→guest and flashing the
    // feed instead of a clean account→guest.
    try {
      await ref.read(sessionProvider.notifier).signOutAndReload();
    } catch (e) {
      // signOut() already falls back to a local sign-out, so getting here means
      // even that failed — surface it instead of leaving a dead button.
      if (!mounted) return;
      setState(() => _signingOut = false);
      _showMessage(context.l10n.signOutError, type: ToastType.error);
      return;
    }

    if (!mounted) return;
    setState(() => _signingOut = false);
    Navigator.of(context).maybePop();
    _showMessage(context.l10n.signedOut);
  }

  /// Confirms then permanently deletes the account. The destructive action is
  /// behind an explicit two-button dialog; on confirm it runs the deletion under
  /// a blocking spinner, resets the session (so a fresh guest is minted) and
  /// leaves Settings.
  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.colors.cardSurface,
        title: Text(context.l10n.deleteAccountTitle),
        content: Text(context.l10n.deleteAccountBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: kDanger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.deleteAccount),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _performDeleteAccount();
  }

  Future<void> _performDeleteAccount() async {
    // Capture everything that needs `context` BEFORE the await, so we never
    // touch a possibly-unmounted context afterwards (the screen pops on success).
    // The toast rides the *root* overlay, so it survives leaving Settings.
    final navigator = Navigator.of(context);
    final overlay = AppToast.capture(context);
    final successMsg = context.l10n.deleteAccountSuccess;
    final errorMsg = context.l10n.deleteAccountError;

    // Blocking, non-dismissible progress overlay while the server works.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    );

    try {
      await SupabaseService.deleteAccount();
      // deleteAccount() ends with a local signOut, whose `signedOut` event the
      // session's auth listener turns into a single flash-free refresh() —
      // re-running ensureSignedIn to mint a fresh guest and rebuild every
      // per-user cache from the new identity. We deliberately do NOT
      // `invalidate(sessionProvider)` here: that flips the session to loading
      // (null userId mid-reload) and trips the identity listener on
      // account→null→guest, flashing the feed instead of a clean transition.
      navigator.pop(); // dismiss the progress overlay
      navigator.maybePop(); // leave Settings, back to the question screen
      AppToast.showOn(overlay, successMsg, type: ToastType.success);
    } catch (e) {
      navigator.pop(); // dismiss the progress overlay
      AppToast.showOn(overlay, errorMsg, type: ToastType.error);
    }
  }

  void _openAuth() => showAuthSheet(context);

  /// Opens the "Suggest a question" sheet — the user's idea lands in the
  /// team's review inbox, not in the catalog.
  void _openSuggestQuestion() => showSuggestQuestionSheet(context);

  /// Turns the daily reminder on/off. Enabling reuses an existing grant or asks
  /// for one, scheduling + persisting only when granted. A denial (or a system
  /// that no longer prompts) leaves the switch off and shows a message with a
  /// one-tap "Open settings" action; we remember the intent so returning with
  /// permission granted finishes the job. Disabling cancels the schedule.
  Future<void> _onReminderToggled(bool enabled) async {
    // Read the notifier up front: cancelling/arming the loop is ~20 sequential
    // platform calls, and a user who flips the switch and immediately leaves
    // Settings unmounts this widget mid-flight — after which `ref` throws.
    final reminder = ref.read(reminderControllerProvider.notifier);
    if (!enabled) {
      _pendingEnable = false;
      await NotificationService.cancelDailyReminder();
      await reminder.setEnabled(false);
      return;
    }

    // Already granted? Don't prompt again — just schedule. Otherwise ask.
    var granted = await NotificationService.areNotificationsEnabled();
    if (!granted) granted = await NotificationService.requestPermission();
    if (!mounted) return;
    if (!granted) {
      // Remember the intent and route the user to settings; the lifecycle
      // re-check completes the enable when they come back with it granted.
      _pendingEnable = true;
      _showPermissionDeniedMessage();
      return; // leave the switch off — nothing persisted yet
    }

    await _scheduleAndEnable();
  }

  /// Flips the switch on and arms the reminder loop for the stored time. The loop
  /// builder reads the local state itself, so a day the user already voted on
  /// gets a post-vote nudge rather than a "go vote" one.
  Future<void> _scheduleAndEnable() async {
    // Everything that needs `context` or `ref` is read before the first await —
    // both are unsafe once the user leaves Settings mid-schedule.
    final l10n = context.l10n;
    final reminder = ref.read(reminderControllerProvider.notifier);
    final prefs = ref.read(sharedPreferencesProvider);
    await reminder.setEnabled(true);
    await rescheduleReminderLoop(prefs: prefs, l10n: l10n);
    _pendingEnable = false;
  }

  /// Reconciles the in-app reminder switch with the real OS permission, on entry
  /// and on every return to the foreground. Two cases it heals:
  ///   * permission revoked while the switch was on → turn it off + cancel, so
  ///     the UI never claims reminders are running when the OS blocks them;
  ///   * the user enabled, got sent to settings, granted, and came back
  ///     ([_pendingEnable]) → finish enabling without a second tap.
  /// No-ops where the plugin isn't live (desktop/web dev, tests).
  Future<void> _syncReminderToggle() async {
    if (!NotificationService.isInitialised) return;
    final enabledOs = await NotificationService.areNotificationsEnabled();
    if (!mounted) return;
    final pref = ref.read(reminderControllerProvider);
    final reminder = ref.read(reminderControllerProvider.notifier);
    if (_pendingEnable && enabledOs) {
      await _scheduleAndEnable();
      return;
    }
    if (pref.enabled && !enabledOs) {
      await NotificationService.cancelDailyReminder();
      await reminder.setEnabled(false);
    }
  }

  /// Tells the user reminders need the OS permission and offers a one-tap jump to
  /// this app's notification settings — the actionable fix for the "nothing
  /// happened" case where the system no longer shows the permission prompt.
  void _showPermissionDeniedMessage() {
    if (!mounted) return;
    AppToast.show(
      context,
      context.l10n.remindersPermissionDenied,
      type: ToastType.error,
      duration: const Duration(seconds: 6),
      action: (
        label: context.l10n.remindersOpenSettings,
        onPressed: NotificationService.openNotificationSettings,
      ),
    );
  }

  /// Opens a time picker and reschedules the reminder for the chosen time.
  Future<void> _openReminderTimePicker() async {
    final current = ref.read(reminderControllerProvider);
    final picked = await showTimePicker(
      context: context,
      initialTime: current.time,
    );
    if (picked == null || !mounted) return;
    // Capture the localizations and the providers before the next await — both
    // `context` and `ref` are unsafe to use after an async gap.
    final l10n = context.l10n;
    final reminder = ref.read(reminderControllerProvider.notifier);
    final prefs = ref.read(sharedPreferencesProvider);
    await reminder.setTime(picked);
    await rescheduleReminderLoop(prefs: prefs, l10n: l10n);
  }

  /// 24-hour `HH:MM` for the reminder-time row — matches the app's clean numeric
  /// style and reads the same in both languages.
  static String _formatTime(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  /// Human-readable name for a language code, shown as the row's trailing label
  /// and the picker options. Each language is named in itself, the convention
  /// for language menus.
  static String _languageName(String code) {
    switch (code) {
      case 'en':
        return 'English';
      case 'pl':
      default:
        return 'Polski';
    }
  }

  /// Opens the language picker and applies the choice.
  ///
  /// Switching the locale rebuilds the app into the new language and re-fetches
  /// the question content (the repository's `p_locale` follows the same source
  /// of truth — see [localeControllerProvider]).
  Future<void> _openLanguagePicker() async {
    final current = ref.read(localeControllerProvider);
    final picked = await showModalBottomSheet<Locale>(
      context: context,
      backgroundColor: context.colors.cardSurface,
      // Without this the sheet is capped at 9/16 of the screen, which a short
      // window or a large system font can push the last option straight out of.
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Text(
                  context.l10n.chooseLanguage,
                  style: TextStyle(
                    color: context.colors.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              for (final locale in kSupportedLocales)
                ListTile(
                  title: Text(
                    _languageName(locale.languageCode),
                    style: TextStyle(color: context.colors.ink, fontSize: 15),
                  ),
                  trailing: locale.languageCode == current.languageCode
                      ? const Icon(Icons.check_rounded, color: AppTheme.spark)
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(locale),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    if (picked == null || !mounted) return;

    final locale = ref.read(localeControllerProvider.notifier);
    final prefs = ref.read(sharedPreferencesProvider);
    await locale.setLocale(picked);

    // Keep the scheduled reminders' text in the newly chosen language. Load
    // the strings for `picked` directly rather than via `context.l10n`, which
    // won't reflect the switch until the next frame.
    final l10n = await AppLocalizations.delegate.load(picked);
    await rescheduleReminderLoop(prefs: prefs, l10n: l10n);
  }

  /// Icon mirroring the chosen appearance, shown as the row's leading glyph.
  static IconData _themeModeIcon(ThemeMode mode) => switch (mode) {
    ThemeMode.system => Icons.brightness_auto_rounded,
    ThemeMode.light => Icons.light_mode_rounded,
    ThemeMode.dark => Icons.dark_mode_rounded,
  };

  /// Localized name for an appearance mode — the row's trailing label and the
  /// picker options.
  static String _themeModeName(BuildContext context, ThemeMode mode) =>
      switch (mode) {
        ThemeMode.system => context.l10n.settingsAppearanceSystem,
        ThemeMode.light => context.l10n.settingsAppearanceLight,
        ThemeMode.dark => context.l10n.settingsAppearanceDark,
      };

  /// Opens the appearance picker (System / Light / Dark) and applies the choice.
  ///
  /// Switching the mode rebuilds `MaterialApp`, which re-resolves `themeMode`
  /// and animates the whole UI to the new palette (see [themeControllerProvider]).
  Future<void> _openAppearancePicker() async {
    final current = ref.read(themeControllerProvider);
    final picked = await showModalBottomSheet<ThemeMode>(
      context: context,
      backgroundColor: context.colors.cardSurface,
      // Three options plus a header don't fit the default 9/16 cap on a short
      // window — "Ciemny" fell off the bottom, painted but out of reach.
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Text(
                  context.l10n.settingsChooseAppearance,
                  style: TextStyle(
                    color: context.colors.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              for (final mode in ThemeMode.values)
                ListTile(
                  leading: Icon(
                    _themeModeIcon(mode),
                    color: context.colors.subtle,
                  ),
                  title: Text(
                    _themeModeName(context, mode),
                    style: TextStyle(color: context.colors.ink, fontSize: 15),
                  ),
                  trailing: mode == current
                      ? const Icon(Icons.check_rounded, color: AppTheme.spark)
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(mode),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    if (picked == null || !mounted) return;
    await ref.read(themeControllerProvider.notifier).setMode(picked);
  }

  /// Pushes the Privacy & data screen — document links plus a plain-language
  /// summary of what the app stores.
  void _openPrivacyData() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const PrivacyDataScreen()));
  }

  /// Pushes the Favorites screen — the user's saved questions as cards.
  void _openFavorites() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const FavoritesScreen()));
  }

  void _openDevTools() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const DevToolsScreen()));
  }

  void _showMessage(String message, {ToastType type = ToastType.info}) {
    if (!mounted) return;
    AppToast.show(context, message, type: type);
  }
}
