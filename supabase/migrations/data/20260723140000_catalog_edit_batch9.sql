-- ============================================================================
-- Catalog edit batch 9 (master diff, rows nr 530-717)
-- 99 deletes (empty PL), 16 question-text edits, 8 smaczki rebuilds.
-- EN adapted by assistant; 3 question + 7 smaczek PL comma/typo fixes.
-- Deletes backed up to *_batch9.backup.json.
-- ============================================================================
begin;

delete from public.daily_questions where publish_date > (now() at time zone 'utc')::date + 1;

delete from public.daily_questions d
using (values
  ('7dc5db30-839f-4d14-8eec-030cc5886c95'),
  ('7e8a142f-5e4b-43a6-bf8e-aeadfebb729c'),
  ('88a4c160-0cc2-47c7-8611-96268faef632'),
  ('8bbe89f3-b725-40a8-8fda-031aad5e494f'),
  ('9de27eec-05cf-4cf3-8954-7772df29dead'),
  ('a6472189-e97c-42da-99cc-13323a75e8c6'),
  ('ad436399-1cde-4ba8-8cd4-586c0e523c42'),
  ('ad93ff0f-fe2b-49d5-a5ea-f30f301cb742'),
  ('b491345a-4ee0-49ce-badd-3ff784f52253'),
  ('b49d42f0-e441-4a12-b320-86cc5b891dea'),
  ('b7139359-3b20-40c0-ab17-b2880077887e'),
  ('b8028b59-c592-4e05-b83d-d87955f4ce10'),
  ('bbf0a758-8b1f-4ab0-8c01-043b544ad64e'),
  ('c1c86351-e71e-45f6-9254-519fa6b3f073'),
  ('c5c145e0-952d-40ac-90c4-376b85f6b95f'),
  ('ca94ee28-4bae-429f-826f-368f4eefc492'),
  ('d57624e6-b901-4055-b905-35d5fc135af9'),
  ('d752385d-1ff6-4c0b-8ee8-b1871dabb672'),
  ('dfcd5e34-7c10-4bab-a3b0-b5c9d140c967'),
  ('e3b31915-201a-4999-8820-063b6d18a8e4'),
  ('e4c4fd65-a7fd-4289-a403-ed1b2be96d4a'),
  ('e661c104-f6d3-49cd-b6d0-351cbf929317'),
  ('e6bae5e1-abc8-421f-be33-0245527750b5'),
  ('ebb1f6d1-2a4a-4cd3-ac8a-62fa0f6f2ad8'),
  ('f141e7dc-57c1-4eea-9d9c-353ef17428d8'),
  ('f67f1701-879b-4583-9ada-811e3067817a'),
  ('ff0078b6-c11f-40d9-8b15-8925ac1fd4d7'),
  ('0c203d0a-b96a-4a5c-9626-72474b5bfefe'),
  ('11ef1b20-2a2d-4919-803b-0d4b1a4d9cab'),
  ('144b0fce-4346-4a2a-8c2e-6a149f955287'),
  ('1632a454-1e85-494c-a147-e61f1850d7a6'),
  ('1beae3f0-7d54-40c5-90d6-ec5fe6684b16'),
  ('1dbc36e1-f86c-43d3-92e2-f0e2fa33b7bf'),
  ('216a719b-6e13-40bc-a529-2ed1fb7c8f81'),
  ('26263240-518f-4153-b9b2-ca8fb747120b'),
  ('2709dc4f-916a-4e71-8f39-bfdc2c1c97cb'),
  ('2950d1f5-5844-444e-8ca3-6c516b321d77'),
  ('2de2eecb-ce26-4089-892b-20e544fea324'),
  ('3631474c-cbdc-49f2-a3eb-2ff542b79f3d'),
  ('46f5cbf0-519e-45a9-915c-22f14fcc64c5'),
  ('4e7832e2-4c29-4f3f-b623-2505bdfcc9d9'),
  ('50e1e09f-4f3e-43dd-b996-3e6156fbc222'),
  ('51d2f5ee-5e70-42d9-a3fc-7e294f91272d'),
  ('57ce9fe6-67d3-4611-9c2e-7851411be60e'),
  ('57d5cbd4-3867-486e-bdf6-e05745632f55'),
  ('59b75d2e-3ddf-4820-adab-6264b2b00794'),
  ('5f3ab678-5a27-435c-a4ef-639311591645'),
  ('6409ca56-e73d-42a3-bbfe-13b92ae9d28d'),
  ('64a7474e-ae72-40fc-ab9d-80ef6d6cd032'),
  ('69cb4878-0c56-4121-ab9c-99f8a30853c7'),
  ('6aec2e85-424d-48fc-bbe1-d0ece0670582'),
  ('6c2eba48-4180-4f69-b963-fa7717d79489'),
  ('6ef197e4-9e08-4830-afaf-3453ce8861c1'),
  ('768fa565-a819-4c71-b75c-766b6d15bfc4'),
  ('78f7cf87-c17f-4830-bf5d-b9e981671746'),
  ('84cf7494-ead3-4c21-8193-3fc221ec2059'),
  ('88e1fd57-de94-4901-a5de-0af952a7c884'),
  ('91175581-1fd0-4a26-97f8-9574063cc40c'),
  ('9252c3d5-708b-4b16-afde-057483272104'),
  ('96263303-3192-45b1-9b83-a7500021affa'),
  ('9c13f95f-4b11-452f-b07d-09cb3dcc44b1'),
  ('a5a5c83a-8b1c-4023-bd4e-ae18c6d5e751'),
  ('a81e62c5-bc8d-4b4a-a40a-3438d85af403'),
  ('aab7f5b7-0a64-45a1-8052-260523474723'),
  ('ad5df2ff-8674-4ab5-8136-37a41e8dd1e5'),
  ('ade1ce86-d909-40f1-abec-837deb8e2c3b'),
  ('b046c69e-5baa-4bbe-bc99-5e717f1aa1ad'),
  ('b193511b-fae5-4ede-91f6-7fc7cd53c974'),
  ('b1d5b385-15d5-4ae1-a305-33c1ef85f17f'),
  ('ba5d1571-7092-4420-bf2b-33ef70219f68'),
  ('c21571d4-8e27-451a-9f27-4a967ec8fe84'),
  ('c2d30b5a-a69a-4f80-9f02-8faf202cbaac'),
  ('c3a23d16-eaff-4620-a236-2f541ec89c21'),
  ('c5e8c488-d800-4a02-95ad-fa29bb554dfa'),
  ('c7207bee-de67-4632-bb3e-afe354a3fb35'),
  ('c7fba7c5-d4c0-4013-827b-694f1fe3409d'),
  ('c9e1232c-3719-4030-ba5b-1f7500bc2008'),
  ('c9fe7c50-ab87-4e26-8fdf-9d8badeb2913'),
  ('cb867236-141b-4487-94f5-ebf978afc04b'),
  ('cd093aac-2979-4cad-b678-0a7fda3f5872'),
  ('d0f42db8-785c-4a4b-9a36-e671e8b22b73'),
  ('d35712e2-2666-4a05-9184-5332323f330a'),
  ('d6ebf7dc-83f0-4de0-98f6-5ecd094b95c4'),
  ('d71f8984-8ea7-436e-a2fd-836fae33c0e4'),
  ('dae679cc-991f-46d6-a1c5-566a811e06e6'),
  ('dbf2b0c2-ec9e-40e1-95ef-8e1167c5bdbe'),
  ('dbf70431-99e8-4042-b27f-efed710d7fbe'),
  ('decb78a5-6c35-402d-a823-4944d3e0e2b6'),
  ('e436137b-9d6d-4033-907e-c1d1cc5480e4'),
  ('e993f9fa-cc26-423a-b8f5-37d40cf2d310'),
  ('ea57ca51-2196-481c-9ef9-7372a4e33d1d'),
  ('ebbc39fe-7f77-4a9e-8ba7-b63cad6adc1c'),
  ('ed5c7fcf-499e-4133-803d-34bc3fd1ddb6'),
  ('edd7401b-4d2d-43ac-ab1a-609041dd7813'),
  ('f27b0638-bb16-4e8e-aa60-20d3e5f32331'),
  ('f30a1323-aa9f-4ea8-ac47-cc5fbba2d105'),
  ('f99ffcdb-2edc-4bac-839f-deefe684964c'),
  ('00d969dc-ba8e-4970-a4a0-5ba174052ccb'),
  ('0112dde5-e816-4ed1-b2fd-2b9bee6c635b')
) as del(id)
where d.question_id = del.id::uuid;

delete from public.questions q
using (values
  ('7dc5db30-839f-4d14-8eec-030cc5886c95'),
  ('7e8a142f-5e4b-43a6-bf8e-aeadfebb729c'),
  ('88a4c160-0cc2-47c7-8611-96268faef632'),
  ('8bbe89f3-b725-40a8-8fda-031aad5e494f'),
  ('9de27eec-05cf-4cf3-8954-7772df29dead'),
  ('a6472189-e97c-42da-99cc-13323a75e8c6'),
  ('ad436399-1cde-4ba8-8cd4-586c0e523c42'),
  ('ad93ff0f-fe2b-49d5-a5ea-f30f301cb742'),
  ('b491345a-4ee0-49ce-badd-3ff784f52253'),
  ('b49d42f0-e441-4a12-b320-86cc5b891dea'),
  ('b7139359-3b20-40c0-ab17-b2880077887e'),
  ('b8028b59-c592-4e05-b83d-d87955f4ce10'),
  ('bbf0a758-8b1f-4ab0-8c01-043b544ad64e'),
  ('c1c86351-e71e-45f6-9254-519fa6b3f073'),
  ('c5c145e0-952d-40ac-90c4-376b85f6b95f'),
  ('ca94ee28-4bae-429f-826f-368f4eefc492'),
  ('d57624e6-b901-4055-b905-35d5fc135af9'),
  ('d752385d-1ff6-4c0b-8ee8-b1871dabb672'),
  ('dfcd5e34-7c10-4bab-a3b0-b5c9d140c967'),
  ('e3b31915-201a-4999-8820-063b6d18a8e4'),
  ('e4c4fd65-a7fd-4289-a403-ed1b2be96d4a'),
  ('e661c104-f6d3-49cd-b6d0-351cbf929317'),
  ('e6bae5e1-abc8-421f-be33-0245527750b5'),
  ('ebb1f6d1-2a4a-4cd3-ac8a-62fa0f6f2ad8'),
  ('f141e7dc-57c1-4eea-9d9c-353ef17428d8'),
  ('f67f1701-879b-4583-9ada-811e3067817a'),
  ('ff0078b6-c11f-40d9-8b15-8925ac1fd4d7'),
  ('0c203d0a-b96a-4a5c-9626-72474b5bfefe'),
  ('11ef1b20-2a2d-4919-803b-0d4b1a4d9cab'),
  ('144b0fce-4346-4a2a-8c2e-6a149f955287'),
  ('1632a454-1e85-494c-a147-e61f1850d7a6'),
  ('1beae3f0-7d54-40c5-90d6-ec5fe6684b16'),
  ('1dbc36e1-f86c-43d3-92e2-f0e2fa33b7bf'),
  ('216a719b-6e13-40bc-a529-2ed1fb7c8f81'),
  ('26263240-518f-4153-b9b2-ca8fb747120b'),
  ('2709dc4f-916a-4e71-8f39-bfdc2c1c97cb'),
  ('2950d1f5-5844-444e-8ca3-6c516b321d77'),
  ('2de2eecb-ce26-4089-892b-20e544fea324'),
  ('3631474c-cbdc-49f2-a3eb-2ff542b79f3d'),
  ('46f5cbf0-519e-45a9-915c-22f14fcc64c5'),
  ('4e7832e2-4c29-4f3f-b623-2505bdfcc9d9'),
  ('50e1e09f-4f3e-43dd-b996-3e6156fbc222'),
  ('51d2f5ee-5e70-42d9-a3fc-7e294f91272d'),
  ('57ce9fe6-67d3-4611-9c2e-7851411be60e'),
  ('57d5cbd4-3867-486e-bdf6-e05745632f55'),
  ('59b75d2e-3ddf-4820-adab-6264b2b00794'),
  ('5f3ab678-5a27-435c-a4ef-639311591645'),
  ('6409ca56-e73d-42a3-bbfe-13b92ae9d28d'),
  ('64a7474e-ae72-40fc-ab9d-80ef6d6cd032'),
  ('69cb4878-0c56-4121-ab9c-99f8a30853c7'),
  ('6aec2e85-424d-48fc-bbe1-d0ece0670582'),
  ('6c2eba48-4180-4f69-b963-fa7717d79489'),
  ('6ef197e4-9e08-4830-afaf-3453ce8861c1'),
  ('768fa565-a819-4c71-b75c-766b6d15bfc4'),
  ('78f7cf87-c17f-4830-bf5d-b9e981671746'),
  ('84cf7494-ead3-4c21-8193-3fc221ec2059'),
  ('88e1fd57-de94-4901-a5de-0af952a7c884'),
  ('91175581-1fd0-4a26-97f8-9574063cc40c'),
  ('9252c3d5-708b-4b16-afde-057483272104'),
  ('96263303-3192-45b1-9b83-a7500021affa'),
  ('9c13f95f-4b11-452f-b07d-09cb3dcc44b1'),
  ('a5a5c83a-8b1c-4023-bd4e-ae18c6d5e751'),
  ('a81e62c5-bc8d-4b4a-a40a-3438d85af403'),
  ('aab7f5b7-0a64-45a1-8052-260523474723'),
  ('ad5df2ff-8674-4ab5-8136-37a41e8dd1e5'),
  ('ade1ce86-d909-40f1-abec-837deb8e2c3b'),
  ('b046c69e-5baa-4bbe-bc99-5e717f1aa1ad'),
  ('b193511b-fae5-4ede-91f6-7fc7cd53c974'),
  ('b1d5b385-15d5-4ae1-a305-33c1ef85f17f'),
  ('ba5d1571-7092-4420-bf2b-33ef70219f68'),
  ('c21571d4-8e27-451a-9f27-4a967ec8fe84'),
  ('c2d30b5a-a69a-4f80-9f02-8faf202cbaac'),
  ('c3a23d16-eaff-4620-a236-2f541ec89c21'),
  ('c5e8c488-d800-4a02-95ad-fa29bb554dfa'),
  ('c7207bee-de67-4632-bb3e-afe354a3fb35'),
  ('c7fba7c5-d4c0-4013-827b-694f1fe3409d'),
  ('c9e1232c-3719-4030-ba5b-1f7500bc2008'),
  ('c9fe7c50-ab87-4e26-8fdf-9d8badeb2913'),
  ('cb867236-141b-4487-94f5-ebf978afc04b'),
  ('cd093aac-2979-4cad-b678-0a7fda3f5872'),
  ('d0f42db8-785c-4a4b-9a36-e671e8b22b73'),
  ('d35712e2-2666-4a05-9184-5332323f330a'),
  ('d6ebf7dc-83f0-4de0-98f6-5ecd094b95c4'),
  ('d71f8984-8ea7-436e-a2fd-836fae33c0e4'),
  ('dae679cc-991f-46d6-a1c5-566a811e06e6'),
  ('dbf2b0c2-ec9e-40e1-95ef-8e1167c5bdbe'),
  ('dbf70431-99e8-4042-b27f-efed710d7fbe'),
  ('decb78a5-6c35-402d-a823-4944d3e0e2b6'),
  ('e436137b-9d6d-4033-907e-c1d1cc5480e4'),
  ('e993f9fa-cc26-423a-b8f5-37d40cf2d310'),
  ('ea57ca51-2196-481c-9ef9-7372a4e33d1d'),
  ('ebbc39fe-7f77-4a9e-8ba7-b63cad6adc1c'),
  ('ed5c7fcf-499e-4133-803d-34bc3fd1ddb6'),
  ('edd7401b-4d2d-43ac-ab1a-609041dd7813'),
  ('f27b0638-bb16-4e8e-aa60-20d3e5f32331'),
  ('f30a1323-aa9f-4ea8-ac47-cc5fbba2d105'),
  ('f99ffcdb-2edc-4bac-839f-deefe684964c'),
  ('00d969dc-ba8e-4970-a4a0-5ba174052ccb'),
  ('0112dde5-e816-4ed1-b2fd-2b9bee6c635b')
) as del(id)
where q.id = del.id::uuid;

with anchor as (select coalesce(max(publish_date), (now() at time zone 'utc')::date) as last_day from public.daily_questions),
pool as (select qq.id, (row_number() over (order by random()))::int as rn from public.questions qq
         where qq.is_active and not exists (select 1 from public.daily_questions d where d.question_id = qq.id))
insert into public.daily_questions (publish_date, question_id)
select (select last_day from anchor) + pool.rn, pool.id from pool;

-- Question text edits.
-- nr532
update public.question_translations set question_text = 'Czy powinno się bronić nieobecnego przyjaciela, gdy inni z niego szydzą?' where question_id = '7fdb6c85-23e8-47be-856d-224111532583' and locale = 'pl';
update public.question_translations set question_text = 'Should you defend an absent friend when others mock them?' where question_id = '7fdb6c85-23e8-47be-856d-224111532583' and locale = 'en';
-- nr535
update public.question_translations set question_text = 'Czy kupowanie podróbek znanych marek jest okej?' where question_id = '83286336-efa8-4c58-9691-b8ba7256ae78' and locale = 'pl';
update public.question_translations set question_text = 'Is buying fake designer goods okay?' where question_id = '83286336-efa8-4c58-9691-b8ba7256ae78' and locale = 'en';
-- nr540
update public.question_translations set question_text = 'Czy bardzo starzy, już niegroźni więźniowie powinni wyjść i umrzeć ze starości na wolności?' where question_id = '96a4efd0-648f-40da-a6cd-4890ad94149f' and locale = 'pl';
update public.question_translations set question_text = 'Should very old prisoners who pose no danger be released to die of old age in freedom?' where question_id = '96a4efd0-648f-40da-a6cd-4890ad94149f' and locale = 'en';
-- nr562
update public.question_translations set question_text = 'Czy powinno się przyznać do jednego pocałunku, który nic nie znaczył?' where question_id = 'c13c5312-6db7-4f88-b4c0-e23b91d77759' and locale = 'pl';
update public.question_translations set question_text = 'Should you confess a one-time kiss that meant nothing?' where question_id = 'c13c5312-6db7-4f88-b4c0-e23b91d77759' and locale = 'en';
-- nr574
update public.question_translations set question_text = 'Czy przyjąłbyś fortunę, gdyby zginął za nią obcy, którego nigdy nie widziałeś?' where question_id = 'e1ce4566-c89d-4632-a6a9-480ee7d7a43f' and locale = 'pl';
update public.question_translations set question_text = 'Would you accept a fortune if a stranger you''d never seen died for it?' where question_id = 'e1ce4566-c89d-4632-a6a9-480ee7d7a43f' and locale = 'en';
-- nr585
update public.question_translations set question_text = 'Czy lepiej jest zdradzić dwa razy z tą samą osobą niż dwa razy z kimś innym?' where question_id = 'f9de71d8-32da-457f-abbd-75687c4420af' and locale = 'pl';
update public.question_translations set question_text = 'Is cheating twice with the same person better than twice with different people?' where question_id = 'f9de71d8-32da-457f-abbd-75687c4420af' and locale = 'en';
-- nr590
update public.question_translations set question_text = 'Czy bardziej się martwimy codziennością przez to, że media pokazują głównie złą stronę świata?' where question_id = '0799d16c-1190-414e-bb15-47d4fc1b11f9' and locale = 'pl';
update public.question_translations set question_text = 'Do we worry more about daily life because the media mostly shows the world''s bad side?' where question_id = '0799d16c-1190-414e-bb15-47d4fc1b11f9' and locale = 'en';
-- nr596
update public.question_translations set question_text = 'Czy powinniśmy mieć możliwość zabrać wszystko, co znajdziemy np. w swoim ogrodzie?' where question_id = '1ac184ba-5d97-4cd3-a3ba-c0d0ecd0b1d6' and locale = 'pl';
update public.question_translations set question_text = 'Should we be allowed to keep anything we find, say, in our own garden?' where question_id = '1ac184ba-5d97-4cd3-a3ba-c0d0ecd0b1d6' and locale = 'en';
-- nr610
update public.question_translations set question_text = 'Czy podkoloryzowałeś kiedyś swoje CV?' where question_id = '3135cc77-14be-4818-b3c6-03d9bba7cebf' and locale = 'pl';
update public.question_translations set question_text = 'Have you ever stretched the truth on your CV?' where question_id = '3135cc77-14be-4818-b3c6-03d9bba7cebf' and locale = 'en';
-- nr614
update public.question_translations set question_text = 'Czy reklamy alkoholu powinny być w ogóle gdziekolwiek dozwolone?' where question_id = '3ef40b09-7423-40f9-a059-53b6680e1e54' and locale = 'pl';
update public.question_translations set question_text = 'Should alcohol ads be allowed anywhere at all?' where question_id = '3ef40b09-7423-40f9-a059-53b6680e1e54' and locale = 'en';
-- nr616
update public.question_translations set question_text = 'Czy reklamy powinny zawierać drastyczne obrazki?' where question_id = '45cbaf5e-93b7-4aa3-ae80-22627cac1f75' and locale = 'pl';
update public.question_translations set question_text = 'Should ads be allowed to use graphic images?' where question_id = '45cbaf5e-93b7-4aa3-ae80-22627cac1f75' and locale = 'en';
-- nr619
update public.question_translations set question_text = 'Czy branie pieniędzy od rodziców w dorosłości to wstyd?' where question_id = '4d395dc7-c802-4bdd-9eca-11db068166f4' and locale = 'pl';
update public.question_translations set question_text = 'Is taking money from your parents as an adult shameful?' where question_id = '4d395dc7-c802-4bdd-9eca-11db068166f4' and locale = 'en';
-- nr647
update public.question_translations set question_text = 'Czy młodsi pacjenci powinni mieć pierwszeństwo, gdy brakuje narządów do przeszczepienia?' where question_id = '85715093-650a-46ae-8077-0904e4e7a935' and locale = 'pl';
update public.question_translations set question_text = 'Should younger patients come first when there aren''t enough organs for transplant?' where question_id = '85715093-650a-46ae-8077-0904e4e7a935' and locale = 'en';
-- nr661
update public.question_translations set question_text = 'Czy świat jest niesprawiedliwie urządzony pod poranne wstawanie?' where question_id = '9f6f19cd-013c-4db2-ba4f-02a52a13baa2' and locale = 'pl';
update public.question_translations set question_text = 'Is the world unfairly built around early rising?' where question_id = '9f6f19cd-013c-4db2-ba4f-02a52a13baa2' and locale = 'en';
-- nr676
update public.question_translations set question_text = 'Jeżeli potwierdziłeś obecność na weselu, ale się na nim nie zjawiłeś, to czy parze młodej należy się koperta?' where question_id = 'bf68fff5-0a93-4cc8-89d3-4598e749c416' and locale = 'pl';
update public.question_translations set question_text = 'If you RSVP''d to a wedding but never showed up, do the newlyweds still deserve a cash gift?' where question_id = 'bf68fff5-0a93-4cc8-89d3-4598e749c416' and locale = 'en';
-- nr703
update public.question_translations set question_text = 'Czy powrót co roku w to samo miejsce na wakacje to zmarnowany urlop?' where question_id = 'e41e2dea-d0e8-4a57-912b-21e911f67999' and locale = 'pl';
update public.question_translations set question_text = 'Is going back to the same holiday spot every year a wasted vacation?' where question_id = 'e41e2dea-d0e8-4a57-912b-21e911f67999' and locale = 'en';

-- Smaczki rebuilds.
-- nr535: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '83286336-efa8-4c58-9691-b8ba7256ae78');
delete from public.question_smaczki where question_id = '83286336-efa8-4c58-9691-b8ba7256ae78';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('83286336-efa8-4c58-9691-b8ba7256ae78',1,true),('83286336-efa8-4c58-9691-b8ba7256ae78',2,true),('83286336-efa8-4c58-9691-b8ba7256ae78',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Przecież i tak ktoś to kupi'),(1,'en','Someone will buy it anyway'),
  (2,'pl','Ktoś stworzył oryginał'),(2,'en','Someone made the real thing'),
  (3,'pl','Za podróbką często stoi praca dzieci'),(3,'en','Behind the fake is often child labor')
) as v(position, locale, text) on v.position = ins.position;

-- nr585: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'f9de71d8-32da-457f-abbd-75687c4420af');
delete from public.question_smaczki where question_id = 'f9de71d8-32da-457f-abbd-75687c4420af';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('f9de71d8-32da-457f-abbd-75687c4420af',1,true),('f9de71d8-32da-457f-abbd-75687c4420af',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Łatwiej powtórzyć z jedną, bo już się znacie'),(1,'en','Easier to repeat with one — you already know each other'),
  (2,'pl','Z dwoma innymi już świadczy o Twoim charakterze'),(2,'en','Twice with different people says something about you')
) as v(position, locale, text) on v.position = ins.position;

-- nr590: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '0799d16c-1190-414e-bb15-47d4fc1b11f9');
delete from public.question_smaczki where question_id = '0799d16c-1190-414e-bb15-47d4fc1b11f9';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('0799d16c-1190-414e-bb15-47d4fc1b11f9',1,true),('0799d16c-1190-414e-bb15-47d4fc1b11f9',2,true),('0799d16c-1190-414e-bb15-47d4fc1b11f9',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Jak człowiek nie wie, to się mniej martwi'),(1,'en','What you don''t know, you don''t worry about'),
  (2,'pl','Bylibyśmy mniej uważni, gdyby omijało nas to, co się dzieje na świecie'),(2,'en','We''d be less alert if the world''s news passed us by'),
  (3,'pl','Jedna wspominka o wojnie, a Ty już spakowany?'),(3,'en','One mention of war and you''re already packed?')
) as v(position, locale, text) on v.position = ins.position;

-- nr596: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '1ac184ba-5d97-4cd3-a3ba-c0d0ecd0b1d6');
delete from public.question_smaczki where question_id = '1ac184ba-5d97-4cd3-a3ba-c0d0ecd0b1d6';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('1ac184ba-5d97-4cd3-a3ba-c0d0ecd0b1d6',1,true),('1ac184ba-5d97-4cd3-a3ba-c0d0ecd0b1d6',2,true),('1ac184ba-5d97-4cd3-a3ba-c0d0ecd0b1d6',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Dlaczego państwo może Ci to zabrać?'),(1,'en','Why can the state take it from you?'),
  (2,'pl','Historia należy do wszystkich'),(2,'en','History belongs to everyone'),
  (3,'pl','„Dla wszystkich" znaczy zwykle: w naszym muzeum'),(3,'en','''For everyone'' usually means in our museum')
) as v(position, locale, text) on v.position = ins.position;

-- nr614: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '3ef40b09-7423-40f9-a059-53b6680e1e54');
delete from public.question_smaczki where question_id = '3ef40b09-7423-40f9-a059-53b6680e1e54';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('3ef40b09-7423-40f9-a059-53b6680e1e54',1,true),('3ef40b09-7423-40f9-a059-53b6680e1e54',2,true),('3ef40b09-7423-40f9-a059-53b6680e1e54',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Po co reklamować coś, co niszczy ludzi?'),(1,'en','Why advertise something that ruins people?'),
  (2,'pl','Każdy chce zarobić'),(2,'en','Everyone wants to earn'),
  (3,'pl','Widzą to nawet dzieci'),(3,'en','Even children see it')
) as v(position, locale, text) on v.position = ins.position;

-- nr618: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '485d9bb9-0d83-42df-a03c-5232ee5ad1b1');
delete from public.question_smaczki where question_id = '485d9bb9-0d83-42df-a03c-5232ee5ad1b1';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('485d9bb9-0d83-42df-a03c-5232ee5ad1b1',1,true),('485d9bb9-0d83-42df-a03c-5232ee5ad1b1',2,true),('485d9bb9-0d83-42df-a03c-5232ee5ad1b1',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Zapracuj jak każdy'),(1,'en','Earn it like everyone else'),
  (2,'pl','Nikt nie musi wpłacać'),(2,'en','No one has to give'),
  (3,'pl','Są poważniejsze zbiórki, jak np. chore dzieci'),(3,'en','There are graver causes — sick children, for one')
) as v(position, locale, text) on v.position = ins.position;

-- nr676: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'bf68fff5-0a93-4cc8-89d3-4598e749c416');
delete from public.question_smaczki where question_id = 'bf68fff5-0a93-4cc8-89d3-4598e749c416';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('bf68fff5-0a93-4cc8-89d3-4598e749c416',1,true),('bf68fff5-0a93-4cc8-89d3-4598e749c416',2,true),('bf68fff5-0a93-4cc8-89d3-4598e749c416',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Zapłacili za talerzyk, powinieneś im to zwrócić'),(1,'en','They paid for your plate — pay it back'),
  (2,'pl','Brak obecności = brak prezentu'),(2,'en','No show, no gift'),
  (3,'pl','Może symboliczny prezent?'),(3,'en','Maybe a token gift?')
) as v(position, locale, text) on v.position = ins.position;

-- nr683: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'c6f8dffe-4b13-4d60-a38e-a4592f391e1e');
delete from public.question_smaczki where question_id = 'c6f8dffe-4b13-4d60-a38e-a4592f391e1e';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('c6f8dffe-4b13-4d60-a38e-a4592f391e1e',1,true),('c6f8dffe-4b13-4d60-a38e-a4592f391e1e',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Jeden zły dzień zwraca wszystko'),(1,'en','One bad day repays it all'),
  (2,'pl','Sprzedają ci spokój, na którym zarabiają'),(2,'en','They sell you a calm they profit from')
) as v(position, locale, text) on v.position = ins.position;

commit;