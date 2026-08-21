# Debatly — panel treści (lokalny)

Panel do edycji i dodawania pytań oraz smaczków. **Uruchamiany tylko lokalnie** —
nie jest nigdzie wystawiony publicznie.

## Uruchomienie

```bash
cd admin
npm install
npm run dev
```

Otwórz http://localhost:3200 i zaloguj się kontem `@debatly.app`.

## Jak to działa (i dlaczego jest bezpieczne)

Panel **nie ma żadnych uprawnień do tabel** i **nie zawiera klucza `service_role`**.
W `.env.local` jest wyłącznie klucz publiczny (publishable), który sam z siebie nie
daje nic.

Każda zmiana idzie przez funkcję `security definer` w bazie (`admin_*`), która
najpierw sprawdza `admin_require()`. Skutek: nawet gdyby ktoś przejął sesję albo
podmienił kod panelu w przeglądarce, może wykonać **wyłącznie te operacje** —
ścieżka „dowolnego zapisu do bazy" nie istnieje.

Baza pilnuje też reguł, których interfejs nie obejdzie:

- smaczki zawsze przenumerowane 1..N (puste pomijane),
- każdy smaczek ma stronę (`side`: przeciw TAK / przeciw NIE / neutralny, brak =
  nieotagowany). Aplikacja serwuje najpierw ten, który atakuje głos danego
  użytkownika, i to on jest darmowy — nieotagowany działa jak neutralny.
  Filtr „🎯 smaczki bez strony" na liście to worklista tagowania,
- pytanie zawsze ma wersję PL i EN oraz wiersz w `question_vote_seeds`,
- usunięcie najpierw zwalnia sloty w `daily_questions` (klucz `ON DELETE RESTRICT`).

## Obieg pracy

```
edycja  →  wersja robocza  →  zgłoszenie  →  zatwierdzenie  →  produkcja
          (draft)            (pending)      (approver)
```

**Ochrona przed konfliktami.** Wersja robocza zapamiętuje hash treści z chwili
rozpoczęcia edycji. Przy zatwierdzaniu hash jest liczony ponownie — jeśli ktoś
w międzyczasie zmienił to pytanie, zatwierdzenie zostaje **odrzucone** zamiast
nadpisać cudzą pracę. Trzeba wtedy odświeżyć i nanieść zmiany na aktualną wersję.

## Role

| rola | może |
|---|---|
| `editor` | tworzyć wersje robocze i zgłaszać je |
| `approver` | dodatkowo zatwierdzać i odrzucać |

Konta nadaje się w tabeli `admin_users`. Nowe osoby można dodać z wyprzedzeniem
przez `admin_invites` (po e-mailu) — uprawnienie aktywuje się samo przy pierwszym
logowaniu, pod warunkiem **potwierdzonego adresu e-mail**.

## Flaga „EN do weryfikacji"

Edytorzy mogą poprawiać polski tekst bez ruszania angielskiego — wtedy pytanie
dostaje flagę **EN do weryfikacji**:

- przy zatwierdzaniu zmiany baza sama wykrywa edycję „tylko PL" (pytanie lub
  smaczki) i ustawia flagę; edycja angielskiego zdejmuje ją automatycznie,
- checkbox w edytorze zaznacza się sam i pozwala ręcznie nadpisać decyzję
  (np. literówka w PL, która nie zmienia sensu — można odznaczyć),
- flagę można też przełączyć od razu, bez wersji roboczej (przycisk pod
  polami PL/EN); **zdjąć flagę może tylko `approver`** — zdjęcie = „tłumaczenie
  zweryfikowane",
- lista pytań ma filtr „🇬🇧 EN do weryfikacji" i czerwoną odznakę przy
  oflagowanych pytaniach; oba przełączenia widać też w historii zmian.

Flaga żyje poza hashem treści, więc jej przełączanie nie unieważnia otwartych
wersji roboczych.

## Hurtowo (zakładka „Hurtowo”, `/bulk`)

Ta sama edycja co pojedyncza, tylko dziesięć pytań naraz — zamiast wyklikiwać
JSON pytanie po pytaniu:

1. **Wybierz** pytania (te same filtry co na liście — np. „🎯 smaczki bez
   strony” to gotowa worklista tagowania). Zaznaczenie przeżywa zmianę strony.
2. **Kopiuj JSON** — panel dociąga pełne snapshoty i wrzuca do schowka paczkę
   `{"questions":[{"id","category","pl","en","smaczki":[{"position","pl","en","side"}]}]}`,
   opcjonalnie z instrukcją formatu dla agenta.
3. **Wklej odpowiedź** agenta. Płot ```` ```json ```` i tekst dookoła są
   obcinane. Dopasowanie po `id`.
4. **Podgląd** — dla każdej pozycji różnica przed/po, ostrzeżenia o limitach,
   odznaki „bez zmian” / „nowe” / „zablokowane”. Odznaczasz, czego nie chcesz,
   i publikujesz całość jednym przyciskiem.

**Scalanie smaczków.** Pola nieobecne w JSON-ie zostają bez zmian, więc
`"smaczki":[{"position":1,"side":"attacks_no"}]` otaguje pierwszy wiersz i nie
ruszy pozostałych. Jeśli **każdy** wiersz ma numer (`position`/`n`/`id`), patch
jest punktowy; jeśli choć jeden go nie ma — JSON jest całą listą i wiersze poza
jego długością znikają. Kasowanie: `{"position":3,"delete":true}`. Pozycja bez
`id` = nowe pytanie. Te same reguły obsługuje przycisk „📥 Wklej” w edytorze
pojedynczego pytania (wspólny kod: `lib/bulk.js`).

**Zapis nie ma skrótu.** Każde pytanie dostaje własny draft
(`admin_save_draft` → `admin_submit_draft` → `admin_approve_draft`) na
snapshotcie pobranym tuż przed zapisem, więc ochrona przed konfliktami, audyt
i automat „EN do weryfikacji” działają jak przy pojedynczej edycji. `editor`
zgłasza całą paczkę do zatwierdzenia, `approver` publikuje. Błąd na jednym
pytaniu nie przerywa reszty — wiersz zostaje na czerwono z komunikatem i można
go ponowić.

## Historia

Każda zatwierdzona zmiana trafia do `admin_audit_log` ze stanem przed i po —
widać ją na dole ekranu edycji pytania.
