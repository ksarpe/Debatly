-- ============================================================================
-- Catalog edit batch 8 (master diff, rows nr 321-529)
-- 36 deletes (empty PL / USUŃ), 11 question-text edits, 2 smaczki rebuilds
-- (incl. the 7 edits held back from batch 7 + the 5 deletes then out of range).
-- EN adapted by assistant; 1 PL typo fix (nr322). Deletes backed up.
-- ============================================================================
begin;

delete from public.daily_questions where publish_date > (now() at time zone 'utc')::date + 1;

delete from public.daily_questions d
using (values
  ('e402a38e-633f-42cc-8251-7756c0400019'),
  ('e68bf239-e098-4daf-966d-fd758766dca6'),
  ('ec645746-b016-4516-9c4b-41af1c3e10d5'),
  ('ec97c70f-efb4-4bc1-bef7-3c608ac9f34a'),
  ('ececca63-ddd3-4871-a5c1-83f6a3ff6c95'),
  ('f74f3cac-b191-4a33-90bd-b905c341a71f'),
  ('f9533f20-6a7b-470f-8722-f9ab095a2ed5'),
  ('f95f292b-26cb-45b9-bf75-735df6860465'),
  ('fc687cb0-2f69-4197-b78d-210a671b5c28'),
  ('fc6f0a3c-823d-4f75-a297-f6663e594a2a'),
  ('fca22e3b-02a5-44a5-9e75-828afb059441'),
  ('016b91dd-fa80-4899-94d0-8848b9043500'),
  ('04ca9179-d021-49e9-932c-48038c76b7ca'),
  ('09731586-b88c-41c8-8cf1-ed82f35e88d1'),
  ('0b04cce4-28a3-45b8-9dc0-92abaa2d3c3e'),
  ('15011519-df22-4e83-84d6-4be52c22c56b'),
  ('1b98f1ff-8c76-4a16-a520-50ee8262a150'),
  ('1d2dc7e1-34d0-4f6c-9b4e-a66ddc6aa444'),
  ('2003a419-90e7-49b1-a4fa-4d119ef052f8'),
  ('25d0c411-a76a-4cd0-bb92-31818e930d66'),
  ('29d606bb-c5bf-4869-8cda-bd6c883afb1c'),
  ('2a008e4f-12f7-4aff-991e-fcc202dbf757'),
  ('359108e8-d19f-483e-b106-0a98e70ed83f'),
  ('35b85aec-8185-4e6d-bc6e-d39d0e6f9271'),
  ('3af35b32-f545-428b-8429-be3289e919d6'),
  ('3b6ed1dc-917a-4abd-9ae3-a3350d4c0cd5'),
  ('4eb63992-02c1-474a-a7e9-cf3463578813'),
  ('4fe50e94-f67d-406f-9808-74e214a32b13'),
  ('5c1564fb-79f1-4e6d-9aa1-40c5950ed5c2'),
  ('5ea7d3ec-614e-45d8-a172-9510c7312a6c'),
  ('5f701e61-63f0-4282-b96e-e6b794b86351'),
  ('5fec28a5-0a4a-4c7c-bc4a-eaed8ec0cd37'),
  ('65d27eda-38ec-4af8-8907-feec04ace3fb'),
  ('6f255059-4740-4d5c-a862-8a8e74a109f6'),
  ('74dd3544-752d-42a8-90d5-f478c8ea4f3f'),
  ('7adb04ce-2a0f-4792-a47c-3b30515585b5')
) as del(id)
where d.question_id = del.id::uuid;

delete from public.questions q
using (values
  ('e402a38e-633f-42cc-8251-7756c0400019'),
  ('e68bf239-e098-4daf-966d-fd758766dca6'),
  ('ec645746-b016-4516-9c4b-41af1c3e10d5'),
  ('ec97c70f-efb4-4bc1-bef7-3c608ac9f34a'),
  ('ececca63-ddd3-4871-a5c1-83f6a3ff6c95'),
  ('f74f3cac-b191-4a33-90bd-b905c341a71f'),
  ('f9533f20-6a7b-470f-8722-f9ab095a2ed5'),
  ('f95f292b-26cb-45b9-bf75-735df6860465'),
  ('fc687cb0-2f69-4197-b78d-210a671b5c28'),
  ('fc6f0a3c-823d-4f75-a297-f6663e594a2a'),
  ('fca22e3b-02a5-44a5-9e75-828afb059441'),
  ('016b91dd-fa80-4899-94d0-8848b9043500'),
  ('04ca9179-d021-49e9-932c-48038c76b7ca'),
  ('09731586-b88c-41c8-8cf1-ed82f35e88d1'),
  ('0b04cce4-28a3-45b8-9dc0-92abaa2d3c3e'),
  ('15011519-df22-4e83-84d6-4be52c22c56b'),
  ('1b98f1ff-8c76-4a16-a520-50ee8262a150'),
  ('1d2dc7e1-34d0-4f6c-9b4e-a66ddc6aa444'),
  ('2003a419-90e7-49b1-a4fa-4d119ef052f8'),
  ('25d0c411-a76a-4cd0-bb92-31818e930d66'),
  ('29d606bb-c5bf-4869-8cda-bd6c883afb1c'),
  ('2a008e4f-12f7-4aff-991e-fcc202dbf757'),
  ('359108e8-d19f-483e-b106-0a98e70ed83f'),
  ('35b85aec-8185-4e6d-bc6e-d39d0e6f9271'),
  ('3af35b32-f545-428b-8429-be3289e919d6'),
  ('3b6ed1dc-917a-4abd-9ae3-a3350d4c0cd5'),
  ('4eb63992-02c1-474a-a7e9-cf3463578813'),
  ('4fe50e94-f67d-406f-9808-74e214a32b13'),
  ('5c1564fb-79f1-4e6d-9aa1-40c5950ed5c2'),
  ('5ea7d3ec-614e-45d8-a172-9510c7312a6c'),
  ('5f701e61-63f0-4282-b96e-e6b794b86351'),
  ('5fec28a5-0a4a-4c7c-bc4a-eaed8ec0cd37'),
  ('65d27eda-38ec-4af8-8907-feec04ace3fb'),
  ('6f255059-4740-4d5c-a862-8a8e74a109f6'),
  ('74dd3544-752d-42a8-90d5-f478c8ea4f3f'),
  ('7adb04ce-2a0f-4792-a47c-3b30515585b5')
) as del(id)
where q.id = del.id::uuid;

with anchor as (select coalesce(max(publish_date), (now() at time zone 'utc')::date) as last_day from public.daily_questions),
pool as (select qq.id, (row_number() over (order by random()))::int as rn from public.questions qq
         where qq.is_active and not exists (select 1 from public.daily_questions d where d.question_id = qq.id))
insert into public.daily_questions (publish_date, question_id)
select (select last_day from anchor) + pool.rn, pool.id from pool;

-- Question text edits.
-- nr325
update public.question_translations set question_text = 'Czy przeprowadziłbyś się daleko od bliskich dla znacznie lepszej pracy?' where question_id = '6c53b79c-d322-4958-9d52-24a3dce28086' and locale = 'pl';
update public.question_translations set question_text = 'Would you move far from everyone you love for a much better job?' where question_id = '6c53b79c-d322-4958-9d52-24a3dce28086' and locale = 'en';
-- nr352
update public.question_translations set question_text = 'Czy powinieneś sprawdzić media społecznościowe swojej randki przed spotkaniem?' where question_id = '8ace3238-9a3d-4f28-8b9e-30a5e609b951' and locale = 'pl';
update public.question_translations set question_text = 'Should you check your date''s social media before meeting them?' where question_id = '8ace3238-9a3d-4f28-8b9e-30a5e609b951' and locale = 'en';
-- nr355
update public.question_translations set question_text = 'Czy napiwek to bardziej kwestia presji niż prawdziwej wdzięczności?' where question_id = '8bb89650-4998-4b4e-bbc7-551ec3acf582' and locale = 'pl';
update public.question_translations set question_text = 'Is tipping more about pressure than genuine gratitude?' where question_id = '8bb89650-4998-4b4e-bbc7-551ec3acf582' and locale = 'en';
-- nr356
update public.question_translations set question_text = 'Czy wolno podarować komuś innemu prezent, którego nigdy i tak nie użyjesz?' where question_id = '8d8a3afd-057e-4855-8fe6-8a53d4a3c553' and locale = 'pl';
update public.question_translations set question_text = 'Is it okay to regift a present you''ll never use anyway?' where question_id = '8d8a3afd-057e-4855-8fe6-8a53d4a3c553' and locale = 'en';
-- nr393
update public.question_translations set question_text = 'Czy wrzucanie mocno podrasowanych zdjęć na profil randkowy jest okej?' where question_id = 'b3a20f43-0175-4337-a3aa-e6c6325fa16b' and locale = 'pl';
update public.question_translations set question_text = 'Is it okay to use heavily edited photos on a dating profile?' where question_id = 'b3a20f43-0175-4337-a3aa-e6c6325fa16b' and locale = 'en';
-- nr412
update public.question_translations set question_text = 'Czy okej jest trzymać przy sobie bliskiego przyjaciela, którego partner nie znosi?' where question_id = 'c3bf47e9-e170-4bce-9929-17c798882f2f' and locale = 'pl';
update public.question_translations set question_text = 'Is it okay to keep a close friend your partner can''t stand?' where question_id = 'c3bf47e9-e170-4bce-9929-17c798882f2f' and locale = 'en';
-- nr465
update public.question_translations set question_text = 'Czy rodzice powinni kłócić się przy dzieciach?' where question_id = '0145b20a-9712-4a1a-bb3f-161d9c95dae2' and locale = 'pl';
update public.question_translations set question_text = 'Should parents argue in front of their children?' where question_id = '0145b20a-9712-4a1a-bb3f-161d9c95dae2' and locale = 'en';
-- nr469
update public.question_translations set question_text = 'Czy dziadkowie wtrącający się w wychowanie wnuków robią prawidłowo?' where question_id = '042e19ca-778b-40a0-bec8-8f00358fe4ba' and locale = 'pl';
update public.question_translations set question_text = 'Are grandparents who meddle in raising the grandchildren in the right?' where question_id = '042e19ca-778b-40a0-bec8-8f00358fe4ba' and locale = 'en';
-- nr473
update public.question_translations set question_text = 'Czy powinieneś kogoś zaprosić tylko dlatego, że on zaprosił ciebie?' where question_id = '09fa3aba-692e-4f5f-a941-82ad0eb16c98' and locale = 'pl';
update public.question_translations set question_text = 'Should you invite someone just because they invited you?' where question_id = '09fa3aba-692e-4f5f-a941-82ad0eb16c98' and locale = 'en';
-- nr475
update public.question_translations set question_text = 'Czy kradzież od złodzieja to wciąż kradzież?' where question_id = '0d3ace6b-e176-4e00-9cbf-72392068bbc4' and locale = 'pl';
update public.question_translations set question_text = 'Is stealing from a thief still stealing?' where question_id = '0d3ace6b-e176-4e00-9cbf-72392068bbc4' and locale = 'en';
-- nr503
update public.question_translations set question_text = 'Czy strach przed samotnością to wystarczający powód, by trwać w związku?' where question_id = '3d409cbf-f14c-4ff3-b6d8-e2d684a68ebb' and locale = 'pl';
update public.question_translations set question_text = 'Is fear of being alone a good enough reason to stay in a relationship?' where question_id = '3d409cbf-f14c-4ff3-b6d8-e2d684a68ebb' and locale = 'en';

-- Smaczki rebuilds.
-- nr322: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '69d6ba84-e33b-4ff4-8d82-3acf69835863');
delete from public.question_smaczki where question_id = '69d6ba84-e33b-4ff4-8d82-3acf69835863';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('69d6ba84-e33b-4ff4-8d82-3acf69835863',1,true),('69d6ba84-e33b-4ff4-8d82-3acf69835863',2,true),('69d6ba84-e33b-4ff4-8d82-3acf69835863',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Skakanie z pracy do pracy skreśla Cię u innych pracodawców'),(1,'en','Job-hopping counts against you with other employers'),
  (2,'pl','Żadna praca nie będzie cieszyć 24/7'),(2,'en','No job is a joy 24/7'),
  (3,'pl','Ciągła ucieczka to też nawyk'),(3,'en','Always fleeing is a habit too')
) as v(position, locale, text) on v.position = ins.position;

-- nr325: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '6c53b79c-d322-4958-9d52-24a3dce28086');
delete from public.question_smaczki where question_id = '6c53b79c-d322-4958-9d52-24a3dce28086';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('6c53b79c-d322-4958-9d52-24a3dce28086',1,true),('6c53b79c-d322-4958-9d52-24a3dce28086',2,true),('6c53b79c-d322-4958-9d52-24a3dce28086',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Może to złoty strzał?'),(1,'en','Maybe it''s the jackpot?'),
  (2,'pl','Awans zostaje, ludzie się rozchodzą'),(2,'en','The promotion stays; the people drift'),
  (3,'pl','A może odwrotnie - Kasa się znudzi, a ludzi już nie będzie'),(3,'en','Or the reverse — the money palls and the people are gone')
) as v(position, locale, text) on v.position = ins.position;

commit;