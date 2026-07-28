-- ============================================================================
-- Catalog edit batch 4 (master diff, rows nr 138-200)
-- 17 deletes, 1 question-text edit, 29 smaczki rebuilds. EN adapted by
-- assistant for every changed PL. 2 PL comma fixes (nr162, nr190).
-- Diff ignores the EN columns and compares smaczki as a COMPACTED list,
-- because prod is renumbered 1..N while the stale master keeps gaps.
-- Deletes backed up to *_batch4.backup.json.
-- ============================================================================
begin;

delete from public.daily_questions where publish_date > (now() at time zone 'utc')::date + 1;

delete from public.daily_questions d
using (values
  ('5605b2a6-9488-4ba1-b6f1-f04bbfae26df'),
  ('5ab5a018-bcbd-4293-8540-6bc9ef7c433a'),
  ('60d2d8b9-e311-43fe-8e72-7dd928571494'),
  ('6be427ed-054a-459f-84ef-d59b35cecd21'),
  ('727fbd96-5d40-4991-a5a3-ba967c6ab5f0'),
  ('7c136405-37cb-4da2-ae03-9c9cbcd69395'),
  ('7d3dbf0c-7f87-4f35-921f-bf2b142684bb'),
  ('8b41ea13-b28b-4eb8-bbc0-e4e1839c2b29'),
  ('8bc77bf8-ca6d-4076-a9e3-ec25d0aeb68f'),
  ('94c2c449-35e6-4260-9db9-29ead647b2b8'),
  ('9f1f791b-82d9-4a88-814a-cd61f8e0c345'),
  ('ad673d95-ff68-4551-bb78-eafece2a14eb'),
  ('b22900cd-14df-439b-bd56-788f7ce82404'),
  ('b8738440-9a60-43e9-8d59-09226004d64d'),
  ('c28c974f-a275-48d3-a734-d99ca49e34c5'),
  ('ef27b58e-0ea9-4211-b5be-ceb9ccffb9e0'),
  ('f2b4cb2d-7b98-4ba0-8970-29654cc4823d')
) as del(id)
where d.question_id = del.id::uuid;

delete from public.questions q
using (values
  ('5605b2a6-9488-4ba1-b6f1-f04bbfae26df'),
  ('5ab5a018-bcbd-4293-8540-6bc9ef7c433a'),
  ('60d2d8b9-e311-43fe-8e72-7dd928571494'),
  ('6be427ed-054a-459f-84ef-d59b35cecd21'),
  ('727fbd96-5d40-4991-a5a3-ba967c6ab5f0'),
  ('7c136405-37cb-4da2-ae03-9c9cbcd69395'),
  ('7d3dbf0c-7f87-4f35-921f-bf2b142684bb'),
  ('8b41ea13-b28b-4eb8-bbc0-e4e1839c2b29'),
  ('8bc77bf8-ca6d-4076-a9e3-ec25d0aeb68f'),
  ('94c2c449-35e6-4260-9db9-29ead647b2b8'),
  ('9f1f791b-82d9-4a88-814a-cd61f8e0c345'),
  ('ad673d95-ff68-4551-bb78-eafece2a14eb'),
  ('b22900cd-14df-439b-bd56-788f7ce82404'),
  ('b8738440-9a60-43e9-8d59-09226004d64d'),
  ('c28c974f-a275-48d3-a734-d99ca49e34c5'),
  ('ef27b58e-0ea9-4211-b5be-ceb9ccffb9e0'),
  ('f2b4cb2d-7b98-4ba0-8970-29654cc4823d')
) as del(id)
where q.id = del.id::uuid;

with anchor as (select coalesce(max(publish_date), (now() at time zone 'utc')::date) as last_day from public.daily_questions),
pool as (select qq.id, (row_number() over (order by random()))::int as rn from public.questions qq
         where qq.is_active and not exists (select 1 from public.daily_questions d where d.question_id = qq.id))
insert into public.daily_questions (publish_date, question_id)
select (select last_day from anchor) + pool.rn, pool.id from pool;

-- Question text edits.
-- nr160
update public.question_translations set question_text = 'Czy płacenie dzieciom za dobre oceny jest okej?' where question_id = '7dfdc5d4-c883-46f9-971e-ed15e017f549' and locale = 'pl';
update public.question_translations set question_text = 'Is it okay to pay kids for good grades?' where question_id = '7dfdc5d4-c883-46f9-971e-ed15e017f549' and locale = 'en';

-- Smaczki rebuilds.
-- nr138: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '51b89269-ace0-4e67-9674-efbc4171ad12');
delete from public.question_smaczki where question_id = '51b89269-ace0-4e67-9674-efbc4171ad12';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('51b89269-ace0-4e67-9674-efbc4171ad12',1,true),('51b89269-ace0-4e67-9674-efbc4171ad12',2,true),('51b89269-ace0-4e67-9674-efbc4171ad12',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Bomby kofeinowe dla nastolatków'),(1,'en','Caffeine bombs for teens'),
  (2,'pl','To tylko gazowany napój, kiedyś nie było problemu'),(2,'en','It''s just a fizzy drink — nobody used to mind'),
  (3,'pl','A co z karą?'),(3,'en','And what''s the penalty?')
) as v(position, locale, text) on v.position = ins.position;

-- nr146: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '65430e26-f9e5-4002-bc4e-ff0aa7037acd');
delete from public.question_smaczki where question_id = '65430e26-f9e5-4002-bc4e-ff0aa7037acd';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('65430e26-f9e5-4002-bc4e-ff0aa7037acd',1,true),('65430e26-f9e5-4002-bc4e-ff0aa7037acd',2,true),('65430e26-f9e5-4002-bc4e-ff0aa7037acd',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','A jak nie ma innej opcji?'),(1,'en','And if there''s no alternative?'),
  (2,'pl','Wyrzucanie doświadczonych?'),(2,'en','Kicking out the experienced?'),
  (3,'pl','Nikt nie oddaje władzy dobrowolnie'),(3,'en','No one gives up power willingly')
) as v(position, locale, text) on v.position = ins.position;

-- nr148: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '6bea2703-3a4c-4636-b00a-14cc0fb0c017');
delete from public.question_smaczki where question_id = '6bea2703-3a4c-4636-b00a-14cc0fb0c017';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('6bea2703-3a4c-4636-b00a-14cc0fb0c017',1,true),('6bea2703-3a4c-4636-b00a-14cc0fb0c017',2,true),('6bea2703-3a4c-4636-b00a-14cc0fb0c017',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Wyobcowanie dziecka nie jest dobre'),(1,'en','Isolating the child isn''t good'),
  (2,'pl','Skradzione dzieciństwo?'),(2,'en','Stolen childhood?'),
  (3,'pl','A do kontaktu z rodzicem?'),(3,'en','And for reaching a parent?')
) as v(position, locale, text) on v.position = ins.position;

-- nr149: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '6c11e1b3-bd78-4914-a7be-6287a657983b');
delete from public.question_smaczki where question_id = '6c11e1b3-bd78-4914-a7be-6287a657983b';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('6c11e1b3-bd78-4914-a7be-6287a657983b',1,true),('6c11e1b3-bd78-4914-a7be-6287a657983b',2,true),('6c11e1b3-bd78-4914-a7be-6287a657983b',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Buduje charakter'),(1,'en','Builds character'),
  (2,'pl','Płacenie za domowe czynności uczy zarabiania'),(2,'en','Paying for chores teaches earning'),
  (3,'pl','Uczysz, że rodzina to współpraca'),(3,'en','You teach that family means pitching in')
) as v(position, locale, text) on v.position = ins.position;

-- nr150: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '6d123f78-7f5d-4615-ab5c-527ca5ff6095');
delete from public.question_smaczki where question_id = '6d123f78-7f5d-4615-ab5c-527ca5ff6095';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('6d123f78-7f5d-4615-ab5c-527ca5ff6095',1,true),('6d123f78-7f5d-4615-ab5c-527ca5ff6095',2,true),('6d123f78-7f5d-4615-ab5c-527ca5ff6095',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Optymalizacja kosztów'),(1,'en','Cutting costs'),
  (2,'pl','Samotny za ekranem?'),(2,'en','Lonely behind a screen?'),
  (3,'pl','Dom i biuro zlewają się w jedno'),(3,'en','Home and office blur into one')
) as v(position, locale, text) on v.position = ins.position;

-- nr152: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '710c0397-7132-49e7-a9e7-6a5720a4e63e');
delete from public.question_smaczki where question_id = '710c0397-7132-49e7-a9e7-6a5720a4e63e';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('710c0397-7132-49e7-a9e7-6a5720a4e63e',1,true),('710c0397-7132-49e7-a9e7-6a5720a4e63e',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Cukier to nowy tytoń'),(1,'en','Sugar is the new tobacco'),
  (2,'pl','Zdrowa żywność i tak jest droższa'),(2,'en','Healthy food already costs more')
) as v(position, locale, text) on v.position = ins.position;

-- nr154: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '739b82e2-7813-475e-9287-8fff8d931b33');
delete from public.question_smaczki where question_id = '739b82e2-7813-475e-9287-8fff8d931b33';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('739b82e2-7813-475e-9287-8fff8d931b33',1,true),('739b82e2-7813-475e-9287-8fff8d931b33',2,true),('739b82e2-7813-475e-9287-8fff8d931b33',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Dyscyplina czy obsesja?'),(1,'en','Discipline or obsession?'),
  (2,'pl','Zdrowie nigdy nie jest próżnością'),(2,'en','Healthy is never vain'),
  (3,'pl','Zwykle chodzi o wygląd, a nie o zdrowie'),(3,'en','It''s usually about looks, not health')
) as v(position, locale, text) on v.position = ins.position;

-- nr155: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '7521b6b4-6aa7-45fb-bb8f-b850667008d6');
delete from public.question_smaczki where question_id = '7521b6b4-6aa7-45fb-bb8f-b850667008d6';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('7521b6b4-6aa7-45fb-bb8f-b850667008d6',1,true),('7521b6b4-6aa7-45fb-bb8f-b850667008d6',2,true),('7521b6b4-6aa7-45fb-bb8f-b850667008d6',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Wydajemy duże pieniądze, żeby zanieczyszczać niebo i okolice'),(1,'en','We spend a fortune to pollute the sky'),
  (2,'pl','Zabijanie radości?'),(2,'en','Killing the joy?'),
  (3,'pl','Pies się chowa, gdy ty się bawisz'),(3,'en','Your dog hides while you celebrate')
) as v(position, locale, text) on v.position = ins.position;

-- nr156: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '768aac89-02f8-4938-9ad4-00e565d2bb3c');
delete from public.question_smaczki where question_id = '768aac89-02f8-4938-9ad4-00e565d2bb3c';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('768aac89-02f8-4938-9ad4-00e565d2bb3c',1,true),('768aac89-02f8-4938-9ad4-00e565d2bb3c',2,true),('768aac89-02f8-4938-9ad4-00e565d2bb3c',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Czy nakierowywanie też jest złe?'),(1,'en','Is steering them wrong too?'),
  (2,'pl','Ich życie?'),(2,'en','Their life?'),
  (3,'pl','Realizujesz swoje marzenie cudzym życiem'),(3,'en','You''re living your dream through their life')
) as v(position, locale, text) on v.position = ins.position;

-- nr157: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '77194da0-7c23-4dbe-8ba0-de998aa3bb50');
delete from public.question_smaczki where question_id = '77194da0-7c23-4dbe-8ba0-de998aa3bb50';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('77194da0-7c23-4dbe-8ba0-de998aa3bb50',1,true),('77194da0-7c23-4dbe-8ba0-de998aa3bb50',2,true),('77194da0-7c23-4dbe-8ba0-de998aa3bb50',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Bez ludzkich uprzedzeń?'),(1,'en','No human bias?'),
  (2,'pl','Nie oceni niektórych aspektów, np. aparycji'),(2,'en','It can''t judge some things — like appearance'),
  (3,'pl','AI uczy się uprzedzeń z twoich danych'),(3,'en','The AI learns its bias from your data')
) as v(position, locale, text) on v.position = ins.position;

-- nr160: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '7dfdc5d4-c883-46f9-971e-ed15e017f549');
delete from public.question_smaczki where question_id = '7dfdc5d4-c883-46f9-971e-ed15e017f549';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('7dfdc5d4-c883-46f9-971e-ed15e017f549',1,true),('7dfdc5d4-c883-46f9-971e-ed15e017f549',2,true),('7dfdc5d4-c883-46f9-971e-ed15e017f549',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Motywacja!'),(1,'en','Motivation!'),
  (2,'pl','Ważny jest efekt'),(2,'en','The result is what counts'),
  (3,'pl','Uczą się dla kasy, nie dla wiedzy'),(3,'en','They learn for cash, not for knowledge')
) as v(position, locale, text) on v.position = ins.position;

-- nr162: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '88c5d7d4-1d12-4c2c-a632-35a58f7c3ac5');
delete from public.question_smaczki where question_id = '88c5d7d4-1d12-4c2c-a632-35a58f7c3ac5';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('88c5d7d4-1d12-4c2c-a632-35a58f7c3ac5',1,true),('88c5d7d4-1d12-4c2c-a632-35a58f7c3ac5',2,true),('88c5d7d4-1d12-4c2c-a632-35a58f7c3ac5',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Bez marnowania'),(1,'en','No waste'),
  (2,'pl','Nie je, bo czeka na coś słodkiego/niezdrowego?'),(2,'en','Not eating because they''re holding out for sweets?'),
  (3,'pl','Uczysz jeść mimo sytości'),(3,'en','You teach eating past ''full''')
) as v(position, locale, text) on v.position = ins.position;

-- nr166: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '8c007727-94af-4084-97b9-e030b20a0b55');
delete from public.question_smaczki where question_id = '8c007727-94af-4084-97b9-e030b20a0b55';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('8c007727-94af-4084-97b9-e030b20a0b55',1,true),('8c007727-94af-4084-97b9-e030b20a0b55',2,true),('8c007727-94af-4084-97b9-e030b20a0b55',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Żadne zwierzę nie musi zginąć'),(1,'en','No animal has to die'),
  (2,'pl','Jedzenie z fabryki nie zastąpi prawdziwego mięsa'),(2,'en','Factory food won''t replace real meat'),
  (3,'pl','„Naturalna" hodowla to też fabryka'),(3,'en','''Natural'' farming is a factory too')
) as v(position, locale, text) on v.position = ins.position;

-- nr167: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '8cd47f0d-62f3-48b1-b280-48eb374bc907');
delete from public.question_smaczki where question_id = '8cd47f0d-62f3-48b1-b280-48eb374bc907';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('8cd47f0d-62f3-48b1-b280-48eb374bc907',1,true),('8cd47f0d-62f3-48b1-b280-48eb374bc907',2,true),('8cd47f0d-62f3-48b1-b280-48eb374bc907',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Chroń mózg'),(1,'en','Protect their brain'),
  (2,'pl','Współczesny świat, może to już czas?'),(2,'en','Modern world — maybe it''s time?'),
  (3,'pl','A ty odkładasz swój telefon?'),(3,'en','And do you put your own phone down?')
) as v(position, locale, text) on v.position = ins.position;

-- nr168: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '8dc57b64-27e9-4e48-8c71-a7c534ab4593');
delete from public.question_smaczki where question_id = '8dc57b64-27e9-4e48-8c71-a7c534ab4593';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('8dc57b64-27e9-4e48-8c71-a7c534ab4593',1,true),('8dc57b64-27e9-4e48-8c71-a7c534ab4593',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','A biologia?'),(1,'en','And biology?'),
  (2,'pl','Dać mu być sobą?'),(2,'en','Let them just be themselves?')
) as v(position, locale, text) on v.position = ins.position;

-- nr169: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '91d9aeff-1eab-4d88-aa4f-5a5a943c8e0a');
delete from public.question_smaczki where question_id = '91d9aeff-1eab-4d88-aa4f-5a5a943c8e0a';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('91d9aeff-1eab-4d88-aa4f-5a5a943c8e0a',1,true),('91d9aeff-1eab-4d88-aa4f-5a5a943c8e0a',2,true),('91d9aeff-1eab-4d88-aa4f-5a5a943c8e0a',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Zawsze obok?'),(1,'en','Always there?'),
  (2,'pl','Czy to nie większa samotność?'),(2,'en','Isn''t that even lonelier?'),
  (3,'pl','Kod zaprogramowany, by cię lubić'),(3,'en','Code programmed to like you')
) as v(position, locale, text) on v.position = ins.position;

-- nr171: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '9a6bffbb-3d7e-48d4-83fa-bc3b52e2a65a');
delete from public.question_smaczki where question_id = '9a6bffbb-3d7e-48d4-83fa-bc3b52e2a65a';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('9a6bffbb-3d7e-48d4-83fa-bc3b52e2a65a',1,true),('9a6bffbb-3d7e-48d4-83fa-bc3b52e2a65a',2,true),('9a6bffbb-3d7e-48d4-83fa-bc3b52e2a65a',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Buduje pewność siebie'),(1,'en','It builds confidence'),
  (2,'pl','Fałszywy świat?'),(2,'en','False world?'),
  (3,'pl','Pierwsza prawdziwa porażka zaboli podwójnie, ale nauczy'),(3,'en','The first real failure hurts double — but teaches')
) as v(position, locale, text) on v.position = ins.position;

-- nr172: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '9bc43037-ebaf-4efc-8ce0-d44d38653fe5');
delete from public.question_smaczki where question_id = '9bc43037-ebaf-4efc-8ce0-d44d38653fe5';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('9bc43037-ebaf-4efc-8ce0-d44d38653fe5',1,true),('9bc43037-ebaf-4efc-8ce0-d44d38653fe5',2,true),('9bc43037-ebaf-4efc-8ce0-d44d38653fe5',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Tylko narzędzie?'),(1,'en','Just a tool?'),
  (2,'pl','W tych czasach może to być całkowite zero wkładu własnego'),(2,'en','These days it can mean zero effort of your own'),
  (3,'pl','Kalkulator zabił umiejętność liczenia?'),(3,'en','Did the calculator kill arithmetic?')
) as v(position, locale, text) on v.position = ins.position;

-- nr179: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'b4ff0cdc-aba4-43a1-ae74-e105aa443f00');
delete from public.question_smaczki where question_id = 'b4ff0cdc-aba4-43a1-ae74-e105aa443f00';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('b4ff0cdc-aba4-43a1-ae74-e105aa443f00',1,true),('b4ff0cdc-aba4-43a1-ae74-e105aa443f00',2,true),('b4ff0cdc-aba4-43a1-ae74-e105aa443f00',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Bezpieczeństwo przede wszystkim'),(1,'en','Safety first'),
  (2,'pl','Rodzice przesadzają, lepiej czasami coś ukryć?'),(2,'en','Parents overreact — better to hide some things?'),
  (3,'pl','Złap raz, a stracisz zaufanie na zawsze'),(3,'en','Caught once, trust gone for good')
) as v(position, locale, text) on v.position = ins.position;

-- nr181: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'b8c9feb1-c199-4cc0-86ab-5cb526fbbab5');
delete from public.question_smaczki where question_id = 'b8c9feb1-c199-4cc0-86ab-5cb526fbbab5';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('b8c9feb1-c199-4cc0-86ab-5cb526fbbab5',1,true),('b8c9feb1-c199-4cc0-86ab-5cb526fbbab5',2,true),('b8c9feb1-c199-4cc0-86ab-5cb526fbbab5',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Masz prawo wiedzieć'),(1,'en','You deserve to know'),
  (2,'pl','Zabijanie radości z jedzenia'),(2,'en','Killing the joy of eating'),
  (3,'pl','Liczba przy deserze by odstraszała'),(3,'en','A number on the dessert would scare you off')
) as v(position, locale, text) on v.position = ins.position;

-- nr183: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'bb378b69-815d-4c5d-ba20-d9ba570fea23');
delete from public.question_smaczki where question_id = 'bb378b69-815d-4c5d-ba20-d9ba570fea23';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('bb378b69-815d-4c5d-ba20-d9ba570fea23',1,true),('bb378b69-815d-4c5d-ba20-d9ba570fea23',2,true),('bb378b69-815d-4c5d-ba20-d9ba570fea23',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Dzieci też to widzą i chłoną'),(1,'en','Kids see it too, and soak it up'),
  (2,'pl','Kto ocenia co śmieciowe, a co nie?'),(2,'en','Who decides what counts as junk?'),
  (3,'pl','Reklama nie zmusza cię do jedzenia'),(3,'en','An ad can''t force-feed you')
) as v(position, locale, text) on v.position = ins.position;

-- nr184: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'c05d6e2e-4fa3-4512-9a93-974d89fbd4d9');
delete from public.question_smaczki where question_id = 'c05d6e2e-4fa3-4512-9a93-974d89fbd4d9';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('c05d6e2e-4fa3-4512-9a93-974d89fbd4d9',1,true),('c05d6e2e-4fa3-4512-9a93-974d89fbd4d9',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Nagroda za dobrą obsługę?'),(1,'en','Reward good service?'),
  (2,'pl','Napiwek to pensja przerzucona na gościa'),(2,'en','Tipping is payroll passed to the guest')
) as v(position, locale, text) on v.position = ins.position;

-- nr187: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'c3ec4e4b-dd95-4b97-9797-80bc21a7ff85');
delete from public.question_smaczki where question_id = 'c3ec4e4b-dd95-4b97-9797-80bc21a7ff85';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('c3ec4e4b-dd95-4b97-9797-80bc21a7ff85',1,true),('c3ec4e4b-dd95-4b97-9797-80bc21a7ff85',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Niepalący nie wybrał tego dymu'),(1,'en','The non-smoker didn''t choose your smoke'),
  (2,'pl','Przestrzeń publiczna, jak nie tam to gdzie?'),(2,'en','Public space — if not there, then where?')
) as v(position, locale, text) on v.position = ins.position;

-- nr188: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'c57c28a0-d6d2-40d7-b84c-d7090d00c419');
delete from public.question_smaczki where question_id = 'c57c28a0-d6d2-40d7-b84c-d7090d00c419';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('c57c28a0-d6d2-40d7-b84c-d7090d00c419',1,true),('c57c28a0-d6d2-40d7-b84c-d7090d00c419',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Niektórym przyda się kopniak'),(1,'en','Some people need a push'),
  (2,'pl','Branża zarabia na twoim niezadowoleniu'),(2,'en','The industry profits from your self-hate')
) as v(position, locale, text) on v.position = ins.position;

-- nr190: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'd0f54795-1f9a-4e42-834a-7b92c4e3b320');
delete from public.question_smaczki where question_id = 'd0f54795-1f9a-4e42-834a-7b92c4e3b320';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('d0f54795-1f9a-4e42-834a-7b92c4e3b320',1,true),('d0f54795-1f9a-4e42-834a-7b92c4e3b320',2,true),('d0f54795-1f9a-4e42-834a-7b92c4e3b320',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Śmierć jako moda?'),(1,'en','Death as fashion?'),
  (2,'pl','Co kraj, to obyczaj. Jada się też różne dzikie zwierzęta'),(2,'en','Every country its custom — wild animals get eaten too'),
  (3,'pl','Skórzane buty nosisz bez wyrzutów?'),(3,'en','Wearing leather shoes without a flinch?')
) as v(position, locale, text) on v.position = ins.position;

-- nr192: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'df12b6d3-d35a-449a-924b-db9445278fe0');
delete from public.question_smaczki where question_id = 'df12b6d3-d35a-449a-924b-db9445278fe0';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('df12b6d3-d35a-449a-924b-db9445278fe0',1,true),('df12b6d3-d35a-449a-924b-db9445278fe0',2,true),('df12b6d3-d35a-449a-924b-db9445278fe0',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Dziecko na początku mało wie, rodzic może pomóc'),(1,'en','A child knows little at first — a parent can help'),
  (2,'pl','Czyje marzenie?'),(2,'en','Whose dream?'),
  (3,'pl','Pasja z przymusu umiera pierwsza'),(3,'en','A forced passion dies first')
) as v(position, locale, text) on v.position = ins.position;

-- nr194: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'e11f4d4f-b743-49ab-93d3-68ab6406896f');
delete from public.question_smaczki where question_id = 'e11f4d4f-b743-49ab-93d3-68ab6406896f';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('e11f4d4f-b743-49ab-93d3-68ab6406896f',1,true),('e11f4d4f-b743-49ab-93d3-68ab6406896f',2,true),('e11f4d4f-b743-49ab-93d3-68ab6406896f',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Zawsze cierpliwy?'),(1,'en','Always patient?'),
  (2,'pl','Przyjaciel na starość?'),(2,'en','A companion in old age?'),
  (3,'pl','Wolisz robota niż własny czas?'),(3,'en','You''d rather a robot than your own time?')
) as v(position, locale, text) on v.position = ins.position;

-- nr195: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'e87c5080-f6d6-41dc-a91d-256b1dedebc4');
delete from public.question_smaczki where question_id = 'e87c5080-f6d6-41dc-a91d-256b1dedebc4';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('e87c5080-f6d6-41dc-a91d-256b1dedebc4',1,true),('e87c5080-f6d6-41dc-a91d-256b1dedebc4',2,true),('e87c5080-f6d6-41dc-a91d-256b1dedebc4',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Moje ciało, mój upgrade'),(1,'en','My body, my upgrade'),
  (2,'pl','Pogoń za wyobrażeniami'),(2,'en','Chasing an image'),
  (3,'pl','Jeden zabieg rzadko jest ostatni'),(3,'en','One procedure is rarely the last')
) as v(position, locale, text) on v.position = ins.position;

-- nr199: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'f281371c-8f2b-46e5-8188-797480c074dc');
delete from public.question_smaczki where question_id = 'f281371c-8f2b-46e5-8188-797480c074dc';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('f281371c-8f2b-46e5-8188-797480c074dc',1,true),('f281371c-8f2b-46e5-8188-797480c074dc',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','A jeśli to praca fizyczna?'),(1,'en','And if it''s physical work?'),
  (2,'pl','To zwykła dyskryminacja'),(2,'en','That''s just discrimination')
) as v(position, locale, text) on v.position = ins.position;

commit;