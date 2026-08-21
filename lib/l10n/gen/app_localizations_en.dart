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
  String get storeUnreachable =>
      'Couldn\'t reach the store. Check your connection and try again.';

  @override
  String get purchaseSyncPending =>
      'Your purchase went through, but we couldn\'t confirm it yet. Try “Restore purchase” in a moment.';

  @override
  String get purchaseAlreadyOwned =>
      'This purchase already belongs to a store account. Tap “Restore purchase”, or sign in to the account that holds it.';

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
  String get authSetNewPasswordTitle => 'Set a new password';

  @override
  String get authSetNewPasswordSubtitle =>
      'You\'re signed in from the link — pick the new password for your account.';

  @override
  String get authNewPasswordLabel => 'NEW PASSWORD';

  @override
  String get authSetNewPasswordCta => 'SAVE NEW PASSWORD';

  @override
  String get authPasswordUpdated => 'Password changed. You\'re signed in.';

  @override
  String get authRecoveryLinkInvalid =>
      'That reset link has expired or was already used. Request a new one.';

  @override
  String get authMissingSupabaseConfig =>
      'Supabase configuration is missing. Run the app with SUPABASE_URL and SUPABASE_ANON_KEY.';

  @override
  String get authMissingGoogleConfig =>
      'GOOGLE_SERVER_CLIENT_ID is missing, so Google is temporarily disabled.';

  @override
  String get authAlreadySignedIn =>
      'You\'re already signed in to your account — no need to register again.';

  @override
  String authRegisteredPendingConfirm(String email) {
    return 'Your account is already registered to $email. Tap the link in that email to confirm it.';
  }

  @override
  String get authErrorInvalidCredentials => 'Incorrect email or password.';

  @override
  String get authErrorEmailNotConfirmed =>
      'Confirm your email first — check your inbox.';

  @override
  String get authErrorEmailExists =>
      'An account with this email already exists. Sign in instead.';

  @override
  String get authErrorSamePassword => 'That\'s already your current password.';

  @override
  String get authErrorWeakPassword =>
      'That password is too weak. Try a longer one.';

  @override
  String get authErrorTooManyRequests =>
      'Too many attempts. Wait a moment and try again.';

  @override
  String get authErrorGeneric => 'Something went wrong. Please try again.';

  @override
  String get authSwitchAccountTitle => 'Sign in to another account?';

  @override
  String get authSwitchAccountBody =>
      'Signing in swaps this device over to that account. Your streak, votes and favourites live on this guest profile and won\'t come along. Want to keep them? Create an account instead — that keeps everything.';

  @override
  String get authSwitchAccountConfirm => 'Sign in anyway';

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
  String get notifStreakSoftTitle => 'Back in the game 🔥';

  @override
  String get notifStreakSoftBody => 'One vote a day keeps a streak alive.';

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
  String get notifDriftTitle1 => 'Your seat is still here 🔥';

  @override
  String get notifDriftBody1 =>
      'A few days without your vote. Come back and say what you think.';

  @override
  String get notifDriftTitle2 => 'Your rank is sliding ⚠️';

  @override
  String get notifDriftBody2 =>
      'Every day without a vote sets you back. One is enough to stop it.';

  @override
  String get notifAwayTitle1 => 'People are still arguing 🔥';

  @override
  String get notifAwayBody1 =>
      'Without you. Come back and see which side you\'re on today.';

  @override
  String get notifAwayTitle2 => 'Changed your mind?';

  @override
  String get notifAwayBody2 =>
      'New questions are waiting. See if you\'re still in the minority.';

  @override
  String get notifChannelDailyName => 'Daily question';

  @override
  String get notifChannelDailyDescription =>
      'Your daily nudge about today\'s question.';

  @override
  String get notifChannelComebackName => 'Come-back reminders';

  @override
  String get notifChannelComebackDescription =>
      'Occasional nudges when you\'ve been away for a while.';

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
  String historyAnsweredCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count answered',
      one: '$count answered',
    );
    return '$_temp0';
  }

  @override
  String get historyTooltip => 'Question history';

  @override
  String get historyEmptyTitle => 'Nothing here yet';

  @override
  String get historyEmptyBody => 'Vote on a question and it will show up here.';

  @override
  String get historyEmptyTodayTitle => 'Nothing today yet';

  @override
  String get historyEmptyTodayBody =>
      'Vote on today\'s question and it will show up here.';

  @override
  String get historyLoadError => 'Couldn\'t load the history.';

  @override
  String historyYourVote(String vote) {
    return 'YOU: $vote';
  }

  @override
  String get historyVersus => 'vs';

  @override
  String get historyLockedTitle => 'Unlock your full history';

  @override
  String get historyLockedBody =>
      'Free accounts see only today here. Go PRO to browse every vote you\'ve ever cast.';

  @override
  String get historySearchTooltip => 'Search history';

  @override
  String historyLoadMore(int count) {
    return 'Load $count more';
  }

  @override
  String get historyNoVotes => 'No votes';

  @override
  String get searchQuestionsHint => 'Search questions…';

  @override
  String get searchClearTooltip => 'Clear search';

  @override
  String get searchCloseTooltip => 'Close search';

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
  String get loadErrorBodyEmpty =>
      'Today\'s question didn\'t come through. Try again in a moment.';

  @override
  String get backendUnavailableTitle => 'Can\'t reach Debatly';

  @override
  String get backendUnavailableBody =>
      'We couldn\'t connect to the server, so nothing you do here would be saved. Try again.';

  @override
  String get offlineBannerLabel => 'You\'re offline';

  @override
  String get offlineResultsHidden => 'Results return when you\'re back online';

  @override
  String get yourVote => 'Your vote';

  @override
  String get goDeeper => 'AGAINST YOU';

  @override
  String get smaczkiBarPro => 'THE CASE AGAINST';

  @override
  String get smaczkiBarFree => 'THE CASE FOR YOU';

  @override
  String smaczkiBarUntagged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count MORE ARGUMENTS',
      one: 'ONE MORE ARGUMENT',
      zero: 'THAT WAS THE LAST ONE',
    );
    return '$_temp0';
  }

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
  String get conformityTooltip => 'Your conformity axis';

  @override
  String get conformityTitle => 'CONFORMITY AXIS';

  @override
  String conformityPctLine(int pct) {
    return '$pct% with the majority';
  }

  @override
  String get axisRungAgainst2 => 'Always against the grain';

  @override
  String get axisRungAgainst1 => 'Usually against the grain';

  @override
  String get axisRungMiddle => 'Fifty-fifty';

  @override
  String get axisRungWith1 => 'Usually with the crowd';

  @override
  String get axisRungWith2 => 'Always with the crowd';

  @override
  String conformityNextTierLabel(String tier) {
    return 'To reach $tier';
  }

  @override
  String conformityVotesNeeded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count votes with the majority',
      one: '$count vote with the majority',
    );
    return '$_temp0';
  }

  @override
  String get conformityEmpty =>
      'Vote on a few questions and you\'ll see which side you usually take.';

  @override
  String get conformityLoadError =>
      'Couldn\'t load your axis — try again in a moment.';

  @override
  String get profileSectionTitle => 'YOUR TYPE';

  @override
  String get profileTypePillar => 'THE PILLAR';

  @override
  String get profileTypeFlow => 'GOES WITH THE FLOW';

  @override
  String get profileTypeWolf => 'THE LONE WOLF';

  @override
  String get profileTypeSeeker => 'THE SEEKER';

  @override
  String get profileDescPillar =>
      'You think like the majority and nothing moves you.';

  @override
  String get profileDescFlow =>
      'You go with the crowd and with every good argument.';

  @override
  String get profileDescWolf => 'Your own mind, end of discussion.';

  @override
  String get profileDescSeeker =>
      'You don\'t buy others\' opinions, but you look for better ones.';

  @override
  String get profileProvisional => 'provisional';

  @override
  String profileProgress(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Answer $n more counters after voting and you\'ll know your type.',
      one: 'Answer 1 more counter after voting and you\'ll know your type.',
    );
    return '$_temp0';
  }

  @override
  String get profileStatCrowdLabel => 'votes with the majority';

  @override
  String get profileStatMovedLabel => 'counters moved you';

  @override
  String get profileLockedFlips => 'The lines that turned you';

  @override
  String get profileLockedLoneliest => 'Your loneliest vote';

  @override
  String get profileLockedRarity => 'Only …% of users share your type';

  @override
  String get profileLockedTrend => 'Your trend over time';

  @override
  String profileRarityLine(int pct) {
    return '$pct% of users share your type';
  }

  @override
  String profileLoneliestLine(int pct) {
    return 'Only $pct% voted like you';
  }

  @override
  String profileSliceLine(int pct, int moved) {
    return '$pct% with the majority · minds changed: $moved';
  }

  @override
  String get profileNotEnoughData => 'Not enough data yet.';

  @override
  String get profileShareHeadline => 'MY DEBATER TYPE';

  @override
  String profileShareCrowdWith(int pct) {
    return 'with the crowd $pct% of the time';
  }

  @override
  String profileShareCrowdAgainst(int pct) {
    return 'against the crowd $pct% of the time';
  }

  @override
  String profileShareQuestionsLine(int count, String crowd) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count questions',
      one: '1 question',
    );
    return '$_temp0 · $crowd';
  }

  @override
  String profileShareMovedLine(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'changed my mind $count times',
      one: 'changed my mind once',
      zero: 'never changed my mind',
    );
    return '$_temp0';
  }

  @override
  String profileShareMessage(String type) {
    return 'I\'m $type. Find your type on Debatly.';
  }

  @override
  String get profileShareSubject => 'My Debatly type';

  @override
  String get profileShareFooter => 'debatly.app';

  @override
  String get newQuestionBadge => 'New';

  @override
  String get newQuestionTooltip =>
      'Freshly added question — the community is just starting to vote.';

  @override
  String get dailyQuestionBadge => 'Question of the day';

  @override
  String get dailyQuestionTooltip =>
      'The shared question of the day — the whole community is voting on it today.';

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
  String get backToDailyQuestion => 'Question of the day';

  @override
  String get updateRequiredTitle => 'Time to update';

  @override
  String get updateRequiredBody =>
      'This version of Debatly is too old to talk to the server. Grab the update and get back to voting.';

  @override
  String get updateRequiredCta => 'Update';

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
  String get suggestQuestionTitle => 'Suggest a question';

  @override
  String get suggestQuestionSettingsSubtitle =>
      'Got an idea that will split the room? Send it in';

  @override
  String get suggestQuestionIntro =>
      'The best questions start with \"Should…\", have no comfortable answer and split the room in half. Rough ideas welcome — we\'ll polish it.';

  @override
  String get suggestQuestionHint => 'Should…?';

  @override
  String get suggestQuestionMinChars => 'At least 10 characters';

  @override
  String get suggestQuestionSend => 'Send suggestion';

  @override
  String get suggestQuestionThanks => 'Thanks! Your idea just reached us.';

  @override
  String get suggestQuestionFailed =>
      'Couldn\'t send it — try again in a moment.';

  @override
  String get suggestQuestionRateLimited =>
      'That\'s plenty for today — come back tomorrow.';

  @override
  String get suggestQuestionNudge =>
      'Got an idea for a question that sticks in people\'s heads? Send it in!';

  @override
  String get suggestQuestionNudgeAction => 'Suggest';

  @override
  String get smaczkiTitle => 'Arguments';

  @override
  String get smaczkiTitleTag => '(smaczki)';

  @override
  String get smaczkiSubtitle => 'You are not going to like this one.';

  @override
  String smaczkiRemaining(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more arguments wait for you.',
      one: 'One more argument waits for you.',
    );
    return '$_temp0';
  }

  @override
  String get smaczekSuggestCta => 'Suggest your own';

  @override
  String get smaczekSuggestHint => 'Your argument…';

  @override
  String get smaczekSuggestMinChars => 'At least 5 characters';

  @override
  String get smaczekSuggestSend => 'Send';

  @override
  String smaczkiLoadError(String error) {
    return 'Couldn\'t load tidbits.\n$error';
  }

  @override
  String get smaczkiEmpty => 'No tidbits for this question yet.';

  @override
  String get smaczkiUnlockCta => 'Unlock';

  @override
  String get smaczkiLockedBeforeVote =>
      'Vote first. Then I\'ll see if you hold.';

  @override
  String get smaczekChallengeEyebrow => 'BEFORE I SHOW YOU THE RESULT';

  @override
  String get challengeHoldCta => 'I\'M NOT BUDGING';

  @override
  String get challengeMovedCta => 'THAT GOT ME';

  @override
  String get smaczkiSheetFreeHeader =>
      'You got the argument against you. Two left: one that defends you, one that complicates it.';

  @override
  String smaczkiSheetFreeHeaderPlain(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'The first one is behind you. $count more wait.',
      one: 'The first one is behind you. One more waits.',
      zero: 'That argument is behind you.',
    );
    return '$_temp0';
  }

  @override
  String resultFlipLine(int percent) {
    return 'The counter-argument flipped $percent% of voters.';
  }

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
  String get onboardingBegin => 'Let\'s begin';

  @override
  String get onboardingWelcomeTitle => 'Think you can read people?';

  @override
  String get onboardingWelcomeTitlePunch => 'How well do you know yourself?';

  @override
  String get onboardingWelcomeBody =>
      'Let\'s find out. You\'ll get a question with no good answer — vote and see how many people think differently than you.';

  @override
  String get onboardingTasteKicker => 'YOUR TURN';

  @override
  String get onboardingTasteQuestion =>
      'Should an obese person have to pay for two plane seats?';

  @override
  String get onboardingTasteHoldOnTitle => 'Hold on…';

  @override
  String get onboardingTasteVotedTakSmaczek1 =>
      'You\'re buying a flight, not centimetres of seat.';

  @override
  String get onboardingTasteVotedTakSmaczek2 =>
      'A tall passenger takes up more room too. Charge them extra as well?';

  @override
  String get onboardingTasteVotedTakSmaczek3 =>
      'And how would you check who pays? A gate scale before boarding?';

  @override
  String get onboardingTasteVotedTakSmaczek4 =>
      'What about people whose weight comes from illness? Punished for life?';

  @override
  String get onboardingTasteVotedNieSmaczek1 =>
      'You already pay extra for a few kilos of luggage.';

  @override
  String get onboardingTasteVotedNieSmaczek2 =>
      'What about the person squeezed next to you? Same fare, worse seat.';

  @override
  String get onboardingTasteVotedNieSmaczek3 =>
      'A heavier plane burns more fuel — you pay the difference in your fare.';

  @override
  String get onboardingTasteVotedNieSmaczek4 =>
      'Would you fly three hours squeezed into half your seat?';

  @override
  String get onboardingTasteChangeMind => 'I\'ve changed my mind';

  @override
  String get onboardingTasteStandFirm => 'I\'m sticking with it';

  @override
  String get onboardingTasteGotYouTitle => 'Got you after all!';

  @override
  String get onboardingTasteGotYouSub => 'See how the others voted.';

  @override
  String get onboardingTasteStandFirmTitle => 'Good to stand your ground!';

  @override
  String get onboardingTasteStandFirmSub => 'But see how the others voted.';

  @override
  String get onboardingTasteSeeNext => 'Let\'s see the next one';

  @override
  String get onboardingTasteNextTitle => 'Let\'s try another one…';

  @override
  String get onboardingTasteQuestion2 =>
      'Should you tell a new partner exactly how many people you\'ve slept with?';

  @override
  String get onboardingTasteSureTitle => 'Are you sure though?';

  @override
  String get onboardingTasteQ2VotedTakSmaczek1 =>
      'There\'s no argument only if your numbers happen to match.';

  @override
  String get onboardingTasteQ2VotedTakSmaczek2 =>
      'If the number isn\'t 100, what does it actually change?';

  @override
  String get onboardingTasteQ2VotedTakSmaczek3 =>
      'The honesty fades, the number stays — back at the very first fight.';

  @override
  String get onboardingTasteQ2VotedTakSmaczek4 =>
      'Would you still tell if your number were embarrassingly big?';

  @override
  String get onboardingTasteQ2VotedNieSmaczek1 =>
      'Starting a relationship on a secret — solid foundation?';

  @override
  String get onboardingTasteQ2VotedNieSmaczek2 =>
      'Hiding the number means you think something\'s wrong with it.';

  @override
  String get onboardingTasteQ2VotedNieSmaczek3 =>
      'The truth comes out anyway — years later, at the worst moment.';

  @override
  String get onboardingTasteQ2VotedNieSmaczek4 =>
      'And if they ask you straight out? Lie to their face?';

  @override
  String get onboardingTasteQ2GotYouTitle => 'See? Nothing is obvious.';

  @override
  String get onboardingTasteQ2GotYouSub => 'And that was only question two…';

  @override
  String get onboardingTasteQ2StandFirmTitle => 'So you can\'t be moved?';

  @override
  String get onboardingTasteQ2StandFirmSub =>
      'We\'ll see. We have plenty of questions…';

  @override
  String get onboardingTasteWhatElse => 'What else have you got?';

  @override
  String get bridgeTitle => 'That was two — hundreds more to go';

  @override
  String get bridgeBody =>
      'You get one new question every day. Free, forever. Don\'t want to wait until tomorrow? Unlock the whole catalogue right away.';

  @override
  String get bridgeCtaPrimary => 'Get today\'s question';

  @override
  String get bridgeCtaSecondary => 'Unlock all';

  @override
  String get bridgeCtaSecondaryHint => '(and many more perks)';

  @override
  String get onboardingNotifyTitle => 'Hey, one more thing';

  @override
  String get onboardingNotifyBody =>
      'I can remind you to vote every day, at a time you pick. Voting takes 10 seconds — and your streak grows on its own. You can always switch it off in settings.';

  @override
  String get onboardingNotifyEnable => 'Turn on reminders';

  @override
  String get onboardingNotifySkip => 'Maybe later';

  @override
  String get wallCountdownCaption => 'Until free';

  @override
  String get wallCtaUnlock => 'Don\'t wait — unlock everything';

  @override
  String get wallCtaCaption => '(new sets every week!)';

  @override
  String get paywallBrand => 'DEBATLY PRO';

  @override
  String get paywallTitleDefault => 'No limits.\nNo end.\nWorldwide.';

  @override
  String paywallProfileHeadline(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n votes.\nSee what they say about you.',
      one: '1 vote.\nSee what it says about you.',
    );
    return '$_temp0';
  }

  @override
  String get paywallSubtitle =>
      '500+ questions, every argument FOR and AGAINST, your entire voting history.';

  @override
  String get paywallFeatureUnlimited => 'Questions with no daily limit';

  @override
  String get paywallFeatureSmaczki => 'Every argument, not just the first';

  @override
  String get paywallFeatureHistory => 'History and favorites forever';

  @override
  String get paywallFeatureOffline =>
      'Offline mode — the whole catalog on your phone';

  @override
  String get paywallSignInLink => 'Sign in';

  @override
  String get paywallLifetime => 'Lifetime';

  @override
  String get paywallAnnual => 'Yearly';

  @override
  String get paywallMonthly => 'Monthly';

  @override
  String get paywallPerMonth => '/mo';

  @override
  String get paywallCta => 'Unlock full access';

  @override
  String paywallLifetimeVsMonthly(int months) {
    String _temp0 = intl.Intl.pluralLogic(
      months,
      locale: localeName,
      other: 'One payment. Cheaper than $months months.',
      one: 'One payment. Cheaper than $months month.',
    );
    return '$_temp0';
  }

  @override
  String paywallMonthlyWeekly(String price) {
    return 'That\'s about $price a week';
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
  String get paywallOfferUnavailable =>
      'Plans are unavailable right now. Check back shortly — and if you already have PRO, use Restore below.';

  @override
  String get paywallTermsLink => 'Terms';

  @override
  String get paywallPrivacyLink => 'Privacy';

  @override
  String paywallBuildStamp(String version, String build, String code) {
    return 'v$version ($build) · ID $code';
  }
}
