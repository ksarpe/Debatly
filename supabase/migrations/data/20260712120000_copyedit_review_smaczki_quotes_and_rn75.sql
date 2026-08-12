-- ============================================================================
-- Editorial review pass over the 1000-question catalog (2026-07-12).
-- ----------------------------------------------------------------------------
-- Full read of all 1000 questions (PL+EN) + smaczki + a dedicated PL<->EN
-- fidelity pass on every question pair. Findings:
--   * Questions: uniformly faithful. Exactly ONE weak question reframed (rn 75).
--   * One real translation drift in a smaczek: 'anything easily' rendered as
--     "za darmo" (for free) instead of "łatwo" (easily) — fixed.
--   * Systematic pattern in the 3rd ("pod włos") smaczek: the EN quotes an
--     idiom ('X' ...) but the PL dropped the quotation marks, leaving some
--     lines ungrammatical. Unified all of them with standard Polish „..." .
--   * One word-order nit (napiwek).
--
-- Idempotent: every UPDATE matches on the exact OLD text, so re-running is a
-- no-op once applied. No UUIDs needed; PL smaczek strings are unique.
-- Total: 1 question (PL+EN) + 60 smaczki (position 3, locale pl).
-- ============================================================================

begin;

-- ── 1) Question reframe (rn 75) ─────────────────────────────────────────────
update question_translations set question_text =
  'Czy pomścić się na kimś, kto cię skrzywdził, gdy w końcu masz przewagę?'
  where question_id = '73f9fec9-df59-43cf-a449-e77a5852a6c0' and locale = 'pl'
    and question_text = 'Czy oszczędzić wroga, który jest teraz bezbronny?';
update question_translations set question_text =
  'Would you get back at someone who hurt you, now that you have the upper hand?'
  where question_id = '73f9fec9-df59-43cf-a449-e77a5852a6c0' and locale = 'en'
    and question_text = 'Should you spare an enemy who is now defenseless?';

-- ── 2) Smaczki with word changes (incl. rn 601 translation fix) ─────────────
update question_smaczki_translations set text = '„Czegoś brakuje" mówią ci, którym samym brak'
  where locale='pl' and text = 'Brakuje mówią ci, którym samym brak';
update question_smaczki_translations set text = '„To tylko maszyna" — mówiono już o wielu istotach'
  where locale='pl' and text = 'To tylko maszyna mówiono o wielu istotach';
update question_smaczki_translations set text = '„Czegoś brakuje" mówią ci, którzy mają jej za dużo'
  where locale='pl' and text = 'Brakuje mówią ci, którzy jej mają za dużo';
update question_smaczki_translations set text = '„Cokolwiek" to nie to samo co „cokolwiek łatwo"'
  where locale='pl' and text = 'Cokolwiek to nie to samo co cokolwiek za darmo';

-- ── 3) Word-order nit (rn 353) ──────────────────────────────────────────────
update question_smaczki_translations set text = 'Napiwek z automatu to nie napiwek, to podatek'
  where locale='pl' and text = 'Napiwek zawsze to nie napiwek, to podatek';

-- ── 4) Add Polish „..." quotes to the 3rd-smaczek idiom pattern (55) ────────
update question_smaczki_translations set text = '„Ogół" nigdy nie płaci — płacą wybrani'
  where locale='pl' and text = 'Ogół nigdy nie płaci — płacą wybrani';
update question_smaczki_translations set text = '„Dość" to często przebrana rezygnacja'
  where locale='pl' and text = 'Dość to często przebrana rezygnacja';
update question_smaczki_translations set text = '„Musiałem" to najstarsza wymówka'
  where locale='pl' and text = 'Musiałem to najstarsza wymówka';
update question_smaczki_translations set text = '„Odwaga" cudzymi oszczędnościami jest łatwa'
  where locale='pl' and text = 'Odwaga cudzymi oszczędnościami jest łatwa';
update question_smaczki_translations set text = '„Później" to najdroższe słowo w życiorysie'
  where locale='pl' and text = 'Później to najdroższe słowo w życiorysie';
update question_smaczki_translations set text = '„Nic do ukrycia" — do pierwszego wycieku'
  where locale='pl' and text = 'Nic do ukrycia — do pierwszego wycieku';
update question_smaczki_translations set text = '„Wystarczająco dobry" — dla kogo?'
  where locale='pl' and text = 'Wystarczająco dobry — dla kogo?';
update question_smaczki_translations set text = '„Obraźliwe" często znaczy „niewygodne"'
  where locale='pl' and text = 'Obraźliwe często znaczy niewygodne';
update question_smaczki_translations set text = '„Wybór" pracy po nocach bywa przymusem'
  where locale='pl' and text = 'Wybór pracy po nocach bywa przymusem';
update question_smaczki_translations set text = '„Naturalna" hodowla to też fabryka'
  where locale='pl' and text = 'Naturalna hodowla to też fabryka';
update question_smaczki_translations set text = '„Cheat" to słowo złodzieja'
  where locale='pl' and text = 'Cheat to słowo złodzieja';
update question_smaczki_translations set text = '„Zwyczajne" to alibi dla strachu'
  where locale='pl' and text = 'Zwyczajne to alibi dla strachu';
update question_smaczki_translations set text = '„Mój talerz nic nie zmieni" — mówią miliardy'
  where locale='pl' and text = 'Mój talerz nic nie zmieni — mówią miliardy';
update question_smaczki_translations set text = '„Usuń" to guzik, nie obietnica'
  where locale='pl' and text = 'Usuń to guzik, nie obietnica';
update question_smaczki_translations set text = '„Zajęty" to często ucieczka od siebie'
  where locale='pl' and text = 'Zajęty to często ucieczka od siebie';
update question_smaczki_translations set text = 'Wkrótce „mam to na wideo" nic nie znaczy'
  where locale='pl' and text = 'Wkrótce mam to na wideo nic nie znaczy';
update question_smaczki_translations set text = '„Tak samo" czasem znaczy ślepo na różnice'
  where locale='pl' and text = 'Tak samo czasem znaczy ślepo na różnice';
update question_smaczki_translations set text = '„Nudne" mówią ci, którzy nie zaznali spokoju'
  where locale='pl' and text = 'Nudne mówią ci, którzy nie zaznali spokoju';
update question_smaczki_translations set text = '„Ja albo on" to już kontrola'
  where locale='pl' and text = 'Ja albo on to już kontrola';
update question_smaczki_translations set text = '„Otwarty" często znaczy, że jedno tego chciało'
  where locale='pl' and text = 'Otwarty często znaczy, że jedno tego chciało';
update question_smaczki_translations set text = '„Nieważne" mówisz, aż nikt nie zadzwoni'
  where locale='pl' and text = 'Nieważne mówisz, aż nikt nie zadzwoni';
update question_smaczki_translations set text = '„Tak mam" znaczy: twój czas mniej wart'
  where locale='pl' and text = 'Tak mam znaczy: twój czas mniej wart';
update question_smaczki_translations set text = '„Zmęczony" brzmi lepiej niż „nie chcę"'
  where locale='pl' and text = 'Zmęczony brzmi lepiej niż nie chcę';
update question_smaczki_translations set text = '„Wszyscy tak robią" to alibi tłumu'
  where locale='pl' and text = 'Wszyscy tak robią to alibi tłumu';
update question_smaczki_translations set text = '„Ta jedyna" to wymówka, by przestać próbować'
  where locale='pl' and text = 'Ta jedyna to wymówka, by przestać próbować';
update question_smaczki_translations set text = '„Natura" to często wygodna wymówka'
  where locale='pl' and text = 'Natura to często wygodna wymówka';
update question_smaczki_translations set text = '„Akceptuj mnie" bywa wymówką, by się nie zmieniać'
  where locale='pl' and text = 'Akceptuj mnie bywa wymówką, by się nie zmieniać';
update question_smaczki_translations set text = '„My nie mamy tajemnic" — z cudzej tajemnicy'
  where locale='pl' and text = 'My nie mamy tajemnic — z cudzej tajemnicy';
update question_smaczki_translations set text = '„Dla wszystkich" znaczy zwykle: w naszym muzeum'
  where locale='pl' and text = 'Dla wszystkich znaczy zwykle: w naszym muzeum';
update question_smaczki_translations set text = '„Bezwstyd" mówią ci, którzy bali się prosić'
  where locale='pl' and text = 'Bezwstyd mówią ci, którzy bali się prosić';
update question_smaczki_translations set text = '„Wykonywałem rozkazy" nie uratuje statku'
  where locale='pl' and text = 'Wykonywałem rozkazy nie uratuje statku';
update question_smaczki_translations set text = '„Zdrowszy" dziś, „lepszy" jutro — kto stawia granicę?'
  where locale='pl' and text = 'Zdrowszy dziś, lepszy jutro — kto stawia granicę?';
update question_smaczki_translations set text = '„Kto rano wstaje" to slogan, nie nauka'
  where locale='pl' and text = 'Kto rano wstaje to slogan, nie nauka';
update question_smaczki_translations set text = '„Zawsze tak robiliśmy" to nie argument'
  where locale='pl' and text = 'Zawsze tak robiliśmy to nie argument';
update question_smaczki_translations set text = '„Zmieniłem się" to często reklama przed nawrotem'
  where locale='pl' and text = 'Zmieniłem się to często reklama przed nawrotem';
update question_smaczki_translations set text = '„Dobrowolnie" przy braku innych opcji to fikcja'
  where locale='pl' and text = 'Dobrowolnie przy braku innych opcji to fikcja';
update question_smaczki_translations set text = '„Wybierz szczęście" łatwo mówić z pełnym brzuchem'
  where locale='pl' and text = 'Wybierz szczęście łatwo mówić z pełnym brzuchem';
update question_smaczki_translations set text = '„Sztuka" na cudzej ścianie to cudzy koszt sprzątania'
  where locale='pl' and text = 'Sztuka na cudzej ścianie to cudzy koszt sprzątania';
update question_smaczki_translations set text = '„Wina konsumenta" to ulubiona bajka koncernów'
  where locale='pl' and text = 'Wina konsumenta to ulubiona bajka koncernów';
update question_smaczki_translations set text = '„Każdy tak robi" to alibi każdego układu'
  where locale='pl' and text = 'Każdy tak robi to alibi każdego układu';
update question_smaczki_translations set text = '„Nie naprawisz" znaczy: kup nowe co dwa lata'
  where locale='pl' and text = 'Nie naprawisz znaczy: kup nowe co dwa lata';
update question_smaczki_translations set text = '„Szczera nieuprzejmość" to często zwykłe chamstwo'
  where locale='pl' and text = 'Szczera nieuprzejmość to często zwykłe chamstwo';
update question_smaczki_translations set text = '„Tata też palił" brzmi jak zielone światło'
  where locale='pl' and text = 'Tata też palił brzmi jak zielone światło';
update question_smaczki_translations set text = '„Książka lepsza" mówią ci, co ją czytali'
  where locale='pl' and text = 'Książka lepsza mówią ci, co ją czytali';
update question_smaczki_translations set text = '„Widziane" bez odpowiedzi mówi więcej niż cisza'
  where locale='pl' and text = 'Widziane bez odpowiedzi mówi więcej niż cisza';
update question_smaczki_translations set text = '„Wystarczy" to często wymówka dla lenistwa'
  where locale='pl' and text = 'Wystarczy to często wymówka dla lenistwa';
update question_smaczki_translations set text = '„Nie wiedziałem" ratuje raz, nie zawsze'
  where locale='pl' and text = 'Nie wiedziałem ratuje raz, nie zawsze';
update question_smaczki_translations set text = '„Nic nowego" mówią ci, którzy nic nie tworzą'
  where locale='pl' and text = 'Nic nowego mówią ci, którzy nic nie tworzą';
update question_smaczki_translations set text = '„Nie rozumiem" bywa winą widza, nie dzieła'
  where locale='pl' and text = 'Nie rozumiem bywa winą widza, nie dzieła';
update question_smaczki_translations set text = '„Należy mi się" opróżnia kasę dla naprawdę potrzebujących'
  where locale='pl' and text = 'Należy mi się opróżnia kasę dla naprawdę potrzebujących';
update question_smaczki_translations set text = '„Używane" też bywa wymówką, by kupować więcej'
  where locale='pl' and text = 'Używane też bywa wymówką, by kupować więcej';
update question_smaczki_translations set text = '„Kicz" to często sztuka, której nie lubią krytycy'
  where locale='pl' and text = 'Kicz to często sztuka, której nie lubią krytycy';
update question_smaczki_translations set text = '„Tylko żartowałem" to tarcza tchórza'
  where locale='pl' and text = 'Tylko żartowałem to tarcza tchórza';
update question_smaczki_translations set text = '„Dziękuję" za wszystko znaczy dziękuję za nic'
  where locale='pl' and text = 'Dziękuję za wszystko znaczy dziękuję za nic';
update question_smaczki_translations set text = '„Kochasz tę pracę" to najtańsza podwyżka'
  where locale='pl' and text = 'Kochasz tę pracę to najtańsza podwyżka';

commit;
