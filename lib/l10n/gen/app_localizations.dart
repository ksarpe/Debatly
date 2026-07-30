import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_pl.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('pl'),
  ];

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @later.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get later;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @orDivider.
  ///
  /// In en, this message translates to:
  /// **'OR'**
  String get orDivider;

  /// No description provided for @restorePurchase.
  ///
  /// In en, this message translates to:
  /// **'Restore purchase'**
  String get restorePurchase;

  /// No description provided for @purchaseNotCompleted.
  ///
  /// In en, this message translates to:
  /// **'Purchase not completed.'**
  String get purchaseNotCompleted;

  /// No description provided for @purchaseRestored.
  ///
  /// In en, this message translates to:
  /// **'Purchase restored.'**
  String get purchaseRestored;

  /// No description provided for @purchaseRestoredCelebrate.
  ///
  /// In en, this message translates to:
  /// **'Purchase restored. 🎉'**
  String get purchaseRestoredCelebrate;

  /// No description provided for @noPreviousPurchase.
  ///
  /// In en, this message translates to:
  /// **'No previous purchase found.'**
  String get noPreviousPurchase;

  /// No description provided for @restoreSignInTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore purchase?'**
  String get restoreSignInTitle;

  /// No description provided for @restoreSignInBody.
  ///
  /// In en, this message translates to:
  /// **'If you bought PRO while signed in to an account, sign in to it — PRO and all your data will come back automatically.'**
  String get restoreSignInBody;

  /// No description provided for @restoreOnThisDevice.
  ///
  /// In en, this message translates to:
  /// **'Restore on this device'**
  String get restoreOnThisDevice;

  /// No description provided for @goPro.
  ///
  /// In en, this message translates to:
  /// **'Go PRO'**
  String get goPro;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @signInShort.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signInShort;

  /// No description provided for @authCreateAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get authCreateAccount;

  /// No description provided for @authEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'EMAIL'**
  String get authEmailLabel;

  /// No description provided for @authPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'PASSWORD'**
  String get authPasswordLabel;

  /// No description provided for @authConfirmPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'REPEAT PASSWORD'**
  String get authConfirmPasswordLabel;

  /// No description provided for @authShowPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get authShowPassword;

  /// No description provided for @authHidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get authHidePassword;

  /// No description provided for @authForgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot your password?'**
  String get authForgotPassword;

  /// No description provided for @authNoAccount.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account? '**
  String get authNoAccount;

  /// No description provided for @authHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? '**
  String get authHaveAccount;

  /// No description provided for @authSignUpFree.
  ///
  /// In en, this message translates to:
  /// **'Sign up free'**
  String get authSignUpFree;

  /// No description provided for @authTabSignIn.
  ///
  /// In en, this message translates to:
  /// **'SIGN IN'**
  String get authTabSignIn;

  /// No description provided for @authTabSignUp.
  ///
  /// In en, this message translates to:
  /// **'SIGN UP'**
  String get authTabSignUp;

  /// No description provided for @authEnterEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter your email.'**
  String get authEnterEmail;

  /// No description provided for @authEnterValidEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email.'**
  String get authEnterValidEmail;

  /// No description provided for @authEnterPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter your password.'**
  String get authEnterPassword;

  /// No description provided for @authMinPassword.
  ///
  /// In en, this message translates to:
  /// **'At least 6 characters.'**
  String get authMinPassword;

  /// No description provided for @authPasswordsMismatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords don\'t match.'**
  String get authPasswordsMismatch;

  /// No description provided for @authAccountCreated.
  ///
  /// In en, this message translates to:
  /// **'Account created.'**
  String get authAccountCreated;

  /// No description provided for @authConfirmEmail.
  ///
  /// In en, this message translates to:
  /// **'Check your email and confirm your account.'**
  String get authConfirmEmail;

  /// No description provided for @authContinueWithApple.
  ///
  /// In en, this message translates to:
  /// **'Continue with Apple'**
  String get authContinueWithApple;

  /// No description provided for @authContinueWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get authContinueWithGoogle;

  /// No description provided for @authLegalConsent.
  ///
  /// In en, this message translates to:
  /// **'By continuing, you agree to our {terms} and {privacy}.'**
  String authLegalConsent(String terms, String privacy);

  /// No description provided for @authLegalTermsLink.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get authLegalTermsLink;

  /// No description provided for @authLegalPrivacyLink.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get authLegalPrivacyLink;

  /// No description provided for @authPasswordResetSent.
  ///
  /// In en, this message translates to:
  /// **'If an account exists for that email, we\'ve sent a reset link.'**
  String get authPasswordResetSent;

  /// No description provided for @authMissingSupabaseConfig.
  ///
  /// In en, this message translates to:
  /// **'Supabase configuration is missing. Run the app with SUPABASE_URL and SUPABASE_ANON_KEY.'**
  String get authMissingSupabaseConfig;

  /// No description provided for @authMissingGoogleConfig.
  ///
  /// In en, this message translates to:
  /// **'GOOGLE_SERVER_CLIENT_ID is missing, so Google is temporarily disabled.'**
  String get authMissingGoogleConfig;

  /// No description provided for @settingsSectionApp.
  ///
  /// In en, this message translates to:
  /// **'APP SETTINGS'**
  String get settingsSectionApp;

  /// No description provided for @settingsSectionAccount.
  ///
  /// In en, this message translates to:
  /// **'ACCOUNT'**
  String get settingsSectionAccount;

  /// No description provided for @settingsReminders.
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get settingsReminders;

  /// No description provided for @settingsRemindersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A daily reminder to vote'**
  String get settingsRemindersSubtitle;

  /// No description provided for @settingsReminderTime.
  ///
  /// In en, this message translates to:
  /// **'Reminder time'**
  String get settingsReminderTime;

  /// No description provided for @remindersPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Turn on notifications in system settings to get reminders.'**
  String get remindersPermissionDenied;

  /// No description provided for @remindersOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get remindersOpenSettings;

  /// No description provided for @notificationDailyTitle.
  ///
  /// In en, this message translates to:
  /// **'New questions are waiting 🔥'**
  String get notificationDailyTitle;

  /// No description provided for @notificationDailyBody.
  ///
  /// In en, this message translates to:
  /// **'Cast your vote and keep your streak alive.'**
  String get notificationDailyBody;

  /// No description provided for @notifNudgeTitle1.
  ///
  /// In en, this message translates to:
  /// **'Pick a side 🔥'**
  String get notifNudgeTitle1;

  /// No description provided for @notifNudgeBody1.
  ///
  /// In en, this message translates to:
  /// **'There\'s a question that splits the room. Which side are you on?'**
  String get notifNudgeBody1;

  /// No description provided for @notifNudgeTitle2.
  ///
  /// In en, this message translates to:
  /// **'Cast your vote today 🤔'**
  String get notifNudgeTitle2;

  /// No description provided for @notifNudgeBody2.
  ///
  /// In en, this message translates to:
  /// **'Plenty of people disagree today. Do you?'**
  String get notifNudgeBody2;

  /// No description provided for @notifNudgeTitle3.
  ///
  /// In en, this message translates to:
  /// **'Yes or no?'**
  String get notifNudgeTitle3;

  /// No description provided for @notifNudgeBody3.
  ///
  /// In en, this message translates to:
  /// **'Cast your vote before everyone else does.'**
  String get notifNudgeBody3;

  /// No description provided for @notifStreakTitle.
  ///
  /// In en, this message translates to:
  /// **'Don\'t let it die 🔥'**
  String get notifStreakTitle;

  /// No description provided for @notifStreakBody.
  ///
  /// In en, this message translates to:
  /// **'Day {streak} of your streak. Vote today to keep it alive.'**
  String notifStreakBody(int streak);

  /// No description provided for @notifGraceTitle.
  ///
  /// In en, this message translates to:
  /// **'Your rank is slipping ⚠️'**
  String get notifGraceTitle;

  /// No description provided for @notifGraceBodyTomorrow.
  ///
  /// In en, this message translates to:
  /// **'It drops tomorrow unless you vote today.'**
  String get notifGraceBodyTomorrow;

  /// No description provided for @notifGraceBodyDays.
  ///
  /// In en, this message translates to:
  /// **'It drops in {days} days. Vote to hold on to it.'**
  String notifGraceBodyDays(int days);

  /// No description provided for @notifMinorityTitle.
  ///
  /// In en, this message translates to:
  /// **'Still in the minority? 🤔'**
  String get notifMinorityTitle;

  /// No description provided for @notifMinorityBody.
  ///
  /// In en, this message translates to:
  /// **'{pct}% disagreed with you. See how the split is shaping up.'**
  String notifMinorityBody(int pct);

  /// No description provided for @notifResultTitle.
  ///
  /// In en, this message translates to:
  /// **'How\'s the vote going?'**
  String get notifResultTitle;

  /// No description provided for @notifResultBody.
  ///
  /// In en, this message translates to:
  /// **'See what the majority actually picked.'**
  String get notifResultBody;

  /// No description provided for @notifNextTitle.
  ///
  /// In en, this message translates to:
  /// **'More questions are waiting 🔮'**
  String get notifNextTitle;

  /// No description provided for @notifNextBody.
  ///
  /// In en, this message translates to:
  /// **'Plenty more to vote on. Will you be in the minority again?'**
  String get notifNextBody;

  /// No description provided for @notifSafeTitle.
  ///
  /// In en, this message translates to:
  /// **'Streak secured 🔥'**
  String get notifSafeTitle;

  /// No description provided for @notifSafeBody.
  ///
  /// In en, this message translates to:
  /// **'Nice one. Come back tomorrow to keep it going.'**
  String get notifSafeBody;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @chooseLanguage.
  ///
  /// In en, this message translates to:
  /// **'Choose language'**
  String get chooseLanguage;

  /// No description provided for @settingsAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// No description provided for @settingsChooseAppearance.
  ///
  /// In en, this message translates to:
  /// **'Choose appearance'**
  String get settingsChooseAppearance;

  /// No description provided for @settingsAppearanceSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsAppearanceSystem;

  /// No description provided for @settingsAppearanceLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsAppearanceLight;

  /// No description provided for @settingsAppearanceDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsAppearanceDark;

  /// No description provided for @settingsPremiumActive.
  ///
  /// In en, this message translates to:
  /// **'Premium active'**
  String get settingsPremiumActive;

  /// No description provided for @settingsGoPremium.
  ///
  /// In en, this message translates to:
  /// **'Go Premium'**
  String get settingsGoPremium;

  /// No description provided for @settingsOfflineQuestions.
  ///
  /// In en, this message translates to:
  /// **'Offline questions'**
  String get settingsOfflineQuestions;

  /// No description provided for @offlineDownloadReady.
  ///
  /// In en, this message translates to:
  /// **'Download all questions to read without internet'**
  String get offlineDownloadReady;

  /// No description provided for @offlineDownloadSynced.
  ///
  /// In en, this message translates to:
  /// **'Downloaded · {date}'**
  String offlineDownloadSynced(String date);

  /// No description provided for @offlineDownloadProgress.
  ///
  /// In en, this message translates to:
  /// **'Downloading… {done}/{total}'**
  String offlineDownloadProgress(int done, int total);

  /// No description provided for @offlineDownloadComplete.
  ///
  /// In en, this message translates to:
  /// **'Questions saved for offline.'**
  String get offlineDownloadComplete;

  /// No description provided for @offlineDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed. Check your connection and try again.'**
  String get offlineDownloadFailed;

  /// No description provided for @settingsPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy & data'**
  String get settingsPrivacy;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// No description provided for @settingsFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorite questions'**
  String get settingsFavorites;

  /// No description provided for @favoritesTitle.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favoritesTitle;

  /// No description provided for @favoritesEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No favorites yet'**
  String get favoritesEmptyTitle;

  /// No description provided for @favoritesEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Tap the star on a question to save it here.'**
  String get favoritesEmptyBody;

  /// No description provided for @favoriteAddTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add to favorites'**
  String get favoriteAddTooltip;

  /// No description provided for @favoriteRemoveTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove from favorites'**
  String get favoriteRemoveTooltip;

  /// No description provided for @favoriteAdded.
  ///
  /// In en, this message translates to:
  /// **'Added to favorites'**
  String get favoriteAdded;

  /// No description provided for @favoriteRemoved.
  ///
  /// In en, this message translates to:
  /// **'Removed from favorites'**
  String get favoriteRemoved;

  /// No description provided for @favoritesPremiumOnly.
  ///
  /// In en, this message translates to:
  /// **'Favorites are a Premium feature.'**
  String get favoritesPremiumOnly;

  /// No description provided for @favoriteError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update favorites.'**
  String get favoriteError;

  /// No description provided for @historyTitle.
  ///
  /// In en, this message translates to:
  /// **'Question history'**
  String get historyTitle;

  /// No description provided for @historySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Every question you voted on, with how people voted.'**
  String get historySubtitle;

  /// No description provided for @historyLabel.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyLabel;

  /// No description provided for @historyTooltip.
  ///
  /// In en, this message translates to:
  /// **'Question history'**
  String get historyTooltip;

  /// No description provided for @historyEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get historyEmptyTitle;

  /// No description provided for @historyEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Vote on a question and it will show up here.'**
  String get historyEmptyBody;

  /// No description provided for @historyLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the history.'**
  String get historyLoadError;

  /// No description provided for @historyPremiumTitle.
  ///
  /// In en, this message translates to:
  /// **'History is a PRO feature'**
  String get historyPremiumTitle;

  /// No description provided for @historyPremiumBody.
  ///
  /// In en, this message translates to:
  /// **'Go PRO to look back at every question you voted on and see how others voted.'**
  String get historyPremiumBody;

  /// No description provided for @historyNoVotes.
  ///
  /// In en, this message translates to:
  /// **'No votes'**
  String get historyNoVotes;

  /// No description provided for @aboutVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version} ({build})'**
  String aboutVersion(String version, String build);

  /// No description provided for @aboutTagline.
  ///
  /// In en, this message translates to:
  /// **'Thought-provoking questions to spark real conversation.'**
  String get aboutTagline;

  /// No description provided for @privacyDocsSection.
  ///
  /// In en, this message translates to:
  /// **'DOCUMENTS'**
  String get privacyDocsSection;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get privacyPolicy;

  /// No description provided for @privacyTerms.
  ///
  /// In en, this message translates to:
  /// **'Terms of service'**
  String get privacyTerms;

  /// No description provided for @privacyDeleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account and data'**
  String get privacyDeleteAccount;

  /// No description provided for @privacyOpenInBrowser.
  ///
  /// In en, this message translates to:
  /// **'Opens in your browser'**
  String get privacyOpenInBrowser;

  /// No description provided for @privacyLinkFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the link.'**
  String get privacyLinkFailed;

  /// No description provided for @privacyDataSection.
  ///
  /// In en, this message translates to:
  /// **'WHAT WE STORE'**
  String get privacyDataSection;

  /// No description provided for @privacyDataIntro.
  ///
  /// In en, this message translates to:
  /// **'A quick overview of the data Debatly keeps and why.'**
  String get privacyDataIntro;

  /// No description provided for @privacyDataAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Account & sign-in'**
  String get privacyDataAccountTitle;

  /// No description provided for @privacyDataAccountBody.
  ///
  /// In en, this message translates to:
  /// **'Your email or sign-in identity — or an anonymous ID for guests — so your progress follows you across devices.'**
  String get privacyDataAccountBody;

  /// No description provided for @privacyDataActivityTitle.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get privacyDataActivityTitle;

  /// No description provided for @privacyDataActivityBody.
  ///
  /// In en, this message translates to:
  /// **'Your votes, streak and rank, used to power your questions and progress.'**
  String get privacyDataActivityBody;

  /// No description provided for @privacyDataPurchasesTitle.
  ///
  /// In en, this message translates to:
  /// **'Purchases'**
  String get privacyDataPurchasesTitle;

  /// No description provided for @privacyDataPurchasesBody.
  ///
  /// In en, this message translates to:
  /// **'Your Premium status, handled through the App Store or Google Play. We never see your card details.'**
  String get privacyDataPurchasesBody;

  /// No description provided for @privacyDataAdsTitle.
  ///
  /// In en, this message translates to:
  /// **'Ads'**
  String get privacyDataAdsTitle;

  /// No description provided for @privacyDataAdsBody.
  ///
  /// In en, this message translates to:
  /// **'Free users see ads via Google AdMob, which may use device identifiers. Premium removes ads entirely.'**
  String get privacyDataAdsBody;

  /// No description provided for @settingsPremiumActiveToast.
  ///
  /// In en, this message translates to:
  /// **'Premium active. 🎉'**
  String get settingsPremiumActiveToast;

  /// No description provided for @manageSubSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Manage subscription'**
  String get manageSubSheetTitle;

  /// No description provided for @manageSubStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Premium active'**
  String get manageSubStatusActive;

  /// No description provided for @manageSubStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled — won\'t renew'**
  String get manageSubStatusCancelled;

  /// No description provided for @manageSubRenewsOn.
  ///
  /// In en, this message translates to:
  /// **'Renews on {date}'**
  String manageSubRenewsOn(String date);

  /// No description provided for @manageSubActiveUntil.
  ///
  /// In en, this message translates to:
  /// **'Active until {date}'**
  String manageSubActiveUntil(String date);

  /// No description provided for @manageSubBilledAppStore.
  ///
  /// In en, this message translates to:
  /// **'Billed through the App Store'**
  String get manageSubBilledAppStore;

  /// No description provided for @manageSubBilledPlayStore.
  ///
  /// In en, this message translates to:
  /// **'Billed through Google Play'**
  String get manageSubBilledPlayStore;

  /// No description provided for @manageSubBilledWeb.
  ///
  /// In en, this message translates to:
  /// **'Billed online'**
  String get manageSubBilledWeb;

  /// No description provided for @manageSubNoteAppStore.
  ///
  /// In en, this message translates to:
  /// **'Apple handles billing for your subscription. To change your plan or cancel, open Subscriptions in the App Store — you\'ll keep Premium until the end of the current period.'**
  String get manageSubNoteAppStore;

  /// No description provided for @manageSubNotePlayStore.
  ///
  /// In en, this message translates to:
  /// **'Google handles billing for your subscription. To change your plan or cancel, open Subscriptions in Google Play — you\'ll keep Premium until the end of the current period.'**
  String get manageSubNotePlayStore;

  /// No description provided for @manageSubNoteWeb.
  ///
  /// In en, this message translates to:
  /// **'Manage or cancel your subscription wherever you purchased it. You\'ll keep Premium until the end of the current period.'**
  String get manageSubNoteWeb;

  /// No description provided for @manageSubButtonAppStore.
  ///
  /// In en, this message translates to:
  /// **'Manage in the App Store'**
  String get manageSubButtonAppStore;

  /// No description provided for @manageSubButtonPlayStore.
  ///
  /// In en, this message translates to:
  /// **'Manage in Google Play'**
  String get manageSubButtonPlayStore;

  /// No description provided for @manageSubButtonGeneric.
  ///
  /// In en, this message translates to:
  /// **'Manage subscription'**
  String get manageSubButtonGeneric;

  /// No description provided for @manageSubOpenFailedAppStore.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the App Store. Open Settings › your name › Subscriptions to manage it.'**
  String get manageSubOpenFailedAppStore;

  /// No description provided for @manageSubOpenFailedPlayStore.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open Google Play. Open Play Store › Menu › Subscriptions to manage it.'**
  String get manageSubOpenFailedPlayStore;

  /// No description provided for @manageSubOpenFailedGeneric.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the subscription page. Manage it wherever you purchased Premium.'**
  String get manageSubOpenFailedGeneric;

  /// No description provided for @signedOut.
  ///
  /// In en, this message translates to:
  /// **'Signed out.'**
  String get signedOut;

  /// No description provided for @signOutError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t sign out. Please check your connection and try again.'**
  String get signOutError;

  /// No description provided for @deleteAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete account?'**
  String get deleteAccountTitle;

  /// No description provided for @deleteAccountBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes your account and all related data — your streak, votes and unlocks. This can\'t be undone. If you have an active Premium subscription, cancel it separately in the App Store or Google Play.'**
  String get deleteAccountBody;

  /// No description provided for @deleteAccountSuccess.
  ///
  /// In en, this message translates to:
  /// **'Your account has been deleted.'**
  String get deleteAccountSuccess;

  /// No description provided for @deleteAccountError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete your account. Please check your connection and try again.'**
  String get deleteAccountError;

  /// No description provided for @guestSession.
  ///
  /// In en, this message translates to:
  /// **'Guest session'**
  String get guestSession;

  /// No description provided for @signInToSaveProgress.
  ///
  /// In en, this message translates to:
  /// **'Sign in to save your progress'**
  String get signInToSaveProgress;

  /// No description provided for @yourAccount.
  ///
  /// In en, this message translates to:
  /// **'Your account'**
  String get yourAccount;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get deleteAccount;

  /// No description provided for @comingSoonNamed.
  ///
  /// In en, this message translates to:
  /// **'{label} — coming soon'**
  String comingSoonNamed(String label);

  /// No description provided for @daysInARow.
  ///
  /// In en, this message translates to:
  /// **'DAYS IN A ROW'**
  String get daysInARow;

  /// No description provided for @streakRecord.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Record: {count} day} other{Record: {count} days}}'**
  String streakRecord(int count);

  /// No description provided for @rankLabel.
  ///
  /// In en, this message translates to:
  /// **'RANK'**
  String get rankLabel;

  /// No description provided for @rankCardTopRank.
  ///
  /// In en, this message translates to:
  /// **'Highest rank'**
  String get rankCardTopRank;

  /// No description provided for @rankCardPromotionReady.
  ///
  /// In en, this message translates to:
  /// **'Promotion ready!'**
  String get rankCardPromotionReady;

  /// No description provided for @rankCardDaysToPromotion.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} day to promotion} other{{count} days to promotion}}'**
  String rankCardDaysToPromotion(int count);

  /// No description provided for @settingsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTooltip;

  /// No description provided for @swipeHint.
  ///
  /// In en, this message translates to:
  /// **'Swipe to see the next question'**
  String get swipeHint;

  /// No description provided for @loadErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load questions'**
  String get loadErrorTitle;

  /// No description provided for @loadErrorBody.
  ///
  /// In en, this message translates to:
  /// **'Check your internet connection and try again.'**
  String get loadErrorBody;

  /// No description provided for @offlineBannerLabel.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline'**
  String get offlineBannerLabel;

  /// No description provided for @offlineResultsHidden.
  ///
  /// In en, this message translates to:
  /// **'Results return when you\'re back online'**
  String get offlineResultsHidden;

  /// No description provided for @yourVote.
  ///
  /// In en, this message translates to:
  /// **'Your vote'**
  String get yourVote;

  /// No description provided for @goDeeper.
  ///
  /// In en, this message translates to:
  /// **'GO DEEPER'**
  String get goDeeper;

  /// No description provided for @shareLabel.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get shareLabel;

  /// No description provided for @shareTooltip.
  ///
  /// In en, this message translates to:
  /// **'Share question'**
  String get shareTooltip;

  /// No description provided for @shareSubject.
  ///
  /// In en, this message translates to:
  /// **'A question from Debatly'**
  String get shareSubject;

  /// No description provided for @shareMessage.
  ///
  /// In en, this message translates to:
  /// **'{question}\n\nDebatly — thought-provoking questions.'**
  String shareMessage(String question);

  /// Brand tagline shown on the shareable question image card, under the question.
  ///
  /// In en, this message translates to:
  /// **'Questions that spark real conversation'**
  String get shareCardTagline;

  /// Punchy call-to-action on the shareable question image card, shown above the debatly.app URL. Mirrors the app's YES/NO vote buttons to nudge the recipient to answer.
  ///
  /// In en, this message translates to:
  /// **'You? Yes or no?'**
  String get shareCardHook;

  /// No description provided for @streakTooltip.
  ///
  /// In en, this message translates to:
  /// **'Your streak'**
  String get streakTooltip;

  /// No description provided for @freeUnlockTooltip.
  ///
  /// In en, this message translates to:
  /// **'Free unlock'**
  String get freeUnlockTooltip;

  /// No description provided for @freeUnlockExplain.
  ///
  /// In en, this message translates to:
  /// **'You have one free unlock — swipe to the next question and it unlocks automatically.'**
  String get freeUnlockExplain;

  /// No description provided for @voteYes.
  ///
  /// In en, this message translates to:
  /// **'YES'**
  String get voteYes;

  /// No description provided for @voteNo.
  ///
  /// In en, this message translates to:
  /// **'NO'**
  String get voteNo;

  /// No description provided for @voteFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not record your vote.'**
  String get voteFailed;

  /// No description provided for @votesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} vote} other{{count} votes}}'**
  String votesCount(int count);

  /// No description provided for @revealFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reveal the question — please try again.'**
  String get revealFailed;

  /// No description provided for @adLoading.
  ///
  /// In en, this message translates to:
  /// **'The ad is still loading — try again in a moment.'**
  String get adLoading;

  /// No description provided for @adNoReward.
  ///
  /// In en, this message translates to:
  /// **'No reward — watch the whole video to unlock.'**
  String get adNoReward;

  /// No description provided for @noConnection.
  ///
  /// In en, this message translates to:
  /// **'No connection — try again in a moment.'**
  String get noConnection;

  /// No description provided for @noMoreTitle.
  ///
  /// In en, this message translates to:
  /// **'That\'s all the questions for now'**
  String get noMoreTitle;

  /// No description provided for @noMoreBody.
  ///
  /// In en, this message translates to:
  /// **'Come back tomorrow for new questions — or go PRO to read without limits.'**
  String get noMoreBody;

  /// No description provided for @backToFreeQuestion.
  ///
  /// In en, this message translates to:
  /// **'Back to the free question'**
  String get backToFreeQuestion;

  /// No description provided for @nextQuestionWaiting.
  ///
  /// In en, this message translates to:
  /// **'The next question is waiting'**
  String get nextQuestionWaiting;

  /// No description provided for @watchAdToReveal.
  ///
  /// In en, this message translates to:
  /// **'Watch an ad to reveal a new question.'**
  String get watchAdToReveal;

  /// No description provided for @adLimitReachedInfo.
  ///
  /// In en, this message translates to:
  /// **'Today\'s free unlocks are used up. Come back tomorrow — or unlock everything with PRO.'**
  String get adLimitReachedInfo;

  /// No description provided for @adLimitReachedToast.
  ///
  /// In en, this message translates to:
  /// **'You\'ve hit today\'s ad unlock limit.'**
  String get adLimitReachedToast;

  /// No description provided for @orSignInFreeQuestion.
  ///
  /// In en, this message translates to:
  /// **'Or sign in to get one free question.'**
  String get orSignInFreeQuestion;

  /// No description provided for @unlockWithAd.
  ///
  /// In en, this message translates to:
  /// **'Unlock with an ad'**
  String get unlockWithAd;

  /// No description provided for @proActiveTitle.
  ///
  /// In en, this message translates to:
  /// **'PRO active 🎉'**
  String get proActiveTitle;

  /// No description provided for @savePromptBody.
  ///
  /// In en, this message translates to:
  /// **'Your PRO is currently tied to a guest account. Create an account (email or Google) so you don\'t lose access after reinstalling or on another device — your progress will be kept.'**
  String get savePromptBody;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get createAccount;

  /// No description provided for @smaczkiTitle.
  ///
  /// In en, this message translates to:
  /// **'Arguments'**
  String get smaczkiTitle;

  /// No description provided for @smaczkiSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tips to deepen the conversation around this question.'**
  String get smaczkiSubtitle;

  /// No description provided for @smaczkiLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load tidbits.\n{error}'**
  String smaczkiLoadError(String error);

  /// No description provided for @smaczkiEmpty.
  ///
  /// In en, this message translates to:
  /// **'No tidbits for this question yet.'**
  String get smaczkiEmpty;

  /// No description provided for @ranksLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load ranks.'**
  String get ranksLoadError;

  /// No description provided for @rankLadder.
  ///
  /// In en, this message translates to:
  /// **'Rank ladder'**
  String get rankLadder;

  /// No description provided for @yourRankUpper.
  ///
  /// In en, this message translates to:
  /// **'YOUR RANK'**
  String get yourRankUpper;

  /// No description provided for @topRankRespect.
  ///
  /// In en, this message translates to:
  /// **'Top rank — respect.'**
  String get topRankRespect;

  /// No description provided for @streakDays.
  ///
  /// In en, this message translates to:
  /// **'Streak: {count, plural, one{{count} day} other{{count} days}}'**
  String streakDays(int count);

  /// No description provided for @longestStreakDays.
  ///
  /// In en, this message translates to:
  /// **'Longest streak: {count, plural, one{{count} day} other{{count} days}}'**
  String longestStreakDays(int count);

  /// No description provided for @daysToRank.
  ///
  /// In en, this message translates to:
  /// **'{remaining, plural, one{{remaining} more day to “{rankName}”} other{{remaining} more days to “{rankName}”}}'**
  String daysToRank(int remaining, String rankName);

  /// No description provided for @rankFrom.
  ///
  /// In en, this message translates to:
  /// **'{minStreak}+'**
  String rankFrom(int minStreak);

  /// Warns how many 'graces' (forgiven missed days) remain before the rank drops a tier.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} grace left — then your rank drops} other{{count} graces left — then your rank drops}}'**
  String streakGraceWarning(int count);

  /// Eyebrow above the rank name on the rank-up celebration.
  ///
  /// In en, this message translates to:
  /// **'NEW RANK'**
  String get rankUpEyebrow;

  /// Streak that earned the new rank, shown in the in-app celebration.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count}-day streak 🔥} other{{count}-day streak 🔥}}'**
  String rankUpStreakLine(int count);

  /// Dismiss button on the rank-up celebration.
  ///
  /// In en, this message translates to:
  /// **'Awesome!'**
  String get rankUpDismiss;

  /// Eyebrow on the shareable rank poster, above the rank name.
  ///
  /// In en, this message translates to:
  /// **'MY NEW RANK'**
  String get rankShareHeadline;

  /// Streak line on the shareable rank poster.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count}-day streak} other{{count}-day streak}}'**
  String rankShareStreakLine(int count);

  /// Subject line when sharing the rank poster (email etc.).
  ///
  /// In en, this message translates to:
  /// **'My rank in Debatly'**
  String get rankShareSubject;

  /// Accompanying text shared alongside the rank poster image.
  ///
  /// In en, this message translates to:
  /// **'My new rank in Debatly: {rank} 🔥\n\nDebatly — thought-provoking questions.'**
  String rankShareMessage(String rank);

  /// No description provided for @onboardingSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboardingSkip;

  /// No description provided for @onboardingNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get onboardingNext;

  /// No description provided for @onboardingWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Debatly'**
  String get onboardingWelcomeTitle;

  /// No description provided for @onboardingWelcomeBody.
  ///
  /// In en, this message translates to:
  /// **'Sharp questions that split the room — vote and see which side you\'re on.'**
  String get onboardingWelcomeBody;

  /// No description provided for @onboardingTasteKicker.
  ///
  /// In en, this message translates to:
  /// **'YOUR TURN'**
  String get onboardingTasteKicker;

  /// No description provided for @onboardingTasteQuestion.
  ///
  /// In en, this message translates to:
  /// **'Is emotional cheating worse than physical cheating?'**
  String get onboardingTasteQuestion;

  /// No description provided for @onboardingTasteMajority.
  ///
  /// In en, this message translates to:
  /// **'You\'re with the majority. 🙌'**
  String get onboardingTasteMajority;

  /// No description provided for @onboardingTasteMinority.
  ///
  /// In en, this message translates to:
  /// **'You\'re in the minority. 👀'**
  String get onboardingTasteMinority;

  /// No description provided for @onboardingTasteContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get onboardingTasteContinue;

  /// No description provided for @onboardingTasteSmaczekIntro.
  ///
  /// In en, this message translates to:
  /// **'Every question also comes with talking points that deepen the conversation. Like this one:'**
  String get onboardingTasteSmaczekIntro;

  /// No description provided for @onboardingTasteSmaczek.
  ///
  /// In en, this message translates to:
  /// **'Psychologists talk about “micro-cheating” — hundreds of small secrets and hidden messages. One night or a thousand whispers: which is harder to forgive?'**
  String get onboardingTasteSmaczek;

  /// No description provided for @onboardingChoiceTitle.
  ///
  /// In en, this message translates to:
  /// **'How do you want to start?'**
  String get onboardingChoiceTitle;

  /// No description provided for @onboardingChoiceBody.
  ///
  /// In en, this message translates to:
  /// **'You can sign in anytime later from settings.'**
  String get onboardingChoiceBody;

  /// No description provided for @onboardingSignInCta.
  ///
  /// In en, this message translates to:
  /// **'Sign in / Sign up'**
  String get onboardingSignInCta;

  /// No description provided for @onboardingSignInHint.
  ///
  /// In en, this message translates to:
  /// **'Save your streak and progress'**
  String get onboardingSignInHint;

  /// No description provided for @onboardingStartAnon.
  ///
  /// In en, this message translates to:
  /// **'Start anonymously'**
  String get onboardingStartAnon;

  /// No description provided for @onboardingStartAnonHint.
  ///
  /// In en, this message translates to:
  /// **'With some limits'**
  String get onboardingStartAnonHint;

  /// No description provided for @onboardingNotifyTitle.
  ///
  /// In en, this message translates to:
  /// **'Never miss a new question'**
  String get onboardingNotifyTitle;

  /// No description provided for @onboardingNotifyBody.
  ///
  /// In en, this message translates to:
  /// **'Turn on reminders and we\'ll nudge you once a day to come and vote. No spam — just one a day.'**
  String get onboardingNotifyBody;

  /// No description provided for @onboardingNotifyEnable.
  ///
  /// In en, this message translates to:
  /// **'Turn on reminders'**
  String get onboardingNotifyEnable;

  /// No description provided for @onboardingNotifySkip.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get onboardingNotifySkip;

  /// No description provided for @paywallTitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock every question and vote'**
  String get paywallTitle;

  /// No description provided for @paywallTitleReadingLimit.
  ///
  /// In en, this message translates to:
  /// **'Keep reading — no limits, no waiting'**
  String get paywallTitleReadingLimit;

  /// No description provided for @paywallTitleAdLimit.
  ///
  /// In en, this message translates to:
  /// **'Don\'t wait until tomorrow — unlock everything'**
  String get paywallTitleAdLimit;

  /// No description provided for @paywallTitleSmaczki.
  ///
  /// In en, this message translates to:
  /// **'Unlock every argument, for every question'**
  String get paywallTitleSmaczki;

  /// No description provided for @paywallTitleFavorites.
  ///
  /// In en, this message translates to:
  /// **'Keep your favorite questions forever'**
  String get paywallTitleFavorites;

  /// No description provided for @paywallTitleHistory.
  ///
  /// In en, this message translates to:
  /// **'Every vote you\'ve cast, in one place'**
  String get paywallTitleHistory;

  /// No description provided for @paywallBenefitUnlimitedTitle.
  ///
  /// In en, this message translates to:
  /// **'Unlimited questions'**
  String get paywallBenefitUnlimitedTitle;

  /// No description provided for @paywallBenefitUnlimitedBody.
  ///
  /// In en, this message translates to:
  /// **'Browse the whole library of 1000 questions — no daily limits, no waiting.'**
  String get paywallBenefitUnlimitedBody;

  /// No description provided for @paywallBenefitNoAdsTitle.
  ///
  /// In en, this message translates to:
  /// **'Zero ads'**
  String get paywallBenefitNoAdsTitle;

  /// No description provided for @paywallBenefitNoAdsBody.
  ///
  /// In en, this message translates to:
  /// **'No rewarded ads, no interruptions — just the next question.'**
  String get paywallBenefitNoAdsBody;

  /// No description provided for @paywallBenefitSmaczkiTitle.
  ///
  /// In en, this message translates to:
  /// **'Arguments for every question'**
  String get paywallBenefitSmaczkiTitle;

  /// No description provided for @paywallBenefitSmaczkiBody.
  ///
  /// In en, this message translates to:
  /// **'Unlock all the talking points that deepen the conversation.'**
  String get paywallBenefitSmaczkiBody;

  /// No description provided for @paywallBenefitFavoritesTitle.
  ///
  /// In en, this message translates to:
  /// **'Favorites & voting history'**
  String get paywallBenefitFavoritesTitle;

  /// No description provided for @paywallBenefitFavoritesBody.
  ///
  /// In en, this message translates to:
  /// **'Save the best questions and look back at every vote you\'ve cast.'**
  String get paywallBenefitFavoritesBody;

  /// No description provided for @paywallLifetime.
  ///
  /// In en, this message translates to:
  /// **'Lifetime'**
  String get paywallLifetime;

  /// No description provided for @paywallAnnual.
  ///
  /// In en, this message translates to:
  /// **'Yearly'**
  String get paywallAnnual;

  /// No description provided for @paywallMonthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get paywallMonthly;

  /// No description provided for @paywallWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get paywallWeekly;

  /// No description provided for @paywallPerMonth.
  ///
  /// In en, this message translates to:
  /// **'/mo'**
  String get paywallPerMonth;

  /// No description provided for @paywallBestValue.
  ///
  /// In en, this message translates to:
  /// **'BEST VALUE'**
  String get paywallBestValue;

  /// No description provided for @paywallCta.
  ///
  /// In en, this message translates to:
  /// **'Unlock full access'**
  String get paywallCta;

  /// Subline on the lifetime plan card: the lifetime price expressed as months of the monthly subscription, rounded so the claim is always true.
  ///
  /// In en, this message translates to:
  /// **'{months, plural, one{Less than {months} month of the subscription} other{Less than {months} months of the subscription}}'**
  String paywallLifetimeVsMonthly(int months);

  /// No description provided for @paywallLifetimeNote.
  ///
  /// In en, this message translates to:
  /// **'One-time payment — yours forever'**
  String get paywallLifetimeNote;

  /// No description provided for @paywallSubscriptionNote.
  ///
  /// In en, this message translates to:
  /// **'No commitment, cancel anytime'**
  String get paywallSubscriptionNote;

  /// No description provided for @paywallLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the offers. Check your connection and try again.'**
  String get paywallLoadError;

  /// No description provided for @paywallTermsLink.
  ///
  /// In en, this message translates to:
  /// **'Terms'**
  String get paywallTermsLink;

  /// No description provided for @paywallPrivacyLink.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get paywallPrivacyLink;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'pl'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'pl':
      return AppLocalizationsPl();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
