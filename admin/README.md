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

## Historia

Każda zatwierdzona zmiana trafia do `admin_audit_log` ze stanem przed i po —
widać ją na dole ekranu edycji pytania.
