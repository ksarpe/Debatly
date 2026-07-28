-- ============================================================================
-- Catalog edit batch 2 (master-file diff, rows up to nr 102)
-- 13 deletes, 3 question-text edits, 48 smaczki rebuilds. EN adapted by
-- assistant for every changed PL (user left EN untouched). 2 PL typos fixed
-- (nr66, nr79). No seed changes. Deletes backed up to *_batch2.backup.json.
-- ============================================================================
begin;

-- 1) Deletions.
delete from public.daily_questions where publish_date > (now() at time zone 'utc')::date + 1;

delete from public.daily_questions d
using (values
  ('112cceab-efca-46b8-8927-20397dbe9d3a'),
  ('17725e28-eb5e-4f79-bb0e-0a513103452b'),
  ('2762f705-62a1-4333-9710-10335a571bac'),
  ('33323a3a-9a28-40f5-91b9-27d55c3fb6fb'),
  ('36fd29cb-ad1a-41ec-a3d7-90ad950921d0'),
  ('3cb957dd-29be-448d-8c6f-39c6a3f10363'),
  ('3f66582c-8790-414b-abfd-f8221a61107e'),
  ('44ca00ab-9914-4e00-93a7-da871543b93c'),
  ('5527504f-3435-4b2f-b7ec-720ae8773fe5'),
  ('5ca746ba-9cf7-4f94-8c73-131a74874307'),
  ('8aec2bff-f45c-43b8-b312-a5ce4d472528'),
  ('8b97b981-a9f2-405f-b95b-2065b23bd9c0'),
  ('b354db77-0631-4036-b901-1e17f694c307')
) as del(id)
where d.question_id = del.id::uuid;

delete from public.questions q
using (values
  ('112cceab-efca-46b8-8927-20397dbe9d3a'),
  ('17725e28-eb5e-4f79-bb0e-0a513103452b'),
  ('2762f705-62a1-4333-9710-10335a571bac'),
  ('33323a3a-9a28-40f5-91b9-27d55c3fb6fb'),
  ('36fd29cb-ad1a-41ec-a3d7-90ad950921d0'),
  ('3cb957dd-29be-448d-8c6f-39c6a3f10363'),
  ('3f66582c-8790-414b-abfd-f8221a61107e'),
  ('44ca00ab-9914-4e00-93a7-da871543b93c'),
  ('5527504f-3435-4b2f-b7ec-720ae8773fe5'),
  ('5ca746ba-9cf7-4f94-8c73-131a74874307'),
  ('8aec2bff-f45c-43b8-b312-a5ce4d472528'),
  ('8b97b981-a9f2-405f-b95b-2065b23bd9c0'),
  ('b354db77-0631-4036-b901-1e17f694c307')
) as del(id)
where q.id = del.id::uuid;

with anchor as (select coalesce(max(publish_date), (now() at time zone 'utc')::date) as last_day from public.daily_questions),
pool as (select qq.id, (row_number() over (order by random()))::int as rn from public.questions qq
         where qq.is_active and not exists (select 1 from public.daily_questions d where d.question_id = qq.id))
insert into public.daily_questions (publish_date, question_id)
select (select last_day from anchor) + pool.rn, pool.id from pool;

-- 2) Question text edits (PL + adapted EN).
-- nr70
update public.question_translations set question_text = 'Czy warto zemścić się na kimś kto Cię skrzywdził, gdy w końcu masz przewagę?' where question_id = '73f9fec9-df59-43cf-a449-e77a5852a6c0' and locale = 'pl';
update public.question_translations set question_text = 'Is it worth getting back at someone who hurt you, now that you finally have the upper hand?' where question_id = '73f9fec9-df59-43cf-a449-e77a5852a6c0' and locale = 'en';
-- nr71
update public.question_translations set question_text = 'Czy życie wieczne byłoby raczej błogosławieństwem czy przekleństwem?' where question_id = '74e30dde-61f9-4995-99ba-9a8a22eaa75d' and locale = 'pl';
update public.question_translations set question_text = 'Would living forever be more of a blessing or a curse?' where question_id = '74e30dde-61f9-4995-99ba-9a8a22eaa75d' and locale = 'en';
-- nr93
update public.question_translations set question_text = 'Czy związki zawarte w internecie są słabsze niż te z prawdziwego życia?' where question_id = 'b1f26e52-5c76-46dd-bf70-7dd3edbc5114' and locale = 'pl';
update public.question_translations set question_text = 'Are relationships formed online weaker than those from real life?' where question_id = 'b1f26e52-5c76-46dd-bf70-7dd3edbc5114' and locale = 'en';

-- 3) Smaczki rebuilds (delete + reinsert renumbered 1..N).
-- nr27: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '15c4cf3b-7fc6-4edc-a533-2eab6bc5deba');
delete from public.question_smaczki where question_id = '15c4cf3b-7fc6-4edc-a533-2eab6bc5deba';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('15c4cf3b-7fc6-4edc-a533-2eab6bc5deba',1,true),('15c4cf3b-7fc6-4edc-a533-2eab6bc5deba',2,true),('15c4cf3b-7fc6-4edc-a533-2eab6bc5deba',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Ludzie dojrzewają?'),(1,'en','People grow?'),
  (2,'pl','Raz zdrajca, zawsze zdrajca?'),(2,'en','Once a traitor?'),
  (3,'pl','Nigdy nie zrobiłeś nic złego?'),(3,'en','Never done anything wrong yourself?')
) as v(position, locale, text) on v.position = ins.position;

-- nr28: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '15dc4795-292a-4b3b-9a8f-c49fa4fe3831');
delete from public.question_smaczki where question_id = '15dc4795-292a-4b3b-9a8f-c49fa4fe3831';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('15dc4795-292a-4b3b-9a8f-c49fa4fe3831',1,true),('15dc4795-292a-4b3b-9a8f-c49fa4fe3831',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Wolny od tego bólu?'),(1,'en','Free of the pain?'),
  (2,'pl','Bez niego nie byłbyś sobą'),(2,'en','It made you who you are')
) as v(position, locale, text) on v.position = ins.position;

-- nr31: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '1c00e567-e413-4ffa-aed8-4c1bed2724b8');
delete from public.question_smaczki where question_id = '1c00e567-e413-4ffa-aed8-4c1bed2724b8';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('1c00e567-e413-4ffa-aed8-4c1bed2724b8',1,true),('1c00e567-e413-4ffa-aed8-4c1bed2724b8',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Świat w kieszeni'),(1,'en','World in your pocket'),
  (2,'pl','Sprawdź swój czas ekranowy, potem odpowiedz'),(2,'en','Check your screen time, then answer')
) as v(position, locale, text) on v.position = ins.position;

-- nr32: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '1fadcb4d-3cf9-4115-a921-ffb0ec50fbaf');
delete from public.question_smaczki where question_id = '1fadcb4d-3cf9-4115-a921-ffb0ec50fbaf';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('1fadcb4d-3cf9-4115-a921-ffb0ec50fbaf',1,true),('1fadcb4d-3cf9-4115-a921-ffb0ec50fbaf',2,true),('1fadcb4d-3cf9-4115-a921-ffb0ec50fbaf',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Nareszcie wolni?'),(1,'en','Free at last?'),
  (2,'pl','A gdzie nasz sens?'),(2,'en','Where''s our purpose?'),
  (3,'pl','Maszyny lepsze od żywego człowieka?'),(3,'en','Machines better than a living person?')
) as v(position, locale, text) on v.position = ins.position;

-- nr34: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '244d8c8f-1d7c-425d-bdb0-9ce6aed77f50');
delete from public.question_smaczki where question_id = '244d8c8f-1d7c-425d-bdb0-9ce6aed77f50';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('244d8c8f-1d7c-425d-bdb0-9ce6aed77f50',1,true),('244d8c8f-1d7c-425d-bdb0-9ce6aed77f50',2,true),('244d8c8f-1d7c-425d-bdb0-9ce6aed77f50',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Bezpieczeństwo ponad wszystko?'),(1,'en','Safety above all?'),
  (2,'pl','Wygodna klatka?'),(2,'en','A comfortable cage?'),
  (3,'pl','Człowiek w rozwiniętym kraju nigdy nie jest w pełni wolny (prawo)'),(3,'en','No one in a developed country is ever fully free')
) as v(position, locale, text) on v.position = ins.position;

-- nr37: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '2fed91a2-f02a-4784-9b14-16164dfd7655');
delete from public.question_smaczki where question_id = '2fed91a2-f02a-4784-9b14-16164dfd7655';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('2fed91a2-f02a-4784-9b14-16164dfd7655',1,true),('2fed91a2-f02a-4784-9b14-16164dfd7655',2,true),('2fed91a2-f02a-4784-9b14-16164dfd7655',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Tam opieka będzie lepsza?'),(1,'en','Better care there?'),
  (2,'pl','Po prostu wygodniej?'),(2,'en','Just more convenient?'),
  (3,'pl','Oni cię nie oddali, gdy byłeś mały'),(3,'en','They didn''t outsource you as a baby')
) as v(position, locale, text) on v.position = ins.position;

-- nr39: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '35d39b95-2927-4461-88a4-917fd7ac6f7b');
delete from public.question_smaczki where question_id = '35d39b95-2927-4461-88a4-917fd7ac6f7b';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('35d39b95-2927-4461-88a4-917fd7ac6f7b',1,true),('35d39b95-2927-4461-88a4-917fd7ac6f7b',2,true),('35d39b95-2927-4461-88a4-917fd7ac6f7b',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Równo znaczy uczciwie?'),(1,'en','Equal is fair?'),
  (2,'pl','Może % od zarobków?'),(2,'en','Maybe a % of income?'),
  (3,'pl','Po równo bywa najbardziej niesprawiedliwe'),(3,'en','Equal can be the least fair split')
) as v(position, locale, text) on v.position = ins.position;

-- nr41: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '3976b21c-eceb-4e54-a264-9d37605963fa');
delete from public.question_smaczki where question_id = '3976b21c-eceb-4e54-a264-9d37605963fa';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('3976b21c-eceb-4e54-a264-9d37605963fa',1,true),('3976b21c-eceb-4e54-a264-9d37605963fa',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Nasz obowiązek to dbanie o nasz dom'),(1,'en','Caring for our home is our duty'),
  (2,'pl','Konieczność zanim będzie za późno'),(2,'en','A must before it''s too late')
) as v(position, locale, text) on v.position = ins.position;

-- nr43: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '3c622a6c-05b0-4ffa-8841-46d80e58566b');
delete from public.question_smaczki where question_id = '3c622a6c-05b0-4ffa-8841-46d80e58566b';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('3c622a6c-05b0-4ffa-8841-46d80e58566b',1,true),('3c622a6c-05b0-4ffa-8841-46d80e58566b',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Nazwisko cię przetrwa'),(1,'en','Your name outlives you'),
  (2,'pl','Sława po śmierci grzeje tylko żywych'),(2,'en','Posthumous fame warms only the living')
) as v(position, locale, text) on v.position = ins.position;

-- nr47: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '406986a1-57b5-46e6-8a03-1530fd70f161');
delete from public.question_smaczki where question_id = '406986a1-57b5-46e6-8a03-1530fd70f161';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('406986a1-57b5-46e6-8a03-1530fd70f161',1,true),('406986a1-57b5-46e6-8a03-1530fd70f161',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Oko za oko?'),(1,'en','Eye for an eye?'),
  (2,'pl','Zemsta w todze wciąż jest zemstą'),(2,'en','Revenge in a robe is still revenge')
) as v(position, locale, text) on v.position = ins.position;

-- nr50: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '48df04da-d22b-4a77-92ca-e29f26d56ca6');
delete from public.question_smaczki where question_id = '48df04da-d22b-4a77-92ca-e29f26d56ca6';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('48df04da-d22b-4a77-92ca-e29f26d56ca6',1,true),('48df04da-d22b-4a77-92ca-e29f26d56ca6',2,true),('48df04da-d22b-4a77-92ca-e29f26d56ca6',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Równowaga się liczy'),(1,'en','Fairness matters'),
  (2,'pl','Miłość to nie rachunki'),(2,'en','Love isn''t a ledger'),
  (3,'pl','Czynów nie policzysz'),(3,'en','You can''t tally the deeds')
) as v(position, locale, text) on v.position = ins.position;

-- nr51: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '4bc5e444-b207-4a03-a5d7-08667d78a4e6');
delete from public.question_smaczki where question_id = '4bc5e444-b207-4a03-a5d7-08667d78a4e6';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('4bc5e444-b207-4a03-a5d7-08667d78a4e6',1,true),('4bc5e444-b207-4a03-a5d7-08667d78a4e6',2,true),('4bc5e444-b207-4a03-a5d7-08667d78a4e6',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Przetrwanie to priorytet'),(1,'en','Survival comes first'),
  (2,'pl','A jeśli każdy tak zacznie?'),(2,'en','Rules bend for all?'),
  (3,'pl','Głodnemu prawo brzmi jak żart'),(3,'en','To the starving, the law sounds like a joke')
) as v(position, locale, text) on v.position = ins.position;

-- nr53: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '52e8efef-aee4-4875-ade1-bfe5694bf029');
delete from public.question_smaczki where question_id = '52e8efef-aee4-4875-ade1-bfe5694bf029';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('52e8efef-aee4-4875-ade1-bfe5694bf029',1,true),('52e8efef-aee4-4875-ade1-bfe5694bf029',2,true),('52e8efef-aee4-4875-ade1-bfe5694bf029',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Wyznacza granicę?'),(1,'en','Sets a clear limit?'),
  (2,'pl','Spokój uczy więcej'),(2,'en','Calm teaches more'),
  (3,'pl','Podniesiony ton to już przemoc czy nie?'),(3,'en','Is a raised voice already abuse?')
) as v(position, locale, text) on v.position = ins.position;

-- nr56: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '579d535f-6f59-40f8-bf68-82b21cd19f9f');
delete from public.question_smaczki where question_id = '579d535f-6f59-40f8-bf68-82b21cd19f9f';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('579d535f-6f59-40f8-bf68-82b21cd19f9f',1,true),('579d535f-6f59-40f8-bf68-82b21cd19f9f',2,true),('579d535f-6f59-40f8-bf68-82b21cd19f9f',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Odliczanie zabija, zanim śmierć zdąży'),(1,'en','The countdown kills before death does'),
  (2,'pl','Tego zegara się nie odzobaczy'),(2,'en','A clock you can''t unsee'),
  (3,'pl','Co to zmieni? Teraz nie można żyć pełnią życia?'),(3,'en','What would it change — can''t you live fully now?')
) as v(position, locale, text) on v.position = ins.position;

-- nr57: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '5a96b78e-d3e9-44b5-bdb5-1f8d006bfe28');
delete from public.question_smaczki where question_id = '5a96b78e-d3e9-44b5-bdb5-1f8d006bfe28';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('5a96b78e-d3e9-44b5-bdb5-1f8d006bfe28',1,true),('5a96b78e-d3e9-44b5-bdb5-1f8d006bfe28',2,true),('5a96b78e-d3e9-44b5-bdb5-1f8d006bfe28',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Mniej zgrzytów?'),(1,'en','Fewer clashes?'),
  (2,'pl','Dopełnienie się jest kluczem, równowagą'),(2,'en','Balance — completing each other is the key'),
  (3,'pl','Wygoda to nie to samo co miłość'),(3,'en','Comfort isn''t the same as love')
) as v(position, locale, text) on v.position = ins.position;

-- nr59: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '5cc0a51e-4a9e-4d07-809a-d0f9b154edee');
delete from public.question_smaczki where question_id = '5cc0a51e-4a9e-4d07-809a-d0f9b154edee';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('5cc0a51e-4a9e-4d07-809a-d0f9b154edee',1,true),('5cc0a51e-4a9e-4d07-809a-d0f9b154edee',2,true),('5cc0a51e-4a9e-4d07-809a-d0f9b154edee',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Sprawiedliwość własną ręką?'),(1,'en','Justice by your hand?'),
  (2,'pl','Niektórym się należy?'),(2,'en','Some have it coming?'),
  (3,'pl','Idąc po zemstę, kop dwa groby'),(3,'en','Before revenge, dig two graves')
) as v(position, locale, text) on v.position = ins.position;

-- nr60: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '5d224cac-b551-4baa-b77b-cc42e1ee0745');
delete from public.question_smaczki where question_id = '5d224cac-b551-4baa-b77b-cc42e1ee0745';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('5d224cac-b551-4baa-b77b-cc42e1ee0745',1,true),('5d224cac-b551-4baa-b77b-cc42e1ee0745',2,true),('5d224cac-b551-4baa-b77b-cc42e1ee0745',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Dzikość ma własną wartość'),(1,'en','Wild has its own worth'),
  (2,'pl','Ziemia jest dla ludzi?'),(2,'en','Is the Earth for people?'),
  (3,'pl','Zysk mija, wycięty las nie odrasta'),(3,'en','The profit fades; the forest won''t regrow')
) as v(position, locale, text) on v.position = ins.position;

-- nr61: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '5fc9abfa-2e41-4223-88a6-95e8e43cd4d6');
delete from public.question_smaczki where question_id = '5fc9abfa-2e41-4223-88a6-95e8e43cd4d6';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('5fc9abfa-2e41-4223-88a6-95e8e43cd4d6',1,true),('5fc9abfa-2e41-4223-88a6-95e8e43cd4d6',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Z partnerem budujesz życie'),(1,'en','You build a life together'),
  (2,'pl','Kto każe wybierać, już cię zamyka'),(2,'en','Whoever makes you choose is already caging you')
) as v(position, locale, text) on v.position = ins.position;

-- nr63: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '67f93fc0-7ac7-4334-b4b1-074ae37cb756');
delete from public.question_smaczki where question_id = '67f93fc0-7ac7-4334-b4b1-074ae37cb756';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('67f93fc0-7ac7-4334-b4b1-074ae37cb756',1,true),('67f93fc0-7ac7-4334-b4b1-074ae37cb756',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Czyje to marzenie?'),(1,'en','Whose dream is it?'),
  (2,'pl','Instynkt czy świadoma decyzja?'),(2,'en','Instinct or a conscious choice?')
) as v(position, locale, text) on v.position = ins.position;

-- nr64: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '68e3d717-7120-4b25-baab-e123a30af94a');
delete from public.question_smaczki where question_id = '68e3d717-7120-4b25-baab-e123a30af94a';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('68e3d717-7120-4b25-baab-e123a30af94a',1,true),('68e3d717-7120-4b25-baab-e123a30af94a',2,true),('68e3d717-7120-4b25-baab-e123a30af94a',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Nie będzie drugiej szansy'),(1,'en','There''s no second chance'),
  (2,'pl','Odebrać mu spokojne pożegnanie?'),(2,'en','Rob him of a peaceful goodbye?'),
  (3,'pl','Kłamiesz dla niego czy dla siebie?'),(3,'en','Lying for him, or for yourself?')
) as v(position, locale, text) on v.position = ins.position;

-- nr65: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '6a95a212-c0ec-46f0-a1f6-c36fd90c55b7');
delete from public.question_smaczki where question_id = '6a95a212-c0ec-46f0-a1f6-c36fd90c55b7';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('6a95a212-c0ec-46f0-a1f6-c36fd90c55b7',1,true),('6a95a212-c0ec-46f0-a1f6-c36fd90c55b7',2,true),('6a95a212-c0ec-46f0-a1f6-c36fd90c55b7',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Każdemu raz się zdarzy?'),(1,'en','Everyone slips once?'),
  (2,'pl','Pewne rzeczy są święte'),(2,'en','Some things are sacred'),
  (3,'pl','Czy zależy to od rodzaju sekretu?'),(3,'en','Does it depend on the secret?')
) as v(position, locale, text) on v.position = ins.position;

-- nr66: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '6b9529be-05c0-446c-9a58-7d706aca77e4');
delete from public.question_smaczki where question_id = '6b9529be-05c0-446c-9a58-7d706aca77e4';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('6b9529be-05c0-446c-9a58-7d706aca77e4',1,true),('6b9529be-05c0-446c-9a58-7d706aca77e4',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Oznaka dojrzałości?'),(1,'en','A sign of maturity?'),
  (2,'pl','Wybaczenie to twój spokój, nie jego wygrana'),(2,'en','Forgiveness is your peace, not their win')
) as v(position, locale, text) on v.position = ins.position;

-- nr68: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '6db69f39-d7c6-4b37-9e85-a954c927f9f6');
delete from public.question_smaczki where question_id = '6db69f39-d7c6-4b37-9e85-a954c927f9f6';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('6db69f39-d7c6-4b37-9e85-a954c927f9f6',1,true),('6db69f39-d7c6-4b37-9e85-a954c927f9f6',2,true),('6db69f39-d7c6-4b37-9e85-a954c927f9f6',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Tego żąda sumienie?'),(1,'en','Conscience demands it?'),
  (2,'pl','Co jeśli nic nie zmieni'),(2,'en','What if it changes nothing?'),
  (3,'pl','Spowiedź zrzuca twój ciężar na innych'),(3,'en','Confession dumps your weight onto them')
) as v(position, locale, text) on v.position = ins.position;

-- nr70: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '73f9fec9-df59-43cf-a449-e77a5852a6c0');
delete from public.question_smaczki where question_id = '73f9fec9-df59-43cf-a449-e77a5852a6c0';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('73f9fec9-df59-43cf-a449-e77a5852a6c0',1,true),('73f9fec9-df59-43cf-a449-e77a5852a6c0',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Litość czyni nas ludźmi?'),(1,'en','Mercy keeps us human?'),
  (2,'pl','On by cię nie oszczędził'),(2,'en','He''d never spare you')
) as v(position, locale, text) on v.position = ins.position;

-- nr71: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '74e30dde-61f9-4995-99ba-9a8a22eaa75d');
delete from public.question_smaczki where question_id = '74e30dde-61f9-4995-99ba-9a8a22eaa75d';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('74e30dde-61f9-4995-99ba-9a8a22eaa75d',1,true),('74e30dde-61f9-4995-99ba-9a8a22eaa75d',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','A jeśli Twój partner też byłby nieśmiertelny?'),(1,'en','What if your partner were immortal too?'),
  (2,'pl','Nieśmiertelny świadek własnej samotności'),(2,'en','An immortal witness to your own loneliness')
) as v(position, locale, text) on v.position = ins.position;

-- nr72: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '7564701c-7620-4ff0-aa6c-27fc46171f01');
delete from public.question_smaczki where question_id = '7564701c-7620-4ff0-aa6c-27fc46171f01';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('7564701c-7620-4ff0-aa6c-27fc46171f01',1,true),('7564701c-7620-4ff0-aa6c-27fc46171f01',2,true),('7564701c-7620-4ff0-aa6c-27fc46171f01',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Głód usprawiedliwia?'),(1,'en','Hunger excuses it?'),
  (2,'pl','To kto za to płaci?'),(2,'en','Then who pays?'),
  (3,'pl','A jeśli to dziecko?'),(3,'en','And if it''s a child?')
) as v(position, locale, text) on v.position = ins.position;

-- nr75: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '8089f16c-a7d6-4c3b-9731-9dbeb1f63a8c');
delete from public.question_smaczki where question_id = '8089f16c-a7d6-4c3b-9731-9dbeb1f63a8c';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('8089f16c-a7d6-4c3b-9731-9dbeb1f63a8c',1,true),('8089f16c-a7d6-4c3b-9731-9dbeb1f63a8c',2,true),('8089f16c-a7d6-4c3b-9731-9dbeb1f63a8c',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Milczenie to wybór?'),(1,'en','Silence is a choice?'),
  (2,'pl','Nie ty zawiniłeś'),(2,'en','It''s not your fault'),
  (3,'pl','Mógłbyś chronić ofiarę'),(3,'en','You could protect the victim')
) as v(position, locale, text) on v.position = ins.position;

-- nr76: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '812addef-6d78-4ab7-9a90-863900bb196e');
delete from public.question_smaczki where question_id = '812addef-6d78-4ab7-9a90-863900bb196e';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('812addef-6d78-4ab7-9a90-863900bb196e',1,true),('812addef-6d78-4ab7-9a90-863900bb196e',2,true),('812addef-6d78-4ab7-9a90-863900bb196e',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Żałować, że nie spróbowałeś?'),(1,'en','Regret what you didn''t try?'),
  (2,'pl','Rachunki nie czekają'),(2,'en','Bills don''t wait'),
  (3,'pl','Co jeśli wiesz, że nie wrócisz do pewnej pracy?'),(3,'en','What if you know you''ll never get that job back?')
) as v(position, locale, text) on v.position = ins.position;

-- nr77: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '84f4cb83-c27d-42cb-bf44-ef016250ff39');
delete from public.question_smaczki where question_id = '84f4cb83-c27d-42cb-bf44-ef016250ff39';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('84f4cb83-c27d-42cb-bf44-ef016250ff39',1,true),('84f4cb83-c27d-42cb-bf44-ef016250ff39',2,true),('84f4cb83-c27d-42cb-bf44-ef016250ff39',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Głowa się wycisza'),(1,'en','The mind goes quiet'),
  (2,'pl','Odcięty od wszystkich nie jesteś szczęśliwy'),(2,'en','Cut off from everyone, you''re not happy'),
  (3,'pl','Czy we współczesnym świecie to możliwe?'),(3,'en','Is that even possible today?')
) as v(position, locale, text) on v.position = ins.position;

-- nr78: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '860a9d78-e404-49da-82e1-dc98fa43f619');
delete from public.question_smaczki where question_id = '860a9d78-e404-49da-82e1-dc98fa43f619';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('860a9d78-e404-49da-82e1-dc98fa43f619',1,true),('860a9d78-e404-49da-82e1-dc98fa43f619',2,true),('860a9d78-e404-49da-82e1-dc98fa43f619',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Piękno potrzebuje duszy?'),(1,'en','Beauty needs a soul?'),
  (2,'pl','Piękno jest w oku patrzącego'),(2,'en','Beauty''s in the eye'),
  (3,'pl','Nie odróżnisz'),(3,'en','You couldn''t tell them apart')
) as v(position, locale, text) on v.position = ins.position;

-- nr79: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '89c2bb8f-0443-41b1-ab9b-c0f5528daa03');
delete from public.question_smaczki where question_id = '89c2bb8f-0443-41b1-ab9b-c0f5528daa03';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('89c2bb8f-0443-41b1-ab9b-c0f5528daa03',1,true),('89c2bb8f-0443-41b1-ab9b-c0f5528daa03',2,true),('89c2bb8f-0443-41b1-ab9b-c0f5528daa03',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Brak rozmyślania o jego wielkości'),(1,'en','No agonizing over how much'),
  (2,'pl','Na napiwek trzeba zasłużyć'),(2,'en','A tip must be earned'),
  (3,'pl','Napiwek i tak stał się standardem'),(3,'en','Tipping became the norm anyway')
) as v(position, locale, text) on v.position = ins.position;

-- nr83: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '9201823c-cf2a-48b6-839d-98bfd8359513');
delete from public.question_smaczki where question_id = '9201823c-cf2a-48b6-839d-98bfd8359513';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('9201823c-cf2a-48b6-839d-98bfd8359513',1,true),('9201823c-cf2a-48b6-839d-98bfd8359513',2,true),('9201823c-cf2a-48b6-839d-98bfd8359513',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Budujesz przyszłość?'),(1,'en','Build a future?'),
  (2,'pl','Później może nie nadejść'),(2,'en','Later may never come'),
  (3,'pl','Może nie wyjść i całe życie będzie poświęcone na ciężką pracę'),(3,'en','It might fail — a whole life spent grinding')
) as v(position, locale, text) on v.position = ins.position;

-- nr86: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '987a79d9-9c1c-4bd5-9c33-90b1bc614142');
delete from public.question_smaczki where question_id = '987a79d9-9c1c-4bd5-9c33-90b1bc614142';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('987a79d9-9c1c-4bd5-9c33-90b1bc614142',1,true),('987a79d9-9c1c-4bd5-9c33-90b1bc614142',2,true),('987a79d9-9c1c-4bd5-9c33-90b1bc614142',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Pełna szczerość?'),(1,'en','Total honesty?'),
  (2,'pl','Po co ranić bez powodu?'),(2,'en','Why wound them?'),
  (3,'pl','To nic nie znaczy'),(3,'en','It meant nothing')
) as v(position, locale, text) on v.position = ins.position;

-- nr87: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '9bcec9bb-419b-4600-99a7-b61916bbd21d');
delete from public.question_smaczki where question_id = '9bcec9bb-419b-4600-99a7-b61916bbd21d';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('9bcec9bb-419b-4600-99a7-b61916bbd21d',1,true),('9bcec9bb-419b-4600-99a7-b61916bbd21d',2,true),('9bcec9bb-419b-4600-99a7-b61916bbd21d',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Dwoje wystarczy'),(1,'en','Two is enough'),
  (2,'pl','Zwierzę zaspokaja instynkty, potrzebę opieki?'),(2,'en','A pet meets the urge to nurture?'),
  (3,'pl','Wygoda i egoizm?'),(3,'en','Convenience and selfishness?')
) as v(position, locale, text) on v.position = ins.position;

-- nr88: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '9cb73e49-f1f0-4b68-9bf5-185f4df785e3');
delete from public.question_smaczki where question_id = '9cb73e49-f1f0-4b68-9bf5-185f4df785e3';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('9cb73e49-f1f0-4b68-9bf5-185f4df785e3',1,true),('9cb73e49-f1f0-4b68-9bf5-185f4df785e3',2,true),('9cb73e49-f1f0-4b68-9bf5-185f4df785e3',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','A co jeśli to Twoje dziecko?'),(1,'en','And if it were your child?'),
  (2,'pl','Czy on by zrobił to samo'),(2,'en','Would he do the same?'),
  (3,'pl','A co jeśli zrobiłby to ponownie?'),(3,'en','And if he''d do it again?')
) as v(position, locale, text) on v.position = ins.position;

-- nr89: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'a17f1406-f037-4bfb-a828-474100a296ed');
delete from public.question_smaczki where question_id = 'a17f1406-f037-4bfb-a828-474100a296ed';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('a17f1406-f037-4bfb-a828-474100a296ed',1,true),('a17f1406-f037-4bfb-a828-474100a296ed',2,true),('a17f1406-f037-4bfb-a828-474100a296ed',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Dzieci czują fałsz'),(1,'en','Kids feel the cracks'),
  (2,'pl','Złudzenie dzieci nie powinno być ważniejsze niż własne szczęście'),(2,'en','A child''s illusion shouldn''t outweigh your own happiness'),
  (3,'pl','Uczysz je, że tak wygląda miłość'),(3,'en','You''re teaching them this is what love is')
) as v(position, locale, text) on v.position = ins.position;

-- nr90: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'a1d27017-c8eb-4c99-b171-cb7fd6cc77bb');
delete from public.question_smaczki where question_id = 'a1d27017-c8eb-4c99-b171-cb7fd6cc77bb';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('a1d27017-c8eb-4c99-b171-cb7fd6cc77bb',1,true),('a1d27017-c8eb-4c99-b171-cb7fd6cc77bb',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','A co jeśli tak lepiej dla wszystkich?'),(1,'en','And if it''s better for everyone?'),
  (2,'pl','Pochowany sekret wciąż truje żywych'),(2,'en','A buried secret still poisons the living')
) as v(position, locale, text) on v.position = ins.position;

-- nr91: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'a8e84a69-9ee9-42c7-a314-31d2f1bb56d1');
delete from public.question_smaczki where question_id = 'a8e84a69-9ee9-42c7-a314-31d2f1bb56d1';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('a8e84a69-9ee9-42c7-a314-31d2f1bb56d1',1,true),('a8e84a69-9ee9-42c7-a314-31d2f1bb56d1',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Nie masz nic do ukrycia?'),(1,'en','Nothing to hide?'),
  (2,'pl','„Nic do ukrycia" — do pierwszego wycieku'),(2,'en','''Nothing to hide'' — until the first leak')
) as v(position, locale, text) on v.position = ins.position;

-- nr92: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'ad4478d3-8331-46fd-a749-12deb4f9a103');
delete from public.question_smaczki where question_id = 'ad4478d3-8331-46fd-a749-12deb4f9a103';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('ad4478d3-8331-46fd-a749-12deb4f9a103',1,true),('ad4478d3-8331-46fd-a749-12deb4f9a103',2,true),('ad4478d3-8331-46fd-a749-12deb4f9a103',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','10 lat na naukę i ciężką pracę też będzie zmarnowane'),(1,'en','Ten years of study and grind would be wasted too'),
  (2,'pl','Lata nie wracają'),(2,'en','Years never come back'),
  (3,'pl','Bogaty trup nie wydaje'),(3,'en','A rich corpse spends nothing')
) as v(position, locale, text) on v.position = ins.position;

-- nr93: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'b1f26e52-5c76-46dd-bf70-7dd3edbc5114');
delete from public.question_smaczki where question_id = 'b1f26e52-5c76-46dd-bf70-7dd3edbc5114';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('b1f26e52-5c76-46dd-bf70-7dd3edbc5114',1,true),('b1f26e52-5c76-46dd-bf70-7dd3edbc5114',2,true),('b1f26e52-5c76-46dd-bf70-7dd3edbc5114',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Kreacja w internecie nie odzwierciedla rzeczywistości'),(1,'en','The online persona isn''t the real person'),
  (2,'pl','Poznać się można wszędzie'),(2,'en','Just another door'),
  (3,'pl','A jeśli nie zobaczycie się przez 5 lat na żywo?'),(3,'en','What if you don''t meet in person for five years?')
) as v(position, locale, text) on v.position = ins.position;

-- nr95: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'b64a1628-9934-4e5c-b55a-ff588e777f07');
delete from public.question_smaczki where question_id = 'b64a1628-9934-4e5c-b55a-ff588e777f07';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('b64a1628-9934-4e5c-b55a-ff588e777f07',1,true),('b64a1628-9934-4e5c-b55a-ff588e777f07',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Prawo do bycia zapomnianym?'),(1,'en','A right to be forgotten?'),
  (2,'pl','Zgadnij, kto najbardziej chce zapomnienia'),(2,'en','Guess who wants the forgetting most')
) as v(position, locale, text) on v.position = ins.position;

-- nr96: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'b9e1471c-7d17-4fc1-9863-2249114bfd47');
delete from public.question_smaczki where question_id = 'b9e1471c-7d17-4fc1-9863-2249114bfd47';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('b9e1471c-7d17-4fc1-9863-2249114bfd47',1,true),('b9e1471c-7d17-4fc1-9863-2249114bfd47',2,true),('b9e1471c-7d17-4fc1-9863-2249114bfd47',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Płacimy za roboczogodziny'),(1,'en','You''re paying for the labor hours'),
  (2,'pl','Niedoskonałość nad ideałem?'),(2,'en','Flaws over perfection?'),
  (3,'pl','Kupujesz historię, nie przedmiot'),(3,'en','You''re buying a story, not an object')
) as v(position, locale, text) on v.position = ins.position;

-- nr97: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'b9ea3313-f244-476e-82d9-f12921516024');
delete from public.question_smaczki where question_id = 'b9ea3313-f244-476e-82d9-f12921516024';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('b9ea3313-f244-476e-82d9-f12921516024',1,true),('b9ea3313-f244-476e-82d9-f12921516024',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Pasją nie zapłacisz czynszu'),(1,'en','Passion won''t pay rent'),
  (2,'pl','Pasja za pensję zmienia się w obowiązek'),(2,'en','Passion becomes a duty once it pays')
) as v(position, locale, text) on v.position = ins.position;

-- nr98: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'bbc007cf-f459-4d66-96df-dd09b4ff57b8');
delete from public.question_smaczki where question_id = 'bbc007cf-f459-4d66-96df-dd09b4ff57b8';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('bbc007cf-f459-4d66-96df-dd09b4ff57b8',1,true),('bbc007cf-f459-4d66-96df-dd09b4ff57b8',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Instynkt ponad prawem?'),(1,'en','Instinct above law?'),
  (2,'pl','Ten obcy też jest czyimś dzieckiem'),(2,'en','That stranger is someone''s child too')
) as v(position, locale, text) on v.position = ins.position;

-- nr99: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'bf0055f9-21a7-4615-940a-1cad65d17ccd');
delete from public.question_smaczki where question_id = 'bf0055f9-21a7-4615-940a-1cad65d17ccd';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('bf0055f9-21a7-4615-940a-1cad65d17ccd',1,true),('bf0055f9-21a7-4615-940a-1cad65d17ccd',2,true),('bf0055f9-21a7-4615-940a-1cad65d17ccd',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Odległość pogłębia uczucie?'),(1,'en','Distance deepens it?'),
  (2,'pl','Miłość potrzebuje bliskości'),(2,'en','Love needs touch'),
  (3,'pl','Kochasz jego czy swoje wyobrażenie o nim?'),(3,'en','Do you love him, or your image of him?')
) as v(position, locale, text) on v.position = ins.position;

-- nr100: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'c3a62fe2-f55f-4d8d-8d76-6e22f58531d9');
delete from public.question_smaczki where question_id = 'c3a62fe2-f55f-4d8d-8d76-6e22f58531d9';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('c3a62fe2-f55f-4d8d-8d76-6e22f58531d9',1,true),('c3a62fe2-f55f-4d8d-8d76-6e22f58531d9',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Stabilność też się liczy'),(1,'en','Security is real'),
  (2,'pl','Pieniądze mówią o zaradności danej osoby'),(2,'en','Money shows how capable someone is')
) as v(position, locale, text) on v.position = ins.position;

-- nr101: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'c4fbed60-ab48-4f03-831f-0d2ec937e739');
delete from public.question_smaczki where question_id = 'c4fbed60-ab48-4f03-831f-0d2ec937e739';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('c4fbed60-ab48-4f03-831f-0d2ec937e739',1,true),('c4fbed60-ab48-4f03-831f-0d2ec937e739',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Starzenie się głowy jest i tak gorsze niż starzenie się ciała'),(1,'en','A mind aging is worse than a body aging anyway'),
  (2,'pl','Wszyscy, których kochasz, i tak się zestarzeją'),(2,'en','Everyone you love still grows old')
) as v(position, locale, text) on v.position = ins.position;

-- nr102: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'c76d0a4e-02e4-4c76-bcb2-29e58b665982');
delete from public.question_smaczki where question_id = 'c76d0a4e-02e4-4c76-bcb2-29e58b665982';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('c76d0a4e-02e4-4c76-bcb2-29e58b665982',1,true),('c76d0a4e-02e4-4c76-bcb2-29e58b665982',2,true),('c76d0a4e-02e4-4c76-bcb2-29e58b665982',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Przynajmniej zostawisz coś potomkom'),(1,'en','At least you''d leave something behind'),
  (2,'pl','Później zapłacisz za lepszą opiekę medyczną'),(2,'en','Later you can pay for better healthcare'),
  (3,'pl','Życie bez pieniędzy i bez zdrowia jest tak samo trudne'),(3,'en','A life without money or health is just as hard')
) as v(position, locale, text) on v.position = ins.position;

commit;