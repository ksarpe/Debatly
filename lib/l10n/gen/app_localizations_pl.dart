// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Polish (`pl`).
class AppLocalizationsPl extends AppLocalizations {
  AppLocalizationsPl([String locale = 'pl']) : super(locale);

  @override
  String get later => 'Później';

  @override
  String get cancel => 'Anuluj';

  @override
  String get tryAgain => 'Spróbuj ponownie';

  @override
  String get orDivider => 'LUB';

  @override
  String get restorePurchase => 'Przywróć zakup';

  @override
  String get purchaseNotCompleted => 'Zakup nie został dokończony.';

  @override
  String get purchaseRestored => 'Zakup przywrócony.';

  @override
  String get purchaseRestoredCelebrate => 'Zakup przywrócony. 🎉';

  @override
  String get noPreviousPurchase => 'Nie znaleziono wcześniejszego zakupu.';

  @override
  String get storeUnreachable =>
      'Nie udało się połączyć ze sklepem. Sprawdź połączenie i spróbuj ponownie.';

  @override
  String get purchaseSyncPending =>
      'Zakup się powiódł, ale nie udało się go jeszcze potwierdzić. Spróbuj za chwilę „Przywróć zakup”.';

  @override
  String get restoreSignInTitle => 'Przywrócić zakup?';

  @override
  String get restoreSignInBody =>
      'Jeśli kupiłeś PRO będąc zalogowanym na konto, zaloguj się na nie — PRO i wszystkie Twoje dane wrócą automatycznie.';

  @override
  String get restoreOnThisDevice => 'Przywróć na tym urządzeniu';

  @override
  String get goPro => 'Przejdź na PRO';

  @override
  String get signIn => 'Zaloguj się';

  @override
  String get authCreateAccount => 'Utwórz konto';

  @override
  String get authWelcomeBackTitle => 'Miło Cię znów widzieć';

  @override
  String get authWelcomeBackSubtitle =>
      'Zaloguj się, żeby wrócić do swoich debat.';

  @override
  String get authRegisterTitle => 'Dołącz do Debatly';

  @override
  String get authRegisterSubtitle => 'Załóż konto i zabierz głos w debacie.';

  @override
  String get authEmailLabel => 'EMAIL';

  @override
  String get authPasswordLabel => 'HASŁO';

  @override
  String get authConfirmPasswordLabel => 'POWTÓRZ HASŁO';

  @override
  String get authShowPassword => 'Pokaż hasło';

  @override
  String get authHidePassword => 'Ukryj hasło';

  @override
  String get authForgotPassword => 'Nie pamiętasz hasła?';

  @override
  String get authTabSignIn => 'ZALOGUJ SIĘ';

  @override
  String get authTabSignUp => 'ZAŁÓŻ KONTO';

  @override
  String get authEnterEmail => 'Podaj email.';

  @override
  String get authEnterValidEmail => 'Podaj poprawny email.';

  @override
  String get authEnterPassword => 'Podaj hasło.';

  @override
  String get authMinPassword => 'Minimum 6 znaków.';

  @override
  String get authPasswordsMismatch => 'Hasła nie są takie same.';

  @override
  String get authAccountCreated => 'Konto utworzone.';

  @override
  String get authConfirmEmail => 'Sprawdź email i potwierdź konto.';

  @override
  String get authContinueWithApple => 'Kontynuuj z Apple';

  @override
  String get authContinueWithGoogle => 'Kontynuuj z Google';

  @override
  String authLegalConsent(String terms, String privacy) {
    return 'Kontynuując, akceptujesz $terms oraz $privacy.';
  }

  @override
  String get authLegalTermsLink => 'Regulamin';

  @override
  String get authLegalPrivacyLink => 'Politykę prywatności';

  @override
  String get authPasswordResetSent =>
      'Jeśli istnieje konto dla tego adresu, wysłaliśmy link do resetu hasła.';

  @override
  String get authSetNewPasswordTitle => 'Ustaw nowe hasło';

  @override
  String get authSetNewPasswordSubtitle =>
      'Link Cię zalogował — wybierz nowe hasło do swojego konta.';

  @override
  String get authNewPasswordLabel => 'NOWE HASŁO';

  @override
  String get authSetNewPasswordCta => 'ZAPISZ NOWE HASŁO';

  @override
  String get authPasswordUpdated => 'Hasło zmienione. Jesteś zalogowany.';

  @override
  String get authRecoveryLinkInvalid =>
      'Ten link do resetu wygasł albo został już użyty. Poproś o nowy.';

  @override
  String get authMissingSupabaseConfig =>
      'Brakuje konfiguracji Supabase. Uruchom aplikację z SUPABASE_URL i SUPABASE_ANON_KEY.';

  @override
  String get authMissingGoogleConfig =>
      'Brakuje GOOGLE_SERVER_CLIENT_ID, więc Google jest chwilowo wyłączone.';

  @override
  String get authAlreadySignedIn =>
      'Twoje konto jest już założone i zalogowane — nie musisz rejestrować się ponownie.';

  @override
  String authRegisteredPendingConfirm(String email) {
    return 'Konto jest już zarejestrowane na adres $email. Kliknij link z maila, aby je potwierdzić.';
  }

  @override
  String get authErrorInvalidCredentials => 'Nieprawidłowy email lub hasło.';

  @override
  String get authErrorEmailNotConfirmed =>
      'Najpierw potwierdź email — sprawdź skrzynkę.';

  @override
  String get authErrorEmailExists =>
      'Konto z tym adresem już istnieje. Zaloguj się.';

  @override
  String get authErrorSamePassword =>
      'To hasło jest już ustawione na Twoim koncie.';

  @override
  String get authErrorWeakPassword => 'Hasło jest zbyt słabe. Użyj dłuższego.';

  @override
  String get authErrorTooManyRequests =>
      'Zbyt wiele prób. Odczekaj chwilę i spróbuj ponownie.';

  @override
  String get settingsSectionApp => 'USTAWIENIA APLIKACJI';

  @override
  String get settingsSectionAccount => 'KONTO';

  @override
  String get settingsReminders => 'Przypomnienia';

  @override
  String get settingsRemindersSubtitle =>
      'Codzienne przypomnienie, by zagłosować';

  @override
  String get settingsReminderTime => 'Godzina przypomnienia';

  @override
  String get remindersPermissionDenied =>
      'Włącz powiadomienia w ustawieniach systemu, aby otrzymywać przypomnienia.';

  @override
  String get remindersOpenSettings => 'Otwórz ustawienia';

  @override
  String get notificationDailyTitle => 'Nowe pytania czekają 🔥';

  @override
  String get notificationDailyBody => 'Oddaj głos i przedłuż swoją serię.';

  @override
  String get notifNudgeTitle1 => 'Wybierz stronę 🔥';

  @override
  String get notifNudgeBody1 =>
      'Jest pytanie, które dzieli ludzi. Po której jesteś stronie?';

  @override
  String get notifNudgeTitle2 => 'Zagłosuj dziś 🤔';

  @override
  String get notifNudgeBody2 => 'Wiele osób się dziś nie zgadza. A Ty?';

  @override
  String get notifNudgeTitle3 => 'Tak czy nie?';

  @override
  String get notifNudgeBody3 => 'Oddaj głos, zanim zrobią to inni.';

  @override
  String get notifStreakTitle => 'Nie zgaś jej 🔥';

  @override
  String notifStreakBody(int streak) {
    return 'Dzień $streak Twojej serii. Zagłosuj dziś, żeby jej nie przerwać.';
  }

  @override
  String get notifGraceTitle => 'Twoja ranga się chwieje ⚠️';

  @override
  String get notifGraceBodyTomorrow =>
      'Spadnie jutro, jeśli dziś nie zagłosujesz.';

  @override
  String notifGraceBodyDays(int days) {
    return 'Spadnie za $days dni. Zagłosuj, żeby ją utrzymać.';
  }

  @override
  String get notifMinorityTitle => 'Wciąż w mniejszości? 🤔';

  @override
  String notifMinorityBody(int pct) {
    return '$pct% nie zgodziło się z Tobą. Zobacz, jak rozkłada się głos.';
  }

  @override
  String get notifResultTitle => 'Jak idzie głosowanie?';

  @override
  String get notifResultBody => 'Sprawdź, co naprawdę wybrała większość.';

  @override
  String get notifNextTitle => 'Czekają kolejne pytania 🔮';

  @override
  String get notifNextBody => 'Jest ich więcej. Znów będziesz w mniejszości?';

  @override
  String get notifSafeTitle => 'Seria zabezpieczona 🔥';

  @override
  String get notifSafeBody => 'Dobra robota. Wróć jutro, żeby ją podtrzymać.';

  @override
  String get settingsLanguage => 'Język';

  @override
  String get chooseLanguage => 'Wybierz język';

  @override
  String get settingsAppearance => 'Wygląd';

  @override
  String get settingsChooseAppearance => 'Wybierz wygląd';

  @override
  String get settingsAppearanceSystem => 'Systemowy';

  @override
  String get settingsAppearanceLight => 'Jasny';

  @override
  String get settingsAppearanceDark => 'Ciemny';

  @override
  String get settingsPremiumActive => 'Premium aktywne';

  @override
  String get settingsGoPremium => 'Przejdź na Premium';

  @override
  String get settingsOfflineQuestions => 'Pytania offline';

  @override
  String get offlineDownloadReady =>
      'Pobierz wszystkie pytania, by czytać bez internetu';

  @override
  String offlineDownloadSynced(String date) {
    return 'Pobrano · $date';
  }

  @override
  String offlineDownloadProgress(int done, int total) {
    return 'Pobieranie… $done/$total';
  }

  @override
  String get offlineDownloadComplete => 'Pytania zapisane na offline.';

  @override
  String get offlineDownloadFailed =>
      'Nie udało się pobrać. Sprawdź połączenie i spróbuj ponownie.';

  @override
  String get settingsPrivacy => 'Prywatność i dane';

  @override
  String get settingsFavorites => 'Ulubione pytania';

  @override
  String get favoritesTitle => 'Ulubione';

  @override
  String get favoritesEmptyTitle => 'Brak ulubionych';

  @override
  String get favoritesEmptyBody =>
      'Dotknij gwiazdki przy pytaniu, aby je tu zapisać.';

  @override
  String get favoriteAddTooltip => 'Dodaj do ulubionych';

  @override
  String get favoriteRemoveTooltip => 'Usuń z ulubionych';

  @override
  String get favoriteAdded => 'Dodano do ulubionych';

  @override
  String get favoriteRemoved => 'Usunięto z ulubionych';

  @override
  String get favoritesPremiumOnly => 'Ulubione to funkcja Premium.';

  @override
  String get favoriteError => 'Nie udało się zaktualizować ulubionych.';

  @override
  String get historyTitle => 'Historia pytań';

  @override
  String historyAnsweredCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Odpowiedziano na $count pytania',
      many: 'Odpowiedziano na $count pytań',
      few: 'Odpowiedziano na $count pytania',
      one: 'Odpowiedziano na 1 pytanie',
    );
    return '$_temp0';
  }

  @override
  String get historyTooltip => 'Historia pytań';

  @override
  String get historyEmptyTitle => 'Brak historii';

  @override
  String get historyEmptyBody => 'Zagłosuj na pytanie, a pojawi się ono tutaj.';

  @override
  String get historyLoadError => 'Nie udało się wczytać historii.';

  @override
  String historyYourVote(String vote) {
    return 'TY: $vote';
  }

  @override
  String get historyVersus => 'vs';

  @override
  String get historyLockedTitle => 'Odblokuj pełną historię';

  @override
  String get historyLockedBody =>
      'Darmowe konto widzi tu tylko dzisiejsze pytanie. Przejdź na PRO, aby przeglądać wszystkie swoje głosy.';

  @override
  String get historySearchTooltip => 'Szukaj w historii';

  @override
  String historyLoadMore(int count) {
    return 'Załaduj jeszcze $count';
  }

  @override
  String get historyNoVotes => 'Brak głosów';

  @override
  String get searchQuestionsHint => 'Szukaj pytania…';

  @override
  String get searchClearTooltip => 'Wyczyść wyszukiwanie';

  @override
  String get searchCloseTooltip => 'Zamknij wyszukiwanie';

  @override
  String get searchNoResultsTitle => 'Brak wyników';

  @override
  String get searchNoResultsBody =>
      'Żadne pytanie nie pasuje do wyszukiwania. Spróbuj innego słowa.';

  @override
  String get privacyDocsSection => 'DOKUMENTY';

  @override
  String get privacyPolicy => 'Polityka prywatności';

  @override
  String get privacyTerms => 'Regulamin';

  @override
  String get privacyDeleteAccount => 'Usuń konto i dane';

  @override
  String get privacyOpenInBrowser => 'Otwiera się w przeglądarce';

  @override
  String get privacyLinkFailed => 'Nie udało się otworzyć linku.';

  @override
  String get privacyDataSection => 'CO PRZECHOWUJEMY';

  @override
  String get privacyDataIntro =>
      'Krótki przegląd danych, które przechowuje Debatly, i po co.';

  @override
  String get privacyDataAccountTitle => 'Konto i logowanie';

  @override
  String get privacyDataAccountBody =>
      'Twój e-mail lub tożsamość logowania — albo anonimowy identyfikator dla gości — aby Twoje postępy były z Tobą na różnych urządzeniach.';

  @override
  String get privacyDataActivityTitle => 'Aktywność';

  @override
  String get privacyDataActivityBody =>
      'Twoje głosy, passa i ranga — napędzają Twoje pytania i postępy.';

  @override
  String get privacyDataPurchasesTitle => 'Zakupy';

  @override
  String get privacyDataPurchasesBody =>
      'Twój status Premium, obsługiwany przez App Store lub Google Play. Nigdy nie widzimy danych Twojej karty.';

  @override
  String get settingsPremiumActiveToast => 'Premium aktywne. 🎉';

  @override
  String get manageSubSheetTitle => 'Zarządzaj subskrypcją';

  @override
  String get manageSubStatusActive => 'Premium aktywne';

  @override
  String get manageSubStatusCancelled => 'Anulowano — nie odnowi się';

  @override
  String get manageSubStatusLifetime => 'Dostęp dożywotni';

  @override
  String get manageSubNoteLifetime =>
      'To jednorazowy zakup — nie ma żadnej subskrypcji do anulowania. Premium zostaje na tym koncie na zawsze.';

  @override
  String get manageSubClose => 'Zamknij';

  @override
  String manageSubRenewsOn(String date) {
    return 'Odnowi się $date';
  }

  @override
  String manageSubActiveUntil(String date) {
    return 'Aktywne do $date';
  }

  @override
  String get manageSubBilledAppStore => 'Rozliczane przez App Store';

  @override
  String get manageSubBilledPlayStore => 'Rozliczane przez Google Play';

  @override
  String get manageSubBilledWeb => 'Rozliczane online';

  @override
  String get manageSubNoteAppStore =>
      'Twoją subskrypcją zarządza Apple. Aby zmienić plan lub anulować, otwórz Subskrypcje w App Store — Premium zachowasz do końca bieżącego okresu.';

  @override
  String get manageSubNotePlayStore =>
      'Twoją subskrypcją zarządza Google. Aby zmienić plan lub anulować, otwórz Subskrypcje w Google Play — Premium zachowasz do końca bieżącego okresu.';

  @override
  String get manageSubNoteWeb =>
      'Subskrypcją zarządzaj lub anuluj ją tam, gdzie ją kupiono. Premium zachowasz do końca bieżącego okresu.';

  @override
  String get manageSubButtonAppStore => 'Zarządzaj w App Store';

  @override
  String get manageSubButtonPlayStore => 'Zarządzaj w Google Play';

  @override
  String get manageSubButtonGeneric => 'Zarządzaj subskrypcją';

  @override
  String get manageSubOpenFailedAppStore =>
      'Nie udało się otworzyć App Store. Wejdź w Ustawienia › Twoje imię › Subskrypcje, aby nią zarządzać.';

  @override
  String get manageSubOpenFailedPlayStore =>
      'Nie udało się otworzyć Google Play. Wejdź w Sklep Play › Menu › Subskrypcje, aby nią zarządzać.';

  @override
  String get manageSubOpenFailedGeneric =>
      'Nie udało się otworzyć strony subskrypcji. Zarządzaj nią tam, gdzie kupiono Premium.';

  @override
  String get signedOut => 'Wylogowano.';

  @override
  String get signOutError =>
      'Nie udało się wylogować. Sprawdź połączenie i spróbuj ponownie.';

  @override
  String get deleteAccountTitle => 'Usunąć konto?';

  @override
  String get deleteAccountBody =>
      'To trwale usunie Twoje konto i wszystkie powiązane dane — serię, głosy i odblokowania. Tej operacji nie można cofnąć. Jeśli masz aktywną subskrypcję Premium, anuluj ją osobno w App Store lub Google Play.';

  @override
  String get deleteAccountSuccess => 'Twoje konto zostało usunięte.';

  @override
  String get deleteAccountError =>
      'Nie udało się usunąć konta. Sprawdź połączenie i spróbuj ponownie.';

  @override
  String get guestSession => 'Sesja gościa';

  @override
  String get accountUnsecuredNote => 'Postępy zapisane tylko na tym telefonie';

  @override
  String get secureAccount => 'Zabezpiecz konto';

  @override
  String get yourAccount => 'Twoje konto';

  @override
  String get signOut => 'Wyloguj się';

  @override
  String get deleteAccount => 'Usuń konto';

  @override
  String get daysInARow => 'DNI Z RZĘDU';

  @override
  String streakRecord(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Rekord: $count dni',
      many: 'Rekord: $count dni',
      few: 'Rekord: $count dni',
      one: 'Rekord: $count dzień',
    );
    return '$_temp0';
  }

  @override
  String get rankLabel => 'RANGA';

  @override
  String get rankCardTopRank => 'Najwyższa ranga';

  @override
  String get rankCardPromotionReady => 'Awans gotowy!';

  @override
  String rankCardDaysToPromotion(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dni do awansu',
      many: '$count dni do awansu',
      few: '$count dni do awansu',
      one: '$count dzień do awansu',
    );
    return '$_temp0';
  }

  @override
  String get rankCardTapHint => 'KLIKNIJ';

  @override
  String get settingsTooltip => 'Ustawienia';

  @override
  String get swipeHint => 'Przesuń, aby zobaczyć następne pytanie';

  @override
  String get loadErrorTitle => 'Nie udało się załadować pytań';

  @override
  String get loadErrorBody =>
      'Sprawdź połączenie z internetem i spróbuj ponownie.';

  @override
  String get loadErrorBodyEmpty =>
      'Nie udało się pobrać dzisiejszego pytania. Spróbuj ponownie za chwilę.';

  @override
  String get offlineBannerLabel => 'Jesteś offline';

  @override
  String get offlineResultsHidden => 'Wyniki wrócą po połączeniu';

  @override
  String get yourVote => 'Twój głos';

  @override
  String get goDeeper => 'PRZECIWKO TOBIE';

  @override
  String get smaczkiBarPro => 'KONTRA';

  @override
  String get smaczkiBarFree => 'ARGUMENT ZA TOBĄ';

  @override
  String get smaczkiBarUntagged => 'JESZCZE DWA ARGUMENTY';

  @override
  String get shareLabel => 'Udostępnij';

  @override
  String get shareTooltip => 'Udostępnij pytanie';

  @override
  String get shareSubject => 'Pytanie z Debatly';

  @override
  String shareMessage(String question) {
    return '$question\n\nDebatly — przewrotne pytania, które rozpalają rozmowę.';
  }

  @override
  String get shareCardTagline => 'Pytania, które rozpalają rozmowę';

  @override
  String get shareCardHook => 'A Ty? TAK czy NIE?';

  @override
  String get streakTooltip => 'Twoja seria';

  @override
  String get conformityTooltip => 'Twoja oś zgodności';

  @override
  String get conformityTitle => 'OŚ ZGODNOŚCI';

  @override
  String conformityPctLine(int pct) {
    return '$pct% z większością';
  }

  @override
  String get axisRungAgainst2 => 'Zawsze pod prąd';

  @override
  String get axisRungAgainst1 => 'Częściej pod prąd';

  @override
  String get axisRungMiddle => 'Pół na pół';

  @override
  String get axisRungWith1 => 'Częściej z tłumem';

  @override
  String get axisRungWith2 => 'Zawsze z tłumem';

  @override
  String conformityNextTierLabel(String tier) {
    return 'Do stopnia «$tier»';
  }

  @override
  String conformityVotesNeeded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count głosu z większością',
      many: '$count głosów z większością',
      few: '$count głosy z większością',
      one: '$count głos z większością',
    );
    return '$_temp0';
  }

  @override
  String get conformityEmpty =>
      'Zagłosuj na kilka pytań, a zobaczysz, po której stronie zwykle jesteś.';

  @override
  String get conformityLoadError =>
      'Nie udało się załadować osi — spróbuj za chwilę.';

  @override
  String get profileSectionTitle => 'TWÓJ TYP';

  @override
  String get profileTypePillar => 'FILAR';

  @override
  String get profileTypeFlow => 'PŁYNIE Z PRĄDEM';

  @override
  String get profileTypeWolf => 'SAMOTNY WILK';

  @override
  String get profileTypeSeeker => 'POSZUKIWACZ';

  @override
  String get profileDescPillar => 'Myślisz jak większość i nic Tobą nie ruszy.';

  @override
  String get profileDescFlow =>
      'Idziesz z tłumem i z każdym dobrym argumentem.';

  @override
  String get profileDescWolf => 'Swoje zdanie i koniec dyskusji.';

  @override
  String get profileDescSeeker =>
      'Nie kupujesz cudzych opinii, ale szukasz lepszych.';

  @override
  String get profileProvisional => 'profil wstępny';

  @override
  String profileProgress(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Jeszcze $n odpowiedzi i poznasz swój typ.',
      many: 'Jeszcze $n odpowiedzi i poznasz swój typ.',
      few: 'Jeszcze $n odpowiedzi i poznasz swój typ.',
      one: 'Jeszcze 1 odpowiedź i poznasz swój typ.',
    );
    return '$_temp0';
  }

  @override
  String get profileStatCrowdLabel => 'głosów z większością';

  @override
  String get profileStatMovedLabel => 'kontr Cię ruszyło';

  @override
  String get profileLockedFlips => 'Zdania, które Cię przewróciły';

  @override
  String get profileLockedLoneliest => 'Twój najbardziej samotny głos';

  @override
  String get profileLockedRarity => 'Twój typ ma tylko …% użytkowników';

  @override
  String get profileLockedTrend => 'Trend w czasie';

  @override
  String profileRarityLine(int pct) {
    return 'Twój typ ma $pct% użytkowników';
  }

  @override
  String profileLoneliestLine(int pct) {
    return 'Tylko $pct% głosowało jak Ty';
  }

  @override
  String profileSliceLine(int pct, int moved) {
    return '$pct% z większością · zmiany zdania: $moved';
  }

  @override
  String get profileNotEnoughData => 'Jeszcze za mało danych.';

  @override
  String get profileShareHeadline => 'MÓJ TYP DEBATANTA';

  @override
  String profileShareCrowdWith(int pct) {
    return 'z tłumem w $pct%';
  }

  @override
  String profileShareCrowdAgainst(int pct) {
    return 'przeciw tłumowi w $pct%';
  }

  @override
  String profileShareQuestionsLine(int count, String crowd) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pytania',
      many: '$count pytań',
      few: '$count pytania',
      one: '1 pytanie',
    );
    return '$_temp0 · $crowd';
  }

  @override
  String profileShareMovedLine(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count razy zmieniłem zdanie',
      many: '$count razy zmieniłem zdanie',
      few: '$count razy zmieniłem zdanie',
      one: 'raz zmieniłem zdanie',
      zero: 'ani razu nie zmieniłem zdania',
    );
    return '$_temp0';
  }

  @override
  String profileShareMessage(String type) {
    return 'Jestem $type. Sprawdź swój typ w Debatly.';
  }

  @override
  String get profileShareSubject => 'Mój typ z Debatly';

  @override
  String get profileShareFooter => 'debatly.app';

  @override
  String get newQuestionBadge => 'Nowe';

  @override
  String get newQuestionTooltip =>
      'Świeżo dodane pytanie — społeczność dopiero zaczyna głosować.';

  @override
  String get voteYes => 'TAK';

  @override
  String get voteNo => 'NIE';

  @override
  String get voteFailed => 'Nie udało się zagłosować.';

  @override
  String get noConnection => 'Brak połączenia — spróbuj ponownie za chwilę.';

  @override
  String get backToLatestQuestion => 'Wróć do najnowszego pytania';

  @override
  String get proActiveTitle => 'PRO aktywne 🎉';

  @override
  String get savePromptBody =>
      'Twoje PRO jest na razie przypisane do konta-gościa. Załóż konto (e-mail lub Google), aby nie stracić dostępu po reinstalacji albo na innym urządzeniu — Twój postęp zostanie zachowany.';

  @override
  String get createAccount => 'Załóż konto';

  @override
  String get secureStreakTitle => 'Zabezpiecz swoją passę 🔥';

  @override
  String secureStreakBody(int streak) {
    return 'Masz już $streak-dniową passę — ale żyje ona tylko na tym telefonie. Załóż konto (e-mail lub Google), a przetrwa reinstalację i zmianę urządzenia.';
  }

  @override
  String get suggestQuestionTitle => 'Zaproponuj pytanie';

  @override
  String get suggestQuestionSettingsSubtitle =>
      'Masz pomysł, który podzieli ludzi? Podrzuć go';

  @override
  String get suggestQuestionIntro =>
      'Najlepsze pytania zaczynają się od „Czy…”, nie mają wygodnej odpowiedzi i dzielą ludzi pół na pół. Może być na surowo — my je doszlifujemy.';

  @override
  String get suggestQuestionHint => 'Czy…?';

  @override
  String get suggestQuestionMinChars => 'Co najmniej 10 znaków';

  @override
  String get suggestQuestionSend => 'Wyślij propozycję';

  @override
  String get suggestQuestionThanks =>
      'Dzięki! Twoja propozycja właśnie do nas dotarła.';

  @override
  String get suggestQuestionFailed =>
      'Nie udało się wysłać — spróbuj za chwilę.';

  @override
  String get suggestQuestionRateLimited =>
      'Na dziś wystarczy — wróć jutro z kolejnym pomysłem.';

  @override
  String get suggestQuestionNudge =>
      'Masz pomysł na pytanie, które utkwi ludziom w głowie? Podrzuć je!';

  @override
  String get suggestQuestionNudgeAction => 'Zaproponuj';

  @override
  String get smaczkiTitle => 'Argumenty';

  @override
  String get smaczkiTitleTag => '(smaczki)';

  @override
  String get smaczkiSubtitle => 'Nie spodoba Ci się to zdanie.';

  @override
  String smaczkiRemaining(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Jeszcze $count argumentu na Ciebie czeka.',
      many: 'Jeszcze $count argumentów na Ciebie czeka.',
      few: 'Jeszcze $count argumenty na Ciebie czekają.',
      one: 'Jeszcze jeden argument na Ciebie czeka.',
    );
    return '$_temp0';
  }

  @override
  String get smaczekSuggestCta => 'Zaproponuj własny';

  @override
  String get smaczekSuggestHint => 'Twój argument…';

  @override
  String get smaczekSuggestMinChars => 'Co najmniej 5 znaków';

  @override
  String get smaczekSuggestSend => 'Wyślij';

  @override
  String smaczkiLoadError(String error) {
    return 'Nie udało się wczytać smaczków.\n$error';
  }

  @override
  String get smaczkiEmpty => 'Do tego pytania nie ma jeszcze smaczków.';

  @override
  String get smaczkiUnlockCta => 'Odblokuj';

  @override
  String get smaczkiLockedBeforeVote =>
      'Najpierw zagłosuj. Potem sprawdzę, czy się utrzymasz.';

  @override
  String get smaczekChallengeEyebrow => 'ZANIM POKAŻĘ WYNIK';

  @override
  String get challengeHoldCta => 'TRZYMAM SIĘ';

  @override
  String get challengeMovedCta => 'TO MNIE RUSZYŁO';

  @override
  String get smaczkiSheetFreeHeader =>
      'Dostałeś argument przeciwko sobie. Zostały dwa: jeden, który Cię broni, i jeden, który komplikuje sprawę.';

  @override
  String smaczkiSheetFreeHeaderPlain(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Pierwszy masz za sobą. Zostało jeszcze $count.',
      few: 'Pierwszy masz za sobą. Zostały jeszcze $count.',
      two: 'Pierwszy masz za sobą. Zostały jeszcze dwa.',
      one: 'Pierwszy masz za sobą. Został jeszcze jeden.',
      zero: 'Ten argument masz już za sobą.',
    );
    return '$_temp0';
  }

  @override
  String resultFlipLine(int percent) {
    return 'Kontra przewróciła $percent% głosujących.';
  }

  @override
  String get ranksLoadError => 'Nie udało się wczytać rang.';

  @override
  String get rankLadder => 'Drabinka rang';

  @override
  String get yourRankUpper => 'TWOJA RANGA';

  @override
  String get topRankRespect => 'Najwyższa ranga — szacun.';

  @override
  String streakDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dni',
      many: '$count dni',
      few: '$count dni',
      one: '$count dzień',
    );
    return 'Seria: $_temp0';
  }

  @override
  String longestStreakDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dni',
      many: '$count dni',
      few: '$count dni',
      one: '$count dzień',
    );
    return 'Najdłuższa seria: $_temp0';
  }

  @override
  String daysToNextRank(int remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: 'Jeszcze $remaining dni do kolejnej rangi',
      many: 'Jeszcze $remaining dni do kolejnej rangi',
      few: 'Jeszcze $remaining dni do kolejnej rangi',
      one: 'Jeszcze $remaining dzień do kolejnej rangi',
    );
    return '$_temp0';
  }

  @override
  String rankFrom(int minStreak) {
    return 'od $minStreak';
  }

  @override
  String streakGraceWarning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Zostało Ci $count łaski — potem ranga spadnie',
      many: 'Zostało Ci $count łask — potem ranga spadnie',
      few: 'Zostały Ci $count łaski — potem ranga spadnie',
      one: 'Została Ci $count łaska — potem ranga spadnie',
    );
    return '$_temp0';
  }

  @override
  String get rankUpEyebrow => 'NOWA RANGA';

  @override
  String rankUpStreakLine(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dnia z rzędu 🔥',
      many: '$count dni z rzędu 🔥',
      few: '$count dni z rzędu 🔥',
      one: '$count dzień z rzędu 🔥',
    );
    return '$_temp0';
  }

  @override
  String get rankUpDismiss => 'Świetnie!';

  @override
  String get rankShareHeadline => 'MOJA NOWA RANGA';

  @override
  String rankShareStreakLine(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dnia z rzędu',
      many: '$count dni z rzędu',
      few: '$count dni z rzędu',
      one: '$count dzień z rzędu',
    );
    return '$_temp0';
  }

  @override
  String get rankShareSubject => 'Moja ranga w Debatly';

  @override
  String rankShareMessage(String rank) {
    return 'Moja nowa ranga w Debatly: $rank 🔥\n\nDebatly — przewrotne pytania, które rozpalają rozmowę.';
  }

  @override
  String get onboardingBegin => 'Zaczynajmy';

  @override
  String get onboardingWelcomeTitle => 'Myślisz, że znasz się na ludziach?';

  @override
  String get onboardingWelcomeTitlePunch => 'A siebie jak dobrze znasz?';

  @override
  String get onboardingWelcomeBody =>
      'Zaraz to sprawdzimy. Dostaniesz pytanie, na które nie ma dobrej odpowiedzi — zagłosuj i zobacz, ilu ludzi myśli inaczej niż ty.';

  @override
  String get onboardingTasteKicker => 'TWÓJ RUCH';

  @override
  String get onboardingTasteQuestion =>
      'Czy osoby otyłe powinny płacić za dwa miejsca w samolocie?';

  @override
  String get onboardingTasteHoldOnTitle => 'Ale chwila…';

  @override
  String get onboardingTasteVotedTakSmaczek1 =>
      'Bilet kupujesz na lot, nie na centymetry fotela.';

  @override
  String get onboardingTasteVotedTakSmaczek2 =>
      'Wysoki pasażer też zajmuje więcej miejsca. Jemu też dopłata?';

  @override
  String get onboardingTasteVotedTakSmaczek3 =>
      'Jak chcesz to weryfikować? Bramka przed wejściem do samolotu?';

  @override
  String get onboardingTasteVotedTakSmaczek4 =>
      'A ci, którzy tyją przez chorobę? Pokrzywdzeni na zawsze?';

  @override
  String get onboardingTasteVotedNieSmaczek1 =>
      'Za kilka kilogramów walizki musisz przecież dopłacić.';

  @override
  String get onboardingTasteVotedNieSmaczek2 =>
      'Co z komfortem osoby obok? Zapłaciła tyle samo, a ma ciaśniej.';

  @override
  String get onboardingTasteVotedNieSmaczek3 =>
      'Cięższy samolot pali więcej. Różnicę dopłacasz w swoim bilecie.';

  @override
  String get onboardingTasteVotedNieSmaczek4 =>
      'Poleciałbyś 3 godziny wciśnięty w pół swojego fotela?';

  @override
  String get onboardingTasteChangeMind => 'Zmieniam zdanie';

  @override
  String get onboardingTasteStandFirm => 'Zostaję przy swoim';

  @override
  String get onboardingTasteGotYouTitle => 'A jednak, mamy Cię!';

  @override
  String get onboardingTasteGotYouSub => 'Zobacz, jak głosowali inni.';

  @override
  String get onboardingTasteStandFirmTitle => 'Warto trzymać swoje stanowisko!';

  @override
  String get onboardingTasteStandFirmSub => 'Ale zobacz, jak głosowali inni.';

  @override
  String get onboardingTasteSeeNext => 'Zobaczmy kolejne';

  @override
  String get onboardingTasteNextTitle => 'Spróbujmy z kolejnym…';

  @override
  String get onboardingTasteQuestion2 =>
      'Czy powinieneś mówić nowemu partnerowi, z iloma osobami spałeś?';

  @override
  String get onboardingTasteSureTitle => 'Czy aby na pewno?';

  @override
  String get onboardingTasteQ2VotedTakSmaczek1 =>
      'Kłótni nie będzie tylko wtedy, gdy wasze liczby są podobne.';

  @override
  String get onboardingTasteQ2VotedTakSmaczek2 =>
      'Jeśli to nie jest setka — co to właściwie zmienia?';

  @override
  String get onboardingTasteQ2VotedTakSmaczek3 =>
      'Szczerość minie, liczba zostanie — wróci w pierwszej kłótni.';

  @override
  String get onboardingTasteQ2VotedTakSmaczek4 =>
      'Powiedziałbyś, gdyby twoja liczba była naprawdę duża?';

  @override
  String get onboardingTasteQ2VotedNieSmaczek1 =>
      'Związek zaczynasz od sekretu — dobry fundament?';

  @override
  String get onboardingTasteQ2VotedNieSmaczek2 =>
      'Ukrywasz liczbę, czyli sam uważasz, że coś jest z nią nie tak.';

  @override
  String get onboardingTasteQ2VotedNieSmaczek3 =>
      'Prawda i tak wyjdzie — po latach, w najgorszym momencie.';

  @override
  String get onboardingTasteQ2VotedNieSmaczek4 =>
      'A jeśli partner zapyta wprost? Skłamiesz w oczy?';

  @override
  String get onboardingTasteQ2GotYouTitle => 'Widzisz? Nic nie jest oczywiste.';

  @override
  String get onboardingTasteQ2GotYouSub => 'A to było dopiero drugie pytanie…';

  @override
  String get onboardingTasteQ2StandFirmTitle => 'Ciebie nie da się ruszyć?';

  @override
  String get onboardingTasteQ2StandFirmSub =>
      'Sprawdzimy. Pytań nam nie zabraknie…';

  @override
  String get onboardingTasteWhatElse => 'Co jeszcze macie?';

  @override
  String get bridgeTitle => 'To były dwa — a zostały jeszcze setki';

  @override
  String get bridgeBody =>
      'Codziennie dostajesz jedno nowe pytanie. Za darmo, na zawsze. Nie chcesz czekać do jutra? Odblokuj cały katalog od razu.';

  @override
  String get bridgeCtaPrimary => 'Odbierz dzisiejsze pytanie';

  @override
  String get bridgeCtaSecondary => 'Odblokuj wszystkie';

  @override
  String get bridgeCtaSecondaryHint => '(i wiele innych korzyści)';

  @override
  String get onboardingNotifyTitle => 'Hej, jeszcze jedno';

  @override
  String get onboardingNotifyBody =>
      'Mogę Ci codziennie przypominać o głosowaniu — o godzinie, którą wybierzesz. Jak coś, to sobie to wyłączysz w ustawieniach.';

  @override
  String get onboardingNotifyEnable => 'Włącz przypomnienia';

  @override
  String get onboardingNotifySkip => 'Może później';

  @override
  String get wallCountdownCaption => 'Do darmowego';

  @override
  String get wallCtaUnlock => 'Nie czekaj — odblokuj wszystkie';

  @override
  String get wallCtaCaption => '(co tydzień nowe zestawy!)';

  @override
  String get paywallBrand => 'DEBATLY PRO';

  @override
  String get paywallTitleDefault => 'Bez limitu.\nBez końca.\nGlobalnie.';

  @override
  String paywallProfileHeadline(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n głosu.\nZobacz, co mówią o Tobie.',
      many: '$n głosów.\nZobacz, co mówią o Tobie.',
      few: '$n głosy.\nZobacz, co mówią o Tobie.',
      one: '1 głos.\nZobacz, co mówi o Tobie.',
    );
    return '$_temp0';
  }

  @override
  String get paywallSubtitle =>
      '500+ pytań, wszystkie argumenty ZA i PRZECIW, cała Twoja historia głosów.';

  @override
  String get paywallFeatureUnlimited => 'Pytania bez limitu dziennego';

  @override
  String get paywallFeatureSmaczki => 'Wszystkie argumenty, nie pierwszy';

  @override
  String get paywallFeatureHistory => 'Historia i ulubione na zawsze';

  @override
  String get paywallFeatureOffline => 'Tryb offline — cały katalog w telefonie';

  @override
  String get paywallSignInLink => 'Zaloguj się';

  @override
  String get paywallLifetime => 'Dożywotni';

  @override
  String get paywallAnnual => 'Roczny';

  @override
  String get paywallMonthly => 'Miesięcznie';

  @override
  String get paywallPerMonth => '/mies.';

  @override
  String get paywallCta => 'Odblokuj pełny dostęp';

  @override
  String paywallLifetimeVsMonthly(int months) {
    String _temp0 = intl.Intl.pluralLogic(
      months,
      locale: localeName,
      other: 'Jednorazowo. Taniej niż $months miesiąca.',
      many: 'Jednorazowo. Taniej niż $months miesięcy.',
      few: 'Jednorazowo. Taniej niż $months miesiące.',
      one: 'Jednorazowo. Taniej niż $months miesiąc.',
    );
    return '$_temp0';
  }

  @override
  String paywallMonthlyWeekly(String price) {
    return 'To ok. $price tygodniowo';
  }

  @override
  String get paywallLifetimeNote => 'Jedna płatność — na zawsze';

  @override
  String get paywallSubscriptionNote =>
      'Odnawia się automatycznie — anulujesz w każdej chwili';

  @override
  String get paywallLoadError =>
      'Nie udało się wczytać oferty. Sprawdź połączenie i spróbuj ponownie.';

  @override
  String get paywallOfferUnavailable =>
      'Plany są chwilowo niedostępne. Zajrzyj za jakiś czas — a jeśli masz już PRO, użyj „Przywróć zakup” poniżej.';

  @override
  String get paywallTermsLink => 'Regulamin';

  @override
  String get paywallPrivacyLink => 'Prywatność';

  @override
  String paywallBuildStamp(String version, String build, String code) {
    return 'v$version ($build) · ID $code';
  }
}
