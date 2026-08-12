-- ============================================================================
-- Catalog edit batch 3 (master-file diff, rows nr 90-136)
-- 12 deletes, 6 question-text edits, 26 smaczki rebuilds. EN adapted by
-- assistant for every changed PL (user left EN untouched). 4 PL typos fixed
-- (nr111, nr112, nr121 smaczki + nr134 question). No seed changes.
-- Deletes backed up to *_batch3.backup.json.
-- ============================================================================
begin;

delete from public.daily_questions where publish_date > (now() at time zone 'utc')::date + 1;

delete from public.daily_questions d
using (values
  ('d002cb6b-dc1d-4220-9df2-276108e06100'),
  ('e7fe5afe-d2e0-4474-9c93-20a45f17caea'),
  ('f005102b-30df-4b52-9697-422ce52251c1'),
  ('f1e673d0-39db-4fd8-8da3-2d4c6048d4ee'),
  ('fe3abcd8-f2d7-43cc-bcb0-cb5d3fd35850'),
  ('0cc7b9ae-08d0-4a3d-bd01-2194380f6e1f'),
  ('0eb5cdb9-c34c-43dd-b317-367d24aa2124'),
  ('0faa86b3-ae65-46c1-9026-0bb03c279141'),
  ('150f2136-acfc-43b5-978d-ad407aca64f3'),
  ('21e7d90b-c1d5-4c00-8b8d-eaf989460cf7'),
  ('238ce879-188a-4ed9-a3c9-6f4bbe6c0b1b'),
  ('459fe263-b93d-4942-b0ee-d4795efaf910')
) as del(id)
where d.question_id = del.id::uuid;

delete from public.questions q
using (values
  ('d002cb6b-dc1d-4220-9df2-276108e06100'),
  ('e7fe5afe-d2e0-4474-9c93-20a45f17caea'),
  ('f005102b-30df-4b52-9697-422ce52251c1'),
  ('f1e673d0-39db-4fd8-8da3-2d4c6048d4ee'),
  ('fe3abcd8-f2d7-43cc-bcb0-cb5d3fd35850'),
  ('0cc7b9ae-08d0-4a3d-bd01-2194380f6e1f'),
  ('0eb5cdb9-c34c-43dd-b317-367d24aa2124'),
  ('0faa86b3-ae65-46c1-9026-0bb03c279141'),
  ('150f2136-acfc-43b5-978d-ad407aca64f3'),
  ('21e7d90b-c1d5-4c00-8b8d-eaf989460cf7'),
  ('238ce879-188a-4ed9-a3c9-6f4bbe6c0b1b'),
  ('459fe263-b93d-4942-b0ee-d4795efaf910')
) as del(id)
where q.id = del.id::uuid;

with anchor as (select coalesce(max(publish_date), (now() at time zone 'utc')::date) as last_day from public.daily_questions),
pool as (select qq.id, (row_number() over (order by random()))::int as rn from public.questions qq
         where qq.is_active and not exists (select 1 from public.daily_questions d where d.question_id = qq.id))
insert into public.daily_questions (publish_date, question_id)
select (select last_day from anchor) + pool.rn, pool.id from pool;

-- Question text edits.
-- nr91
update public.question_translations set question_text = 'Czy utrzymywać starą przyjaźń, gdy nie macie już nic wspólnego?' where question_id = 'c8f48861-e03e-4009-80fe-126235099979' and locale = 'pl';
update public.question_translations set question_text = 'Should you keep an old friendship when you no longer have anything in common?' where question_id = 'c8f48861-e03e-4009-80fe-126235099979' and locale = 'en';
-- nr93
update public.question_translations set question_text = 'Czy powinno się zerwać kontakt z raniącą cię rodziną?' where question_id = 'd4ec7814-64c9-44d6-b695-ab52f5e138a9' and locale = 'pl';
update public.question_translations set question_text = 'Should you cut off family members who hurt you?' where question_id = 'd4ec7814-64c9-44d6-b695-ab52f5e138a9' and locale = 'en';
-- nr100
update public.question_translations set question_text = 'Czy da się zostać szczerymi przyjaciółmi z byłym partnerem?' where question_id = 'ee514625-9f02-4ba7-86f9-a0a3b96dfcb1' and locale = 'pl';
update public.question_translations set question_text = 'Is it possible to stay genuine friends with an ex-partner?' where question_id = 'ee514625-9f02-4ba7-86f9-a0a3b96dfcb1' and locale = 'en';
-- nr128
update public.question_translations set question_text = 'Czy powinieneś pozwolić dziecku rzucić pasje, gdy tylko straci zainteresowanie?' where question_id = '37435f36-0877-4921-b3fa-87f876fc42cc' and locale = 'pl';
update public.question_translations set question_text = 'Should you let your child quit a hobby the moment they lose interest?' where question_id = '37435f36-0877-4921-b3fa-87f876fc42cc' and locale = 'en';
-- nr130
update public.question_translations set question_text = 'Czy słodycze powinny być zakazane dla dzieci?' where question_id = '3a5a5003-be7a-40b4-b047-a1d358ca3d87' and locale = 'pl';
update public.question_translations set question_text = 'Should sweets be off-limits for kids?' where question_id = '3a5a5003-be7a-40b4-b047-a1d358ca3d87' and locale = 'en';
-- nr134
update public.question_translations set question_text = 'Czy powinieneś mówić dzieciom, jakie problemy finansowe ma rodzina?' where question_id = '493f7127-261a-44ec-973d-cbf0e5753ec6' and locale = 'pl';
update public.question_translations set question_text = 'Should you tell your kids about the family''s money problems?' where question_id = '493f7127-261a-44ec-973d-cbf0e5753ec6' and locale = 'en';

-- Smaczki rebuilds.
-- nr90: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'c7715dd2-3685-421b-a018-96bddcb60664');
delete from public.question_smaczki where question_id = 'c7715dd2-3685-421b-a018-96bddcb60664';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('c7715dd2-3685-421b-a018-96bddcb60664',1,true),('c7715dd2-3685-421b-a018-96bddcb60664',2,true),('c7715dd2-3685-421b-a018-96bddcb60664',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Dumni z miłości?'),(1,'en','Proud of your love?'),
  (2,'pl','Prawdziwa miłość lubi ciszę'),(2,'en','Real love stays private'),
  (3,'pl','Najgłośniejsze pary rozstają się w ciszy'),(3,'en','The loudest couples split in silence')
) as v(position, locale, text) on v.position = ins.position;

-- nr91: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'c8f48861-e03e-4009-80fe-126235099979');
delete from public.question_smaczki where question_id = 'c8f48861-e03e-4009-80fe-126235099979';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('c8f48861-e03e-4009-80fe-126235099979',1,true),('c8f48861-e03e-4009-80fe-126235099979',2,true),('c8f48861-e03e-4009-80fe-126235099979',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Z jakiegoś powodu kiedyś się przyjaźniliście'),(1,'en','You became friends for a reason'),
  (2,'pl','Tylko nostalgia?'),(2,'en','Just nostalgia?'),
  (3,'pl','Trzymasz człowieka czy wspomnienie?'),(3,'en','Holding the person, or the memory?')
) as v(position, locale, text) on v.position = ins.position;

-- nr93: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'd4ec7814-64c9-44d6-b695-ab52f5e138a9');
delete from public.question_smaczki where question_id = 'd4ec7814-64c9-44d6-b695-ab52f5e138a9';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('d4ec7814-64c9-44d6-b695-ab52f5e138a9',1,true),('d4ec7814-64c9-44d6-b695-ab52f5e138a9',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Rodziny nie wybierasz, a na resztę życia masz wpływ'),(1,'en','You don''t pick your family — the rest of your life you do'),
  (2,'pl','Zobowiązania tylko w jedną stronę?'),(2,'en','Obligations only one way?')
) as v(position, locale, text) on v.position = ins.position;

-- nr94: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'd64bc98c-d637-4bf9-8dba-f911c7ecf294');
delete from public.question_smaczki where question_id = 'd64bc98c-d637-4bf9-8dba-f911c7ecf294';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('d64bc98c-d637-4bf9-8dba-f911c7ecf294',1,true),('d64bc98c-d637-4bf9-8dba-f911c7ecf294',2,true),('d64bc98c-d637-4bf9-8dba-f911c7ecf294',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Wychowali cię'),(1,'en','They raised you'),
  (2,'pl','A jeśli cię zawiedli? A teraz i tak wykorzystują?'),(2,'en','And if they failed you — and still use you?'),
  (3,'pl','Każdy ma jedno życie'),(3,'en','Everyone gets one life')
) as v(position, locale, text) on v.position = ins.position;

-- nr95: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'd81b1b26-6a24-4f80-9ee0-1035ca8a3047');
delete from public.question_smaczki where question_id = 'd81b1b26-6a24-4f80-9ee0-1035ca8a3047';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('d81b1b26-6a24-4f80-9ee0-1035ca8a3047',1,true),('d81b1b26-6a24-4f80-9ee0-1035ca8a3047',2,true),('d81b1b26-6a24-4f80-9ee0-1035ca8a3047',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Jego sprawa'),(1,'en','It''s his business'),
  (2,'pl','Może Ciebie też okłamuje?'),(2,'en','Maybe he lies to you too?'),
  (3,'pl','Cudzy sekret staje się twoim ciężarem'),(3,'en','Their secret becomes your burden')
) as v(position, locale, text) on v.position = ins.position;

-- nr96: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'e0c09634-e3a2-4f77-8c70-1cde7de47356');
delete from public.question_smaczki where question_id = 'e0c09634-e3a2-4f77-8c70-1cde7de47356';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('e0c09634-e3a2-4f77-8c70-1cde7de47356',1,true),('e0c09634-e3a2-4f77-8c70-1cde7de47356',2,true),('e0c09634-e3a2-4f77-8c70-1cde7de47356',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Liczą się tylko czyny?'),(1,'en','Only deeds count?'),
  (2,'pl','Co cię powstrzymało?'),(2,'en','What stopped you?'),
  (3,'pl','Ludzie myślą o różnych dziwnych rzeczach'),(3,'en','People think all kinds of strange things')
) as v(position, locale, text) on v.position = ins.position;

-- nr97: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'e2f49168-00ec-41ff-aad2-86ec09ce0740');
delete from public.question_smaczki where question_id = 'e2f49168-00ec-41ff-aad2-86ec09ce0740';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('e2f49168-00ec-41ff-aad2-86ec09ce0740',1,true),('e2f49168-00ec-41ff-aad2-86ec09ce0740',2,true),('e2f49168-00ec-41ff-aad2-86ec09ce0740',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Najpierw prawdziwy świat'),(1,'en','Real world first'),
  (2,'pl','Zostanie w tyle za rówieśnikami?'),(2,'en','Left behind by peers?'),
  (3,'pl','Ewolucja, czy to nie za szybko dla mózgu?'),(3,'en','Evolution — too fast for the brain?')
) as v(position, locale, text) on v.position = ins.position;

-- nr99: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'ea9f2a4b-0145-4e05-9677-f8941205ed78');
delete from public.question_smaczki where question_id = 'ea9f2a4b-0145-4e05-9677-f8941205ed78';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('ea9f2a4b-0145-4e05-9677-f8941205ed78',1,true),('ea9f2a4b-0145-4e05-9677-f8941205ed78',2,true),('ea9f2a4b-0145-4e05-9677-f8941205ed78',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Chronić niewinność?'),(1,'en','Protect their innocence?'),
  (2,'pl','Prawda ich wzmacnia?'),(2,'en','Truth makes them strong?'),
  (3,'pl','Chronisz je czy utrzymujesz własny komfort?'),(3,'en','Protecting them, or your own comfort?')
) as v(position, locale, text) on v.position = ins.position;

-- nr102: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'f0115cbf-7882-4e22-819c-6d6987d311a4');
delete from public.question_smaczki where question_id = 'f0115cbf-7882-4e22-819c-6d6987d311a4';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('f0115cbf-7882-4e22-819c-6d6987d311a4',1,true),('f0115cbf-7882-4e22-819c-6d6987d311a4',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Jeśli to był przypadek?'),(1,'en','What if it was an accident?'),
  (2,'pl','A jeśli to było coś bardzo złego? Czy ludzie się zmieniają?'),(2,'en','And if it was something terrible? Do people change?')
) as v(position, locale, text) on v.position = ins.position;

-- nr106: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'f6e053cf-4ff4-41cc-b073-a9506fbc402d');
delete from public.question_smaczki where question_id = 'f6e053cf-4ff4-41cc-b073-a9506fbc402d';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('f6e053cf-4ff4-41cc-b073-a9506fbc402d',1,true),('f6e053cf-4ff4-41cc-b073-a9506fbc402d',2,true),('f6e053cf-4ff4-41cc-b073-a9506fbc402d',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Winić czyjeś uczucia?'),(1,'en','Blame someone''s feelings?'),
  (2,'pl','Powiedz to ofierze'),(2,'en','Tell that to the victim'),
  (3,'pl','Piekło brukowane dobrymi chęciami'),(3,'en','The road to hell is paved with these')
) as v(position, locale, text) on v.position = ins.position;

-- nr107: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = 'f92381dd-90d4-4437-ab5d-7a2f4086a5a4');
delete from public.question_smaczki where question_id = 'f92381dd-90d4-4437-ab5d-7a2f4086a5a4';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('f92381dd-90d4-4437-ab5d-7a2f4086a5a4',1,true),('f92381dd-90d4-4437-ab5d-7a2f4086a5a4',2,true),('f92381dd-90d4-4437-ab5d-7a2f4086a5a4',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Jesteśmy sobie coś winni?'),(1,'en','We owe each other?'),
  (2,'pl','Twoje życie należy do ciebie'),(2,'en','Your life is yours'),
  (3,'pl','A jak to nic niewinne dziecko?'),(3,'en','And if it''s a completely innocent child?')
) as v(position, locale, text) on v.position = ins.position;

-- nr109: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '04cb8a54-9eeb-4afd-9342-d46ffd8f5aa1');
delete from public.question_smaczki where question_id = '04cb8a54-9eeb-4afd-9342-d46ffd8f5aa1';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('04cb8a54-9eeb-4afd-9342-d46ffd8f5aa1',1,true),('04cb8a54-9eeb-4afd-9342-d46ffd8f5aa1',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Traktujesz się jak dziecko?'),(1,'en','Treating yourself like a kid?'),
  (2,'pl','Blokada przyznaje, że przegrałeś z sobą'),(2,'en','A lock admits you lost to yourself')
) as v(position, locale, text) on v.position = ins.position;

-- nr110: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '067b7ce6-b861-474e-b3c5-34ea08893292');
delete from public.question_smaczki where question_id = '067b7ce6-b861-474e-b3c5-34ea08893292';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('067b7ce6-b861-474e-b3c5-34ea08893292',1,true),('067b7ce6-b861-474e-b3c5-34ea08893292',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Sięgaj po więcej?'),(1,'en','Reach for more?'),
  (2,'pl','Spokój to też zwycięstwo'),(2,'en','Peace is winning too')
) as v(position, locale, text) on v.position = ins.position;

-- nr111: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '0987b202-98bb-4586-b44b-f5afaba0d7e3');
delete from public.question_smaczki where question_id = '0987b202-98bb-4586-b44b-f5afaba0d7e3';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('0987b202-98bb-4586-b44b-f5afaba0d7e3',1,true),('0987b202-98bb-4586-b44b-f5afaba0d7e3',2,true),('0987b202-98bb-4586-b44b-f5afaba0d7e3',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Prawo na nowy start?'),(1,'en','Right to move on?'),
  (2,'pl','Ludzie mają prawo wiedzieć dla własnego bezpieczeństwa'),(2,'en','People have a right to know, for their own safety'),
  (3,'pl','Kara skończona, piętno wieczne?'),(3,'en','Sentence served, stigma forever?')
) as v(position, locale, text) on v.position = ins.position;

-- nr112: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '09e0d16d-aa5c-48f4-bf33-9e6c95f9a354');
delete from public.question_smaczki where question_id = '09e0d16d-aa5c-48f4-bf33-9e6c95f9a354';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('09e0d16d-aa5c-48f4-bf33-9e6c95f9a354',1,true),('09e0d16d-aa5c-48f4-bf33-9e6c95f9a354',2,true),('09e0d16d-aa5c-48f4-bf33-9e6c95f9a354',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Koniec wyścigu?'),(1,'en','End the race?'),
  (2,'pl','Czy istnieliby influencerzy?'),(2,'en','Would influencers even exist?'),
  (3,'pl','Bez licznika i tak byś się porównywał'),(3,'en','You''d compare anyway, counter or not')
) as v(position, locale, text) on v.position = ins.position;

-- nr113: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '0b30f36c-e6c6-4d00-9278-45b9df8e1a30');
delete from public.question_smaczki where question_id = '0b30f36c-e6c6-4d00-9278-45b9df8e1a30';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('0b30f36c-e6c6-4d00-9278-45b9df8e1a30',1,true),('0b30f36c-e6c6-4d00-9278-45b9df8e1a30',2,true),('0b30f36c-e6c6-4d00-9278-45b9df8e1a30',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Religie zawsze można zmienić'),(1,'en','You can always change religion'),
  (2,'pl','Wolny wybór?'),(2,'en','Free to choose?'),
  (3,'pl','Wiara z domu to loteria'),(3,'en','The faith you''re born into is a lottery')
) as v(position, locale, text) on v.position = ins.position;

-- nr114: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '0c7e3c0f-f862-4c4b-88e2-5964931915fa');
delete from public.question_smaczki where question_id = '0c7e3c0f-f862-4c4b-88e2-5964931915fa';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('0c7e3c0f-f862-4c4b-88e2-5964931915fa',1,true),('0c7e3c0f-f862-4c4b-88e2-5964931915fa',2,true),('0c7e3c0f-f862-4c4b-88e2-5964931915fa',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Śmierć nieświadomego może uratuje pięć osób'),(1,'en','An unaware person''s death might save five'),
  (2,'pl','Moje ciało wciąż jest moje'),(2,'en','My body is still mine'),
  (3,'pl','A jak ktoś zapomni, a chciałby oddać?'),(3,'en','And if someone forgets, but would have donated?')
) as v(position, locale, text) on v.position = ins.position;

-- nr121: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '1c64dad7-392a-4ecf-b5c7-54a47edcc31b');
delete from public.question_smaczki where question_id = '1c64dad7-392a-4ecf-b5c7-54a47edcc31b';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('1c64dad7-392a-4ecf-b5c7-54a47edcc31b',1,true),('1c64dad7-392a-4ecf-b5c7-54a47edcc31b',2,true),('1c64dad7-392a-4ecf-b5c7-54a47edcc31b',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Czy zależy od tego jakie to zwierzę?'),(1,'en','Does it depend on the animal?'),
  (2,'pl','Gdzie jest granica?'),(2,'en','Where''s the line?'),
  (3,'pl','Odmówiłbyś leku, który tak powstał?'),(3,'en','Would you refuse a cure made this way?')
) as v(position, locale, text) on v.position = ins.position;

-- nr123: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '1f056bfe-b249-4356-bd32-6fb63a3dd515');
delete from public.question_smaczki where question_id = '1f056bfe-b249-4356-bd32-6fb63a3dd515';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('1f056bfe-b249-4356-bd32-6fb63a3dd515',1,true),('1f056bfe-b249-4356-bd32-6fb63a3dd515',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Ich sprzęt?'),(1,'en','Their computer?'),
  (2,'pl','Czy powinieneś pisać sms''y w pracy?'),(2,'en','Should you be texting at work?')
) as v(position, locale, text) on v.position = ins.position;

-- nr127: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '2a43d344-370a-472f-b7b3-6cd85940654c');
delete from public.question_smaczki where question_id = '2a43d344-370a-472f-b7b3-6cd85940654c';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('2a43d344-370a-472f-b7b3-6cd85940654c',1,true),('2a43d344-370a-472f-b7b3-6cd85940654c',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','To tylko gra?'),(1,'en','Just a game?'),
  (2,'pl','Ktoś lepszy zawsze o jedno przesunięcie'),(2,'en','Someone better is always one swipe away')
) as v(position, locale, text) on v.position = ins.position;

-- nr128: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '37435f36-0877-4921-b3fa-87f876fc42cc');
delete from public.question_smaczki where question_id = '37435f36-0877-4921-b3fa-87f876fc42cc';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('37435f36-0877-4921-b3fa-87f876fc42cc',1,true),('37435f36-0877-4921-b3fa-87f876fc42cc',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Może to chwilowa zachcianka'),(1,'en','Maybe it''s a passing whim'),
  (2,'pl','Uczysz, że trudne znaczy do porzucenia'),(2,'en','You teach it that hard means quit')
) as v(position, locale, text) on v.position = ins.position;

-- nr130: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '3a5a5003-be7a-40b4-b047-a1d358ca3d87');
delete from public.question_smaczki where question_id = '3a5a5003-be7a-40b4-b047-a1d358ca3d87';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('3a5a5003-be7a-40b4-b047-a1d358ca3d87',1,true),('3a5a5003-be7a-40b4-b047-a1d358ca3d87',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Zdrowie, zęby?'),(1,'en','Health, teeth?'),
  (2,'pl','Zakazany cukierek staje się skarbem'),(2,'en','The banned sweet becomes treasure')
) as v(position, locale, text) on v.position = ins.position;

-- nr131: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '4061f4e5-4be8-4b2c-b673-326768013ac0');
delete from public.question_smaczki where question_id = '4061f4e5-4be8-4b2c-b673-326768013ac0';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('4061f4e5-4be8-4b2c-b673-326768013ac0',1,true),('4061f4e5-4be8-4b2c-b673-326768013ac0',2,true),('4061f4e5-4be8-4b2c-b673-326768013ac0',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Zagrożenie dla sąsiadów'),(1,'en','A danger to the neighbors'),
  (2,'pl','Czyje życie, czyj wybór?'),(2,'en','Whose life, whose choice?'),
  (3,'pl','Czemu sami wyznaczamy jaki zwierzak może być udomowiony'),(3,'en','Why do we decide which animal counts as a pet?')
) as v(position, locale, text) on v.position = ins.position;

-- nr132: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '43a5f8fb-62e6-442d-a856-836e131f98e7');
delete from public.question_smaczki where question_id = '43a5f8fb-62e6-442d-a856-836e131f98e7';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('43a5f8fb-62e6-442d-a856-836e131f98e7',1,true),('43a5f8fb-62e6-442d-a856-836e131f98e7',2,true),('43a5f8fb-62e6-442d-a856-836e131f98e7',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Powtórka pomaga'),(1,'en','Practice helps'),
  (2,'pl','Po coś jest w końcu szkoła'),(2,'en','School exists for a reason'),
  (3,'pl','Ty po pracy nie robisz nadgodzin gratis'),(3,'en','You wouldn''t take unpaid overtime home')
) as v(position, locale, text) on v.position = ins.position;

-- nr135: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '49a38dba-981a-46a1-b6db-dd11b0108aee');
delete from public.question_smaczki where question_id = '49a38dba-981a-46a1-b6db-dd11b0108aee';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('49a38dba-981a-46a1-b6db-dd11b0108aee',1,true),('49a38dba-981a-46a1-b6db-dd11b0108aee',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Koniec z trollami?'),(1,'en','No more trolls?'),
  (2,'pl','Żegnaj prywatności?'),(2,'en','Goodbye privacy?')
) as v(position, locale, text) on v.position = ins.position;

-- nr136: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '4a33cd2f-ee4a-42ac-88a5-2fa576ea5e17');
delete from public.question_smaczki where question_id = '4a33cd2f-ee4a-42ac-88a5-2fa576ea5e17';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('4a33cd2f-ee4a-42ac-88a5-2fa576ea5e17',1,true),('4a33cd2f-ee4a-42ac-88a5-2fa576ea5e17',2,true),('4a33cd2f-ee4a-42ac-88a5-2fa576ea5e17',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Czemu mam płacić za twoje wybory?'),(1,'en','Why should I pay for your choices?'),
  (2,'pl','Karanie ludzi za bycie ludźmi'),(2,'en','Punishing people for being human'),
  (3,'pl','Pozytywne testy na narkotyki, albo płuca palacza = wyższe opłaty'),(3,'en','Positive drug tests or smoker''s lungs = higher premiums')
) as v(position, locale, text) on v.position = ins.position;

commit;