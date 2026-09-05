# Szablony maili auth

> **Te pliki są FALLBACKIEM.** Maile wysyła edge function
> [`send-auth-email`](../functions/send-auth-email/index.ts) przez Send Email Hook —
> to ona wybiera język użytkownika i renderuje treść. Szablony poniżej działają
> tylko wtedy, gdy hook jest wyłączony w dashboardzie. Edytując treść maili,
> edytuj [`emails.ts`](../functions/send-auth-email/emails.ts).

Kopie robocze szablonów wklejanych ręcznie w **Supabase Dashboard → Authentication
→ Emails**. Dashboard jest źródłem prawdy — te pliki są po to, żeby zmiany były
w gicie i żeby dało się je zdiffować, tak jak `supabase/migrations/`.

Reguła „no hard-coded UI text" z [CLAUDE.md](../../CLAUDE.md) tu **nie obowiązuje** —
maile renderuje GoTrue po stronie serwera, nie Flutter, więc ARB-y ich nie widzą.

## Które szablony są używane

| Szablon | Plik | Co go wywołuje |
|---|---|---|
| Reset password | [reset-password.html](reset-password.html) | `resetPasswordForEmail()` — [supabase_service.dart](../../lib/services/supabase_service.dart), link „Nie pamiętasz hasła?" pod legacy formularzem |
| Confirm sign up | [confirm-signup.html](confirm-signup.html) | **Tylko stare buildy (< 2.4).** Apka od 2026-09-05 nie woła `signUp()` — arkusz logowania jest social-only |
| Change email address | [change-email.html](change-email.html) | **Tylko stare buildy (< 2.4).** `updateUser(email:)` przy upgrade gościa zniknął razem z rejestracją mailem |
| Magic link | dashboard (bez kopii w repo) | **Panel admina** — `signInWithOtp` w [AuthGate.jsx](../../admin/components/AuthGate.jsx). Dlatego providera Email nie wolno wyłączyć |

**Nieużywane** (nie ma sensu ich ruszać): Invite user, Reauthentication — nikt
nie woła `inviteUserByEmail` ani `reauthenticate`. Google i Apple idą przez
`signInWithIdToken` / `linkIdentityWithIdToken`, czyli bez maila.

Pułapka (historyczna, wciąż żywa dla starych buildów): rejestracja gościa **nie**
wysyłała „Confirm sign up", tylko „Change email address" — bo anonimowy user był
podnoszony w miejscu przez `updateUser`, żeby nie zgubić streaka. Dlatego
`change-email.html` jest napisany neutralnie i musi wyglądać sensownie także
jako pierwszy mail powitalny. Nie kasuj go, dopóki gate `app_update_gate` nie
wymusi 2.4+.

## Tematy wiadomości

Wklej w pole **Subject** nad body:

| Szablon | Subject |
|---|---|
| Confirm sign up | `Potwierdź adres e-mail · Confirm your email` |
| Reset password | `Reset hasła w Debatly · Reset your password` |
| Change email address | `Potwierdź nowy adres e-mail · Confirm your new email` |

## Dwujęzyczność

GoTrue trzyma **jeden szablon na typ maila**, bez lokalizacji, a apka jest PL+EN.
Dlatego te fallbackowe szablony mają treść po polsku plus zwięzły akapit
`English:` pod linią — kompromis na wypadek, gdyby hook był wyłączony.

Właściwe rozwiązanie jest już wdrożone: hook `send-auth-email` czyta język
z `profiles.locale` (z fallbackiem na `user_metadata.locale`) i renderuje mail
w jednym języku. Skąd się tam bierze język — patrz
[funkcja](../functions/send-auth-email/index.ts) i migracja
`20260813130000_profile_locale.sql`.

## Logo

Header ma na razie tekstowy lockup `Debatly.` (pomarańczowa kropka = `spark`
`#F97316` z [app_theme.dart](../../lib/core/theme/app_theme.dart)). Żeby wstawić
`assets/images/logo.png`, wrzuć go do publicznego bucketa w Supabase Storage
i podmień `<span>` na zakomentowany w pliku `<img>`. Nie osadzaj base64 —
Gmail wycina `data:` w obrazkach.

## Zasady, których trzymają się te pliki

Klienty pocztowe to nie przeglądarki, więc:

- layout na `<table role="presentation">`, nie na flex/grid,
- style **inline** — Gmail wycina `<style>` z `<head>`, a Supabase i tak wkleja
  tylko body,
- CTA to `<td bgcolor>` z `<a>` w środku, nie `<button>` — w Outlooku (Word
  engine) tło przetrwa, zaokrąglenie nie,
- szerokość 560 px + `max-width:100%`,
- kolory podane jawnie na każdym elemencie, bez `prefers-color-scheme` —
  Gmail i Outlook go nie wspierają, a półśrodek daje gorszy efekt niż wymuszony
  jasny motyw,
- ukryty preheader na starcie — to on ląduje w podglądzie skrzynki obok tematu.

## Test przed wdrożeniem

1. Wklej do dashboardu, **Save changes**.
2. Podgląd zakładką *Preview* — pokazuje render, ale nie podstawia zmiennych.
3. Realny test: zarejestruj konto na własny adres i sprawdź na telefonie
   (Gmail app) oraz w Outlook Web — to dwa najbardziej kapryśne rendery.
