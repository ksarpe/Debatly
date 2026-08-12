-- ============================================================================
-- Catalog edit batch 11 — FINAL (master diff, rows nr 801-982)
-- 114 deletes (empty PL), 12 question-text edits, 9 smaczki rebuilds.
-- EN adapted by assistant; 2 question + 4 smaczek PL punctuation fixes.
-- Completes the full catalog pass (1000 -> final count).
-- Deletes backed up to *_batch11.backup.json.
-- ============================================================================
begin;

create temporary table _del11 (id uuid) on commit drop;
insert into _del11 (id) select unnest(array[
  'bb4e4efc-1e27-46a9-be1e-ee70a0b8d76f',
  'c06941b9-3075-4f7d-9239-49459d890b12',
  'c20db688-4bdb-423c-a525-ee365af447ae',
  'c5f8d056-ee4e-4c87-ab5c-92f7a37ed52c',
  'c5fd35c7-93d4-47b9-b148-26828b9efaca',
  'cac7e931-3d6a-4f7c-a8c5-cbdded9baaeb',
  'cfa552aa-fc3f-433b-8124-f69f7b74297f',
  'd4bdc7be-d214-4d4e-bfed-ba1e88b787a4',
  'd56af368-1c3d-4762-9377-5d4269a27282',
  'd7287d9c-298f-41ce-b35e-af2b840d38c8',
  'd8084a49-053d-4c24-b551-0641cbbefa01',
  'd90b8030-002f-4e2b-a3fa-e284d21c3c0d',
  'da42fcab-6688-468e-8db5-3698af198b07',
  'dab8dd41-b4a0-475a-ae28-b748d8bc04b8',
  'df4ee062-8f72-40d7-90c9-b70caa23893c',
  'e2551641-6197-4736-bc19-20194c50d16d',
  'e821933a-9c00-4468-acdb-7236fcb21d37',
  'e82215f1-a981-47ee-81be-2cfc71f84b24',
  'ead948de-5036-401f-8762-d034a770ab34',
  'f0cdbc0b-47ad-4638-a33e-a0a20bf4c5f9',
  'f2cc84d6-53e6-4d97-9fae-d14c01ec496f',
  'f72d3e65-095c-499b-a972-f880787d7f81',
  'fdfd239b-f6c4-485c-bbdb-d40d5f6394a3',
  'fedb8e94-4b26-4bad-b52b-da1efc37f358',
  '08211ec2-c9dd-419c-9baa-5d0ee879f510',
  '0a700d15-f20d-42c1-b6fe-3e687734d23d',
  '0ae68f07-eec1-4b77-b542-4ccbd813a894',
  '0b48efe8-c066-46cc-8f52-7c649e958289',
  '0bf3777c-422c-46d4-a9ab-1c5b5d6727f8',
  '0cae6a80-cf77-4b16-97c7-9607525c15d7',
  '10f6e134-fed8-4711-931f-25afaa44cd34',
  '11a6329f-492f-4af2-88aa-345016b443d6',
  '12cb7f67-6ff5-4da7-a7ed-6306d66be824',
  '1334f6cc-2113-498b-9eb0-49e6ca365736',
  '144aa97d-99d7-4f60-b8df-6fa16872f348',
  '146edf06-a4f1-42c2-9667-6625aa3abb0e',
  '1707506b-9809-483a-a6a5-7c92577aefad',
  '17bc3fc0-0d2f-447d-8176-0d61f2219db5',
  '1d30d24c-0ccb-4822-8dde-92ae390228e1',
  '23bdace2-50ad-4bb1-91d2-ec21120cd669',
  '250ad385-dd05-45cc-9281-78c3cac849ce',
  '27e77f1d-b1ee-436e-a248-df812c8fe0ff',
  '31103edd-0a9f-4942-a91d-7e0f40956914',
  '33b7f4e0-9de3-4772-b96a-1860cfbb76f5',
  '3e5bfa40-2e2d-4a1c-8aba-c1e29c46983c',
  '46926320-952d-494b-ba4b-1e7ef5af24fc',
  '485f569e-92d1-48b4-9c9b-b1c51b0d5711',
  '5017ef33-7df4-425c-8d37-3ac320b61641',
  '5b3f8dfc-ca8e-4182-8084-e2b84492fe60',
  '5ba50285-51ee-4395-a231-3561db52cc2a',
  '6317d6de-2087-4d38-88eb-ca01f43767a8',
  '6727f4ae-3ad9-4dec-a7cb-dac78f20bb5e',
  '689a7e91-94f5-4d31-bb6d-3997d49a39fb',
  '6d95c0df-5f9a-40b9-b31d-58d2b01eef18',
  '728f8750-94d4-4c59-a764-8111ef18d416',
  '7b45bc16-7077-4daf-8a14-8910fc341003',
  '7b9105a4-1308-4e54-9648-2548aecf4133',
  '7bedeb6a-55ec-4ff3-9d25-42d4654671de',
  '808a33d4-9d47-49d5-93ce-5632394c1c7b',
  '80b95b7a-591e-40ef-83f3-2108b4ba9391',
  '81e40acc-4f6e-44c7-a895-4971f34f6c6c',
  '83f022cd-8f44-4bfd-960c-b7ef58d00eeb',
  '86465249-cdc4-4e56-b9f2-a32ba0624c53',
  '881ecff9-7402-4151-80e2-7cf3cbdddcb7',
  '88bf5f56-5597-4ee5-8888-0e21dd9f8379',
  '8a7a363a-cdbf-4a0c-b614-4e574b01f098',
  '8da0f2f4-e793-441c-a37e-05a5e946876a',
  '967423a8-85d2-408b-b3f9-8b10a1911792',
  '969582a8-d82e-40af-b4dc-1e3bf5d81489',
  'a8096fc6-7c14-4a4e-a944-9a923c48c24c',
  'a8db6c87-9cb9-4884-8270-7ffa32181d01',
  'a9f5d390-84cf-4692-9490-06e8642be60d',
  'ab2bb157-e70a-4bd5-9d91-49f2bf553d32',
  'b15ecec3-247c-42dd-bce2-fc6823ca8c0b',
  'b3063c81-8080-40e6-96a8-fd659977ba08',
  'bb9cd554-c2e7-4ac5-a8d2-4170af1c1ed5',
  'bd9d1893-193b-47c6-85a2-b604b64f1dc1',
  'c1909efa-47f7-4f55-9400-45173b659456',
  'c690161e-9251-4843-9ef5-d352689af760',
  'ca544ed2-8694-4f8b-83de-dded107222f8',
  'd0229a15-34ab-46f3-85a1-8021a035801b',
  'd14f8d93-51a9-4205-b33d-4d934704ad11',
  'd29914e1-efe0-4ccd-a584-5ef2a2093750',
  'd9e56493-a0da-4af7-8003-95b744fc55fc',
  'db263ba8-84f4-4bdf-b369-2e7249924bad',
  'dd18f4d5-7e27-4878-85e2-7d64efc2bec2',
  'e01539d1-423d-4acd-90f8-fced3ac87850',
  'e0896fa1-12ac-47e8-bc6d-8368401a8ea3',
  'e1eb77cc-c04a-4f37-bd13-8064f542600d',
  'e2d9ad87-2c5f-49cd-a4f7-d363d0c5174c',
  'e8be4cbf-09a5-486f-9592-3f0a01d99c1c',
  'e9580e42-36ca-405a-b5e2-1a10eda8ae3d',
  'ea3224b5-6feb-4bc7-92fe-90cda1f218c9',
  'ea4322c5-ba07-44ce-a93d-0e02b248fc76',
  'ef342a96-08b0-4b51-9e35-e133325463e2',
  'f01ab1e9-46e2-41d5-b2c9-98321eeaea56',
  'f0b9d5b4-f941-4e18-b2db-d72b0a68fd31',
  'f5ed6a22-fdad-424b-8a7c-1d796e8a7f63',
  'fb49d79a-02cf-4b97-963d-0a6fb79714bc',
  'fe4303b4-f486-4cfe-a432-bf913164b5fe',
  'fff0489b-0003-4a0c-b77e-ad6064423dd5',
  '1c720059-efaa-4f46-9cc0-32e17316e188',
  '26e486fa-69a2-4235-8409-a11cdc446046',
  '4dbbb0fd-66c4-43ed-8100-aaa508730949',
  '6ac80494-cf8b-4275-a970-803d7ba1f486',
  '7ffbed14-3a16-4811-8fa7-f10b1a6ba8d6',
  '80639910-8e56-4dea-9d85-9d3cd2bc03b8',
  '871ae119-0b90-404e-a4bc-838ca0a4d3b7',
  '98a7be46-518b-48fe-8ba1-9f36ab3cb28e',
  'a11ed0b6-816d-45cd-9dd2-9ef41e993621',
  'b4a36dfc-101f-4a66-b2fe-a9c82feeb6b0',
  'b5da072b-24e2-4298-9c5e-96dad6994bc3',
  'ecad5eaf-a542-48b2-8e01-c144eeca7212',
  'ee0e3aeb-08d6-403b-bf05-1d226e010d6a'
]::uuid[]);

delete from public.daily_questions where publish_date > (now() at time zone 'utc')::date + 1;
delete from public.daily_questions d using _del11 t where d.question_id = t.id;
delete from public.questions qq using _del11 t where qq.id = t.id;

with anchor as (select coalesce(max(publish_date), (now() at time zone 'utc')::date) as last_day from public.daily_questions),
pool as (select q2.id, (row_number() over (order by random()))::int as rn from public.questions q2
         where q2.is_active and not exists (select 1 from public.daily_questions d where d.question_id = q2.id))
insert into public.daily_questions (publish_date, question_id)
select (select last_day from anchor) + pool.rn, pool.id from pool;

-- Question text edits.
-- nr807
update public.question_translations set question_text = 'Czy zgadzasz się z tym, że jedno ze swoich dzieci zawsze kocha się bardziej?' where question_id = 'ca0d4287-c37f-41e3-8319-d6076e04858f' and locale = 'pl';
update public.question_translations set question_text = 'Do you agree that a parent always loves one of their children more?' where question_id = 'ca0d4287-c37f-41e3-8319-d6076e04858f' and locale = 'en';
-- nr810
update public.question_translations set question_text = 'Czy to hipokryzja oceniać innych, że kupują drogie ubrania i samochody, samemu posiadając najnowszy telefon?' where question_id = 'ceb4be50-405f-4e46-8ff0-fb963bd4f18f' and locale = 'pl';
update public.question_translations set question_text = 'Is it hypocrisy to judge people for expensive clothes and cars while owning the newest phone?' where question_id = 'ceb4be50-405f-4e46-8ff0-fb963bd4f18f' and locale = 'en';
-- nr813
update public.question_translations set question_text = 'Czy ukochane stare filmy powinno się zostawić w spokoju zamiast robić remaki?' where question_id = 'd2e8d529-b9b5-4ae8-91b7-f50a1ebe4cd6' and locale = 'pl';
update public.question_translations set question_text = 'Should beloved old films be left alone rather than remade?' where question_id = 'd2e8d529-b9b5-4ae8-91b7-f50a1ebe4cd6' and locale = 'en';
-- nr825
update public.question_translations set question_text = 'Czy powinniśmy udawać zachwyt prezentem, który ci się nie podoba?' where question_id = 'e0fdf1a3-2103-45b7-b9cc-6b9327623c9a' and locale = 'pl';
update public.question_translations set question_text = 'Should you pretend to love a gift you hate?' where question_id = 'e0fdf1a3-2103-45b7-b9cc-6b9327623c9a' and locale = 'en';
-- nr828
update public.question_translations set question_text = 'Czy stare książki powinno się redagować, usuwając słowa, które dziś są uznawane za obraźliwe?' where question_id = 'e4e2352f-ba76-48b9-a51f-5da945c6cc3f' and locale = 'pl';
update public.question_translations set question_text = 'Should old books be edited to remove words now considered offensive?' where question_id = 'e4e2352f-ba76-48b9-a51f-5da945c6cc3f' and locale = 'en';
-- nr831
update public.question_translations set question_text = 'Czy potrzebujemy głośnego pogrzebu i wielkiego, drogiego pomnika?' where question_id = 'e8c2ba33-57b1-4c1b-b464-6bd792f60687' and locale = 'pl';
update public.question_translations set question_text = 'Do we need a loud funeral and a big, expensive headstone?' where question_id = 'e8c2ba33-57b1-4c1b-b464-6bd792f60687' and locale = 'en';
-- nr871
update public.question_translations set question_text = 'Czy myślisz, że porzuciłbyś przyjaciół, gdybyś wygrał w loterii duże pieniądze?' where question_id = '459bcb33-4d62-4eab-9c55-354ee531145c' and locale = 'pl';
update public.question_translations set question_text = 'Do you think you''d drop your friends if you won big on the lottery?' where question_id = '459bcb33-4d62-4eab-9c55-354ee531145c' and locale = 'en';
-- nr881
update public.question_translations set question_text = 'Czy rodzic powinien zeznawać przeciwko dziecku?' where question_id = '59396fb0-0a4e-4680-b237-63cb1a8e321a' and locale = 'pl';
update public.question_translations set question_text = 'Should a parent testify against their own child?' where question_id = '59396fb0-0a4e-4680-b237-63cb1a8e321a' and locale = 'en';
-- nr885
update public.question_translations set question_text = 'Czy powinieneś powiedzieć sprzedawcy, że liczy sobie za mało?' where question_id = '5c176a94-bf66-43be-8790-d63a62a67a13' and locale = 'pl';
update public.question_translations set question_text = 'Should you tell a seller they''re charging too little?' where question_id = '5c176a94-bf66-43be-8790-d63a62a67a13' and locale = 'en';
-- nr891
update public.question_translations set question_text = 'Czy powinien istnieć cichy przymus chodzenia na integracje w pracy po godzinach?' where question_id = '664e20cb-f0cf-4ebd-8b1a-00aa2de55bb6' and locale = 'pl';
update public.question_translations set question_text = 'Should there be unspoken pressure to attend work socials after hours?' where question_id = '664e20cb-f0cf-4ebd-8b1a-00aa2de55bb6' and locale = 'en';
-- nr911
update public.question_translations set question_text = 'Czy w porządku jest przyjmowanie dofinansowania od państwa, jeśli i tak masz dużo pieniędzy?' where question_id = '8b81a5cd-b43b-4799-8f11-b4116ae85e9f' and locale = 'pl';
update public.question_translations set question_text = 'Is it okay to take state support when you already have plenty of money?' where question_id = '8b81a5cd-b43b-4799-8f11-b4116ae85e9f' and locale = 'en';
-- nr961
update public.question_translations set question_text = 'Czy wolność słowa powinna obejmować prawo do obrażania?' where question_id = 'f803ace0-4095-4f83-aba1-e6dd8d35fa03' and locale = 'pl';
update public.question_translations set question_text = 'Should free speech include the right to offend?' where question_id = 'f803ace0-4095-4f83-aba1-e6dd8d35fa03' and locale = 'en';

-- Smaczki rebuilds.
-- nr810: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'ceb4be50-405f-4e46-8ff0-fb963bd4f18f');
delete from public.question_smaczki where question_id = 'ceb4be50-405f-4e46-8ff0-fb963bd4f18f';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('ceb4be50-405f-4e46-8ff0-fb963bd4f18f',1,true),('ceb4be50-405f-4e46-8ff0-fb963bd4f18f',2,true),('ceb4be50-405f-4e46-8ff0-fb963bd4f18f',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Telefon bardziej potrzebny niż drogi ciuch?'),(1,'en','A phone is more useful than pricey clothes?'),
  (2,'pl','Twoje pieniądze, twoje zabawki'),(2,'en','Your money, your toys'),
  (3,'pl','Każdy przecież ma inne priorytety w życiu'),(3,'en','Everyone has different priorities')
) as v(position, locale, text) on v.position = ins.position;

-- nr823: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'dca96994-9de0-4a00-b9aa-3e6f7636ce19');
delete from public.question_smaczki where question_id = 'dca96994-9de0-4a00-b9aa-3e6f7636ce19';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('dca96994-9de0-4a00-b9aa-3e6f7636ce19',1,true),('dca96994-9de0-4a00-b9aa-3e6f7636ce19',2,true),('dca96994-9de0-4a00-b9aa-3e6f7636ce19',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Matura też powinna być sportem, bo rywalizujemy o miejsce na uczelni'),(1,'en','Then exams are a sport too — we compete for university places'),
  (2,'pl','Sport to ciało, nie plansza'),(2,'en','Sport means body, not board'),
  (3,'pl','Serce bije jak przy biegu — to nie sport?'),(3,'en','The heart pounds like a sprint — not a sport?')
) as v(position, locale, text) on v.position = ins.position;

-- nr831: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'e8c2ba33-57b1-4c1b-b464-6bd792f60687');
delete from public.question_smaczki where question_id = 'e8c2ba33-57b1-4c1b-b464-6bd792f60687';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('e8c2ba33-57b1-4c1b-b464-6bd792f60687',1,true),('e8c2ba33-57b1-4c1b-b464-6bd792f60687',2,true),('e8c2ba33-57b1-4c1b-b464-6bd792f60687',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Rytuały czynią czas widzialnym'),(1,'en','Rituals make time visible'),
  (2,'pl','Pamięć zostaje niezależnie od ceny pomnika'),(2,'en','The memory stays whatever the headstone cost'),
  (3,'pl','Bez rytuału wielka chwila mija jak każda inna'),(3,'en','With no ritual, the big moment passes like any other')
) as v(position, locale, text) on v.position = ins.position;

-- nr876: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '4b2aaee9-0e85-49bb-81df-c455af6f8280');
delete from public.question_smaczki where question_id = '4b2aaee9-0e85-49bb-81df-c455af6f8280';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('4b2aaee9-0e85-49bb-81df-c455af6f8280',1,true),('4b2aaee9-0e85-49bb-81df-c455af6f8280',2,true),('4b2aaee9-0e85-49bb-81df-c455af6f8280',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Ktoś inny zamieszkał w twojej głowie'),(1,'en','Someone else moved into your head'),
  (2,'pl','Życie jest za krótkie na złe filmy'),(2,'en','Life is too short for bad films'),
  (3,'pl','Nie zdarzyło ci się oglądać filmu ze słabymi recenzjami, a uznałeś, że był świetny?'),(3,'en','Never watched a badly reviewed film and loved it?')
) as v(position, locale, text) on v.position = ins.position;

-- nr881: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '59396fb0-0a4e-4680-b237-63cb1a8e321a');
delete from public.question_smaczki where question_id = '59396fb0-0a4e-4680-b237-63cb1a8e321a';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('59396fb0-0a4e-4680-b237-63cb1a8e321a',1,true),('59396fb0-0a4e-4680-b237-63cb1a8e321a',2,true),('59396fb0-0a4e-4680-b237-63cb1a8e321a',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Dziecko powinno być bezwzględnie chronione'),(1,'en','A child should be protected no matter what'),
  (2,'pl','A co jak czyn jest bardzo karygodny?'),(2,'en','And if the act was truly grave?'),
  (3,'pl','A jeśli rodzic chce tylko coś zyskać?'),(3,'en','And if the parent just wants something out of it?')
) as v(position, locale, text) on v.position = ins.position;

-- nr891: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '664e20cb-f0cf-4ebd-8b1a-00aa2de55bb6');
delete from public.question_smaczki where question_id = '664e20cb-f0cf-4ebd-8b1a-00aa2de55bb6';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('664e20cb-f0cf-4ebd-8b1a-00aa2de55bb6',1,true),('664e20cb-f0cf-4ebd-8b1a-00aa2de55bb6',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Masz przecież swoje życie i problemy'),(1,'en','You have your own life and problems'),
  (2,'pl','Im lepiej się znasz z tymi ludźmi, tym lepsza praca'),(2,'en','The better you know them, the better the work')
) as v(position, locale, text) on v.position = ins.position;

-- nr902: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '8107da3b-beaa-4b7b-81c6-98e106a6aa86');
delete from public.question_smaczki where question_id = '8107da3b-beaa-4b7b-81c6-98e106a6aa86';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('8107da3b-beaa-4b7b-81c6-98e106a6aa86',1,true),('8107da3b-beaa-4b7b-81c6-98e106a6aa86',2,true),('8107da3b-beaa-4b7b-81c6-98e106a6aa86',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Nie sposób przestrzegać niewidzialnego'),(1,'en','You can''t obey what you can''t see'),
  (2,'pl','Niewiedza stałaby się strategią, a ludzie lubią to wykorzystywać'),(2,'en','Ignorance would become a strategy, and people exploit that'),
  (3,'pl','„Nie wiedziałem" ratuje raz, nie zawsze'),(3,'en','''I didn''t know'' works once, not always')
) as v(position, locale, text) on v.position = ins.position;

-- nr911: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '8b81a5cd-b43b-4799-8f11-b4116ae85e9f');
delete from public.question_smaczki where question_id = '8b81a5cd-b43b-4799-8f11-b4116ae85e9f';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('8b81a5cd-b43b-4799-8f11-b4116ae85e9f',1,true),('8b81a5cd-b43b-4799-8f11-b4116ae85e9f',2,true),('8b81a5cd-b43b-4799-8f11-b4116ae85e9f',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Państwo daje, to trzeba brać'),(1,'en','The state offers it, so take it'),
  (2,'pl','Te pieniądze i tak będą wykorzystane na kogoś innego, jak nie ciebie'),(2,'en','That money goes to someone else if not to you'),
  (3,'pl','Wielkie korporacje dostają dofinansowania na kolejne produkty, a i tak zarabiają miliardy'),(3,'en','Big corporations get subsidies for new products and still make billions')
) as v(position, locale, text) on v.position = ins.position;

-- nr938: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'd6bcc3bc-b751-404a-a716-0ded454f0de3');
delete from public.question_smaczki where question_id = 'd6bcc3bc-b751-404a-a716-0ded454f0de3';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('d6bcc3bc-b751-404a-a716-0ded454f0de3',1,true),('d6bcc3bc-b751-404a-a716-0ded454f0de3',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Przeszli tę drogę przed tobą'),(1,'en','They walked the road ahead of you'),
  (2,'pl','Stare mapy, nowe drogi'),(2,'en','Old maps, new roads')
) as v(position, locale, text) on v.position = ins.position;

commit;