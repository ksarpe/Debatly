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

  /// No description provided for @storeUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the store. Check your connection and try again.'**
  String get storeUnreachable;

  /// No description provided for @purchaseSyncPending.
  ///
  /// In en, this message translates to:
  /// **'Your purchase went through, but we couldn\'t confirm it yet. Try “Restore purchase” in a moment.'**
  String get purchaseSyncPending;

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

  /// No description provided for @authCreateAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get authCreateAccount;

  /// No description provided for @authWelcomeBackTitle.
  ///
  /// In en, this message translates to:
  /// **'Good to see you again'**
  String get authWelcomeBackTitle;

  /// No description provided for @authWelcomeBackSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to get back to your debates.'**
  String get authWelcomeBackSubtitle;

  /// No description provided for @authRegisterTitle.
  ///
  /// In en, this message translates to:
  /// **'Join Debatly'**
  String get authRegisterTitle;

  /// No description provided for @authRegisterSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create an account and take a side in the debate.'**
  String get authRegisterSubtitle;

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

  /// No description provided for @authSetNewPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Set a new password'**
  String get authSetNewPasswordTitle;

  /// No description provided for @authSetNewPasswordSubtitle.
  ///
  /// In en, this message translates to:
  /// **'You\'re signed in from the link — pick the new password for your account.'**
  String get authSetNewPasswordSubtitle;

  /// No description provided for @authNewPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'NEW PASSWORD'**
  String get authNewPasswordLabel;

  /// No description provided for @authSetNewPasswordCta.
  ///
  /// In en, this message translates to:
  /// **'SAVE NEW PASSWORD'**
  String get authSetNewPasswordCta;

  /// No description provided for @authPasswordUpdated.
  ///
  /// In en, this message translates to:
  /// **'Password changed. You\'re signed in.'**
  String get authPasswordUpdated;

  /// No description provided for @authRecoveryLinkInvalid.
  ///
  /// In en, this message translates to:
  /// **'That reset link has expired or was already used. Request a new one.'**
  String get authRecoveryLinkInvalid;

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

  /// No description provided for @authAlreadySignedIn.
  ///
  /// In en, this message translates to:
  /// **'You\'re already signed in to your account — no need to register again.'**
  String get authAlreadySignedIn;

  /// No description provided for @authRegisteredPendingConfirm.
  ///
  /// In en, this message translates to:
  /// **'Your account is already registered to {email}. Tap the link in that email to confirm it.'**
  String authRegisteredPendingConfirm(String email);

  /// No description provided for @authErrorInvalidCredentials.
  ///
  /// In en, this message translates to:
  /// **'Incorrect email or password.'**
  String get authErrorInvalidCredentials;

  /// No description provided for @authErrorEmailNotConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirm your email first — check your inbox.'**
  String get authErrorEmailNotConfirmed;

  /// No description provided for @authErrorEmailExists.
  ///
  /// In en, this message translates to:
  /// **'An account with this email already exists. Sign in instead.'**
  String get authErrorEmailExists;

  /// No description provided for @authErrorSamePassword.
  ///
  /// In en, this message translates to:
  /// **'That\'s already your current password.'**
  String get authErrorSamePassword;

  /// No description provided for @authErrorWeakPassword.
  ///
  /// In en, this message translates to:
  /// **'That password is too weak. Try a longer one.'**
  String get authErrorWeakPassword;

  /// No description provided for @authErrorTooManyRequests.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Wait a moment and try again.'**
  String get authErrorTooManyRequests;

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

  /// No description provided for @historyAnsweredCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} answered} other{{count} answered}}'**
  String historyAnsweredCount(int count);

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

  /// No description provided for @historyYourVote.
  ///
  /// In en, this message translates to:
  /// **'YOU: {vote}'**
  String historyYourVote(String vote);

  /// No description provided for @historyVersus.
  ///
  /// In en, this message translates to:
  /// **'vs'**
  String get historyVersus;

  /// No description provided for @historyLockedTitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock your full history'**
  String get historyLockedTitle;

  /// No description provided for @historyLockedBody.
  ///
  /// In en, this message translates to:
  /// **'Free accounts see only today here. Go PRO to browse every vote you\'ve ever cast.'**
  String get historyLockedBody;

  /// No description provided for @historySearchTooltip.
  ///
  /// In en, this message translates to:
  /// **'Search history'**
  String get historySearchTooltip;

  /// No description provided for @historyLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load {count} more'**
  String historyLoadMore(int count);

  /// No description provided for @historyNoVotes.
  ///
  /// In en, this message translates to:
  /// **'No votes'**
  String get historyNoVotes;

  /// No description provided for @searchQuestionsHint.
  ///
  /// In en, this message translates to:
  /// **'Search questions…'**
  String get searchQuestionsHint;

  /// No description provided for @searchClearTooltip.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get searchClearTooltip;

  /// No description provided for @searchCloseTooltip.
  ///
  /// In en, this message translates to:
  /// **'Close search'**
  String get searchCloseTooltip;

  /// No description provided for @searchNoResultsTitle.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get searchNoResultsTitle;

  /// No description provided for @searchNoResultsBody.
  ///
  /// In en, this message translates to:
  /// **'No questions match your search. Try a different word.'**
  String get searchNoResultsBody;

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

  /// No description provided for @manageSubStatusLifetime.
  ///
  /// In en, this message translates to:
  /// **'Lifetime access'**
  String get manageSubStatusLifetime;

  /// No description provided for @manageSubNoteLifetime.
  ///
  /// In en, this message translates to:
  /// **'This was a one-time purchase — there is no subscription to cancel. Premium stays on this account forever.'**
  String get manageSubNoteLifetime;

  /// No description provided for @manageSubClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get manageSubClose;

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

  /// No description provided for @accountUnsecuredNote.
  ///
  /// In en, this message translates to:
  /// **'Your progress is saved only on this phone'**
  String get accountUnsecuredNote;

  /// No description provided for @secureAccount.
  ///
  /// In en, this message translates to:
  /// **'Secure account'**
  String get secureAccount;

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

  /// Affordance on the rank stat card telling the user it opens the rank ladder.
  ///
  /// In en, this message translates to:
  /// **'TAP'**
  String get rankCardTapHint;

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

  /// No description provided for @loadErrorBodyEmpty.
  ///
  /// In en, this message translates to:
  /// **'Today\'s question didn\'t come through. Try again in a moment.'**
  String get loadErrorBodyEmpty;

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
  /// **'AGAINST YOU'**
  String get goDeeper;

  /// No description provided for @smaczkiBarPro.
  ///
  /// In en, this message translates to:
  /// **'THE CASE AGAINST'**
  String get smaczkiBarPro;

  /// No description provided for @smaczkiBarFree.
  ///
  /// In en, this message translates to:
  /// **'TWO MORE LEFT'**
  String get smaczkiBarFree;

  /// No description provided for @smaczkiBarUntagged.
  ///
  /// In en, this message translates to:
  /// **'TWO MORE ARGUMENTS'**
  String get smaczkiBarUntagged;

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

  /// Tooltip on the top-bar icon that opens the conformity-axis panel.
  ///
  /// In en, this message translates to:
  /// **'Your conformity axis'**
  String get conformityTooltip;

  /// Uppercase eyebrow title of the slide-down conformity panel.
  ///
  /// In en, this message translates to:
  /// **'CONFORMITY AXIS'**
  String get conformityTitle;

  /// Header line of the conformity panel: share of the user's votes cast on the majority side.
  ///
  /// In en, this message translates to:
  /// **'{pct}% with the majority'**
  String conformityPctLine(int pct);

  /// Conformity tier for 0-19% votes with the majority. Rendered uppercase on the axis.
  ///
  /// In en, this message translates to:
  /// **'Lone wolf'**
  String get conformityTierLoneWolf;

  /// No description provided for @conformityTierRebel.
  ///
  /// In en, this message translates to:
  /// **'Rebel'**
  String get conformityTierRebel;

  /// No description provided for @conformityTierIndependent.
  ///
  /// In en, this message translates to:
  /// **'Independent'**
  String get conformityTierIndependent;

  /// No description provided for @conformityTierInTheCurrent.
  ///
  /// In en, this message translates to:
  /// **'With the flow'**
  String get conformityTierInTheCurrent;

  /// No description provided for @conformityTierCrowdVoice.
  ///
  /// In en, this message translates to:
  /// **'Voice of the crowd'**
  String get conformityTierCrowdVoice;

  /// Footer of the conformity panel: progress line toward the next tier up the axis.
  ///
  /// In en, this message translates to:
  /// **'To reach {tier}'**
  String conformityNextTierLabel(String tier);

  /// How many consecutive with-the-majority votes would reach the next tier.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} vote with the majority} other{{count} votes with the majority}}'**
  String conformityVotesNeeded(int count);

  /// No description provided for @conformityEmpty.
  ///
  /// In en, this message translates to:
  /// **'Vote on a few questions and you\'ll see which side you usually take.'**
  String get conformityEmpty;

  /// No description provided for @conformityLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your axis — try again in a moment.'**
  String get conformityLoadError;

  /// Small pill badge shown above a question added to the catalog within the last two weeks.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get newQuestionBadge;

  /// Tooltip shown when tapping the 'New' badge, explaining why the vote count may still be low.
  ///
  /// In en, this message translates to:
  /// **'Freshly added question — the community is just starting to vote.'**
  String get newQuestionTooltip;

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

  /// No description provided for @noConnection.
  ///
  /// In en, this message translates to:
  /// **'No connection — try again in a moment.'**
  String get noConnection;

  /// No description provided for @backToLatestQuestion.
  ///
  /// In en, this message translates to:
  /// **'Back to the latest question'**
  String get backToLatestQuestion;

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

  /// No description provided for @secureStreakTitle.
  ///
  /// In en, this message translates to:
  /// **'Secure your streak 🔥'**
  String get secureStreakTitle;

  /// No description provided for @secureStreakBody.
  ///
  /// In en, this message translates to:
  /// **'You\'re on a {streak}-day streak — but it only lives on this phone. Create an account (email or Google) and it will survive a reinstall or a new device.'**
  String secureStreakBody(int streak);

  /// No description provided for @suggestQuestionTitle.
  ///
  /// In en, this message translates to:
  /// **'Suggest a question'**
  String get suggestQuestionTitle;

  /// No description provided for @suggestQuestionSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Got an idea that will split the room? Send it in'**
  String get suggestQuestionSettingsSubtitle;

  /// No description provided for @suggestQuestionIntro.
  ///
  /// In en, this message translates to:
  /// **'The best questions start with \"Should…\", have no comfortable answer and split the room in half. Rough ideas welcome — we\'ll polish it.'**
  String get suggestQuestionIntro;

  /// No description provided for @suggestQuestionHint.
  ///
  /// In en, this message translates to:
  /// **'Should…?'**
  String get suggestQuestionHint;

  /// No description provided for @suggestQuestionMinChars.
  ///
  /// In en, this message translates to:
  /// **'At least 10 characters'**
  String get suggestQuestionMinChars;

  /// No description provided for @suggestQuestionSend.
  ///
  /// In en, this message translates to:
  /// **'Send suggestion'**
  String get suggestQuestionSend;

  /// No description provided for @suggestQuestionThanks.
  ///
  /// In en, this message translates to:
  /// **'Thanks! Your idea just reached us.'**
  String get suggestQuestionThanks;

  /// No description provided for @suggestQuestionFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send it — try again in a moment.'**
  String get suggestQuestionFailed;

  /// No description provided for @suggestQuestionRateLimited.
  ///
  /// In en, this message translates to:
  /// **'That\'s plenty for today — come back tomorrow.'**
  String get suggestQuestionRateLimited;

  /// No description provided for @suggestQuestionNudge.
  ///
  /// In en, this message translates to:
  /// **'Got an idea for a question that sticks in people\'s heads? Send it in!'**
  String get suggestQuestionNudge;

  /// No description provided for @suggestQuestionNudgeAction.
  ///
  /// In en, this message translates to:
  /// **'Suggest'**
  String get suggestQuestionNudgeAction;

  /// No description provided for @smaczkiTitle.
  ///
  /// In en, this message translates to:
  /// **'Arguments'**
  String get smaczkiTitle;

  /// No description provided for @smaczkiTitleTag.
  ///
  /// In en, this message translates to:
  /// **'(smaczki)'**
  String get smaczkiTitleTag;

  /// No description provided for @smaczkiSubtitle.
  ///
  /// In en, this message translates to:
  /// **'You are not going to like this one.'**
  String get smaczkiSubtitle;

  /// How many arguments are left besides the one served right after the vote.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{One more left. Also against you.} =2{Two more left. Both against you.} other{{count} more left. All against you.}}'**
  String smaczkiRemaining(int count);

  /// No description provided for @smaczekSuggestCta.
  ///
  /// In en, this message translates to:
  /// **'Suggest your own'**
  String get smaczekSuggestCta;

  /// No description provided for @smaczekSuggestHint.
  ///
  /// In en, this message translates to:
  /// **'Your argument…'**
  String get smaczekSuggestHint;

  /// No description provided for @smaczekSuggestMinChars.
  ///
  /// In en, this message translates to:
  /// **'At least 5 characters'**
  String get smaczekSuggestMinChars;

  /// No description provided for @smaczekSuggestSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get smaczekSuggestSend;

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

  /// No description provided for @smaczkiUnlockCta.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get smaczkiUnlockCta;

  /// No description provided for @smaczkiLockedBeforeVote.
  ///
  /// In en, this message translates to:
  /// **'Vote first. Then I\'ll see if you hold.'**
  String get smaczkiLockedBeforeVote;

  /// No description provided for @smaczekChallengeEyebrow.
  ///
  /// In en, this message translates to:
  /// **'BEFORE I SHOW YOU THE RESULT'**
  String get smaczekChallengeEyebrow;

  /// No description provided for @challengeHoldCta.
  ///
  /// In en, this message translates to:
  /// **'I\'M NOT BUDGING'**
  String get challengeHoldCta;

  /// No description provided for @challengeMovedCta.
  ///
  /// In en, this message translates to:
  /// **'THAT GOT ME'**
  String get challengeMovedCta;

  /// No description provided for @smaczkiSheetFreeHeader.
  ///
  /// In en, this message translates to:
  /// **'You\'ve read the first. Two left — both against you.'**
  String get smaczkiSheetFreeHeader;

  /// No description provided for @resultFlipLine.
  ///
  /// In en, this message translates to:
  /// **'The counter-argument flipped {percent}% of voters.'**
  String resultFlipLine(int percent);

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

  /// Progress line in the rank sheet. Deliberately does not name the next rank — it stays a surprise until it is unlocked.
  ///
  /// In en, this message translates to:
  /// **'{remaining, plural, one{{remaining} more day to the next rank} other{{remaining} more days to the next rank}}'**
  String daysToNextRank(int remaining);

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

  /// No description provided for @onboardingBegin.
  ///
  /// In en, this message translates to:
  /// **'Let\'s begin'**
  String get onboardingBegin;

  /// No description provided for @onboardingWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Think you can read people?'**
  String get onboardingWelcomeTitle;

  /// No description provided for @onboardingWelcomeTitlePunch.
  ///
  /// In en, this message translates to:
  /// **'How well do you know yourself?'**
  String get onboardingWelcomeTitlePunch;

  /// No description provided for @onboardingWelcomeBody.
  ///
  /// In en, this message translates to:
  /// **'Let\'s find out. You\'ll get a question with no good answer — vote and see how many people think differently than you.'**
  String get onboardingWelcomeBody;

  /// No description provided for @onboardingTasteKicker.
  ///
  /// In en, this message translates to:
  /// **'YOUR TURN'**
  String get onboardingTasteKicker;

  /// No description provided for @onboardingTasteQuestion.
  ///
  /// In en, this message translates to:
  /// **'Should an obese person have to pay for two plane seats?'**
  String get onboardingTasteQuestion;

  /// No description provided for @onboardingTasteHoldOnTitle.
  ///
  /// In en, this message translates to:
  /// **'Hold on…'**
  String get onboardingTasteHoldOnTitle;

  /// No description provided for @onboardingTasteVotedTakSmaczek1.
  ///
  /// In en, this message translates to:
  /// **'You\'re buying a flight, not centimetres of seat.'**
  String get onboardingTasteVotedTakSmaczek1;

  /// No description provided for @onboardingTasteVotedTakSmaczek2.
  ///
  /// In en, this message translates to:
  /// **'A tall passenger takes up more room too. Charge them extra as well?'**
  String get onboardingTasteVotedTakSmaczek2;

  /// No description provided for @onboardingTasteVotedTakSmaczek3.
  ///
  /// In en, this message translates to:
  /// **'And how would you check who pays? A gate scale before boarding?'**
  String get onboardingTasteVotedTakSmaczek3;

  /// No description provided for @onboardingTasteVotedTakSmaczek4.
  ///
  /// In en, this message translates to:
  /// **'What about people whose weight comes from illness? Punished for life?'**
  String get onboardingTasteVotedTakSmaczek4;

  /// No description provided for @onboardingTasteVotedNieSmaczek1.
  ///
  /// In en, this message translates to:
  /// **'You already pay extra for a few kilos of luggage.'**
  String get onboardingTasteVotedNieSmaczek1;

  /// No description provided for @onboardingTasteVotedNieSmaczek2.
  ///
  /// In en, this message translates to:
  /// **'What about the person squeezed next to you? Same fare, worse seat.'**
  String get onboardingTasteVotedNieSmaczek2;

  /// No description provided for @onboardingTasteVotedNieSmaczek3.
  ///
  /// In en, this message translates to:
  /// **'A heavier plane burns more fuel — you pay the difference in your fare.'**
  String get onboardingTasteVotedNieSmaczek3;

  /// No description provided for @onboardingTasteVotedNieSmaczek4.
  ///
  /// In en, this message translates to:
  /// **'Would you fly three hours squeezed into half your seat?'**
  String get onboardingTasteVotedNieSmaczek4;

  /// No description provided for @onboardingTasteChangeMind.
  ///
  /// In en, this message translates to:
  /// **'I\'ve changed my mind'**
  String get onboardingTasteChangeMind;

  /// No description provided for @onboardingTasteStandFirm.
  ///
  /// In en, this message translates to:
  /// **'I\'m sticking with it'**
  String get onboardingTasteStandFirm;

  /// No description provided for @onboardingTasteGotYouTitle.
  ///
  /// In en, this message translates to:
  /// **'Got you after all!'**
  String get onboardingTasteGotYouTitle;

  /// No description provided for @onboardingTasteGotYouSub.
  ///
  /// In en, this message translates to:
  /// **'See how the others voted.'**
  String get onboardingTasteGotYouSub;

  /// No description provided for @onboardingTasteStandFirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Good to stand your ground!'**
  String get onboardingTasteStandFirmTitle;

  /// No description provided for @onboardingTasteStandFirmSub.
  ///
  /// In en, this message translates to:
  /// **'But see how the others voted.'**
  String get onboardingTasteStandFirmSub;

  /// No description provided for @onboardingTasteSeeNext.
  ///
  /// In en, this message translates to:
  /// **'Let\'s see the next one'**
  String get onboardingTasteSeeNext;

  /// No description provided for @onboardingTasteNextTitle.
  ///
  /// In en, this message translates to:
  /// **'Let\'s try another one…'**
  String get onboardingTasteNextTitle;

  /// No description provided for @onboardingTasteQuestion2.
  ///
  /// In en, this message translates to:
  /// **'Should you tell a new partner exactly how many people you\'ve slept with?'**
  String get onboardingTasteQuestion2;

  /// No description provided for @onboardingTasteSureTitle.
  ///
  /// In en, this message translates to:
  /// **'Are you sure though?'**
  String get onboardingTasteSureTitle;

  /// No description provided for @onboardingTasteQ2VotedTakSmaczek1.
  ///
  /// In en, this message translates to:
  /// **'There\'s no argument only if your numbers happen to match.'**
  String get onboardingTasteQ2VotedTakSmaczek1;

  /// No description provided for @onboardingTasteQ2VotedTakSmaczek2.
  ///
  /// In en, this message translates to:
  /// **'If the number isn\'t 100, what does it actually change?'**
  String get onboardingTasteQ2VotedTakSmaczek2;

  /// No description provided for @onboardingTasteQ2VotedTakSmaczek3.
  ///
  /// In en, this message translates to:
  /// **'The honesty fades, the number stays — back at the very first fight.'**
  String get onboardingTasteQ2VotedTakSmaczek3;

  /// No description provided for @onboardingTasteQ2VotedTakSmaczek4.
  ///
  /// In en, this message translates to:
  /// **'Would you still tell if your number were embarrassingly big?'**
  String get onboardingTasteQ2VotedTakSmaczek4;

  /// No description provided for @onboardingTasteQ2VotedNieSmaczek1.
  ///
  /// In en, this message translates to:
  /// **'Starting a relationship on a secret — solid foundation?'**
  String get onboardingTasteQ2VotedNieSmaczek1;

  /// No description provided for @onboardingTasteQ2VotedNieSmaczek2.
  ///
  /// In en, this message translates to:
  /// **'Hiding the number means you think something\'s wrong with it.'**
  String get onboardingTasteQ2VotedNieSmaczek2;

  /// No description provided for @onboardingTasteQ2VotedNieSmaczek3.
  ///
  /// In en, this message translates to:
  /// **'The truth comes out anyway — years later, at the worst moment.'**
  String get onboardingTasteQ2VotedNieSmaczek3;

  /// No description provided for @onboardingTasteQ2VotedNieSmaczek4.
  ///
  /// In en, this message translates to:
  /// **'And if they ask you straight out? Lie to their face?'**
  String get onboardingTasteQ2VotedNieSmaczek4;

  /// No description provided for @onboardingTasteQ2GotYouTitle.
  ///
  /// In en, this message translates to:
  /// **'See? Nothing is obvious.'**
  String get onboardingTasteQ2GotYouTitle;

  /// No description provided for @onboardingTasteQ2GotYouSub.
  ///
  /// In en, this message translates to:
  /// **'And that was only question two…'**
  String get onboardingTasteQ2GotYouSub;

  /// No description provided for @onboardingTasteQ2StandFirmTitle.
  ///
  /// In en, this message translates to:
  /// **'So you can\'t be moved?'**
  String get onboardingTasteQ2StandFirmTitle;

  /// No description provided for @onboardingTasteQ2StandFirmSub.
  ///
  /// In en, this message translates to:
  /// **'We\'ll see. We have plenty of questions…'**
  String get onboardingTasteQ2StandFirmSub;

  /// No description provided for @onboardingTasteWhatElse.
  ///
  /// In en, this message translates to:
  /// **'What else have you got?'**
  String get onboardingTasteWhatElse;

  /// Headline of the bridge screen shown right after the onboarding taste votes — it explains the freemium model instead of walling the user.
  ///
  /// In en, this message translates to:
  /// **'That was two — hundreds more to go'**
  String get bridgeTitle;

  /// No description provided for @bridgeBody.
  ///
  /// In en, this message translates to:
  /// **'You get one new question every day. Free, forever. Don\'t want to wait until tomorrow? Unlock the whole catalogue right away.'**
  String get bridgeBody;

  /// Primary (visually dominant) bridge CTA — continues into the app for free.
  ///
  /// In en, this message translates to:
  /// **'Get today\'s question'**
  String get bridgeCtaPrimary;

  /// Secondary bridge CTA — opens the paywall sheet.
  ///
  /// In en, this message translates to:
  /// **'Unlock all'**
  String get bridgeCtaSecondary;

  /// Small line under the secondary bridge CTA label — hints that PRO carries more than just the catalog.
  ///
  /// In en, this message translates to:
  /// **'(and many more perks)'**
  String get bridgeCtaSecondaryHint;

  /// No description provided for @onboardingNotifyTitle.
  ///
  /// In en, this message translates to:
  /// **'Hey, one more thing'**
  String get onboardingNotifyTitle;

  /// No description provided for @onboardingNotifyBody.
  ///
  /// In en, this message translates to:
  /// **'I can remind you to vote every day, at a time you pick. Voting takes 10 seconds — and your streak grows on its own. You can always switch it off in settings.'**
  String get onboardingNotifyBody;

  /// No description provided for @onboardingNotifyEnable.
  ///
  /// In en, this message translates to:
  /// **'Turn on reminders'**
  String get onboardingNotifyEnable;

  /// No description provided for @onboardingNotifySkip.
  ///
  /// In en, this message translates to:
  /// **'Maybe later'**
  String get onboardingNotifySkip;

  /// Tiny uppercase caption set inside the day wall's circular countdown, under the live HH:MM:SS ticking down to the user's local midnight. Keep it short — it has to fit inside the ring.
  ///
  /// In en, this message translates to:
  /// **'Until free'**
  String get wallCountdownCaption;

  /// No description provided for @wallCtaUnlock.
  ///
  /// In en, this message translates to:
  /// **'Don\'t wait — unlock everything'**
  String get wallCtaUnlock;

  /// Small second line inside the day wall's unlock CTA pill, under the main label, teasing that the catalog keeps growing.
  ///
  /// In en, this message translates to:
  /// **'(new sets every week!)'**
  String get wallCtaCaption;

  /// Small uppercase brand label at the top of the paywall sheet. A brand mark — identical in every locale.
  ///
  /// In en, this message translates to:
  /// **'DEBATLY PRO'**
  String get paywallBrand;

  /// The paywall headline — the same fixed slogan for every entry point. Three short lines separated by explicit newlines.
  ///
  /// In en, this message translates to:
  /// **'No limits.\nNo end.\nWorldwide.'**
  String get paywallTitleDefault;

  /// No description provided for @paywallSubtitle.
  ///
  /// In en, this message translates to:
  /// **'500+ questions, every argument FOR and AGAINST, your entire voting history.'**
  String get paywallSubtitle;

  /// First row of the paywall's compact feature list.
  ///
  /// In en, this message translates to:
  /// **'Questions with no daily limit'**
  String get paywallFeatureUnlimited;

  /// No description provided for @paywallFeatureSmaczki.
  ///
  /// In en, this message translates to:
  /// **'Every argument, not just the first'**
  String get paywallFeatureSmaczki;

  /// No description provided for @paywallFeatureHistory.
  ///
  /// In en, this message translates to:
  /// **'History and favorites forever'**
  String get paywallFeatureHistory;

  /// No description provided for @paywallFeatureOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline mode — the whole catalog on your phone'**
  String get paywallFeatureOffline;

  /// No description provided for @paywallSignInLink.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get paywallSignInLink;

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

  /// No description provided for @paywallPerMonth.
  ///
  /// In en, this message translates to:
  /// **'/mo'**
  String get paywallPerMonth;

  /// No description provided for @paywallCta.
  ///
  /// In en, this message translates to:
  /// **'Unlock full access'**
  String get paywallCta;

  /// Subline on the lifetime plan card: one-time payment, anchored against months of the monthly subscription, rounded so the claim is always true.
  ///
  /// In en, this message translates to:
  /// **'{months, plural, one{One payment. Cheaper than {months} month.} other{One payment. Cheaper than {months} months.}}'**
  String paywallLifetimeVsMonthly(int months);

  /// Subline on the monthly plan card: the monthly price recomputed as its weekly equivalent (price × 12 / 52), already formatted with the store currency.
  ///
  /// In en, this message translates to:
  /// **'That\'s about {price} a week'**
  String paywallMonthlyWeekly(String price);

  /// No description provided for @paywallLifetimeNote.
  ///
  /// In en, this message translates to:
  /// **'One-time payment — yours forever'**
  String get paywallLifetimeNote;

  /// No description provided for @paywallSubscriptionNote.
  ///
  /// In en, this message translates to:
  /// **'Auto-renews until cancelled — cancel anytime'**
  String get paywallSubscriptionNote;

  /// No description provided for @paywallLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the offers. Check your connection and try again.'**
  String get paywallLoadError;

  /// No description provided for @paywallOfferUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Plans are unavailable right now. Check back shortly — and if you already have PRO, use Restore below.'**
  String get paywallOfferUnavailable;

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

  /// Muted support stamp at the very bottom of the paywall: app version plus a short user code (last 4 characters of the Supabase uid) the user can read out so support can find their account.
  ///
  /// In en, this message translates to:
  /// **'v{version} ({build}) · ID {code}'**
  String paywallBuildStamp(String version, String build, String code);
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
