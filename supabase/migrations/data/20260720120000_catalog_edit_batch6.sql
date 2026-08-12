-- ============================================================================
-- Catalog edit batch 6 (master diff, rows nr 258-320)
-- 24 deletes, 4 question-text edits, 26 smaczki rebuilds. Master is now
-- PL-only (user removed EN + seed columns); EN adapted by assistant.
-- 1 question comma fix (nr271) + 3 smaczek comma fixes. Deletes backed up.
-- ============================================================================
begin;

delete from public.daily_questions where publish_date > (now() at time zone 'utc')::date + 1;

delete from public.daily_questions d
using (values
  ('2cae755a-2e0b-4e1f-bb4b-24bb84b09eef'),
  ('2e5b5233-a995-4d9a-9513-234f898d004f'),
  ('3205f50b-ed69-4021-b7e0-c9c89addce20'),
  ('343b207e-f821-41dc-ab83-120fbe2dfde8'),
  ('39ed09d3-3c70-4981-89b0-913201e093a2'),
  ('3d9f64b4-a4f5-4d12-b389-699870c19e18'),
  ('4136eed0-9962-43a7-b443-fda38826ad88'),
  ('430df1ac-91da-454d-a77d-c89889b19146'),
  ('4321b34a-4f98-4194-bd87-f3c69306a959'),
  ('44aa3257-cee9-4b41-9576-d17417193f15'),
  ('4507f969-b014-4bf3-8a7c-ee1cc7216a73'),
  ('48b92470-f2a3-45e0-9f28-9a03509229ed'),
  ('4d813042-0757-40c0-9388-ae852d43c11b'),
  ('525784cf-e611-431b-8579-b7a4fa6f907f'),
  ('5354f609-8e87-4926-8ca7-19079f837a0c'),
  ('55e461ba-b00c-4d8a-b577-1a53770d0c15'),
  ('57e8c47d-4321-486b-a764-70ff5d86fc1e'),
  ('5992809f-85aa-4cac-860b-4770663c6b97'),
  ('5d6fe76d-334b-4160-8b38-d3e766c9e1dd'),
  ('5eae3cd4-4120-41f2-8cc8-382464802762'),
  ('61185cde-051b-4686-bc35-1db7b533f5dd'),
  ('652f4d70-4c1b-4864-b799-1db3ea9898b0'),
  ('65bda3ae-bd1c-4ea6-b66e-6c64df813c3b'),
  ('67a65eff-a5d4-4a90-8846-cbc7d891c774')
) as del(id)
where d.question_id = del.id::uuid;

delete from public.questions q
using (values
  ('2cae755a-2e0b-4e1f-bb4b-24bb84b09eef'),
  ('2e5b5233-a995-4d9a-9513-234f898d004f'),
  ('3205f50b-ed69-4021-b7e0-c9c89addce20'),
  ('343b207e-f821-41dc-ab83-120fbe2dfde8'),
  ('39ed09d3-3c70-4981-89b0-913201e093a2'),
  ('3d9f64b4-a4f5-4d12-b389-699870c19e18'),
  ('4136eed0-9962-43a7-b443-fda38826ad88'),
  ('430df1ac-91da-454d-a77d-c89889b19146'),
  ('4321b34a-4f98-4194-bd87-f3c69306a959'),
  ('44aa3257-cee9-4b41-9576-d17417193f15'),
  ('4507f969-b014-4bf3-8a7c-ee1cc7216a73'),
  ('48b92470-f2a3-45e0-9f28-9a03509229ed'),
  ('4d813042-0757-40c0-9388-ae852d43c11b'),
  ('525784cf-e611-431b-8579-b7a4fa6f907f'),
  ('5354f609-8e87-4926-8ca7-19079f837a0c'),
  ('55e461ba-b00c-4d8a-b577-1a53770d0c15'),
  ('57e8c47d-4321-486b-a764-70ff5d86fc1e'),
  ('5992809f-85aa-4cac-860b-4770663c6b97'),
  ('5d6fe76d-334b-4160-8b38-d3e766c9e1dd'),
  ('5eae3cd4-4120-41f2-8cc8-382464802762'),
  ('61185cde-051b-4686-bc35-1db7b533f5dd'),
  ('652f4d70-4c1b-4864-b799-1db3ea9898b0'),
  ('65bda3ae-bd1c-4ea6-b66e-6c64df813c3b'),
  ('67a65eff-a5d4-4a90-8846-cbc7d891c774')
) as del(id)
where q.id = del.id::uuid;

with anchor as (select coalesce(max(publish_date), (now() at time zone 'utc')::date) as last_day from public.daily_questions),
pool as (select qq.id, (row_number() over (order by random()))::int as rn from public.questions qq
         where qq.is_active and not exists (select 1 from public.daily_questions d where d.question_id = qq.id))
insert into public.daily_questions (publish_date, question_id)
select (select last_day from anchor) + pool.rn, pool.id from pool;

-- Question text edits.
-- nr258
update public.question_translations set question_text = 'Czy zamieszkanie nowożeńców z rodzicami dla oszczędności to dobry pomysł?' where question_id = '2bf22fc7-41ed-4749-ac7f-598a6f87660e' and locale = 'pl';
update public.question_translations set question_text = 'Is it a good idea for newlyweds to move in with parents to save money?' where question_id = '2bf22fc7-41ed-4749-ac7f-598a6f87660e' and locale = 'en';
-- nr271
update public.question_translations set question_text = 'Czy rodzice, którzy nie jedzą mięsa, powinni wychowywać dziecko na wegetarianina?' where question_id = '37a00851-59ec-4581-a106-cc7e71d58cf8' and locale = 'pl';
update public.question_translations set question_text = 'Should parents who don''t eat meat raise their child as a vegetarian?' where question_id = '37a00851-59ec-4581-a106-cc7e71d58cf8' and locale = 'en';
-- nr277
update public.question_translations set question_text = 'Czy zbiórki na zwierzęta są okej, jeśli jest tyle cierpiących ludzi?' where question_id = '3987e035-7d8c-4700-84e2-10a099672743' and locale = 'pl';
update public.question_translations set question_text = 'Are fundraisers for animals okay when so many people are suffering?' where question_id = '3987e035-7d8c-4700-84e2-10a099672743' and locale = 'en';
-- nr300
update public.question_translations set question_text = 'Czy podczas chudnięcia, kiedykolwiek naprawdę chodzi o zdrowie, a nie wygląd?' where question_id = '53aea1a4-b346-4eb1-8e71-22a507844501' and locale = 'pl';
update public.question_translations set question_text = 'When losing weight, is it ever really about health, not looks?' where question_id = '53aea1a4-b346-4eb1-8e71-22a507844501' and locale = 'en';

-- Smaczki rebuilds.
-- nr261: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '2f01e0ef-c23b-445a-9f90-c140b8d7fa8f');
delete from public.question_smaczki where question_id = '2f01e0ef-c23b-445a-9f90-c140b8d7fa8f';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('2f01e0ef-c23b-445a-9f90-c140b8d7fa8f',1,true),('2f01e0ef-c23b-445a-9f90-c140b8d7fa8f',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Prawo do prywatności?'),(1,'en','A right to privacy?'),
  (2,'pl','Co ukrywa?'),(2,'en','What''s hidden?')
) as v(position, locale, text) on v.position = ins.position;

-- nr269: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '3692c25d-264f-446a-baa7-80ab204393f7');
delete from public.question_smaczki where question_id = '3692c25d-264f-446a-baa7-80ab204393f7';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('3692c25d-264f-446a-baa7-80ab204393f7',1,true),('3692c25d-264f-446a-baa7-80ab204393f7',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Dojrzały i miły?'),(1,'en','Mature and kind?'),
  (2,'pl','Drzwi uchylone?'),(2,'en','Door left open?')
) as v(position, locale, text) on v.position = ins.position;

-- nr270: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '36b67b22-d0f5-4e87-a382-9003e58f775c');
delete from public.question_smaczki where question_id = '36b67b22-d0f5-4e87-a382-9003e58f775c';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('36b67b22-d0f5-4e87-a382-9003e58f775c',1,true),('36b67b22-d0f5-4e87-a382-9003e58f775c',2,true),('36b67b22-d0f5-4e87-a382-9003e58f775c',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Mały klaps nie zrobi krzywdy?'),(1,'en','A little smack does no harm?'),
  (2,'pl','Uczysz strachu?'),(2,'en','Teaching fear?'),
  (3,'pl','Uczysz, że silniejszy ma rację'),(3,'en','You teach that the stronger one wins')
) as v(position, locale, text) on v.position = ins.position;

-- nr271: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '37a00851-59ec-4581-a106-cc7e71d58cf8');
delete from public.question_smaczki where question_id = '37a00851-59ec-4581-a106-cc7e71d58cf8';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('37a00851-59ec-4581-a106-cc7e71d58cf8',1,true),('37a00851-59ec-4581-a106-cc7e71d58cf8',2,true),('37a00851-59ec-4581-a106-cc7e71d58cf8',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Twoje wartości?'),(1,'en','Your values?'),
  (2,'pl','Zastąpisz im jakoś brakujące składniki?'),(2,'en','Will you replace the missing nutrients?'),
  (3,'pl','Mięsożerca też narzuca dziecku dietę'),(3,'en','The meat-eater imposes a diet too')
) as v(position, locale, text) on v.position = ins.position;

-- nr273: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '37bb73fe-e02f-4fb8-87ce-533feafdf686');
delete from public.question_smaczki where question_id = '37bb73fe-e02f-4fb8-87ce-533feafdf686';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('37bb73fe-e02f-4fb8-87ce-533feafdf686',1,true),('37bb73fe-e02f-4fb8-87ce-533feafdf686',2,true),('37bb73fe-e02f-4fb8-87ce-533feafdf686',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Muzyka rozwija?'),(1,'en','Music builds brains?'),
  (2,'pl','Sztuka na siłę?'),(2,'en','Forced art?'),
  (3,'pl','Zmuszony znienawidzi muzykę'),(3,'en','Forced, they''ll come to hate music')
) as v(position, locale, text) on v.position = ins.position;

-- nr274: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '38524108-1cf9-4fdd-9729-eba3f5b8fe41');
delete from public.question_smaczki where question_id = '38524108-1cf9-4fdd-9729-eba3f5b8fe41';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('38524108-1cf9-4fdd-9729-eba3f5b8fe41',1,true),('38524108-1cf9-4fdd-9729-eba3f5b8fe41',2,true),('38524108-1cf9-4fdd-9729-eba3f5b8fe41',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Płaci podatki?'),(1,'en','Does it pay taxes?'),
  (2,'pl','Tylko popisy?'),(2,'en','Just showing off?'),
  (3,'pl','Zazdrość nazywa cudzą pracę zabawą'),(3,'en','Envy calls someone''s work ''just playing''')
) as v(position, locale, text) on v.position = ins.position;

-- nr275: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '38fc2fe2-4dce-4871-892d-f20cef2b5bbf');
delete from public.question_smaczki where question_id = '38fc2fe2-4dce-4871-892d-f20cef2b5bbf';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('38fc2fe2-4dce-4871-892d-f20cef2b5bbf',1,true),('38fc2fe2-4dce-4871-892d-f20cef2b5bbf',2,true),('38fc2fe2-4dce-4871-892d-f20cef2b5bbf',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','W telefonie obecnie jest wszystko'),(1,'en','These days the phone holds everything'),
  (2,'pl','Tylko nawyk?'),(2,'en','Just a habit?'),
  (3,'pl','Jak zgubisz, to panikujesz?'),(3,'en','Lose it and you panic?')
) as v(position, locale, text) on v.position = ins.position;

-- nr277: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '3987e035-7d8c-4700-84e2-10a099672743');
delete from public.question_smaczki where question_id = '3987e035-7d8c-4700-84e2-10a099672743';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('3987e035-7d8c-4700-84e2-10a099672743',1,true),('3987e035-7d8c-4700-84e2-10a099672743',2,true),('3987e035-7d8c-4700-84e2-10a099672743',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Każdy sam decyduje komu pomaga'),(1,'en','Everyone decides who they help'),
  (2,'pl','Dla niektórych życie zwierzęcia jest cenniejsze'),(2,'en','Some value an animal''s life more'),
  (3,'pl','Czy zwierzęta i tak nie powinny żyć dziko, a my je udomowiliśmy i stawiamy nad ludźmi?'),(3,'en','Shouldn''t animals live wild anyway — we tamed them and now put them above people?')
) as v(position, locale, text) on v.position = ins.position;

-- nr281: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '3e61b8d0-76cc-4564-b47c-3fa08c8d5d0b');
delete from public.question_smaczki where question_id = '3e61b8d0-76cc-4564-b47c-3fa08c8d5d0b';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('3e61b8d0-76cc-4564-b47c-3fa08c8d5d0b',1,true),('3e61b8d0-76cc-4564-b47c-3fa08c8d5d0b',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Niech będzie równo?'),(1,'en','Keep it even?'),
  (2,'pl','Żeby nie było niekomfortowo przy dużej dysproporcji?'),(2,'en','To avoid awkwardness when the gap is big?')
) as v(position, locale, text) on v.position = ins.position;

-- nr282: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '3f47055a-8af7-48d0-9258-84ac46951f9f');
delete from public.question_smaczki where question_id = '3f47055a-8af7-48d0-9258-84ac46951f9f';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('3f47055a-8af7-48d0-9258-84ac46951f9f',1,true),('3f47055a-8af7-48d0-9258-84ac46951f9f',2,true),('3f47055a-8af7-48d0-9258-84ac46951f9f',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Ekologia?'),(1,'en','Eco-friendly?'),
  (2,'pl','Kolejny ekran?'),(2,'en','Yet another screen?'),
  (3,'pl','Ekran kusi wszystkim oprócz nauki'),(3,'en','A screen tempts with everything but the lesson')
) as v(position, locale, text) on v.position = ins.position;

-- nr284: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '425a6c8e-2075-49b3-b709-185d1432efaf');
delete from public.question_smaczki where question_id = '425a6c8e-2075-49b3-b709-185d1432efaf';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('425a6c8e-2075-49b3-b709-185d1432efaf',1,true),('425a6c8e-2075-49b3-b709-185d1432efaf',2,true),('425a6c8e-2075-49b3-b709-185d1432efaf',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Kradzież twojej twarzy?'),(1,'en','Stealing your face?'),
  (2,'pl','A jeśli to w niewinnej sprawie?'),(2,'en','And if it''s for something harmless?'),
  (3,'pl','Jutro twoja twarz mówi coś, czego nie powiedziałeś'),(3,'en','Tomorrow your face says things you never said')
) as v(position, locale, text) on v.position = ins.position;

-- nr289: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '457efe46-3d30-46cc-8610-0678e8110c8e');
delete from public.question_smaczki where question_id = '457efe46-3d30-46cc-8610-0678e8110c8e';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('457efe46-3d30-46cc-8610-0678e8110c8e',1,true),('457efe46-3d30-46cc-8610-0678e8110c8e',2,true),('457efe46-3d30-46cc-8610-0678e8110c8e',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','A czy Twój tata ma przyjaciółki?'),(1,'en','Does your dad have female friends?'),
  (2,'pl','Zaufanie czy kontrola?'),(2,'en','Trust or control?'),
  (3,'pl','Czy możesz zakazać im tej relacji?'),(3,'en','Can you forbid them that friendship?')
) as v(position, locale, text) on v.position = ins.position;

-- nr291: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '48ccd4dc-a917-4058-af56-4f5f1c6921d0');
delete from public.question_smaczki where question_id = '48ccd4dc-a917-4058-af56-4f5f1c6921d0';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('48ccd4dc-a917-4058-af56-4f5f1c6921d0',1,true),('48ccd4dc-a917-4058-af56-4f5f1c6921d0',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Nie ma bezinteresowności?'),(1,'en','No truly selfless act?'),
  (2,'pl','Nawet dobry uczynek karmi twoje ego'),(2,'en','Even a good deed feeds your ego')
) as v(position, locale, text) on v.position = ins.position;

-- nr293: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '4b7ea130-d8b0-4ea4-a824-6d7bf9a7e4fb');
delete from public.question_smaczki where question_id = '4b7ea130-d8b0-4ea4-a824-6d7bf9a7e4fb';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('4b7ea130-d8b0-4ea4-a824-6d7bf9a7e4fb',1,true),('4b7ea130-d8b0-4ea4-a824-6d7bf9a7e4fb',2,true),('4b7ea130-d8b0-4ea4-a824-6d7bf9a7e4fb',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Teraz to twoja rodzina?'),(1,'en','They''re your family now?'),
  (2,'pl','Krew się nie zmienia?'),(2,'en','Blood never changes?'),
  (3,'pl','Czy zawsze to zależy od tego, czyje zdanie uznasz za słuszne?'),(3,'en','Does it always come down to whose side you take?')
) as v(position, locale, text) on v.position = ins.position;

-- nr294: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '4bd18d1f-22bf-46df-b004-91a46ffa824e');
delete from public.question_smaczki where question_id = '4bd18d1f-22bf-46df-b004-91a46ffa824e';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('4bd18d1f-22bf-46df-b004-91a46ffa824e',1,true),('4bd18d1f-22bf-46df-b004-91a46ffa824e',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Przekaż wartości?'),(1,'en','Pass on values?'),
  (2,'pl','Niech myślą sami?'),(2,'en','Let them think?')
) as v(position, locale, text) on v.position = ins.position;

-- nr298: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '5307207e-fa56-4066-930a-fb287458a97c');
delete from public.question_smaczki where question_id = '5307207e-fa56-4066-930a-fb287458a97c';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('5307207e-fa56-4066-930a-fb287458a97c',1,true),('5307207e-fa56-4066-930a-fb287458a97c',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Za młodzi, by wiedzieć?'),(1,'en','Too young to know?'),
  (2,'pl','Nie wybierze tego, czego nie zna'),(2,'en','You can''t choose what you''ve never met')
) as v(position, locale, text) on v.position = ins.position;

-- nr302: 1 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '5742276f-2547-4069-9cb1-9e3849cc9bf2');
delete from public.question_smaczki where question_id = '5742276f-2547-4069-9cb1-9e3849cc9bf2';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('5742276f-2547-4069-9cb1-9e3849cc9bf2',1,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Równo to nie zawsze sprawiedliwie'),(1,'en','Equal isn''t always fair')
) as v(position, locale, text) on v.position = ins.position;

-- nr304: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '589fbfde-a1da-4158-9775-83c72c927c1c');
delete from public.question_smaczki where question_id = '589fbfde-a1da-4158-9775-83c72c927c1c';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('589fbfde-a1da-4158-9775-83c72c927c1c',1,true),('589fbfde-a1da-4158-9775-83c72c927c1c',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Czy to dalej dobry uczynek?'),(1,'en','Is it still a good deed?'),
  (2,'pl','Głodnemu obojętne, czemu dostał chleb'),(2,'en','The hungry don''t care why you gave')
) as v(position, locale, text) on v.position = ins.position;

-- nr306: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '5bd9a980-cf4d-41e2-939b-5755921f1b4a');
delete from public.question_smaczki where question_id = '5bd9a980-cf4d-41e2-939b-5755921f1b4a';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('5bd9a980-cf4d-41e2-939b-5755921f1b4a',1,true),('5bd9a980-cf4d-41e2-939b-5755921f1b4a',2,true),('5bd9a980-cf4d-41e2-939b-5755921f1b4a',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Skoro komuś nie zależy, to co za różnica'),(1,'en','If they don''t care, what does it matter?'),
  (2,'pl','A jeśli prawda zaboli?'),(2,'en','And if the truth hurts?'),
  (3,'pl','Jedno zdanie kosztuje mniej niż cisza'),(3,'en','One sentence costs less than silence')
) as v(position, locale, text) on v.position = ins.position;

-- nr309: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '60e12b25-ed5b-43ad-bfa4-7588c5153ff9');
delete from public.question_smaczki where question_id = '60e12b25-ed5b-43ad-bfa4-7588c5153ff9';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('60e12b25-ed5b-43ad-bfa4-7588c5153ff9',1,true),('60e12b25-ed5b-43ad-bfa4-7588c5153ff9',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Zobaczysz śmierć swoich dzieci i wnuków'),(1,'en','You''ll watch your children and grandchildren die'),
  (2,'pl','Bystry umysł w świecie samych obcych'),(2,'en','A sharp mind in a world of strangers')
) as v(position, locale, text) on v.position = ins.position;

-- nr311: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '611b33b3-9a8a-4a68-9e33-589da4452364');
delete from public.question_smaczki where question_id = '611b33b3-9a8a-4a68-9e33-589da4452364';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('611b33b3-9a8a-4a68-9e33-589da4452364',1,true),('611b33b3-9a8a-4a68-9e33-589da4452364',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Zwykła rozmowa, niewinna zabawa'),(1,'en','Just talk, harmless fun'),
  (2,'pl','Robiłbyś to przy partnerze?'),(2,'en','Would you do it with your partner watching?')
) as v(position, locale, text) on v.position = ins.position;

-- nr312: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '646b3e43-1bc3-4cea-a02c-43c87a33f88c');
delete from public.question_smaczki where question_id = '646b3e43-1bc3-4cea-a02c-43c87a33f88c';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('646b3e43-1bc3-4cea-a02c-43c87a33f88c',1,true),('646b3e43-1bc3-4cea-a02c-43c87a33f88c',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Przemoc rodzi przemoc?'),(1,'en','Violence breeds violence?'),
  (2,'pl','Nadstawianie policzka słabo działa na placu zabaw'),(2,'en','Turning the cheek rarely works on the playground')
) as v(position, locale, text) on v.position = ins.position;

-- nr316: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '65cee7c1-3e53-4f8d-80fc-0ae863231417');
delete from public.question_smaczki where question_id = '65cee7c1-3e53-4f8d-80fc-0ae863231417';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('65cee7c1-3e53-4f8d-80fc-0ae863231417',1,true),('65cee7c1-3e53-4f8d-80fc-0ae863231417',2,true),('65cee7c1-3e53-4f8d-80fc-0ae863231417',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Na odpoczynek trzeba zasłużyć?'),(1,'en','Rest is earned?'),
  (2,'pl','Odpoczynek to prawo'),(2,'en','Rest is a right'),
  (3,'pl','Wina to twój szef lub ambicje w twojej głowie'),(3,'en','Blame your boss, or the ambition in your head')
) as v(position, locale, text) on v.position = ins.position;

-- nr317: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '6629c7c4-5f77-43c6-9026-52a2ab29fb75');
delete from public.question_smaczki where question_id = '6629c7c4-5f77-43c6-9026-52a2ab29fb75';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('6629c7c4-5f77-43c6-9026-52a2ab29fb75',1,true),('6629c7c4-5f77-43c6-9026-52a2ab29fb75',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','To kultura'),(1,'en','It''s the culture'),
  (2,'pl','A jeśli starszy sam nie wykazuje szacunku?'),(2,'en','And if the elder shows no respect themselves?')
) as v(position, locale, text) on v.position = ins.position;

-- nr318: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '6734fd1b-a3d7-40b4-a854-5317647899b9');
delete from public.question_smaczki where question_id = '6734fd1b-a3d7-40b4-a854-5317647899b9';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('6734fd1b-a3d7-40b4-a854-5317647899b9',1,true),('6734fd1b-a3d7-40b4-a854-5317647899b9',2,true),('6734fd1b-a3d7-40b4-a854-5317647899b9',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','A jak pozna przyjaznych rówieśników?'),(1,'en','And how will they meet friendly peers?'),
  (2,'pl','Czy jakiś wiek jest granicą?'),(2,'en','Is there an age cutoff?'),
  (3,'pl','Obcego nie wpuścisz drzwiami — a ekranem?'),(3,'en','You''d stop a stranger at the door, not the screen?')
) as v(position, locale, text) on v.position = ins.position;

-- nr320: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '6859c462-8a50-4fc1-9e14-6af69586f798');
delete from public.question_smaczki where question_id = '6859c462-8a50-4fc1-9e14-6af69586f798';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('6859c462-8a50-4fc1-9e14-6af69586f798',1,true),('6859c462-8a50-4fc1-9e14-6af69586f798',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Czemu nie zostać młodym?'),(1,'en','Why not stay young?'),
  (2,'pl','Walka z czasem to wojna zawsze przegrana'),(2,'en','Fighting time is a war you always lose')
) as v(position, locale, text) on v.position = ins.position;

commit;