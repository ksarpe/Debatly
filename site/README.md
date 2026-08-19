# Strony na debatly.app

> **Te pliki NIE są hostowane z tego repo.** Strona marketingowa `debatly.app`
> stoi osobno — tutaj trzymamy tylko te podstrony, w które celuje aplikacja,
> żeby były w gicie i dało się je zdiffować. Ta sama konwencja co
> [`supabase/templates/`](../supabase/templates/README.md): źródłem prawdy jest
> to, co faktycznie wisi pod adresem, a repo trzyma kopię roboczą.

Zmieniając cokolwiek tutaj, **wgraj to na serwer** — inaczej aplikacja wskazuje
na treść, której nie ma.

## Podstrony

| Katalog | Adres docelowy | Kto na to wskazuje |
|---|---|---|
| [`reset-hasla/`](reset-hasla/index.html) | `https://debatly.app/reset-hasla` | `AppConfig.passwordResetRedirectUrl` → `resetPasswordForEmail(redirectTo:)` |

Inne podstrony, do których aplikacja linkuje, a których nie ma jeszcze w repo:
`/privacy`, `/terms`, `/delete-account`, `/email-potwierdzony`
(patrz `AppConfig`).

## `reset-hasla` — most między mailem a aplikacją

Mail z resetem prowadzi do `/auth/v1/verify` w GoTrue, a ten przekierowuje pod
adres z `redirect_to`. Gdy celował prosto w `debatly://reset-password`, na
telefonie działało znakomicie, a wszędzie indziej było ślepą uliczką:
przeglądarka na laptopie dostaje nieznany schemat i pokazuje błąd protokołu.
Nasza domena nie była wtedy w ogóle odwiedzana, więc żadna strona nie mogła
pomóc.

Teraz przekierowanie ląduje na tej stronie, a ona przerzuca do aplikacji:

- **telefon** — natychmiastowy skok w `debatly://reset-password` z zachowanym
  query stringiem, plus przycisk awaryjny, gdyby automat nie zadziałał;
- **komputer** — wyjaśnienie, że trzeba dokończyć na telefonie, bez próby
  otwierania schematu (to właśnie ta próba dawała okno błędu);
- **wygasły / zużyty link** — GoTrue zwraca `error` w query albo w hashu;
  strona mówi o tym wprost i odsyła po nowy link do aplikacji.

Strona **nie może** dokończyć resetu sama. Flow to PKCE — `code_verifier` leży
w pamięci tej instalacji aplikacji, która o reset poprosiła. Żadna strona ani
inne urządzenie tego nie wymieni.

Język: polski, angielski gdy `navigator.language` nie jest polskie. Reguła
„no hard-coded UI text" z [CLAUDE.md](../CLAUDE.md) tu nie obowiązuje — to nie
Flutter, ARB-y tej strony nie widzą.

**Bezpieczeństwo:** `code` w URL-u to jednorazowe poświadczenie. Strona
przekazuje je wyłącznie do aplikacji, nie ma żadnych zewnętrznych zasobów ani
własnych requestów. Nie dodawaj tu analityki, fontów z CDN ani pikseli.

## Kolejność wdrożenia (ważna)

Aplikacja i strona są sprzężone — wypuszczenie ich w złej kolejności psuje
reset hasła:

1. wgraj `reset-hasla/` pod `https://debatly.app/reset-hasla`;
2. dodaj ten adres w Supabase → Authentication → URL Configuration →
   Redirect URLs;
3. dopiero wtedy wypuszczaj build aplikacji, który tam celuje.

Awaryjnie da się wrócić do starego zachowania bez zmiany kodu:
`--dart-define=PASSWORD_RESET_REDIRECT_URL=debatly://reset-password`
(ten wpis warto zostawić na liście Redirect URLs właśnie po to).
