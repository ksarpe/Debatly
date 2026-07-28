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

- smaczki zawsze przenumerowane 1..N (puste pomijane, pozycja 1 = darmowy teaser),
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

## Historia

Każda zatwierdzona zmiana trafia do `admin_audit_log` ze stanem przed i po —
widać ją na dole ekranu edycji pytania.
