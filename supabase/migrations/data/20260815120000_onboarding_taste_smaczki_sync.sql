-- ============================================================================
-- 2026-08-15 — sync the two onboarding taste questions' smaczki with the new
-- copy shipped in the app's onboarding (app_pl.arb / app_en.arb, first 3 of
-- the 4 onboarding lines — the catalog keeps exactly 3 smaczki per question).
--
-- Questions touched:
--   8b54aec1  "Czy osoby otyłe powinny płacić za dwa miejsca w samolocie?"
--   ad75972d  "Czy powinieneś mówić nowemu partnerowi, z iloma osobami spałeś?"
--
-- Pre-edit rows are snapshotted in
-- backups/20260815120000_onboarding_taste_smaczki_sync.backup.json.
--
-- Updates target smaczek ids directly and are guarded by the current prod
-- text, so a repeated apply is a no-op and a drifted row is left untouched.
-- ============================================================================
begin;

-- 8b54aec1 — otyłość / dwa miejsca w samolocie
update question_smaczki_translations
   set text = 'Za kilka kilogramów walizki musisz przecież dopłacić.'
 where smaczek_id = '8fb13235-587f-4743-9949-9982110c1c8f' and locale = 'pl'
   and text = 'Dopłaciłbyś do szerszych foteli dla wszystkich?';

update question_smaczki_translations
   set text = 'You already pay extra for a few kilos of luggage.'
 where smaczek_id = '8fb13235-587f-4743-9949-9982110c1c8f' and locale = 'en'
   and text = 'Would you chip in for wider seats for everyone?';

update question_smaczki_translations
   set text = 'Co z komfortem osoby obok? Zapłaciła tyle samo, a ma ciaśniej.'
 where smaczek_id = '04099a4b-6c1f-43c0-9ba4-b724f53639ee' and locale = 'pl'
   and text = 'Twoja walizka waży mniej, a płacisz za nią osobno';

update question_smaczki_translations
   set text = 'What about the person squeezed next to you? Same fare, worse seat.'
 where smaczek_id = '04099a4b-6c1f-43c0-9ba4-b724f53639ee' and locale = 'en'
   and text = 'Your suitcase weighs less and you pay for it separately';

update question_smaczki_translations
   set text = 'Jak chcesz to weryfikować? Bramka przed wejściem do samolotu?'
 where smaczek_id = '8b683146-d982-4b84-adba-2243be536e26' and locale = 'pl'
   and text = 'Nie chodzi o wagę, tylko o to, kto siedzi obok ciebie';

update question_smaczki_translations
   set text = 'And how would you check who pays? A gate scale before boarding?'
 where smaczek_id = '8b683146-d982-4b84-adba-2243be536e26' and locale = 'en'
   and text = 'This is not about weight, it is about who sits next to you';

-- ad75972d — liczba partnerów
update question_smaczki_translations
   set text = 'Kłótni nie będzie tylko wtedy, gdy wasze liczby są podobne.'
 where smaczek_id = 'af1ca4fa-5ebc-46df-a43a-57a8931d2bda' and locale = 'pl'
   and text = 'Powiesz liczbę i on zacznie liczyć, kto to był';

update question_smaczki_translations
   set text = 'There''s no argument only if your numbers happen to match.'
 where smaczek_id = 'af1ca4fa-5ebc-46df-a43a-57a8931d2bda' and locale = 'en'
   and text = 'Give the number and they''ll start counting who they were';

update question_smaczki_translations
   set text = 'Nie będzie cię to gryzło, gdy już się dowiesz? A partnera?'
 where smaczek_id = '5236a623-f996-42c3-a577-d95f0072a158' and locale = 'pl'
   and text = 'Zapytasz go o jego liczbę? I co z nią zrobisz?';

update question_smaczki_translations
   set text = 'Once you know, will it stop bugging you? Will it stop bugging them?'
 where smaczek_id = '5236a623-f996-42c3-a577-d95f0072a158' and locale = 'en'
   and text = 'Will you ask for their number? And then what?';

update question_smaczki_translations
   set text = 'Jeśli to nie jest setka — co to właściwie zmienia?'
 where smaczek_id = 'fec4f12b-e640-4c89-bca7-307ada96f6d6' and locale = 'pl'
   and text = 'Zapytałbyś, gdybyś wiedział, że odpowiedź zaboli?';

update question_smaczki_translations
   set text = 'If the number isn''t 100, what does it actually change?'
 where smaczek_id = 'fec4f12b-e640-4c89-bca7-307ada96f6d6' and locale = 'en'
   and text = 'Would you ask if you knew the answer would hurt?';

commit;
