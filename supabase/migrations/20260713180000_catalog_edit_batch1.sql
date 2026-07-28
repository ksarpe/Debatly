-- ============================================================================
-- Catalog edit batch 1 (rows 1-30 of exports/question_fixed.xlsx)
-- Source: user-marked AKCJA (USUŃ/ZMIANA/ZOSTAW), PL edited in place,
-- EN adapted by assistant. Seeds: yes_pct = table value; total = 6 when
-- pct==50 (light 50/50 nudge), else 30. Two obvious PL typos fixed (nr14, nr18).
-- Deleted rows backed up to *_batch1.backup.json next to this file.
-- ============================================================================
begin;

-- 1) Deletions (USUŃ). daily_questions is ON DELETE RESTRICT, so free the
--    future calendar first, then delete (cascades translations/smaczki/
--    seen/votes/favorites/seeds/user_daily), then rebuild calendar gapless.
delete from public.daily_questions
where publish_date > (now() at time zone 'utc')::date + 1;

delete from public.daily_questions d
using (values
  ('27771fe7-97a1-43bb-9cbd-097428493731'),
  ('55f83d74-90ea-45e0-8af5-41d3860bddaf'),
  ('0245de6a-fa5a-4351-997d-d1ac64fc5a05'),
  ('0446cb4d-d2c7-4a32-ae38-cf1e291fd785'),
  ('0a843403-4f90-4cfc-b898-2f5162ebe9a2')
) as del(id)
where d.question_id = del.id::uuid;

delete from public.questions q
using (values
  ('27771fe7-97a1-43bb-9cbd-097428493731'),
  ('55f83d74-90ea-45e0-8af5-41d3860bddaf'),
  ('0245de6a-fa5a-4351-997d-d1ac64fc5a05'),
  ('0446cb4d-d2c7-4a32-ae38-cf1e291fd785'),
  ('0a843403-4f90-4cfc-b898-2f5162ebe9a2')
) as del(id)
where q.id = del.id::uuid;

with anchor as (
  select coalesce(max(publish_date), (now() at time zone 'utc')::date) as last_day
  from public.daily_questions),
pool as (
  select qq.id, (row_number() over (order by random()))::int as rn
  from public.questions qq
  where qq.is_active and not exists (
    select 1 from public.daily_questions d where d.question_id = qq.id))
insert into public.daily_questions (publish_date, question_id)
select (select last_day from anchor) + pool.rn, pool.id from pool;

-- 2) Question text edits (ZMIANA) — PL + adapted EN.
-- nr5
update public.question_translations set question_text = 'Czy sztuczna inteligencja powinna móc podejmować ważne medyczne decyzje?' where question_id = '16bece38-eb48-4317-bb73-51b3ceb64b0f' and locale = 'pl';
update public.question_translations set question_text = 'Should an AI be allowed to make important medical decisions?' where question_id = '16bece38-eb48-4317-bb73-51b3ceb64b0f' and locale = 'en';
-- nr14
update public.question_translations set question_text = 'Czy kraje powinny otworzyć granice i pozwolić każdemu na swobodną migrację?' where question_id = '64942b79-9416-47ca-a4c1-71eabf70c25c' and locale = 'pl';
update public.question_translations set question_text = 'Should countries open their borders and allow anyone to migrate freely?' where question_id = '64942b79-9416-47ca-a4c1-71eabf70c25c' and locale = 'en';
-- nr21
update public.question_translations set question_text = 'Czy oryginał dzieła sztuki powinien być wart więcej niż jego idealna kopia?' where question_id = '00ffa4ea-a56b-401c-a7d8-f413bb8c988a' and locale = 'pl';
update public.question_translations set question_text = 'Should an original artwork be worth more than a flawless copy of it?' where question_id = '00ffa4ea-a56b-401c-a7d8-f413bb8c988a' and locale = 'en';

-- 3) Smaczki rebuilds (ZMIANA rows whose smaczki changed): delete + reinsert
--    renumbered 1..N so position 1 stays the free teaser.
-- nr1: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '299ccf44-0471-4320-a97f-7bc73e894ca9');
delete from public.question_smaczki where question_id = '299ccf44-0471-4320-a97f-7bc73e894ca9';
with ins as (
  insert into public.question_smaczki (question_id, position, is_active) values ('299ccf44-0471-4320-a97f-7bc73e894ca9',1,true),('299ccf44-0471-4320-a97f-7bc73e894ca9',2,true),('299ccf44-0471-4320-a97f-7bc73e894ca9',3,true)
  returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Państwo zarobi z podatków'),
  (1,'en','The state profits from the taxes'),
  (2,'pl','Minimalizacja czarnego rynku'),
  (2,'en','It shrinks the black market'),
  (3,'pl','Zakaz nie usuwa zawodu, tylko ochronę'),
  (3,'en','A ban removes the safety, not the trade')
) as v(position, locale, text) on v.position = ins.position;

-- nr2: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '57d93dd4-a41f-48cc-8de5-ac2280ea0bd9');
delete from public.question_smaczki where question_id = '57d93dd4-a41f-48cc-8de5-ac2280ea0bd9';
with ins as (
  insert into public.question_smaczki (question_id, position, is_active) values ('57d93dd4-a41f-48cc-8de5-ac2280ea0bd9',1,true),('57d93dd4-a41f-48cc-8de5-ac2280ea0bd9',2,true)
  returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Było między wami coś więcej?'),
  (1,'en','Were you already intimate?'),
  (2,'pl','Cisza to też odpowiedź — tchórzliwa'),
  (2,'en','Silence is an answer too — a coward''s one')
) as v(position, locale, text) on v.position = ins.position;

-- nr3: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'e0734eeb-d0e0-4432-8d37-0bac4257b19f');
delete from public.question_smaczki where question_id = 'e0734eeb-d0e0-4432-8d37-0bac4257b19f';
with ins as (
  insert into public.question_smaczki (question_id, position, is_active) values ('e0734eeb-d0e0-4432-8d37-0bac4257b19f',1,true),('e0734eeb-d0e0-4432-8d37-0bac4257b19f',2,true)
  returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Nikt nie potrzebuje tylu pieniędzy'),
  (1,'en','Nobody needs that much money'),
  (2,'pl','Zazdrość lubi nazywać się sprawiedliwością'),
  (2,'en','Envy loves to call itself justice')
) as v(position, locale, text) on v.position = ins.position;

-- nr4: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '0d84cbe7-9085-4e16-a6ca-1a43b460b074');
delete from public.question_smaczki where question_id = '0d84cbe7-9085-4e16-a6ca-1a43b460b074';
with ins as (
  insert into public.question_smaczki (question_id, position, is_active) values ('0d84cbe7-9085-4e16-a6ca-1a43b460b074',1,true),('0d84cbe7-9085-4e16-a6ca-1a43b460b074',2,true),('0d84cbe7-9085-4e16-a6ca-1a43b460b074',3,true)
  returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Kto wydaje licencję?'),
  (1,'en','Who issues the license?'),
  (2,'pl','Może domowy kurs?'),
  (2,'en','Maybe a home course?'),
  (3,'pl','A twoi rodzice by ją dostali?'),
  (3,'en','Would your own parents have passed?')
) as v(position, locale, text) on v.position = ins.position;

-- nr5: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '16bece38-eb48-4317-bb73-51b3ceb64b0f');
delete from public.question_smaczki where question_id = '16bece38-eb48-4317-bb73-51b3ceb64b0f';
with ins as (
  insert into public.question_smaczki (question_id, position, is_active) values ('16bece38-eb48-4317-bb73-51b3ceb64b0f',1,true),('16bece38-eb48-4317-bb73-51b3ceb64b0f',2,true)
  returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Kto ponosi winę?'),
  (1,'en','Who is to blame?'),
  (2,'pl','Zmęczony lekarz też się myli'),
  (2,'en','A tired doctor makes mistakes too')
) as v(position, locale, text) on v.position = ins.position;

-- nr6: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '23f0212c-93b8-4ac6-beed-b08694b88f7a');
delete from public.question_smaczki where question_id = '23f0212c-93b8-4ac6-beed-b08694b88f7a';
with ins as (
  insert into public.question_smaczki (question_id, position, is_active) values ('23f0212c-93b8-4ac6-beed-b08694b88f7a',1,true),('23f0212c-93b8-4ac6-beed-b08694b88f7a',2,true),('23f0212c-93b8-4ac6-beed-b08694b88f7a',3,true)
  returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Towary i karetki też jadą tymi drogami'),
  (1,'en','Goods and ambulances use those roads too'),
  (2,'pl','Może mniejszy % podatku?'),
  (2,'en','Maybe a smaller tax rate?'),
  (3,'pl','Pieszy dotuje twój samochód a nie eksploatuje dróg'),
  (3,'en','Pedestrians subsidize your car without wearing the roads')
) as v(position, locale, text) on v.position = ins.position;

-- nr8: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '3278873d-6d56-4b17-8611-29b8c717b325');
delete from public.question_smaczki where question_id = '3278873d-6d56-4b17-8611-29b8c717b325';
with ins as (
  insert into public.question_smaczki (question_id, position, is_active) values ('3278873d-6d56-4b17-8611-29b8c717b325',1,true),('3278873d-6d56-4b17-8611-29b8c717b325',2,true)
  returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Kto ocenia moralność?'),
  (1,'en','Who judges morality?'),
  (2,'pl','Żołnierz musi się z tym liczyć'),
  (2,'en','A soldier has to reckon with that')
) as v(position, locale, text) on v.position = ins.position;

-- nr9: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '3787034d-00af-47cd-8161-413071480d3a');
delete from public.question_smaczki where question_id = '3787034d-00af-47cd-8161-413071480d3a';
with ins as (
  insert into public.question_smaczki (question_id, position, is_active) values ('3787034d-00af-47cd-8161-413071480d3a',1,true),('3787034d-00af-47cd-8161-413071480d3a',2,true)
  returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Plan B dla ludzkości?'),
  (1,'en','Humanity''s plan B?'),
  (2,'pl','To prywatne pieniądze'),
  (2,'en','It''s private money')
) as v(position, locale, text) on v.position = ins.position;

-- nr10: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '3e6018b0-8701-49d0-996a-3cc54aeb2605');
delete from public.question_smaczki where question_id = '3e6018b0-8701-49d0-996a-3cc54aeb2605';
with ins as (
  insert into public.question_smaczki (question_id, position, is_active) values ('3e6018b0-8701-49d0-996a-3cc54aeb2605',1,true),('3e6018b0-8701-49d0-996a-3cc54aeb2605',2,true),('3e6018b0-8701-49d0-996a-3cc54aeb2605',3,true)
  returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','A niepełnosprawni?'),
  (1,'en','What about the disabled?'),
  (2,'pl','Dostawy i rzemieślnicy?'),
  (2,'en','Deliveries and tradespeople?'),
  (3,'pl','Można zaparkować gdzie indziej'),
  (3,'en','You could park somewhere else')
) as v(position, locale, text) on v.position = ins.position;

-- nr13: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '5f63e9e9-4b46-49dc-9b4d-290d7b936de5');
delete from public.question_smaczki where question_id = '5f63e9e9-4b46-49dc-9b4d-290d7b936de5';
with ins as (
  insert into public.question_smaczki (question_id, position, is_active) values ('5f63e9e9-4b46-49dc-9b4d-290d7b936de5',1,true),('5f63e9e9-4b46-49dc-9b4d-290d7b936de5',2,true),('5f63e9e9-4b46-49dc-9b4d-290d7b936de5',3,true)
  returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Opodatkować bardziej miliarderów i pomóc jawnie biednym?'),
  (1,'en','Tax billionaires more and openly help the poor?'),
  (2,'pl','Zawsze będą osoby głodujące'),
  (2,'en','There will always be people going hungry'),
  (3,'pl','Głodni nie zjedzą jego jachtu'),
  (3,'en','The hungry can''t eat his yacht')
) as v(position, locale, text) on v.position = ins.position;

-- nr14: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '64942b79-9416-47ca-a4c1-71eabf70c25c');
delete from public.question_smaczki where question_id = '64942b79-9416-47ca-a4c1-71eabf70c25c';
with ins as (
  insert into public.question_smaczki (question_id, position, is_active) values ('64942b79-9416-47ca-a4c1-71eabf70c25c',1,true),('64942b79-9416-47ca-a4c1-71eabf70c25c',2,true),('64942b79-9416-47ca-a4c1-71eabf70c25c',3,true)
  returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Granica to loteria urodzenia'),
  (1,'en','A border is a birth lottery'),
  (2,'pl','Jak odsiać przestępców?'),
  (2,'en','Screening criminals?'),
  (3,'pl','Nierównomierne zasiedlenie?'),
  (3,'en','Uneven settlement?')
) as v(position, locale, text) on v.position = ins.position;

-- nr15: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '854248e9-f7f6-403d-9179-60845c107d7c');
delete from public.question_smaczki where question_id = '854248e9-f7f6-403d-9179-60845c107d7c';
with ins as (
  insert into public.question_smaczki (question_id, position, is_active) values ('854248e9-f7f6-403d-9179-60845c107d7c',1,true),('854248e9-f7f6-403d-9179-60845c107d7c',2,true)
  returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Zabić, by pokazać, że zabijać nie wolno'),
  (1,'en','Kill to prove that killing is wrong'),
  (2,'pl','A pomyłka sądowa?'),
  (2,'en','What about wrongful conviction?')
) as v(position, locale, text) on v.position = ins.position;

-- nr16: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '8b54aec1-b9a0-41b7-9a2d-766d886cfe50');
delete from public.question_smaczki where question_id = '8b54aec1-b9a0-41b7-9a2d-766d886cfe50';
with ins as (
  insert into public.question_smaczki (question_id, position, is_active) values ('8b54aec1-b9a0-41b7-9a2d-766d886cfe50',1,true),('8b54aec1-b9a0-41b7-9a2d-766d886cfe50',2,true),('8b54aec1-b9a0-41b7-9a2d-766d886cfe50',3,true)
  returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Limit wagi czy wymiarów?'),
  (1,'en','Weight limit, or size?'),
  (2,'pl','Ograniczony komfort osoby obok, która płaci tyle samo'),
  (2,'en','It cramps the person beside you, who paid the same'),
  (3,'pl','Powinny być większe miejsca'),
  (3,'en','Seats should just be bigger')
) as v(position, locale, text) on v.position = ins.position;

-- nr17: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '9dd0395c-604a-4a17-bbdb-7bd45249aaaa');
delete from public.question_smaczki where question_id = '9dd0395c-604a-4a17-bbdb-7bd45249aaaa';
with ins as (
  insert into public.question_smaczki (question_id, position, is_active) values ('9dd0395c-604a-4a17-bbdb-7bd45249aaaa',1,true),('9dd0395c-604a-4a17-bbdb-7bd45249aaaa',2,true)
  returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Depresja czy decyzja?'),
  (1,'en','Depression or decision?'),
  (2,'pl','Psu skracamy cierpienie z litości'),
  (2,'en','We end a dog''s pain out of mercy')
) as v(position, locale, text) on v.position = ins.position;

-- nr18: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'a466cde4-fe77-4696-95c5-03ec9531c5a2');
delete from public.question_smaczki where question_id = 'a466cde4-fe77-4696-95c5-03ec9531c5a2';
with ins as (
  insert into public.question_smaczki (question_id, position, is_active) values ('a466cde4-fe77-4696-95c5-03ec9531c5a2',1,true),('a466cde4-fe77-4696-95c5-03ec9531c5a2',2,true),('a466cde4-fe77-4696-95c5-03ec9531c5a2',3,true)
  returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Ratują gatunki?'),
  (1,'en','Do they save species?'),
  (2,'pl','Sporo zwierząt w zoo, żyłoby lepiej na wolności'),
  (2,'en','Many zoo animals would live better in the wild'),
  (3,'pl','Co z chorymi osobnikami?'),
  (3,'en','What about the sick ones?')
) as v(position, locale, text) on v.position = ins.position;

-- nr19: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'c1118fa8-c151-40c8-88cb-9d870779d444');
delete from public.question_smaczki where question_id = 'c1118fa8-c151-40c8-88cb-9d870779d444';
with ins as (
  insert into public.question_smaczki (question_id, position, is_active) values ('c1118fa8-c151-40c8-88cb-9d870779d444',1,true),('c1118fa8-c151-40c8-88cb-9d870779d444',2,true),('c1118fa8-c151-40c8-88cb-9d870779d444',3,true)
  returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Brak głosu to też głos'),
  (1,'en','Not voting is a vote too'),
  (2,'pl','Głosowanie na ślepo?'),
  (2,'en','Uninformed voters?'),
  (3,'pl','Frekwencja to nie mądrość'),
  (3,'en','Turnout isn''t wisdom')
) as v(position, locale, text) on v.position = ins.position;

-- nr20: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'd493fe32-6a1f-4a33-9e70-ba2358a0650c');
delete from public.question_smaczki where question_id = 'd493fe32-6a1f-4a33-9e70-ba2358a0650c';
with ins as (
  insert into public.question_smaczki (question_id, position, is_active) values ('d493fe32-6a1f-4a33-9e70-ba2358a0650c',1,true),('d493fe32-6a1f-4a33-9e70-ba2358a0650c',2,true),('d493fe32-6a1f-4a33-9e70-ba2358a0650c',3,true)
  returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Zdrowie psychiczne?'),
  (1,'en','Mental health?'),
  (2,'pl','Wyobcowanie nastolatków'),
  (2,'en','It alienates teenagers'),
  (3,'pl','Może jakieś limity?'),
  (3,'en','Maybe some limits, then?')
) as v(position, locale, text) on v.position = ins.position;

-- nr22: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '02451f1e-8961-479d-a886-5903f09429ea');
delete from public.question_smaczki where question_id = '02451f1e-8961-479d-a886-5903f09429ea';
with ins as (
  insert into public.question_smaczki (question_id, position, is_active) values ('02451f1e-8961-479d-a886-5903f09429ea',1,true),('02451f1e-8961-479d-a886-5903f09429ea',2,true),('02451f1e-8961-479d-a886-5903f09429ea',3,true)
  returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','A zaufanie?'),
  (1,'en','And the trust?'),
  (2,'pl','Jak nie ma czego ukryć, to nie ma problemu'),
  (2,'en','Nothing to hide, nothing to fear'),
  (3,'pl','Naruszanie prywatności'),
  (3,'en','An invasion of privacy')
) as v(position, locale, text) on v.position = ins.position;

-- nr24: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '0303b05c-a9b7-483b-b4e0-1f50b5ebce7e');
delete from public.question_smaczki where question_id = '0303b05c-a9b7-483b-b4e0-1f50b5ebce7e';
with ins as (
  insert into public.question_smaczki (question_id, position, is_active) values ('0303b05c-a9b7-483b-b4e0-1f50b5ebce7e',1,true),('0303b05c-a9b7-483b-b4e0-1f50b5ebce7e',2,true)
  returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Prawda za każdą cenę?'),
  (1,'en','Truth at any cost?'),
  (2,'pl','Dla czyjegoś dobra czy dla twojej ulgi?'),
  (2,'en','For someone''s good, or for your relief?')
) as v(position, locale, text) on v.position = ins.position;

-- nr26: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '049e8a14-65b7-466a-b613-f84a0abf80b3');
delete from public.question_smaczki where question_id = '049e8a14-65b7-466a-b613-f84a0abf80b3';
with ins as (
  insert into public.question_smaczki (question_id, position, is_active) values ('049e8a14-65b7-466a-b613-f84a0abf80b3',1,true),('049e8a14-65b7-466a-b613-f84a0abf80b3',2,true),('049e8a14-65b7-466a-b613-f84a0abf80b3',3,true)
  returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Na wszelki wypadek?'),
  (1,'en','Just in case?'),
  (2,'pl','Związek to nie fuzja'),
  (2,'en','Still your own person'),
  (3,'pl','Zaufanie na dowód to już nie zaufanie'),
  (3,'en','Trust that needs proof isn''t trust')
) as v(position, locale, text) on v.position = ins.position;

-- nr28: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '0cebc5c6-3921-417d-870c-5a354b47c6d5');
delete from public.question_smaczki where question_id = '0cebc5c6-3921-417d-870c-5a354b47c6d5';
with ins as (
  insert into public.question_smaczki (question_id, position, is_active) values ('0cebc5c6-3921-417d-870c-5a354b47c6d5',1,true),('0cebc5c6-3921-417d-870c-5a354b47c6d5',2,true)
  returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Gdzie jest granica spokrewnienia?'),
  (1,'en','Where does kinship end?'),
  (2,'pl','Rodzina jest najważniejsza'),
  (2,'en','Family comes first')
) as v(position, locale, text) on v.position = ins.position;

-- nr29: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '0d05b2f0-675e-4523-ba04-3c8b85bf5008');
delete from public.question_smaczki where question_id = '0d05b2f0-675e-4523-ba04-3c8b85bf5008';
with ins as (
  insert into public.question_smaczki (question_id, position, is_active) values ('0d05b2f0-675e-4523-ba04-3c8b85bf5008',1,true),('0d05b2f0-675e-4523-ba04-3c8b85bf5008',2,true),('0d05b2f0-675e-4523-ba04-3c8b85bf5008',3,true)
  returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Dowód, że nam zależy?'),
  (1,'en','Proof that we care?'),
  (2,'pl','W zdrowym związku nie powinno być powodów'),
  (2,'en','A healthy relationship gives no reason to'),
  (3,'pl','Dla jego czy swojego dobra? Tęsknota przed brakiem tej osoby obok'),
  (3,'en','For their good or your own? Missing them before they''re gone')
) as v(position, locale, text) on v.position = ins.position;

-- nr30: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '0d6ae136-c2d7-4ada-959d-60b2d50ed694');
delete from public.question_smaczki where question_id = '0d6ae136-c2d7-4ada-959d-60b2d50ed694';
with ins as (
  insert into public.question_smaczki (question_id, position, is_active) values ('0d6ae136-c2d7-4ada-959d-60b2d50ed694',1,true),('0d6ae136-c2d7-4ada-959d-60b2d50ed694',2,true),('0d6ae136-c2d7-4ada-959d-60b2d50ed694',3,true)
  returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Przyjaciel mówi prawdę'),
  (1,'en','Real friends are honest'),
  (2,'pl','Wyczuj chwilę, przełóż na później'),
  (2,'en','Read the moment, save it for later'),
  (3,'pl','Czasem chcą ucha, nie sędziego'),
  (3,'en','Sometimes they want an ear, not a judge')
) as v(position, locale, text) on v.position = ins.position;

-- 4) Vote seeds (EDIT + LEAVE rows): yes_pct = table value; total = 6 when
--    pct==50 (light 50/50 nudge), else 30.
update public.question_vote_seeds set seed_yes_pct = 38, seed_total = 30 where question_id = '299ccf44-0471-4320-a97f-7bc73e894ca9';  -- nr1
update public.question_vote_seeds set seed_yes_pct = 30, seed_total = 30 where question_id = '57d93dd4-a41f-48cc-8de5-ac2280ea0bd9';  -- nr2
update public.question_vote_seeds set seed_yes_pct = 55, seed_total = 30 where question_id = 'e0734eeb-d0e0-4432-8d37-0bac4257b19f';  -- nr3
update public.question_vote_seeds set seed_yes_pct = 40, seed_total = 30 where question_id = '0d84cbe7-9085-4e16-a6ca-1a43b460b074';  -- nr4
update public.question_vote_seeds set seed_yes_pct = 55, seed_total = 30 where question_id = '16bece38-eb48-4317-bb73-51b3ceb64b0f';  -- nr5
update public.question_vote_seeds set seed_yes_pct = 48, seed_total = 30 where question_id = '23f0212c-93b8-4ac6-beed-b08694b88f7a';  -- nr6
update public.question_vote_seeds set seed_yes_pct = 36, seed_total = 30 where question_id = '3278873d-6d56-4b17-8611-29b8c717b325';  -- nr8
update public.question_vote_seeds set seed_yes_pct = 7, seed_total = 30 where question_id = '3787034d-00af-47cd-8161-413071480d3a';  -- nr9
update public.question_vote_seeds set seed_yes_pct = 14, seed_total = 30 where question_id = '3e6018b0-8701-49d0-996a-3cc54aeb2605';  -- nr10
update public.question_vote_seeds set seed_yes_pct = 22, seed_total = 30 where question_id = '5a11d14b-8587-49a1-a12c-c7a1df4e9e29';  -- nr12
update public.question_vote_seeds set seed_yes_pct = 56, seed_total = 30 where question_id = '5f63e9e9-4b46-49dc-9b4d-290d7b936de5';  -- nr13
update public.question_vote_seeds set seed_yes_pct = 11, seed_total = 30 where question_id = '64942b79-9416-47ca-a4c1-71eabf70c25c';  -- nr14
update public.question_vote_seeds set seed_yes_pct = 68, seed_total = 30 where question_id = '854248e9-f7f6-403d-9179-60845c107d7c';  -- nr15
update public.question_vote_seeds set seed_yes_pct = 50, seed_total = 6 where question_id = '8b54aec1-b9a0-41b7-9a2d-766d886cfe50';  -- nr16
update public.question_vote_seeds set seed_yes_pct = 50, seed_total = 6 where question_id = '9dd0395c-604a-4a17-bbdb-7bd45249aaaa';  -- nr17
update public.question_vote_seeds set seed_yes_pct = 44, seed_total = 30 where question_id = 'a466cde4-fe77-4696-95c5-03ec9531c5a2';  -- nr18
update public.question_vote_seeds set seed_yes_pct = 77, seed_total = 30 where question_id = 'c1118fa8-c151-40c8-88cb-9d870779d444';  -- nr19
update public.question_vote_seeds set seed_yes_pct = 35, seed_total = 30 where question_id = 'd493fe32-6a1f-4a33-9e70-ba2358a0650c';  -- nr20
update public.question_vote_seeds set seed_yes_pct = 33, seed_total = 30 where question_id = '00ffa4ea-a56b-401c-a7d8-f413bb8c988a';  -- nr21
update public.question_vote_seeds set seed_yes_pct = 50, seed_total = 6 where question_id = '02451f1e-8961-479d-a886-5903f09429ea';  -- nr22
update public.question_vote_seeds set seed_yes_pct = 50, seed_total = 6 where question_id = '0303b05c-a9b7-483b-b4e0-1f50b5ebce7e';  -- nr24
update public.question_vote_seeds set seed_yes_pct = 50, seed_total = 6 where question_id = '049e8a14-65b7-466a-b613-f84a0abf80b3';  -- nr26
update public.question_vote_seeds set seed_yes_pct = 50, seed_total = 6 where question_id = '0cebc5c6-3921-417d-870c-5a354b47c6d5';  -- nr28
update public.question_vote_seeds set seed_yes_pct = 50, seed_total = 6 where question_id = '0d05b2f0-675e-4523-ba04-3c8b85bf5008';  -- nr29
update public.question_vote_seeds set seed_yes_pct = 50, seed_total = 6 where question_id = '0d6ae136-c2d7-4ada-959d-60b2d50ed694';  -- nr30

commit;