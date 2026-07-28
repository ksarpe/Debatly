-- ============================================================================
-- Catalog edit batch 10 (master diff, rows nr 718-800)
-- 51 deletes (empty PL), 6 question-text edits, 1 smaczki rebuild.
-- EN adapted by assistant; 1 question comma fix (nr774).
-- Deletes backed up to *_batch10.backup.json.
-- ============================================================================
begin;

delete from public.daily_questions where publish_date > (now() at time zone 'utc')::date + 1;

delete from public.daily_questions d
using (values
  ('043a138a-941c-466e-a366-57f9195c1030'),
  ('04a28993-3e6a-451f-9fef-4fd6bc7d006d'),
  ('04d06e74-bab1-4311-ae47-b3370a48567f'),
  ('0bfed230-2483-451a-ab72-8c506361d15b'),
  ('190935a8-1f7c-4e5b-89de-99e9be4ee1c7'),
  ('1a70dabc-1867-481e-b435-32b9fcde6771'),
  ('1af7d72c-bb3b-4584-a185-65783bfd8fdc'),
  ('1cce1527-55e2-47f1-a434-401e0442e7d1'),
  ('1cf2e6df-365c-40d0-b8c3-157184852e87'),
  ('242f76e6-a585-4c50-a71e-f4bc39f85164'),
  ('28ca3573-b027-44d6-8856-fa85f9803252'),
  ('2b6e7460-ef6e-46d0-8b3e-5eec705ee223'),
  ('2b80e965-11e8-4059-8e78-b257e2c1af01'),
  ('2dfeb0e1-aae7-4c0c-b370-b8f586870e8b'),
  ('2e49d45b-940d-4a89-a657-5cf0252bdbd9'),
  ('2f7dc8d1-e4f7-4ec9-8c33-7a5d0e51d027'),
  ('30810951-7228-47c7-b567-11ffa42e6bc7'),
  ('4567a5da-a4d3-4d59-b759-2c579e672709'),
  ('4a2ad90b-9680-44f0-a2af-18b1bb940520'),
  ('4bbcfc87-ee7a-4641-8ba0-55317d7b6d21'),
  ('58e41c2f-89f9-4b62-9291-71171ce17239'),
  ('5b3e9dd9-6e04-49cc-9e27-0555a099c5c8'),
  ('6936d4fa-cebb-488f-98d0-b4630d68e7fe'),
  ('6e65162c-e16b-4983-a648-c0628c742984'),
  ('6efc88f5-0b5d-42f3-a150-0804a1f1c564'),
  ('789a4f7d-42f2-41dd-a732-fb7f9da879d9'),
  ('79c4daae-f485-40e4-8e2a-43c17e2594b0'),
  ('7a7ae81b-5e95-4780-a8f2-deef6d74c306'),
  ('7fde4f2d-b522-400e-8760-9332abe4486b'),
  ('81daf510-2f8a-40ef-ba0c-bca1838db5d8'),
  ('81fa382a-35a0-476c-90eb-57383b6159f7'),
  ('842344a3-ee9f-4243-a561-97bbd46f0404'),
  ('854dfbb2-dfc6-4e43-bd6e-477898269801'),
  ('87877972-c051-4145-a61d-5fd727af9677'),
  ('8e6be412-c00d-447c-8be0-2f61b0066935'),
  ('8f1aeb86-31f3-4088-a3dc-6196d609b18a'),
  ('932e0f56-0858-46b7-b01d-eaa5773c4bb1'),
  ('953f3615-a290-4dd0-8fc9-94499ede19b8'),
  ('978c57b8-3661-4261-a6bf-775d8e2fc45a'),
  ('982bbbb6-92eb-4217-868a-25f5bb2d4f29'),
  ('9d881f58-1820-410b-bde4-e664e124bd32'),
  ('9dcaaba8-bf8a-4ca9-a8ad-98251de3be97'),
  ('9e612283-ce96-4566-85e5-ac1c7db2a9b0'),
  ('a3812e42-dfd0-4f23-8633-c5f2d93b6ada'),
  ('a3b99e21-2528-4d97-8159-57db8b543816'),
  ('a744323e-5107-498a-a3f4-f4c2eaf59130'),
  ('a91f8cab-3ede-4341-9a8a-c92bb99c4593'),
  ('aacff73a-42ad-4bf9-92d3-40917db66d69'),
  ('abd8ae51-bf6c-4ff3-a560-ae1b640c896a'),
  ('b7a26c3c-e0d6-466d-88af-52f36da31654'),
  ('b87ac3fc-210c-4f54-93f4-fdd45bdf42ad')
) as del(id)
where d.question_id = del.id::uuid;

delete from public.questions q
using (values
  ('043a138a-941c-466e-a366-57f9195c1030'),
  ('04a28993-3e6a-451f-9fef-4fd6bc7d006d'),
  ('04d06e74-bab1-4311-ae47-b3370a48567f'),
  ('0bfed230-2483-451a-ab72-8c506361d15b'),
  ('190935a8-1f7c-4e5b-89de-99e9be4ee1c7'),
  ('1a70dabc-1867-481e-b435-32b9fcde6771'),
  ('1af7d72c-bb3b-4584-a185-65783bfd8fdc'),
  ('1cce1527-55e2-47f1-a434-401e0442e7d1'),
  ('1cf2e6df-365c-40d0-b8c3-157184852e87'),
  ('242f76e6-a585-4c50-a71e-f4bc39f85164'),
  ('28ca3573-b027-44d6-8856-fa85f9803252'),
  ('2b6e7460-ef6e-46d0-8b3e-5eec705ee223'),
  ('2b80e965-11e8-4059-8e78-b257e2c1af01'),
  ('2dfeb0e1-aae7-4c0c-b370-b8f586870e8b'),
  ('2e49d45b-940d-4a89-a657-5cf0252bdbd9'),
  ('2f7dc8d1-e4f7-4ec9-8c33-7a5d0e51d027'),
  ('30810951-7228-47c7-b567-11ffa42e6bc7'),
  ('4567a5da-a4d3-4d59-b759-2c579e672709'),
  ('4a2ad90b-9680-44f0-a2af-18b1bb940520'),
  ('4bbcfc87-ee7a-4641-8ba0-55317d7b6d21'),
  ('58e41c2f-89f9-4b62-9291-71171ce17239'),
  ('5b3e9dd9-6e04-49cc-9e27-0555a099c5c8'),
  ('6936d4fa-cebb-488f-98d0-b4630d68e7fe'),
  ('6e65162c-e16b-4983-a648-c0628c742984'),
  ('6efc88f5-0b5d-42f3-a150-0804a1f1c564'),
  ('789a4f7d-42f2-41dd-a732-fb7f9da879d9'),
  ('79c4daae-f485-40e4-8e2a-43c17e2594b0'),
  ('7a7ae81b-5e95-4780-a8f2-deef6d74c306'),
  ('7fde4f2d-b522-400e-8760-9332abe4486b'),
  ('81daf510-2f8a-40ef-ba0c-bca1838db5d8'),
  ('81fa382a-35a0-476c-90eb-57383b6159f7'),
  ('842344a3-ee9f-4243-a561-97bbd46f0404'),
  ('854dfbb2-dfc6-4e43-bd6e-477898269801'),
  ('87877972-c051-4145-a61d-5fd727af9677'),
  ('8e6be412-c00d-447c-8be0-2f61b0066935'),
  ('8f1aeb86-31f3-4088-a3dc-6196d609b18a'),
  ('932e0f56-0858-46b7-b01d-eaa5773c4bb1'),
  ('953f3615-a290-4dd0-8fc9-94499ede19b8'),
  ('978c57b8-3661-4261-a6bf-775d8e2fc45a'),
  ('982bbbb6-92eb-4217-868a-25f5bb2d4f29'),
  ('9d881f58-1820-410b-bde4-e664e124bd32'),
  ('9dcaaba8-bf8a-4ca9-a8ad-98251de3be97'),
  ('9e612283-ce96-4566-85e5-ac1c7db2a9b0'),
  ('a3812e42-dfd0-4f23-8633-c5f2d93b6ada'),
  ('a3b99e21-2528-4d97-8159-57db8b543816'),
  ('a744323e-5107-498a-a3f4-f4c2eaf59130'),
  ('a91f8cab-3ede-4341-9a8a-c92bb99c4593'),
  ('aacff73a-42ad-4bf9-92d3-40917db66d69'),
  ('abd8ae51-bf6c-4ff3-a560-ae1b640c896a'),
  ('b7a26c3c-e0d6-466d-88af-52f36da31654'),
  ('b87ac3fc-210c-4f54-93f4-fdd45bdf42ad')
) as del(id)
where q.id = del.id::uuid;

with anchor as (select coalesce(max(publish_date), (now() at time zone 'utc')::date) as last_day from public.daily_questions),
pool as (select qq.id, (row_number() over (order by random()))::int as rn from public.questions qq
         where qq.is_active and not exists (select 1 from public.daily_questions d where d.question_id = qq.id))
insert into public.daily_questions (publish_date, question_id)
select (select last_day from anchor) + pool.rn, pool.id from pool;

-- Question text edits.
-- nr726
update public.question_translations set question_text = 'Czy nazwanie dziecka własnym imieniem to jest w porządku?' where question_id = '1488c33f-e736-4b66-b7e5-f483705e077a' and locale = 'pl';
update public.question_translations set question_text = 'Is naming your child after yourself okay?' where question_id = '1488c33f-e736-4b66-b7e5-f483705e077a' and locale = 'en';
-- nr752
update public.question_translations set question_text = 'Czy kac z własnej winy zasługuje na zwolnienie lekarskie?' where question_id = '5e189d64-9881-45c3-afcc-d7557779676f' and locale = 'pl';
update public.question_translations set question_text = 'Does a self-inflicted hangover deserve a sick day?' where question_id = '5e189d64-9881-45c3-afcc-d7557779676f' and locale = 'en';
-- nr763
update public.question_translations set question_text = 'Czy wydawanie fortuny na hobby, które nic nie zarabia, to dobra praktyka?' where question_id = '7c70b3f4-d1b5-4956-a624-1b1ee7e1c379' and locale = 'pl';
update public.question_translations set question_text = 'Is spending a fortune on a hobby that earns nothing a good practice?' where question_id = '7c70b3f4-d1b5-4956-a624-1b1ee7e1c379' and locale = 'en';
-- nr764
update public.question_translations set question_text = 'Czy poprawianie czyichś błędów językowych w pół opowieści jest niegrzeczne?' where question_id = '7c8369b8-065c-470e-b5c7-cb6ecc02c16b' and locale = 'pl';
update public.question_translations set question_text = 'Is correcting someone''s grammar mid-story rude?' where question_id = '7c8369b8-065c-470e-b5c7-cb6ecc02c16b' and locale = 'en';
-- nr774
update public.question_translations set question_text = 'Czy firmy powinny mieć obowiązek dokładnego wyjaśnienia, dlaczego kandydat nie został przyjęty?' where question_id = '91314ad4-dfd3-405f-9b7a-e2351630edff' and locale = 'pl';
update public.question_translations set question_text = 'Should companies be required to explain exactly why a candidate was rejected?' where question_id = '91314ad4-dfd3-405f-9b7a-e2351630edff' and locale = 'en';
-- nr787
update public.question_translations set question_text = 'Czy dbanie o formę i zdrowie to obowiązek wobec tych, którzy cię kochają?' where question_id = 'a44ab29a-95f1-46b9-bf02-d4dbf469b6eb' and locale = 'pl';
update public.question_translations set question_text = 'Is staying fit and healthy a duty you owe the people who love you?' where question_id = 'a44ab29a-95f1-46b9-bf02-d4dbf469b6eb' and locale = 'en';

-- Smaczki rebuilds.
-- nr743: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '3a62eefa-65bb-4dc6-95ed-e50b6341e215');
delete from public.question_smaczki where question_id = '3a62eefa-65bb-4dc6-95ed-e50b6341e215';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('3a62eefa-65bb-4dc6-95ed-e50b6341e215',1,true),('3a62eefa-65bb-4dc6-95ed-e50b6341e215',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Tanie rzeczy żyją krótko z definicji'),(1,'en','Cheap things live short lives by design'),
  (2,'pl','Psują się celowo, byś kupił drugi raz'),(2,'en','Built to break so you buy it twice')
) as v(position, locale, text) on v.position = ins.position;

commit;