// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get later => 'Later';

  @override
  String get cancel => 'Cancel';

  @override
  String get tryAgain => 'Try again';

  @override
  String get orDivider => 'OR';

  @override
  String get restorePurchase => 'Restore purchase';

  @override
  String get purchaseNotCompleted => 'Purchase not completed.';

  @override
  String get purchaseRestored => 'Purchase restored.';

  @override
  String get purchaseRestoredCelebrate => 'Purchase restored. 🎉';

  @override
  String get noPreviousPurchase => 'No previous purchase found.';

  @override
  String get purchaseSyncPending =>
      'Your purchase went through, but we couldn\'t confirm it yet. Try “Restore purchase” in a moment.';

  @override
  String get restoreSignInTitle => 'Restore purchase?';

  @override
  String get restoreSignInBody =>
      'If you bought PRO while signed in to an account, sign in to it — PRO and all your data will come back automatically.';

  @override
  String get restoreOnThisDevice => 'Restore on this device';

  @override
  String get goPro => 'Go PRO';

  @override
  String get signIn => 'Sign in';

  @override
  String get authCreateAccount => 'Create account';

  @override
  String get authWelcomeBackTitle => 'Good to see you again';

  @override
  String get authWelcomeBackSubtitle => 'Sign in to get back to your debates.';

  @override
  String get authRegisterTitle => 'Join Debatly';

  @override
  String get authRegisterSubtitle =>
      'Create an account and take a side in the debate.';

  @override
  String get authEmailLabel => 'EMAIL';

  @override
  String get authPasswordLabel => 'PASSWORD';

  @override
  String get authConfirmPasswordLabel => 'REPEAT PASSWORD';

  @override
  String get authShowPassword => 'Show password';

  @override
  String get authHidePassword => 'Hide password';

  @override
  String get authForgotPassword => 'Forgot your password?';

  @override
  String get authTabSignIn => 'SIGN IN';

  @override
  String get authTabSignUp => 'SIGN UP';

  @override
  String get authEnterEmail => 'Enter your email.';

  @override
  String get authEnterValidEmail => 'Enter a valid email.';

  @override
  String get authEnterPassword => 'Enter your password.';

  @override
  String get authMinPassword => 'At least 6 characters.';

  @override
  String get authPasswordsMismatch => 'Passwords don\'t match.';

  @override
  String get authAccountCreated => 'Account created.';

  @override
  String get authConfirmEmail => 'Check your email and confirm your account.';

  @override
  String get authContinueWithApple => 'Continue with Apple';

  @override
  String get authContinueWithGoogle => 'Continue with Google';

  @override
  String authLegalConsent(String terms, String privacy) {
    return 'By continuing, you agree to our $terms and $privacy.';
  }

  @override
  String get authLegalTermsLink => 'Terms of Service';

  @override
  String get authLegalPrivacyLink => 'Privacy Policy';

  @override
  String get authPasswordResetSent =>
      'If an account exists for that email, we\'ve sent a reset link.';

  @override
  String get authMissingSupabaseConfig =>
      'Supabase configuration is missing. Run the app with SUPABASE_URL and SUPABASE_ANON_KEY.';

  @override
  String get authMissingGoogleConfig =>
      'GOOGLE_SERVER_CLIENT_ID is missing, so Google is temporarily disabled.';

  @override
  String get settingsSectionApp => 'APP SETTINGS';

  @override
  String get settingsSectionAccount => 'ACCOUNT';

  @override
  String get settingsReminders => 'Reminders';

  @override
  String get settingsRemindersSubtitle => 'A daily reminder to vote';

  @override
  String get settingsReminderTime => 'Reminder time';

  @override
  String get remindersPermissionDenied =>
      'Turn on notifications in system settings to get reminders.';

  @override
  String get remindersOpenSettings => 'Open settings';

  @override
  String get notificationDailyTitle => 'New questions are waiting 🔥';

  @override
  String get notificationDailyBody =>
      'Cast your vote and keep your streak alive.';

  @override
  String get notifNudgeTitle1 => 'Pick a side 🔥';

  @override
  String get notifNudgeBody1 =>
      'There\'s a question that splits the room. Which side are you on?';

  @override
  String get notifNudgeTitle2 => 'Cast your vote today 🤔';

  @override
  String get notifNudgeBody2 => 'Plenty of people disagree today. Do you?';

  @override
  String get notifNudgeTitle3 => 'Yes or no?';

  @override
  String get notifNudgeBody3 => 'Cast your vote before everyone else does.';

  @override
  String get notifStreakTitle => 'Don\'t let it die 🔥';

  @override
  String notifStreakBody(int streak) {
    return 'Day $streak of your streak. Vote today to keep it alive.';
  }

  @override
  String get notifGraceTitle => 'Your rank is slipping ⚠️';

  @override
  String get notifGraceBodyTomorrow =>
      'It drops tomorrow unless you vote today.';

  @override
  String notifGraceBodyDays(int days) {
    return 'It drops in $days days. Vote to hold on to it.';
  }

  @override
  String get notifMinorityTitle => 'Still in the minority? 🤔';

  @override
  String notifMinorityBody(int pct) {
    return '$pct% disagreed with you. See how the split is shaping up.';
  }

  @override
  String get notifResultTitle => 'How\'s the vote going?';

  @override
  String get notifResultBody => 'See what the majority actually picked.';

  @override
  String get notifNextTitle => 'More questions are waiting 🔮';

  @override
  String get notifNextBody =>
      'Plenty more to vote on. Will you be in the minority again?';

  @override
  String get notifSafeTitle => 'Streak secured 🔥';

  @override
  String get notifSafeBody => 'Nice one. Come back tomorrow to keep it going.';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get chooseLanguage => 'Choose language';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsChooseAppearance => 'Choose appearance';

  @override
  String get settingsAppearanceSystem => 'System';

  @override
  String get settingsAppearanceLight => 'Light';

  @override
  String get settingsAppearanceDark => 'Dark';

  @override
  String get settingsPremiumActive => 'Premium active';

  @override
  String get settingsGoPremium => 'Go Premium';

  @override
  String get settingsOfflineQuestions => 'Offline questions';

  @override
  String get offlineDownloadReady =>
      'Download all questions to read without internet';

  @override
  String offlineDownloadSynced(String date) {
    return 'Downloaded · $date';
  }

  @override
  String offlineDownloadProgress(int done, int total) {
    return 'Downloading… $done/$total';
  }

  @override
  String get offlineDownloadComplete => 'Questions saved for offline.';

  @override
  String get offlineDownloadFailed =>
      'Download failed. Check your connection and try again.';

  @override
  String get settingsPrivacy => 'Privacy & data';

  @override
  String get settingsFavorites => 'Favorite questions';

  @override
  String get favoritesTitle => 'Favorites';

  @override
  String get favoritesEmptyTitle => 'No favorites yet';

  @override
  String get favoritesEmptyBody =>
      'Tap the star on a question to save it here.';

  @override
  String get favoriteAddTooltip => 'Add to favorites';

  @override
  String get favoriteRemoveTooltip => 'Remove from favorites';

  @override
  String get favoriteAdded => 'Added to favorites';

  @override
  String get favoriteRemoved => 'Removed from favorites';

  @override
  String get favoritesPremiumOnly => 'Favorites are a Premium feature.';

  @override
  String get favoriteError => 'Couldn\'t update favorites.';

  @override
  String get historyTitle => 'Question history';

  @override
  String get historySubtitle =>
      'Every question you voted on, with how people voted.';

  @override
  String get historyTooltip => 'Question history';

  @override
  String get historyEmptyTitle => 'Nothing here yet';

  @override
  String get historyEmptyBody => 'Vote on a question and it will show up here.';

  @override
  String get historyLoadError => 'Couldn\'t load the history.';

  @override
  String get historyPremiumTitle => 'History is a PRO feature';

  @override
  String get historyPremiumBody =>
      'Go PRO to look back at every question you voted on and see how others voted.';

  @override
  String get historyNoVotes => 'No votes';

  @override
  String get searchQuestionsHint => 'Search questions…';

  @override
  String get searchClearTooltip => 'Clear search';

  @override
  String get searchNoResultsTitle => 'No matches';

  @override
  String get searchNoResultsBody =>
      'No questions match your search. Try a different word.';

  @override
  String get privacyDocsSection => 'DOCUMENTS';

  @override
  String get privacyPolicy => 'Privacy policy';

  @override
  String get privacyTerms => 'Terms of service';

  @override
  String get privacyDeleteAccount => 'Delete account and data';

  @override
  String get privacyOpenInBrowser => 'Opens in your browser';

  @override
  String get privacyLinkFailed => 'Couldn\'t open the link.';

  @override
  String get privacyDataSection => 'WHAT WE STORE';

  @override
  String get privacyDataIntro =>
      'A quick overview of the data Debatly keeps and why.';

  @override
  String get privacyDataAccountTitle => 'Account & sign-in';

  @override
  String get privacyDataAccountBody =>
      'Your email or sign-in identity — or an anonymous ID for guests — so your progress follows you across devices.';

  @override
  String get privacyDataActivityTitle => 'Activity';

  @override
  String get privacyDataActivityBody =>
      'Your votes, streak and rank, used to power your questions and progress.';

  @override
  String get privacyDataPurchasesTitle => 'Purchases';

  @override
  String get privacyDataPurchasesBody =>
      'Your Premium status, handled through the App Store or Google Play. We never see your card details.';

  @override
  String get settingsPremiumActiveToast => 'Premium active. 🎉';

  @override
  String get manageSubSheetTitle => 'Manage subscription';

  @override
  String get manageSubStatusActive => 'Premium active';

  @override
  String get manageSubStatusCancelled => 'Cancelled — won\'t renew';

  @override
  String get manageSubStatusLifetime => 'Lifetime access';

  @override
  String get manageSubNoteLifetime =>
      'This was a one-time purchase — there is no subscription to cancel. Premium stays on this account forever.';

  @override
  String get manageSubClose => 'Close';

  @override
  String manageSubRenewsOn(String date) {
    return 'Renews on $date';
  }

  @override
  String manageSubActiveUntil(String date) {
    return 'Active until $date';
  }

  @override
  String get manageSubBilledAppStore => 'Billed through the App Store';

  @override
  String get manageSubBilledPlayStore => 'Billed through Google Play';

  @override
  String get manageSubBilledWeb => 'Billed online';

  @override
  String get manageSubNoteAppStore =>
      'Apple handles billing for your subscription. To change your plan or cancel, open Subscriptions in the App Store — you\'ll keep Premium until the end of the current period.';

  @override
  String get manageSubNotePlayStore =>
      'Google handles billing for your subscription. To change your plan or cancel, open Subscriptions in Google Play — you\'ll keep Premium until the end of the current period.';

  @override
  String get manageSubNoteWeb =>
      'Manage or cancel your subscription wherever you purchased it. You\'ll keep Premium until the end of the current period.';

  @override
  String get manageSubButtonAppStore => 'Manage in the App Store';

  @override
  String get manageSubButtonPlayStore => 'Manage in Google Play';

  @override
  String get manageSubButtonGeneric => 'Manage subscription';

  @override
  String get manageSubOpenFailedAppStore =>
      'Couldn\'t open the App Store. Open Settings › your name › Subscriptions to manage it.';

  @override
  String get manageSubOpenFailedPlayStore =>
      'Couldn\'t open Google Play. Open Play Store › Menu › Subscriptions to manage it.';

  @override
  String get manageSubOpenFailedGeneric =>
      'Couldn\'t open the subscription page. Manage it wherever you purchased Premium.';

  @override
  String get signedOut => 'Signed out.';

  @override
  String get signOutError =>
      'Couldn\'t sign out. Please check your connection and try again.';

  @override
  String get deleteAccountTitle => 'Delete account?';

  @override
  String get deleteAccountBody =>
      'This permanently deletes your account and all related data — your streak, votes and unlocks. This can\'t be undone. If you have an active Premium subscription, cancel it separately in the App Store or Google Play.';

  @override
  String get deleteAccountSuccess => 'Your account has been deleted.';

  @override
  String get deleteAccountError =>
      'Couldn\'t delete your account. Please check your connection and try again.';

  @override
  String get guestSession => 'Guest session';

  @override
  String get accountUnsecuredNote =>
      'Your progress is saved only on this phone';

  @override
  String get secureAccount => 'Secure account';

  @override
  String get yourAccount => 'Your account';

  @override
  String get signOut => 'Sign out';

  @override
  String get deleteAccount => 'Delete account';

  @override
  String get daysInARow => 'DAYS IN A ROW';

  @override
  String streakRecord(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Record: $count days',
      one: 'Record: $count day',
    );
    return '$_temp0';
  }

  @override
  String get rankLabel => 'RANK';

  @override
  String get rankCardTopRank => 'Highest rank';

  @override
  String get rankCardPromotionReady => 'Promotion ready!';

  @override
  String rankCardDaysToPromotion(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days to promotion',
      one: '$count day to promotion',
    );
    return '$_temp0';
  }

  @override
  String get rankCardTapHint => 'TAP';

  @override
  String get settingsTooltip => 'Settings';

  @override
  String get swipeHint => 'Swipe to see the next question';

  @override
  String get loadErrorTitle => 'Couldn\'t load questions';

  @override
  String get loadErrorBody => 'Check your internet connection and try again.';

  @override
  String get offlineBannerLabel => 'You\'re offline';

  @override
  String get offlineResultsHidden => 'Results return when you\'re back online';

  @override
  String get yourVote => 'Your vote';

  @override
  String get goDeeper => 'GO DEEPER';

  @override
  String get shareLabel => 'Share';

  @override
  String get shareTooltip => 'Share question';

  @override
  String get shareSubject => 'A question from Debatly';

  @override
  String shareMessage(String question) {
    return '$question\n\nDebatly — thought-provoking questions.';
  }

  @override
  String get shareCardTagline => 'Questions that spark real conversation';

  @override
  String get shareCardHook => 'You? Yes or no?';

  @override
  String get streakTooltip => 'Your streak';

  @override
  String get newQuestionBadge => 'New';

  @override
  String get newQuestionTooltip =>
      'Freshly added question — the community is just starting to vote.';

  @override
  String get voteYes => 'YES';

  @override
  String get voteNo => 'NO';

  @override
  String get voteFailed => 'Could not record your vote.';

  @override
  String get noConnection => 'No connection — try again in a moment.';

  @override
  String get backToLatestQuestion => 'Back to the latest question';

  @override
  String get proActiveTitle => 'PRO active 🎉';

  @override
  String get savePromptBody =>
      'Your PRO is currently tied to a guest account. Create an account (email or Google) so you don\'t lose access after reinstalling or on another device — your progress will be kept.';

  @override
  String get createAccount => 'Create account';

  @override
  String get secureStreakTitle => 'Secure your streak 🔥';

  @override
  String secureStreakBody(int streak) {
    return 'You\'re on a $streak-day streak — but it only lives on this phone. Create an account (email or Google) and it will survive a reinstall or a new device.';
  }

  @override
  String get smaczkiTitle => 'Arguments';

  @override
  String get smaczkiSubtitle =>
      'Tips to deepen the conversation around this question.';

  @override
  String smaczkiLoadError(String error) {
    return 'Couldn\'t load tidbits.\n$error';
  }

  @override
  String get smaczkiEmpty => 'No tidbits for this question yet.';

  @override
  String get ranksLoadError => 'Could not load ranks.';

  @override
  String get rankLadder => 'Rank ladder';

  @override
  String get yourRankUpper => 'YOUR RANK';

  @override
  String get topRankRespect => 'Top rank — respect.';

  @override
  String streakDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '$count day',
    );
    return 'Streak: $_temp0';
  }

  @override
  String longestStreakDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '$count day',
    );
    return 'Longest streak: $_temp0';
  }

  @override
  String daysToNextRank(int remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: '$remaining more days to the next rank',
      one: '$remaining more day to the next rank',
    );
    return '$_temp0';
  }

  @override
  String rankFrom(int minStreak) {
    return '$minStreak+';
  }

  @override
  String streakGraceWarning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count graces left — then your rank drops',
      one: '$count grace left — then your rank drops',
    );
    return '$_temp0';
  }

  @override
  String get rankUpEyebrow => 'NEW RANK';

  @override
  String rankUpStreakLine(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count-day streak 🔥',
      one: '$count-day streak 🔥',
    );
    return '$_temp0';
  }

  @override
  String get rankUpDismiss => 'Awesome!';

  @override
  String get rankShareHeadline => 'MY NEW RANK';

  @override
  String rankShareStreakLine(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count-day streak',
      one: '$count-day streak',
    );
    return '$_temp0';
  }

  @override
  String get rankShareSubject => 'My rank in Debatly';

  @override
  String rankShareMessage(String rank) {
    return 'My new rank in Debatly: $rank 🔥\n\nDebatly — thought-provoking questions.';
  }

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingWelcomeTitle => 'Think you know the answer?';

  @override
  String get onboardingWelcomeBody =>
      'In a moment you\'ll get a question with no good answer. Vote — and see how many people think differently than you.';

  @override
  String get onboardingTasteKicker => 'YOUR TURN';

  @override
  String get onboardingTasteQuestion =>
      'Should an obese person have to pay for two plane seats?';

  @override
  String get onboardingTasteHoldOnTitle => 'Hold on…';

  @override
  String get onboardingTasteSmaczek1 =>
      'You already pay extra for a few kilos of luggage.';

  @override
  String get onboardingTasteSmaczek2 =>
      'What about the person squeezed next to you? Same fare, worse seat.';

  @override
  String get onboardingTasteSmaczek3 =>
      'And how would you check who pays? A gate scale before boarding?';

  @override
  String get onboardingTasteSmaczek4 =>
      'What about people whose weight comes from illness? Punished for life?';

  @override
  String get onboardingTasteRead => 'Okay, let me vote!';

  @override
  String get onboardingTasteRevoteKicker => 'VOTE AGAIN';

  @override
  String get onboardingTasteContinue => 'Continue';

  @override
  String get onboardingTasteNextTitle => 'Let\'s try another one…';

  @override
  String get onboardingTasteQuestion2 =>
      'Should you tell a new partner exactly how many people you\'ve slept with?';

  @override
  String get onboardingTasteSureTitle => 'Are you sure though?';

  @override
  String get onboardingTasteQ2Smaczek1 =>
      'There\'s no argument only if your numbers happen to match.';

  @override
  String get onboardingTasteQ2Smaczek2 =>
      'Once you know, will it stop bugging you? Will it stop bugging them?';

  @override
  String get onboardingTasteQ2Smaczek3 =>
      'If the number isn\'t 100, what does it actually change?';

  @override
  String get onboardingTasteQ2Smaczek4 =>
      'And if it is 100 — would you rather know, or rather tell?';

  @override
  String get onboardingCatalogTitle => 'And we\'ve got 500+ more like these';

  @override
  String get onboardingCatalogBody =>
      'Every single one with vote results from the whole world. Cast your vote and find out whether you think like the majority — or the whole world has it wrong. And each question comes with arguments that can change your mind.';

  @override
  String get onboardingCatalogPerfectFor => 'PERFECT FOR';

  @override
  String get onboardingCatalogUse1 => 'dates';

  @override
  String get onboardingCatalogUse2 => 'get-togethers with friends';

  @override
  String get onboardingCatalogUse3 => 'evenings for two';

  @override
  String get onboardingCatalogUse4 => 'talks around the family table';

  @override
  String get onboardingNotifyTitle => 'Tomorrow\'s question is waiting';

  @override
  String get onboardingNotifyBody =>
      'One notification a day, at a time you pick. Voting takes 10 seconds — and your streak grows every day.';

  @override
  String get onboardingNotifyEnable => 'Turn on reminders';

  @override
  String get onboardingNotifySkip => 'Not now';

  @override
  String get onboardingNotifyFootnote =>
      'You can turn reminders off or change the time in settings.';

  @override
  String get paywallTitle => 'Unlock every question and vote';

  @override
  String get paywallTitleHardWall => 'See how the whole world voted';

  @override
  String get paywallSubtitleHardWall =>
      '500+ questions that split the room — and every argument you need to defend your take.';

  @override
  String get paywallTitleSmaczki => 'Unlock every argument, for every question';

  @override
  String get paywallTitleFavorites => 'Keep your favorite questions forever';

  @override
  String get paywallTitleHistory => 'Every vote you\'ve cast, in one place';

  @override
  String get paywallWhatYouGet => 'EVERYTHING YOU GET';

  @override
  String get paywallBenefitUnlimitedTitle => 'The full 500+ question catalog';

  @override
  String get paywallBenefitUnlimitedBody =>
      'Every divisive question at your fingertips — no limits, no waiting.';

  @override
  String get paywallBenefitOfflineTitle => 'Works offline';

  @override
  String get paywallBenefitOfflineBody =>
      'Download the whole catalog and keep reading with no connection.';

  @override
  String get paywallBenefitSmaczkiTitle => 'Arguments FOR and AGAINST';

  @override
  String get paywallBenefitSmaczkiBody =>
      'Talking points for every question — ammunition so you never lose a debate.';

  @override
  String get paywallBenefitSplitTitle => 'Votes from around the world';

  @override
  String get paywallBenefitSplitBody =>
      'After every vote, see how the whole world split — how many think like you, and how many don\'t.';

  @override
  String get paywallBenefitFreshTitle => 'Dozens of new questions';

  @override
  String get paywallBenefitFreshBody =>
      'The catalog keeps growing — we add fresh questions all the time.';

  @override
  String get paywallBenefitStreakTitle => 'Streaks & ranks';

  @override
  String get paywallBenefitStreakBody =>
      'Vote daily, keep your streak alive and climb the rank ladder.';

  @override
  String get paywallBenefitFavoritesTitle => 'Favorites & voting history';

  @override
  String get paywallBenefitFavoritesBody =>
      'Save the best questions and look back at every vote you\'ve cast.';

  @override
  String get paywallSignInLink => 'Sign in';

  @override
  String get paywallLifetime => 'Lifetime';

  @override
  String get paywallAnnual => 'Yearly';

  @override
  String get paywallMonthly => 'Monthly';

  @override
  String get paywallWeekly => 'Weekly';

  @override
  String get paywallPerMonth => '/mo';

  @override
  String get paywallBestValue => 'BEST VALUE';

  @override
  String get paywallCta => 'Unlock full access';

  @override
  String paywallLifetimeVsMonthly(int months) {
    String _temp0 = intl.Intl.pluralLogic(
      months,
      locale: localeName,
      other: 'Less than $months months of the subscription',
      one: 'Less than $months month of the subscription',
    );
    return '$_temp0';
  }

  @override
  String get paywallLifetimeNote => 'One-time payment — yours forever';

  @override
  String get paywallSubscriptionNote =>
      'Auto-renews until cancelled — cancel anytime';

  @override
  String get paywallLoadError =>
      'Couldn\'t load the offers. Check your connection and try again.';

  @override
  String get paywallTermsLink => 'Terms';

  @override
  String get paywallPrivacyLink => 'Privacy';
}
