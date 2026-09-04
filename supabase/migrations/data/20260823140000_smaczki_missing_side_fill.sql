-- 20260823140000_smaczki_missing_side_fill.sql
-- Adds ONE new argument (position 4, PL+EN) to each of the 58 active questions
-- that the 2026-08-23 re-audit (20260823120000_smaczki_side_reaudit.sql) left
-- with every smaczek aimed at the same answer.
--
-- Why they exist: the earlier backfill forced a per-question balance, so each
-- question LOOKED like it served both sides. Once the tags were made honest,
-- 58 questions turned out to argue only one way - a voter on the other side
-- gets no readable row and the gate silently skips. 55 of them sit in the
-- daily_picks calendar, so they WILL be served.
--
-- Each new row's `side` is the side that had no argument, verified against the
-- live gap set before writing (58 proposals / 58 gaps / 0 wrong direction).
-- House limits respected: PL <= 67 chars (max here 62), EN <= 73 (max here 70).
--
-- Existing smaczki are NOT touched - this migration only INSERTs.
-- Revert:
--   delete from question_smaczki_translations t using question_smaczki s
--   where t.smaczek_id = s.id and s.position = 4
--     and s.created_at >= '2026-08-23'::date;
--   delete from question_smaczki
--   where position = 4 and created_at >= '2026-08-23'::date;

begin;

with nowe(question_id, "position", side, pl, en) as (values
  -- Czy anonimowe pomaganie, gdy nikt nie wie o Twoim wsparciu, jest szlachetniejsze niż jawna dobroczynność?
  ('e3d4ac40-3a87-4be6-91bb-0f4450965ff2'::uuid, 4::smallint, 'attacks_no', 'Czy nazwisko wykute na tablicy nie jest już zapłatą?', 'Isn''t a name carved on the donor wall already a payment?'),
  -- Czy ból uczy więcej, niż przyjemność kiedykolwiek nauczy?
  ('b8c39abb-9a72-4888-9ac4-37fbc874dbc8'::uuid, 4::smallint, 'attacks_no', 'Żaden komplement nie zmienił cię tak, jak jedno upokorzenie.', 'No compliment ever changed you the way one humiliation did.'),
  -- Czy dzieci powinny być uczone, by zawsze szanować starszych, bez względu na wszystko?
  ('6629c7c4-5f77-43c6-9026-52a2ab29fb75'::uuid, 4::smallint, 'attacks_no', 'Za czterdzieści lat to ty będziesz tym starszym.', 'In forty years, you are the elder they get to judge.'),
  -- Czy dzieci powinny uczyć się na pamięć faktów, które łatwo wygooglować?
  ('df649239-a030-48d9-83f6-65460ec68911'::uuid, 4::smallint, 'attacks_yes', 'Wkuwanie królów po kolei zniechęciło cię do historii na lata.', 'Cramming lists of kings is what put you off history for years.'),
  -- Czy firmy powinny móc prosić stażystów o darmową pracę?
  ('218164b4-d1a4-44c2-a731-3d6df2d9701d'::uuid, 4::smallint, 'attacks_no', 'Zakaż tego, a firma nie zapłaci — po prostu nikogo nie weźmie.', 'Ban it and the firm won''t pay — it just won''t take anyone.'),
  -- Czy małżeństwo może być spełnione bez dzieci?
  ('9bcec9bb-419b-4600-99a7-b61916bbd21d'::uuid, 4::smallint, 'attacks_no', 'Znasz pary, które miały dziecko, żeby coś naprawić?', 'Know a couple who had a baby to fix the marriage?'),
  -- Czy obietnica dana dziecku zobowiązuje tak samo jak ta dana dorosłemu?
  ('f2816085-f7e3-4e33-b42a-c947366ec947'::uuid, 4::smallint, 'attacks_yes', 'Jak dotrzymasz obietnicy, że nigdy nie umrzesz?', 'How will you keep the promise that you will never die?'),
  -- Czy oddanie starszego rodzica do domu opieki jest czymś złym?
  ('2fed91a2-f02a-4784-9b14-16164dfd7655'::uuid, 4::smallint, 'attacks_yes', 'Zmienisz mu opatrunek o trzeciej w nocy, dzień po dniu?', 'Will you be changing his dressing at three every morning?'),
  -- Czy pary powinny czasem wyjeżdżać na osobne wakacje?
  ('b6f3f5d1-eb59-4aa8-b5cf-1e4f2909ed5c'::uuid, 4::smallint, 'attacks_no', 'Ile miejsc twój partner skreślił, bo ty tam nie chciałeś?', 'How many of their dream trips have you quietly crossed off?'),
  -- Czy porzuciłbyś znajomych, gdybyś wygrał fortunę na loterii?
  ('459bcb33-4d62-4eab-9c55-354ee531145c'::uuid, 4::smallint, 'attacks_yes', 'Kto ci powie prawdę, gdy wszyscy nowi żyją z twojej wygranej?', 'Who tells you the truth once every new friend lives off you?'),
  -- Czy powinieneś dawać małemu dziecku specjalnie wygrywać w grach?
  ('9a6bffbb-3d7e-48d4-83fa-bc3b52e2a65a'::uuid, 4::smallint, 'attacks_no', 'Dziecko, które nigdy nie wygrywa, po prostu przestaje grać.', 'A child who never wins simply stops playing with you.'),
  -- Czy powinieneś zdradzić partnerowi każdy szczegół swojej miłosnej przeszłości?
  ('a5d5f23d-7a1a-48dd-959d-913c4dfb9d31'::uuid, 4::smallint, 'attacks_no', 'To, czego nie powiesz, powie kiedyś ktoś inny na imprezie.', 'What you skip, someone at a party will say for you.'),
  -- Czy przyjaciele powinni płacić sobie pełną cenę za profesjonalną pracę?
  ('025ca657-ba32-4b53-8c78-15077d8e9e45'::uuid, 4::smallint, 'attacks_yes', 'Pełna faktura zamienia przyjaciela w klienta.', 'A full invoice turns a friend into a client.'),
  -- Czy reklamy alkoholu powinny być w ogóle gdziekolwiek dozwolone?
  ('3ef40b09-7423-40f9-a059-53b6680e1e54'::uuid, 4::smallint, 'attacks_yes', 'Ten billboard widzi też ktoś, kto właśnie wraca z odwyku.', 'That billboard also finds someone fresh out of rehab.'),
  -- Czy strach przed samotnością to wystarczający powód, by trwać w związku?
  ('3d409cbf-f14c-4ff3-b6d8-e2d684a68ebb'::uuid, 4::smallint, 'attacks_no', 'Kto poda ci wodę, gdy leżysz z gorączką w pustym mieszkaniu?', 'Who brings you water in an empty flat when the fever hits?'),
  -- Czy telefony powinny być zakazane w szkołach przez cały dzień?
  ('9fde18ec-0bf7-42cf-802d-044fdf678478'::uuid, 4::smallint, 'attacks_no', 'Przerwa bez telefonów to jedyne miejsce, gdzie dzieci gadają.', 'A phone-free break is the only place children still talk.'),
  -- Czy ten, kto zaprosił na randkę, powinien zawsze zapłacić rachunek?
  ('9b348a54-667d-4084-9385-76a3a959702b'::uuid, 4::smallint, 'attacks_no', 'Ty wybrałeś lokal i cenę, a rachunek ma być wspólny?', 'You picked the place and the price — and now you split it?'),
  -- Czy to hipokryzja oceniać innych za drogie ubrania i auta, samemu mając najnowszy telefon?
  ('ceb4be50-405f-4e46-8ff0-fb963bd4f18f'::uuid, 4::smallint, 'attacks_yes', 'Trzeba być bez grzechu, żeby nazwać cudzy wydatek głupim?', 'Do you have to be sinless before you can call a purchase silly?'),
  -- Czy to w porządku, że jedni zostają miliarderami, gdy inni głodują?
  ('5f63e9e9-4b46-49dc-9b4d-290d7b936de5'::uuid, 4::smallint, 'attacks_yes', 'Miliarda nikt nie zarobił sam — ktoś przy tym harował.', 'Nobody earns a billion alone — someone else did the hours.'),
  -- Czy to właśnie strach przed śmiercią czyni życie cennym?
  ('1f82d7e4-48da-49bb-92d7-544a7b331598'::uuid, 4::smallint, 'attacks_yes', 'Kiedy byłeś naprawdę szczęśliwy, myślałeś w ogóle o śmierci?', 'When you were truly happy, were you thinking about death?'),
  -- Czy to zdrada trzymać prezenty od dawnej miłości?
  ('0e573e33-e62f-4009-ad37-eab49c4aefe4'::uuid, 4::smallint, 'attacks_yes', 'Zegarek nie wie, kto ci go dał.', 'The watch has no idea who gave it to you.'),
  -- Czy to złe dawać na cele dobroczynne głównie dla poklasku?
  ('589fbfde-a1da-4158-9775-83c72c927c1c'::uuid, 4::smallint, 'attacks_no', 'Twój datek idzie po ładne zdjęcie, a nie tam, gdzie boli.', 'Your money follows the photo op, not the need nobody films.'),
  -- Czy to złe rozmnażać nowe zwierzęta, gdy schroniska są pełne?
  ('d12a4aa7-4a7d-4c03-9305-f7dc77dcf21a'::uuid, 4::smallint, 'attacks_yes', 'Nie hodowca zapełnił schronisko, tylko poprzedni właściciel.', 'The breeder did not fill that shelter — the previous owner did.'),
  -- Czy uczniowie powinni móc pisać wypracowania z pomocą AI?
  ('9bc43037-ebaf-4efc-8ce0-d44d38653fe5'::uuid, 4::smallint, 'attacks_yes', 'Kto nigdy nie napisał złego akapitu, nie napisze dobrego.', 'You only write a good paragraph after writing bad ones.'),
  -- Czy ukrywanie łez przed dziećmi to ich ochrona?
  ('e428c03e-671a-4397-889b-fbe252ffdddc'::uuid, 4::smallint, 'attacks_no', 'Kogo obwini dziecko, gdy zobaczy, jak się rozsypujesz?', 'Who will a child blame when they see you fall apart?'),
  -- Czy w głębi duszy każdy działa głównie z własnego interesu?
  ('48ccd4dc-a917-4058-af56-4f5f1c6921d0'::uuid, 4::smallint, 'attacks_yes', 'Nazwiesz każdy dobry uczynek egoizmem — tak jest ci wygodniej.', 'You will call any kind act selfish — it saves you the doubt.'),
  -- Czy w ogóle warto pożyczać pieniądze bliskiemu przyjacielowi?
  ('945cd618-3ce8-478e-8059-45673146cdc7'::uuid, 4::smallint, 'attacks_no', 'Pamiętasz, kto pożyczył tobie, gdy było najgorzej?', 'Remember who lent you money when you had none?'),
  -- Czy w porządku mieć tajne oszczędności, o których partner nie wie?
  ('c2000cd7-d26c-4c4a-b52a-eee70975e749'::uuid, 4::smallint, 'attacks_no', 'Gdybyś musiał wyjść dziś w nocy, za co kupisz bilet?', 'If you had to leave tonight, whose money buys the ticket?'),
  -- Czy wakacje w resorcie są równie wartościowe jak „prawdziwe” podróżowanie?
  ('7b49f88d-8dce-4b49-9dee-015fa0a158ae'::uuid, 4::smallint, 'attacks_no', 'Kto ustalił, że urlop musi być trudny, żeby się liczył?', 'Who decided a holiday has to be hard work to count?'),
  -- Czy warto poślubić kogoś, kogo twoja rodzina otwarcie nie akceptuje?
  ('e70ba262-7e76-46c1-b1b2-6013a58601dd'::uuid, 4::smallint, 'attacks_no', 'Twoim dziadkom też ktoś odradzał ten ślub — i wzięli go.', 'Someone warned your grandparents off each other — they married anyway.'),
  -- Czy warto założyć biznes z najlepszym przyjacielem?
  ('aa76d989-ab98-48f7-9cd6-08e195eafb38'::uuid, 4::smallint, 'attacks_no', 'Wolisz wspólnika, którego poznałeś na godzinnej rozmowie?', 'Would you rather partner with someone you met at one interview?'),
  -- Czy wieczne spóźnianie się to cicha forma braku szacunku?
  ('59ad8d8b-c692-42dc-a051-a083535ff6dc'::uuid, 4::smallint, 'attacks_yes', 'Ten sam człowiek zrywa się w nocy, gdy dzwonisz z problemem.', 'The same person turns up at midnight when you need them.'),
  -- Czy większość ludzi byłaby szczęśliwsza po miesiącu zupełnie bez internetu?
  ('84f4cb83-c27d-42cb-bf44-ef016250ff39'::uuid, 4::smallint, 'attacks_no', 'Pamiętasz ten weekend bez zasięgu — chciałeś wracać?', 'Remember that weekend with no signal — did you want it to end?'),
  -- Czy większość ludzi łamałaby zasady, gdyby nigdy nie mogła zostać przyłapana?
  ('71fa587e-485f-4a6d-861c-87bb0f4b0b1a'::uuid, 4::smallint, 'attacks_yes', 'Odprowadzasz wózek do sklepu, choć nikt tego nie sprawdza.', 'You still return the trolley, and nobody is checking.'),
  -- Czy wolałbyś zostać skrzywdzonym, niż skrzywdzić?
  ('ae55bf9c-0af6-416b-82fa-624c4f722438'::uuid, 4::smallint, 'attacks_no', 'Krzywdę, którą zrobiłeś, nosisz ty — nie ten drugi.', 'The harm you cause is the one you carry, not them.'),
  -- Czy wolno okłamać umierającego, by dać mu spokój?
  ('68e3d717-7120-4b25-baab-e123a30af94a'::uuid, 4::smallint, 'attacks_no', 'Prawda nic tu nie zmieni — poza ostatnim tygodniem strachu.', 'The truth changes nothing now, except his last week of fear.'),
  -- Czy wolno zwrócić uwagę cudzemu niegrzecznemu dziecku?
  ('09988e50-5ea9-4f73-80de-a3a09986f4ab'::uuid, 4::smallint, 'attacks_no', 'Kopie w twój fotel od godziny, a ty milczysz z grzeczności?', 'An hour of kicking your seat, and you stay polite?'),
  -- Czy wolno, by jedno z partnerów nigdy nie pracowało i żyło na koszt drugiego?
  ('df0ad2de-5fc0-42be-9bc2-815b6a7849a6'::uuid, 4::smallint, 'attacks_no', 'Dom, zakupy i pranie to praca — tylko nikt za nią nie płaci.', 'Cooking, laundry and errands are work — nobody pays for them.'),
  -- Czy wskakiwanie w nowy związek zaraz po rozstaniu to błąd?
  ('3503d263-4c9c-4e4c-9932-07d57f8c4a85'::uuid, 4::smallint, 'attacks_yes', 'A jeśli ten związek skończył się w twojej głowie rok temu?', 'What if it ended in your head a year before it ended?'),
  -- Czy wybaczyć dla własnego spokoju, nawet gdy druga strona nie żałuje?
  ('6b9529be-05c0-446c-9a58-7d706aca77e4'::uuid, 4::smallint, 'attacks_no', 'Ile lat jeszcze ma ci zabrać ktoś, kto o tym nie pamięta?', 'How many more years will you give a man who forgot it?'),
  -- Czy wydawanie fortuny na jeden dzień ślubu jest tego warte?
  ('b67e2300-c3c4-46cb-aec1-5a43e4c5fb5d'::uuid, 4::smallint, 'attacks_no', 'Wszyscy twoi bliscy w jednym pokoju — jeden raz w życiu.', 'Everyone you love in one room — that happens once.'),
  -- Czy wypada odwołać plany w ostatniej chwili dla lepszej oferty?
  ('11962158-eb0f-44b2-a393-1757dea565ba'::uuid, 4::smallint, 'attacks_no', 'Piwo z kumplem może być za tydzień — ten koncert nie.', 'The pub is still there next week — the gig is not.'),
  -- Czy zamiast oczekiwania napiwku cena powinna po prostu obejmować wszystko?
  ('c05d6e2e-4fa3-4512-9a93-974d89fbd4d9'::uuid, 4::smallint, 'attacks_yes', 'Kelner dostanie te same pieniądze — po co ma się starać?', 'Same money either way — why would the waiter still try?'),
  -- Czy zamieszkanie nowożeńców z rodzicami dla oszczędności to dobry pomysł?
  ('2bf22fc7-41ed-4749-ac7f-598a6f87660e'::uuid, 4::smallint, 'attacks_no', 'Dwa lata u teściów to wkład własny na swoje cztery kąty.', 'Two years with the in-laws is the deposit on your own place.'),
  -- Czy zamieszkanie razem głównie dla oszczędności to błąd?
  ('c8151f9f-5e0f-424a-a049-e829e9ad2922'::uuid, 4::smallint, 'attacks_yes', 'Twoi dziadkowie zamieszkali razem z miłości czy z biedy?', 'Did your grandparents move in for love, or because they had to?'),
  -- Czy zatrudnianie własnej rodziny to błąd?
  ('04a84a55-fadc-49ef-b011-bafd811c28fe'::uuid, 4::smallint, 'attacks_yes', 'Kto zostanie, gdy przyjdzie chudy miesiąc — obcy czy siostra?', 'When the bad month comes, who stays — a stranger or your sister?'),
  -- Czy zawsze warto wybrać pracę, którą kochasz, zamiast lepiej płatnej?
  ('b9ea3313-f244-476e-82d9-f12921516024'::uuid, 4::smallint, 'attacks_no', 'Policz niedzielne wieczory oddane za tę różnicę w pensji.', 'Count the Sunday nights you traded for that pay rise.'),
  -- Czy zdradzenie sekretu przyjaciela partnerowi to wciąż dochowanie tajemnicy?
  ('fb20305a-6d4a-41e6-bb81-5ccdb886018d'::uuid, 4::smallint, 'attacks_no', 'Twój przyjaciel też opowiedział to komuś — właśnie tobie.', 'Your friend told someone too — that someone was you.'),
  -- Czy zgadzasz się z tym, że jedno ze swoich dzieci zawsze kocha się bardziej?
  ('ca0d4287-c37f-41e3-8319-d6076e04858f'::uuid, 4::smallint, 'attacks_yes', 'To, co bierzesz za większą miłość, bywa większym strachem.', 'What you read as more love is often just more worry.'),
  -- Czy zostanie rodzicem po pięćdziesiątce jest fair wobec dziecka?
  ('67752e62-566e-40b5-9672-f022865cda6c'::uuid, 4::smallint, 'attacks_no', 'Wolałbyś nie istnieć, niż mieć starszego ojca?', 'Would you rather not exist than have an older father?'),
  -- Czy zrobiłbyś test DNA, wiedząc, że może ujawnić rodzinne sekrety?
  ('02aa559b-1fe5-417c-9e98-fe2fcf671f22'::uuid, 4::smallint, 'attacks_no', 'Twoje dzieci odziedziczą to, czego wolałeś nie sprawdzić.', 'Your children inherit the thing you chose not to look at.'),
  -- Czy zwracanie ubrań założonych raz na imprezę to forma kradzieży?
  ('01922977-4af0-4958-b43a-25a9c2c725d1'::uuid, 4::smallint, 'attacks_yes', 'Który złodziej wraca do sklepu i oddaje łup?', 'What thief walks back in and hands the loot over?'),
  -- Czy świat, w którym maszyny wykonują całą pracę, byłby czymś dobrym?
  ('1fadcb4d-3cf9-4115-a921-ffb0ec50fbaf'::uuid, 4::smallint, 'attacks_no', 'Nikt nie tęskni za kopalnią, kiedy odzyska płuca.', 'Nobody misses the pit once they get their lungs back.'),
  -- Czy świat, w którym nikt nie może kłamać, byłby lepszy?
  ('e1245db1-10a5-4b6b-a177-a845aef9c87d'::uuid, 4::smallint, 'attacks_no', 'Ile kosztowało cię ostatnie kłamstwo, w które uwierzyłeś?', 'What did the last lie you believed actually cost you?'),
  -- Czy życie wieczne byłoby raczej przekleństwem niż błogosławieństwem?
  ('74e30dde-61f9-4995-99ba-9a8a22eaa75d'::uuid, 4::smallint, 'attacks_yes', 'Przekleństwo, a do lekarza biegniesz z każdym guzkiem?', 'A curse, yet you run to the doctor over every lump?'),
  -- Gdybyś mógł na zawsze pozostać fizycznie trzydziestolatkiem, czy byś chciał?
  ('c4fbed60-ab48-4f03-831f-0d2ec937e739'::uuid, 4::smallint, 'attacks_no', 'Właśnie wybrałeś kolana, które za trzydzieści lat cię zdradzą.', 'You just chose the knees that will betray you in thirty years.'),
  -- Gdybyś mógł usłyszeć, co ludzie naprawdę myślą, chciałbyś?
  ('2a577655-3e0a-49ab-986b-df8b0cb1a4c4'::uuid, 4::smallint, 'attacks_no', 'Wolisz się domyślać przez lata, niż usłyszeć to raz?', 'Would you rather guess for years than hear it once?'),
  -- Gdybyś mógł wymazać swoje najboleśniejsze wspomnienie, czy powinieneś to zrobić?
  ('15dc4795-292a-4b3b-9a8f-c49fa4fe3831'::uuid, 4::smallint, 'attacks_no', 'Ile razy w tym roku to wspomnienie obudziło cię o trzeciej?', 'How many times this year has it woken you at three?')
),
ins as (
  insert into question_smaczki (question_id, "position", is_active, side)
  select n.question_id, n."position", true, n.side from nowe n
  returning id, question_id
)
insert into question_smaczki_translations (smaczek_id, locale, text)
select i.id, t.locale, t.text
from ins i
join nowe n on n.question_id = i.question_id
cross join lateral (values ('pl', n.pl), ('en', n.en)) as t(locale, text);

commit;
