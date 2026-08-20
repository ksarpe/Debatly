# Testy manualne — checklista po releasie

Ręczna checklista do przeklikania na **fizycznym telefonie** po każdym większym
releasie (nowa wersja w Play / TestFlight). Cel: po przejściu wszystkiego z
priorytetem P0 możesz powiedzieć „okej, działa" — bez zgadywania.

Testy automatyczne (`flutter test`, 68 plików) pokrywają logikę i widgety,
a `integration_test/app_smoke_test.dart` przechodzi całą apkę end-to-end na
mockowych danych (osiem pozycji z tej listy — oznaczone 🤖).
Ta lista celowo pokrywa to, czego one **nie** dotykają: prawdziwe SDK (Supabase,
RevenueCat, Google/Apple Sign-In), OS (powiadomienia, deep linki, share sheet,
sklep), zimne starty, reinstalacje i realne dane.

---

## Legenda

| Znacznik | Znaczenie |
|---|---|
| **P0** | Blokuje release. Zawsze, przy każdej wersji. (~35–45 min) |
| **P1** | Przy większym releasie / gdy zmieniał się dany obszar. (~45 min) |
| **P2** | Regresje rzadkie — raz na kilka wersji albo po zmianie w tym module. |
| 🧑 | Tylko człowiek z telefonem (OS, sklep, poczta, palec). |
| ⚙️ | Człowiek klika, ale ja mogę przygotować dane albo zweryfikować wynik w bazie. |
| 🤖 | Mogę zrobić sam (patrz sekcja „Co mogę zautomatyzować"). |

Wynik zapisuj obok testu: `OK` / `FAIL + krótki opis` / `N/A`.

---

## 0. Przygotowanie środowiska

Bez tego połowa testów jest bezwartościowa:

- [ ] Build **release** (nie debug!) z prawdziwymi kluczami
      (`--dart-define-from-file=env/prod.json`). Debug ma włączone DEV tools,
      inne zachowanie Sentry i inny podpis → inne zachowanie zakupów.
- [ ] Telefon Android **i** iPhone, jeśli release idzie na obie platformy.
      Minimum: ta platforma, na której coś się zmieniło.
- [ ] Trzy tożsamości pod ręką:
  - **GOŚĆ** — świeża instalacja, bez konta (anonimowe UUID).
  - **FREE z kontem** — e-mail **spoza** `kDevToolsTesterEmails`
    (inaczej zobaczysz sekcję DEV i nie przetestujesz widoku realnego usera).
  - **PRO** — konto z aktywną subskrypcją (sandbox / license testers w Play).
- [ ] Konto testowe w **sandboxie sklepu** (App Store Sandbox / Play License
      Testers) — inaczej zakup obciąży kartę.
- [ ] Skrzynka mailowa, do której masz dostęp **na telefonie** (potwierdzenie
      konta, reset hasła).
- [ ] Dostęp do Sentry i do tabeli `app_events` w Supabase.
- [ ] Zanotuj wersję i numer builda — wchodzą do raportu na końcu pliku.

> **Pułapka doby:** część testów (ściana dnia, paywall raz na dobę) zależy od
> **lokalnej północy**, a streak od **doby UTC**. To są dwa różne zegary, celowo.
> Żeby przeskoczyć „dzień", zmień datę w ustawieniach systemu telefonu.

---

## A. Instalacja, zimny start, onboarding

### A1 · Pierwsza instalacja i onboarding — **P0** 🧑
**Warunek:** apka całkowicie odinstalowana (kasuje dane lokalne i anonimowe UUID).

| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Zainstaluj i uruchom | Splash z logo, bez błysku białym tłem, bez crasha |
| 2 | Poczekaj na koniec splasha | Ekran powitalny onboardingu — NIE feed i NIE paywall |
| 3 | Przejdź dalej | Pierwsze pytanie „smakowe": tekst czytelny, dwa kafle TAK/NIE |
| 4 | Zagłosuj | Pokazuje się realny split społeczności; **głos NIE jest zapisywany** jako Twój (to tylko degustacja) |
| 5 | Drugie pytanie, zagłosuj | To samo; kropki postępu przesuwają się |
| 6 | Przejdź dalej | Bridge: CTA darmowej ścieżki jest **dominujące**, PRO drugorzędne |
| 7 | Wybierz darmową ścieżkę | Ekran zgody na przypomnienia |
| 8 | Odrzuć przypomnienia | Onboarding się kończy, ląduje feed z pytaniem dnia |
| 9 | Zrekapituluj cały przebieg | **Ani razu nie wyskoczył paywall** — to twarda reguła produktu |

### A2 · Drugi start (ciepły) — **P0** 🧑
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Ubij apkę z listy zadań i odpal ponownie | Splash → od razu feed, **bez onboardingu** |
| 2 | Sprawdź pytanie dnia | To samo co przed ubiciem (w tej samej dobie nie losuje nowego) |

### A3 · Zgoda na powiadomienia w onboardingu — **P1** 🧑
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Reinstall → onboarding → ekran przypomnień | Tłumaczy po co, nie straszy |
| 2 | Zaakceptuj | Pojawia się **systemowy** dialog uprawnień (Android 13+ / iOS) |
| 3 | Przyznaj uprawnienie | Wraca do apki, idzie do feedu; w Ustawieniach przełącznik przypomnień jest **włączony** |
| 4 | Ustawienia → godzina przypomnienia | Widoczna domyślna godzina, da się zmienić |

### A4 · Odmowa uprawnień do powiadomień — **P1** 🧑
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Reinstall → onboarding → odmów w systemowym dialogu | Apka idzie dalej normalnie, nic nie blokuje |
| 2 | Ustawienia → włącz przypomnienia | Komunikat o odrzuconym uprawnieniu + akcja **„Otwórz ustawienia"** |
| 3 | Tapnij tę akcję | Otwierają się ustawienia powiadomień **tej** aplikacji w systemie |
| 4 | Włącz tam powiadomienia i wróć przyciskiem wstecz | Przełącznik w apce **sam** przeskakuje na włączony, bez restartu apki |

### A5 · Aktualizacja z poprzedniej wersji (nie reinstall!) — **P0** ⚙️
**Warunek:** na telefonie stoi **poprzedni** release z realnym stanem (głosy, streak, ew. PRO).

| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Zainstaluj nową wersję **na wierzch** starej | Instalacja przechodzi, bez błędu podpisu |
| 2 | Uruchom | **Brak onboardingu** — apka pamięta, że już był |
| 3 | Ustawienia: streak i ranga | Te same wartości co przed aktualizacją |
| 4 | Status PRO (jeśli był) | Nadal PRO, **bez** konieczności „Przywróć zakupy" |
| 5 | Historia głosów | Poprzednie głosy na miejscu |

> Ten test najczęściej wyłapuje katastrofy (nadpisane UUID, wyczyszczone
> preferencje, zmieniony klucz cache'a). Nie zastępuj go świeżą instalką.

---

## B. Pytanie dnia, głosowanie i kontra (smaczek)

### B1 · Głos na pytanie dnia — **P0** ⚙️
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Odpal apkę (dziś jeszcze bez głosu) | Pytanie dnia, dwa kafle, **brak** widocznego splitu |
| 2 | Tapnij TAK (lub NIE) | Kafel się zaznacza, haptyk; **słupki NIE pojawiają się od razu** |
| 3 | Obserwuj | Wpada **kontra** (smaczek): słowo po słowie, uderza w Twój kafel |
| 4 | Poczekaj aż tekst się skończy | Dopiero teraz odblokowują się odpowiedzi „TRZYMAM SIĘ" / „TO MNIE RUSZYŁO" (wcześniej nieaktywne) |
| 5 | Wybierz „TRZYMAM SIĘ" | Bramka się zamyka, **dopiero teraz** pojawiają się słupki ze splitem |
| 6 | Sprawdź swój głos na słupkach | Podświetlona strona, którą wybrałeś w kroku 2 |
| 7 | Linia pod pytaniem | Przy ≥30 rozegranych bramkach: „Kontra przewróciła X%". Poniżej progu linii **nie ma** (nie „0%") |

### B2 · Głos jest ostateczny (first-write-wins) — **P0** ⚙️
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Po B1 ubij apkę i odpal ponownie | Pytanie dnia pokazuje się **już zagłosowane**, z Twoim wyborem |
| 2 | Spróbuj tapnąć drugi kafel | Nic się nie zmienia |
| 3 | Cofnij datę w telefonie i wróć do pytania | Nadal pierwotny wybór — nie da się przegłosować |

### B3 · „TO MNIE RUSZYŁO" nie zmienia głosu — **P0** ⚙️
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Na nowym pytaniu (PRO) zagłosuj TAK | Wpada kontra |
| 2 | Wybierz „TO MNIE RUSZYŁO" | Słupki się pojawiają, ale **Twój głos to nadal TAK** — nie przeskakuje na NIE |
| 3 | Otwórz historię | Wpis pokazuje TAK |

### B4 · Wyjście z kontry przyciskiem wstecz — **P1** ⚙️
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Zagłosuj, a w trakcie spadania słów naciśnij systemowy **wstecz** | Bramka się zamyka, pokazują się słupki — to nie jest pułapka |
| 2 | Otwórz panel smaczków (pigułka na dolnym pasku) | Darmowy user **nadal ma** swój jeden czytelny smaczek — cofnięcie go nie spaliło |

### B5 · Panel smaczków zablokowany przed głosem — **P0** 🤖🧑
**Pokryte smoke testem** (`flutter test integration_test/app_smoke_test.dart`) — ręcznie tylko gdy zmieniał się dolny pasek.
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Na **niezagłosowanym** pytaniu tapnij pigułkę smaczków | Pigułka jest widoczna, ale tap daje toast „Najpierw zagłosuj" — panel się **nie** otwiera |
| 2 | Zagłosuj i tapnij ponownie | Panel się otwiera |
| 3 | Jako FREE policz czytelne smaczki | Dokładnie **jeden** czytelny, reszta z kłódką |
| 4 | Jako PRO | Wszystkie czytelne |

### B6 · Limit bramek w sesji — **P2** ⚙️ (PRO)
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Zagłosuj po kolei na 11 pytaniach z katalogu | Pierwsze 10 pokazuje bramkę z kontrą; 11. idzie prosto do słupków |
| 2 | Zminimalizuj apkę na >30 min i wróć | Bramki wracają (licznik zresetowany) |
| 3 | Obejrzyj drugą i kolejne bramki | Są **kompaktowe**, ale tekst kontry jest w całości i kafel nadal się trzęsie |

### B7 · Pytanie bez czytelnej kontry — **P2** ⚙️
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Zagłosuj na pytaniu bez pasującego smaczka | Bramka **nie** pojawia się wcale, słupki od razu — bez pustego ekranu i bez zawieszki |

---

## C. Ściana dnia (day wall) i rolowanie doby

### C1 · Ściana dnia po zagłosowaniu — **P0** 🤖🧑 (konto FREE)
**Pokryte smoke testem** poza wyglądem rozmycia i odliczaniem na żywo — te obejrzyj okiem.
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Jako FREE zagłosuj na pytaniu dnia i zamknij bramkę | Widać słupki |
| 2 | Przesuń palcem **do przodu** | Ściana dnia: rozmyta zajawka następnego pytania (widoczne pierwsze ~4 słowa), odliczanie, CTA odblokowania |
| 3 | Sprawdź odliczanie | Leci na żywo, do **lokalnej północy** |
| 4 | Przesuń **wstecz** albo naciśnij systemowy wstecz | Wraca na pytanie dnia — ściana nie więzi użytkownika |
| 5 | Górny pasek | Chip ze streakiem nadal widoczny na ścianie |

### C2 · Paywall po pierwszym uderzeniu w ścianę — **P0** 🤖🧑
**Pokryte smoke testem** (reguła „raz na dobę”) — ręcznie sprawdź tylko treść i ceny (D1).
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Jako FREE, po zagłosowaniu, uderz pierwszy raz w ścianę | Paywall otwiera się **automatycznie**, raz |
| 2 | Zamknij (X albo systemowy wstecz) | Zamyka się, wraca ściana / feed |
| 3 | Uderz w ścianę drugi raz tego samego dnia | Paywall **nie** otwiera się automatycznie (limit 1×/dobę) |
| 4 | Tapnij CTA odblokowania na ścianie | Paywall otwiera się (ręcznie zawsze wolno) |

### C3 · Paywall nigdy przed pierwszym głosem — **P0** 🤖
**Pokryte smoke testem** — ręcznie tylko przy zmianach w onboardingu.
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Świeża instalka, przejdź onboarding, **nie głosuj** | Feed z pytaniem dnia |
| 2 | Spróbuj przesunąć do przodu | Ściana dnia się pokazuje, ale paywall **NIE** otwiera się sam |
| 3 | Zagłosuj i uderz w ścianę | Dopiero teraz paywall wchodzi automatycznie |

### C4 · Rolowanie doby — **P1** 🧑
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Zagłosuj dziś, zostaw apkę w tle | — |
| 2 | Zmień datę telefonu na jutro (albo poczekaj do północy) i wróć do apki | **Nowe** pytanie dnia, gotowe do głosowania |
| 3 | Zagłosuj i sprawdź streak | Podbił się o 1 |
| 4 | Otwórz historię | Wczorajszy głos jest, z prawidłową datą |

---

## D. Paywall, zakup, przywracanie

> **Zawsze na koncie sandbox.** Po testach anuluj subskrypcję testową, żeby nie
> odnawiała się w tle i nie fałszowała kolejnych testów FREE.

### D1 · Wygląd i treść paywalla — **P0** 🧑
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Otwórz paywall z dowolnego miejsca | Fullscreen, nagłówek-slogan („Bez limitu. / Bez końca. / Globalnie.") + podtytuł o katalogu |
| 2 | Sprawdź plany | Miesięczny **19,99 zł** (preselected) i dożywotni **69,99 zł**; brak tygodniowego, rocznego i trialu |
| 3 | Podlinijka przy miesięcznym | „To ok. X zł tygodniowo"; **brak** plakietki „best value" |
| 4 | X i systemowy wstecz | Oba zamykają paywall — jest zawsze zamykalny |
| 5 | Stopka | Linki do Regulaminu i Prywatności otwierają przeglądarkę |

### D2 · Zakup subskrypcji miesięcznej — **P0** 🧑
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Tapnij CTA zakupu miesięcznego | Natywny arkusz sklepu z ceną 19,99 zł |
| 2 | Potwierdź zakup (sandbox) | Sklep potwierdza |
| 3 | Wróć do apki | Paywall zamyka się sam, feed odblokowany — **bez restartu apki** |
| 4 | Przesuń do przodu | Kolejne pytanie z katalogu, **żadnej** ściany dnia |
| 5 | Jeśli byłeś gościem | Pojawia się propozycja zabezpieczenia konta — dopiero **PO** zakupie |
| 6 | Ustawienia | Sekcja subskrypcji zamiast „Zostań PRO" |

### D3 · Anulowanie zakupu w połowie — **P0** 🧑
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Otwórz paywall, tapnij zakup, **anuluj** w arkuszu sklepu | Wraca do paywalla; brak crasha, brak zawieszonego spinnera |
| 2 | Sprawdź status | Nadal FREE, nic nie odblokowane |
| 3 | Spróbuj kupić ponownie | Zakup startuje normalnie |

### D4 · Zakup dożywotni — **P1** 🧑
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Kup plan dożywotni (69,99 zł) | Odblokowanie jak w D2 |
| 2 | Ustawienia → zarządzanie subskrypcją | Status **dożywotni**, bez daty odnowienia; treść nie sugeruje anulowania |

### D5 · Przywracanie zakupów — **P0** 🧑
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Odinstaluj apkę z aktywnym PRO, zainstaluj ponownie, przejdź onboarding | Startuje jako FREE (nowe anonimowe UUID) |
| 2 | Ustawienia → **Przywróć zakupy** | Komunikat o przywróceniu, status zmienia się na PRO |
| 3 | Wariant: zaloguj się na konto, na którym było PRO | PRO wraca razem z kontem, bez ręcznego przywracania |
| 4 | Przywróć zakupy na koncie, które nic nie kupiło | Komunikat „brak poprzednich zakupów" — nie błąd i nie cisza |

### D6 · Zarządzanie subskrypcją — **P1** 🧑
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Ustawienia → zarządzanie subskrypcją | Arkusz z datą odnowienia i informacją, gdzie się anuluje |
| 2 | Tapnij „Zarządzaj w…" | Otwiera ekran subskrypcji **właściwego sklepu** (Play / App Store), nie stronę www |
| 3 | Przeczytaj treść | Jasne, że apka sama nie anuluje subskrypcji |

### D7 · Wygaśnięcie PRO — **P2** ⚙️
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Anuluj subskrypcję sandbox i doczekaj wygaśnięcia (sandbox skraca okresy) | Apka wraca do trybu FREE |
| 2 | Ulubione | Lista **nadal dostępna** do odczytu — zbudowana wcześniej nie znika |
| 3 | Historia | Widać tylko dzisiejsze karty + zablokowany panel starszej historii |

---

## E. Konto: rejestracja, logowanie, wylogowanie

### E1 · Rejestracja e-mailem (upgrade gościa) — **P0** ⚙️
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Jako GOŚĆ zagłosuj kilka razy, zanotuj streak i liczbę głosów | Streak > 0 |
| 2 | Ustawienia → „Zabezpiecz konto" | Ekran auth, zakładka rejestracji |
| 3 | E-mail + hasło + powtórz hasło, zatwierdź | Komunikat o potwierdzeniu e-maila / utworzeniu konta |
| 4 | Otwórz mail i kliknij link potwierdzający | Ląduje na `/email-potwierdzony`, strona czytelna po polsku |
| 5 | Wróć do apki | Konto aktywne, w Ustawieniach e-mail zamiast „sesja gościa" |
| 6 | **Sprawdź streak i historię** | **Identyczne jak w kroku 1** — rejestracja podniosła to samo UUID, nie założyła pustego konta |

### E2 · Walidacja formularza — **P1** 🧑
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Zatwierdź pusty formularz | Błąd „podaj e-mail" |
| 2 | Wpisz `abc` jako e-mail | Błąd „podaj poprawny e-mail" |
| 3 | Za krótkie hasło | Błąd o minimalnej długości |
| 4 | Przy rejestracji różne hasła w obu polach | Błąd „hasła nie są zgodne" |
| 5 | Tapnij ikonę oka przy haśle | Hasło pokazuje się / chowa |

### E3 · Logowanie na istniejące konto — **P0** ⚙️
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Wyloguj się, wejdź w logowanie, podaj poprawne dane | Zalogowanie, powrót do feedu |
| 2 | Sprawdź streak, historię, ulubione, PRO | Wszystko z tego konta, nie z sesji gościa |
| 3 | Wpisz złe hasło | Konkretny komunikat „nieprawidłowe dane", nie ogólny błąd |
| 4 | Zaloguj się na konto z **niepotwierdzonym** mailem | Komunikat „potwierdź e-mail" |
| 5 | Spróbuj 5× pod rząd źle | Komunikat o zbyt wielu próbach, nie crash |

### E4 · Logowanie Google — **P0 (Android)** 🧑
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Ekran auth → „Kontynuuj z Google" | Natywny wybór konta Google |
| 2 | Wybierz konto | Powrót do apki, zalogowany, feed |
| 3 | Anuluj wybór konta (wstecz) | Powrót na ekran auth, bez błędu i bez zawieszonego spinnera |
| 4 | Wyloguj i zaloguj Googlem ponownie | Ten sam stan konta (streak, PRO) |

### E5 · Logowanie Apple — **P0 (iOS)** 🧑
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Ekran auth | Widoczne **oba** przyciski: Apple (pierwszy) i Google |
| 2 | Zaloguj przez Apple z opcją **„Ukryj mój adres"** | Logowanie działa, konto zakładane |
| 3 | Wyloguj i zaloguj Apple ponownie | Trafia na **to samo** konto, nie tworzy nowego |
| 4 | Sprawdź, że Google działa też na iOS | Przycisk aktywny — to jest ścieżka przenoszenia konta z Androida |

### E6 · Przełączenie konta (konflikt tożsamości) — **P1** ⚙️
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Jako gość z postępem spróbuj **zalogować się** na istniejące konto | Ostrzeżenie, że postęp sesji gościa zostanie porzucony, z alternatywą „załóż konto" |
| 2 | Anuluj | Wraca na formularz z **zachowanym** wpisanym e-mailem |
| 3 | Potwierdź przełączenie | Ląduje na docelowym koncie z jego danymi |

### E7 · Wylogowanie — **P0** 🤖🧑
**Pokryte smoke testem** (przejście do widoku gościa) — ręcznie zostaje krok 4: czy sesja naprawdę zniknęła po ubiciu apki.
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Ustawienia → wyloguj | Komunikat „wylogowano", wraca do feedu |
| 2 | Ustawienia | Nagłówek pokazuje sesję gościa + przycisk „Zabezpiecz konto" |
| 3 | Feed | Apka **działa dalej** jako gość — nie ma ekranu logowania blokującego wejście |
| 4 | Ubij apkę i odpal | Nadal wylogowany (sesja naprawdę zniknęła) |

### E8 · Wylogowanie bez sieci — **P2** 🧑
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Tryb samolotowy → Ustawienia → wyloguj | Albo wylogowuje lokalnie, albo czytelny błąd sieci — **nie** wisi w spinnerze |

---

## F. Hasło

### F1 · Reset hasła end-to-end — **P0** 🧑
**Najbardziej kruchy łańcuch w apce: mail → strona www → deep link → apka.**

| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Logowanie → „Nie pamiętasz hasła" → podaj e-mail | Komunikat, że mail został wysłany |
| 2 | Otwórz maila **na telefonie** i kliknij link | Otwiera się `debatly.app/reset-hasla/` — ładuje się natychmiast, po polsku |
| 3 | Obserwuj | Strona przeskakuje do apki (`debatly://reset-password`); system może zapytać „otworzyć w Debatly?" |
| 4 | W apce | Otwiera się arkusz **ustawiania nowego hasła** — nie feed, nie cisza |
| 5 | Wpisz nowe hasło i zatwierdź | Potwierdzenie, jesteś zalogowany |
| 6 | Wyloguj i zaloguj **nowym** hasłem | Działa |
| 7 | Spróbuj **starego** hasła | Nie działa |

### F2 · Reset — link zużyty / z innego telefonu — **P1** 🧑
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Kliknij **ten sam** link po raz drugi | Apka pokazuje komunikat, że link jest nieważny — nie milczy i nie wyrzuca na feed bez słowa |
| 2 | Kliknij link na **innym** telefonie niż ten, który go zamówił | To samo: czytelny komunikat (kod PKCE należy do tamtej instalacji) |

### F3 · Reset otwarty na desktopie — **P1** 🤖
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Otwórz link resetu w przeglądarce na komputerze | Strona `/reset-hasla/` tłumaczy, że trzeba otworzyć na telefonie z apką — nie jest pusta ani 404 |
| 2 | DevTools → Network | Strona **nie ładuje niczego z zewnątrz** (brak bundla Next, fontów, analityki) — jednorazowy kod z URL-a nigdzie nie wycieka |

### F4 · Nowe hasło = stare hasło — **P2** 🧑
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | W arkuszu nowego hasła wpisz dotychczasowe hasło | Czytelny komunikat „to samo hasło", nie ogólny błąd |

---

## G. Usuwanie konta

### G1 · Usunięcie konta z kontem e-mail — **P0** ⚙️
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Ustawienia → na sam dół → „Usuń konto" | Dialog potwierdzenia z jasnym opisem konsekwencji |
| 2 | Anuluj | Nic się nie dzieje |
| 3 | Potwierdź | Komunikat o usunięciu; apka wraca do świeżej sesji |
| 4 | Spróbuj zalogować się na usunięte konto | Nie da się |
| 5 | Sprawdź w Supabase (`auth.users`, głosy, profil) | Rekordy usera zniknęły |

### G2 · Usunięcie konta jako GOŚĆ — **P0** 🧑
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Jako gość (bez konta) zagłosuj kilka razy | Streak > 0 |
| 2 | Ustawienia → na sam dół | Wiersz **„Usuń konto" JEST widoczny** także dla gościa (wymóg App Review 5.1.1(v) i Play) |
| 3 | Potwierdź usunięcie | Głosy, streak i profil znikają, apka startuje od nowa |

---

## H. Funkcje PRO

### H1 · Swipe po katalogu — **P0** 🧑 (PRO)
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Przesuwaj do przodu przez ~10 pytań | Płynnie, bez zacięć, bez pustych kart, bez powtórek pod rząd |
| 2 | Przesuń wstecz | Wraca do poprzednich z zapamiętanym stanem (zagłosowane pokazują słupki) |
| 3 | Dojedź do końca decka | Sensowny stan końcowy — nie pusty ekran i nie wieczny spinner |

### H2 · Ulubione — **P1** 🧑
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Jako FREE tapnij gwiazdkę na pytaniu | Otwiera się paywall |
| 2 | Jako PRO tapnij gwiazdkę | Gwiazdka zapala się, haptyk |
| 3 | Ustawienia → Ulubione | Pytanie na liście, licznik się zgadza |
| 4 | Odznacz gwiazdkę | Znika z listy |
| 5 | Ubij apkę, sprawdź ponownie | Stan ulubionych przetrwał |

### H3 · Historia głosów — **P0** 🧑
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Jako FREE otwórz historię | Ekran się otwiera (nie jest zablokowany): **dzisiejsza** karta + zablokowany panel starszej historii |
| 2 | Tapnij zablokowany panel | Otwiera się paywall |
| 3 | Jako PRO otwórz historię | Pełna historia pogrupowana po dniach, dwie karty w rzędzie |
| 4 | Przewiń daleko w dół | Pojawia się przyklejony **X** w miejscu tego z nagłówka — zamknięcie zawsze jednym tapnięciem |
| 5 | Użyj wyszukiwarki | Filtruje karty po treści pytania |
| 6 | Otwórz kartę z historii | Pokazuje pytanie ze splitem i Twoim głosem |

### H4 · Pobieranie offline — **P1** 🧑 (PRO)
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Ustawienia → wiersz pobierania offline | Podtytuł: gotowe / data ostatniego pobrania |
| 2 | Tapnij | Spinner + licznik postępu (zrobione/wszystkie), rośnie |
| 3 | Poczekaj do końca | Zielony ptaszek + data |
| 4 | Tryb samolotowy → przeglądaj pytania | Pytania i smaczki otwierają się z cache'a |
| 5 | Przerwij pobieranie w połowie (wyjdź z ekranu) | Brak crasha; ponowne wejście pokazuje sensowny stan |

### H5 · Profil debaty — **P1** ⚙️
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Na koncie z <6 głosami otwórz panel konformizmu | Profil zablokowany, pasek postępu pokazuje **oba** liczniki (głosy i bramki), ten dalszy w tyle |
| 2 | Dobij do 6 głosów **i** 6 kwalifikujących się bramek | Profil odblokowuje się jako „profil wstępny" |
| 3 | Siatka 2×2 | Jeden z: FILAR / PŁYNIE Z PRĄDEM / SAMOTNY WILK / POSZUKIWACZ — nazwa brzmi neutralnie, nie jak kara |
| 4 | Jako FREE | Widoczne: typ, oba procenty, szczebel osi, karta do udostępnienia. Zablokowane wiersze mają **widoczne liczniki**, nie puste |
| 5 | Tapnij zablokowany wiersz | Paywall z nagłówkiem portretowym („{n} głosów. Zobacz, co mówią o Tobie.") |
| 6 | Jako PRO | Trend, rzadkość typu, „zdania, które Cię przewróciły", najbardziej samotny głos |
| 7 | Dobij do 12 głosów | Profil przechodzi na pełny |

### H6 · Zbyt szybka odpowiedź w bramce — **P2** ⚙️
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Zagłosuj i **od razu** (<1,5 s od otwarcia bramki) tapnij „TRZYMAM SIĘ" | Głos i wynik działają normalnie, ale ta bramka **nie** liczy się do odporności w profilu |
| 2 | Przeczytaj kontrę normalnie (>1,5 s) i odpowiedz | Licznik bramek w profilu podbija się |

---

## I. Streak, ranga, udostępnianie

### I1 · Streak — **P0** ⚙️
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Zagłosuj pierwszy raz danego dnia | Chip streaka w górnym pasku podbija się o 1 |
| 2 | Zagłosuj drugi raz tego samego dnia (PRO, inne pytanie) | Streak **się nie zmienia** (max raz na dobę UTC) |
| 3 | Przeskocz dzień bez głosowania | Streak nie rośnie; po 3 dniach przerwy ranga spada o jeden szczebel |

### I2 · Awans rangi — **P1** ⚙️
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Dobij głosami do progu awansu | Celebracja awansu (arkusz + konfetti), raz |
| 2 | Zamknij ją | Wraca do feedu; przy tym samym awansie nie pokazuje się drugi raz |
| 3 | Ustawienia → karta rangi | Nowa ranga i postęp do kolejnej |

### I3 · Karta do udostępnienia (pytanie) — **P0** 🧑
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Po zagłosowaniu tapnij udostępnianie | Generuje się grafika z pytaniem i splitem — czytelna, nic nie ucięte |
| 2 | Systemowy share sheet | Otwiera się; wyślij obrazek do siebie (np. Messenger/Telegram) |
| 3 | Obejrzyj wysłany obrazek | Ostry, poprawne polskie znaki, logo i link widoczne |
| 4 | Powtórz w trybie jasnym i ciemnym | Obie wersje czytelne |

### I4 · Karta rangi / profilu — **P1** 🧑
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Udostępnij kartę rangi z Ustawień | Grafika generuje się i wychodzi na share sheet |
| 2 | Udostępnij kartę profilu debaty | To samo; typ i procenty poprawne |

### I5 · Prośba o ocenę — **P2** 🧑
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Na świeżej instalce zagłosuj 3 razy | Po 3. głosie pojawia się natywny arkusz oceny |
| 2 | Zamknij go i głosuj dalej tego samego dnia | **Nie** pojawia się drugi raz tego dnia |
| 3 | Dobij do 7. głosu (kolejnego dnia) | Prośba pojawia się jeszcze raz |
| 4 | Jeśli tego dnia wypada awans rangi | Prośba wchodzi **po** celebracji awansu, nie na niej |

---

## J. Powiadomienia

### J1 · Dostarczenie przypomnienia — **P0** 🧑
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Ustawienia → ustaw przypomnienie za ~3 minuty | Godzina zapisana i widoczna |
| 2 | Ubij apkę z listy zadań | — |
| 3 | Poczekaj do ustawionej godziny | Powiadomienie **przychodzi** mimo ubitej apki, z sensowną polską treścią |
| 4 | Tapnij powiadomienie | Otwiera apkę na pytaniu dnia |

### J2 · Wyłączenie przypomnień — **P0** 🧑
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Wyłącz przełącznik, ustaw godzinę za 2 min, ubij apkę | Powiadomienie **nie** przychodzi |

### J3 · Treść po zagłosowaniu — **P2** 🧑
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Zagłosuj dziś, ustaw przypomnienie za 3 min, ubij apkę | Treść nie brzmi jak „zagłosuj dziś" — uwzględnia, że już zagłosowałeś |

### J4 · Przypomnienie po zmianie języka — **P2** 🧑
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Przełącz apkę na angielski, ustaw przypomnienie za 2 min, ubij apkę | Powiadomienie przychodzi **po angielsku** |

---

## K. Ustawienia i wygląd

### K1 · Zmiana języka — **P0** 🧑
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Ustawienia → język → angielski | Cały interfejs przełącza się natychmiast, bez restartu |
| 2 | Przejdź przez feed, paywall, historię, profil, ustawienia | **Nigdzie** nie zostało polskiego tekstu (i odwrotnie po powrocie na PL) |
| 3 | Treść pytań i smaczków | Też po angielsku |
| 4 | Ubij apkę i odpal | Język zapamiętany |

### K2 · Motyw jasny / ciemny / systemowy — **P0** 🧑
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Przełącz na jasny | Wszystkie ekrany czytelne, brak białego tekstu na białym tle |
| 2 | Przełącz na ciemny | To samo w drugą stronę |
| 3 | Ustaw „systemowy" i zmień motyw w systemie | Apka podąża za systemem |
| 4 | Sprawdź w obu motywach paywall, bramkę kontry i karty share | Poprawne kolory, w tym paski systemowe u góry i dołu |

### K3 · Zaproponuj pytanie — **P1** ⚙️
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Ustawienia → karta „zaproponuj pytanie" | Otwiera się arkusz |
| 2 | Wyślij propozycję | Potwierdzenie wysłania |
| 3 | Sprawdź `question_suggestions` w Supabase | Rekord z `kind = question` istnieje |
| 4 | Wyślij pustą / za długą treść | Walidacja blokuje, komunikat czytelny |

### K4 · Prywatność i dane — **P1** 🧑
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Ustawienia → Prywatność i dane | Sekcja dokumentów + sekcja „jakie dane zbieramy" |
| 2 | Polityka prywatności | Otwiera `debatly.app/privacy`, strona się ładuje |
| 3 | Regulamin | Otwiera `/terms` |
| 4 | Link usunięcia konta | Otwiera `/delete-account` |

### K5 · Sekcja DEV niewidoczna dla usera — **P0** 🧑
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Build release, zalogowany na e-mail **spoza** listy testerów | W Ustawieniach **nie ma** sekcji „DEV" |
| 2 | Zaloguj na e-mail testera | Sekcja DEV się pojawia |

### K6 · Wersja aplikacji — **P0** 🧑
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Ustawienia → na samym dole | Numer wersji i build zgadza się z tym, co wypuściłeś |

---

## L. Sieć, błędy, przypadki brzegowe

### L1 · Brak internetu przy starcie — **P0** 🧑
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Tryb samolotowy → ubij apkę → odpal | Czytelny stan błędu / baner offline z ponowieniem — **nie** biały ekran i nie wieczny spinner |
| 2 | **Krytyczne:** obejrzyj pytania | Apka **nigdy** nie pokazuje danych mockowych w buildzie z kluczami (wymyślone pytania, zmyślony split) |
| 3 | Wyłącz samolotowy i tapnij ponowienie | Ładuje realne dane; sesja i streak **te same** co przedtem |

### L2 · Utrata sieci w trakcie głosowania — **P1** 🧑
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Włącz samolotowy, zagłosuj | Komunikat o braku połączenia, brak crasha |
| 2 | Wyłącz samolotowy, zagłosuj ponownie | Głos wchodzi normalnie |

### L3 · Wolny backend — **P2** 🧑
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Na słabym łączu (3G / throttling) zagłosuj | Jeśli smaczek nie przyjdzie w ~2,5 s: **od razu słupki**, bez czekania |

### L4 · Małe ekrany, duża czcionka, tablet — **P2** 🧑
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Najmniejszy dostępny telefon | Długie pytanie mieści się bez ucięcia i bez scrolla w kaflu |
| 2 | Tablet (jeśli wspierany) | Treść jest powiększona, nie rozciągnięta na całą szerokość |
| 3 | Maksymalny rozmiar czcionki w systemie | Nic się nie nakłada, przyciski nadal klikalne |

---

## M. Regresje krytyczne (rzeczy, które już raz zepsuły produkcję)

### M1 · Anonimowe UUID przeżywa nieudany start — **P0** ⚙️
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Zbuduj postęp jako gość, zanotuj streak | — |
| 2 | Tryb samolotowy → ubij apkę → odpal → poczekaj na ekran błędu | Ekran błędu z ponowieniem |
| 3 | Włącz sieć i tapnij **ponów** | Ten sam user: streak i głosy na miejscu — **nie** świeże, puste konto |

### M2 · Zero trybu mock w buildzie produkcyjnym — **P0** ⚙️
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Przejrzyj pytania w buildzie release | Zgadzają się z katalogiem w Supabase |
| 2 | Zagłosuj i sprawdź wiersz w bazie | Głos zapisany — nie zniknął w próżni |

### M3 · Zdarzenia analityczne lecą — **P1** 🤖
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Przejdź: onboarding → głos → ściana → paywall → zamknięcie | — |
| 2 | Sprawdź `app_events` w Supabase | Widać m.in. `daily_vote_cast`, `wall_reached`, `paywall_shown`, `paywall_dismissed`, `smaczek_challenge` z sensownymi properties |

### M4 · Sentry łapie błędy — **P1** ⚙️
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Po sesji testowej sprawdź dashboard Sentry | Nowe eventy z **tej** wersji; ścieżki plików czytelne (symbole wgrane) |
| 2 | Porównaj z poprzednią wersją | Zero nowych typów crashy |

### M5 · Deep link nigdy nie ląduje na 404 — **P0** 🤖
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Otwórz `https://debatly.app/reset-hasla/` | Strona **istnieje** (200), nie 404 — 404 spala jednorazowy kod i zamyka konto właściciela |
| 2 | Otwórz `https://debatly.app/email-potwierdzony/` | Strona istnieje i jest po polsku |

---

## N. Strony webowe (gdy release obejmuje landing)

### N1 · Landing EN i PL — **P1** 🤖
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | Otwórz `debatly.app` i `debatly.app/pl/` na telefonie | Obie ładują się, treść w odpowiednim języku |
| 2 | Przyciski sklepów | Prowadzą do właściwych kart App Store / Google Play |
| 3 | Przełącznik języka | Działa i prowadzi na drugą wersję |

### N2 · Strony podpięte pod apkę — **P1** 🤖
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | `/privacy`, `/terms`, `/delete-account`, `/contact` | Wszystkie się otwierają, brak `[TODO: …]` w treści |

### N3 · Strona resetu hasła — **P0** 🤖
| # | Krok | Oczekiwany efekt |
|---|---|---|
| 1 | `/reset-hasla/` na telefonie | Próbuje otworzyć apkę; na desktopie tłumaczy się słowami |
| 2 | Podgląd źródła strony | Zero skryptów zewnętrznych, zero fontów z CDN, `noindex` |

---

## Szybka ścieżka „smoke" (~20 minut)

Gdy release jest mały i chcesz jednego przebiegu:

`A5` → `A2` → `B1` → `B2` → `C1` → `C2` → `E3` → `E7` → `F1` → `D5` →
`H3` → `K1` → `K2` → `J1` → `M5`

Jeśli którykolwiek padnie — **nie wypuszczaj**.

---

## Co mogę zautomatyzować / zrobić za Ciebie

Podział jest szczery: co wymaga prawdziwego sklepu, prawdziwej skrzynki albo
systemowego dialogu, zostaje przy Tobie.

### 🤖 Robię sam — wystarczy, że napiszesz zdanie

| Co | Czym | Które testy zdejmuje |
|---|---|---|
| Bramki jakości kodu | `dart format .`, `flutter analyze --fatal-infos --fatal-warnings`, `flutter test` | Wszystkie regresje logiki (68 plików testów) |
| Smoke integracyjny (5 przebiegów) | `flutter test integration_test/app_smoke_test.dart -d <device>` | `A2`, `B1`, `B3`, `B5`, `C1`, `C2`, `C3`, `E7` — reguły ściany dnia i paywalla, blokada panelu smaczków, bramka kontry, wylogowanie |
| Parytet tłumaczeń | Porównanie kluczy `app_en.arb` ↔ `app_pl.arb` + szukanie hardkodowanych stringów w widgetach | Dużą część `K1` (zostaje Ci przegląd wizualny) |
| Weryfikacja danych po Twojej sesji | Supabase MCP: `app_events`, wiersze głosów, `question_suggestions`, `get_debate_profile` | `M3` + weryfikacje w `B1`, `B2`, `K3`, `G1` |
| Reguła „głos jest ostateczny" po stronie serwera | Dwa wywołania `cast_daily_vote` przez SQL i porównanie zwróconego `my_choice` | `B2` (warstwa backendu) |
| Wszystkie testy stron www | Przeglądarka: 200/404, treść, `noindex`, brak zewnętrznych requestów, hreflang, sitemapa | `N1`, `N2`, `N3`, `F3`, `M5` |
| Zdrowie backendu | Supabase MCP `get_advisors` (RLS, indeksy), przegląd logów | Profilaktyka przed `M2` |

### ⚙️ Mogę przygotować albo dopisać — klikasz Ty

| Co mogę zrobić | Co zostaje Tobie |
|---|---|
| Dorzucić do smoke testu kolejne ścieżki (np. ekran historii, zmiana języka, ulubione) — dzisiejsze pięć przebiegów pokrywa `A2`, `B1`, `B3`, `B5`, `C1`–`C3`, `E7` | Uruchomienie na fizycznym telefonie (`-d <device-id>`) i ocena wyglądu — test sprawdza zachowanie, nie estetykę |
| Dopisać golden testy motywu jasnego/ciemnego dla kart share, paywalla i bramki kontry | Wizualna ocena na realnym ekranie (`K2`, `I3`) |
| Ustawić konto testowe w stan „5 głosów, 5 bramek" przez SQL, żebyś nie klikał 6 razy | Odblokowanie profilu i ocena treści (`H5`) |
| Wyzerować streak, głosy albo status potwierdzenia maila w bazie przed testem | Sam test na telefonie |
| Dodać workflow CI z emulatorem Androida pod smoke test | Decyzja, czy chcesz płacić za emulator w CI |

### 🧑 Tylko Ty — tego nie da się sensownie zautomatyzować

- **Wszystko wokół sklepu** (`D2`–`D7`): sandbox Apple/Google, natywne arkusze
  zakupu, przywracanie po reinstalacji, zarządzanie subskrypcją.
- **Logowanie społecznościowe** (`E4`, `E5`) — natywne dialogi Google/Apple.
- **Cały łańcuch resetu hasła z maila** (`F1`, `F2`) — mail na telefonie
  i przejęcie deep linku przez OS.
- **Dostarczanie powiadomień** (`J1`–`J4`) — trzeba poczekać na system przy
  ubitej apce.
- **Systemowe dialogi uprawnień** (`A3`, `A4`).
- **Share sheet i wygląd wygenerowanej grafiki** (`I3`, `I4`).
- **Aktualizacja „na wierzch" i reinstalacja** (`A5`, `D5`, `M1`) — to test
  prawdziwego urządzenia z prawdziwym stanem.
- **Haptyka, płynność animacji, czytelność w słońcu** — subiektywne, wymaga oka.

### Jak mnie wywołać

- „przelec bramki jakości i smoke integracyjny" → wiersze 1–2 z tabeli 🤖 (zdejmuje 8 pozycji z listy)
- „sprawdź strony www z checklisty" → `N1`–`N3`, `F3`, `M5`
- „zweryfikuj w bazie, co zapisała moja sesja testowa" → `M3` + weryfikacje danych
- „ustaw mi konto X na 5 głosów i 5 bramek" → przygotowanie pod `H5`
- „dopisz do integration testu ścianę dnia i reguły paywalla" → rozszerzenie ⚙️

---

## Raport z przebiegu

Kopiuj przy każdym releasie:

```
Wersja:            x.y.z (build N)
Platforma:         Android <model, wersja OS> / iOS <model, wersja>
Data:
Zakres:            P0 / P0+P1 / pełny
Wynik:             PASS / FAIL
Niezdane testy:    <ID + opis>
Uwagi:
```
