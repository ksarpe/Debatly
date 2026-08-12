-- ============================================================================
-- Catalog edit batch 5 (master diff, rows nr 201-257)
-- 24 deletes, 2 question-text edits, 18 smaczki rebuilds. EN adapted by
-- assistant for every changed PL. 1 PL comma fix (nr248).
-- Diff ignores the EN columns and compares smaczki as a COMPACTED list,
-- because prod is renumbered 1..N while the stale master keeps gaps.
-- Deletes backed up to *_batch5.backup.json.
-- ============================================================================
begin;

delete from public.daily_questions where publish_date > (now() at time zone 'utc')::date + 1;

delete from public.daily_questions d
using (values
  ('fecc9d88-049f-419b-9837-3cb26476d151'),
  ('0122e884-25be-489a-a243-cc12ba80a3e7'),
  ('012aa897-e789-4e08-b7e5-54bc5c9b1db2'),
  ('01d9bbef-56fe-4cb3-92d7-7452eade098d'),
  ('0220968b-6648-4c31-a795-14ed2953e95e'),
  ('047b3061-e975-4cc4-a9ae-1bae31f511e2'),
  ('07c1209e-eb9b-4bfb-a7bc-658506464cef'),
  ('09aa5f38-6905-422e-b12f-086231eb571c'),
  ('0d84dc1a-0a33-4a91-8d4d-e03c43b180e2'),
  ('102eef52-02cb-4057-bc49-97ab0efe7a72'),
  ('13a2352e-e6fb-4118-8b3f-90c8a6c4f692'),
  ('146086e7-45cd-445c-a04f-af961cd7d085'),
  ('15190b24-d99d-41ba-aa8f-8cf665f1a57a'),
  ('15fdaea8-e17e-4961-a27f-5bcc0995b3bd'),
  ('1681e78a-d232-45e9-aa33-0aa54afa7fd7'),
  ('17ed929a-f40b-48b4-8912-42666e7ab47f'),
  ('19499321-12ba-4248-ad3c-2e9f2a20e963'),
  ('1bdf8e5b-f0d1-47fc-bf15-bd9007e32e2d'),
  ('1bfe41c0-14ef-44f2-ab0d-dd07c1a46e5e'),
  ('1faaf97b-1667-4862-8f69-bfc5efef114e'),
  ('244e48d2-400c-4fe5-9e28-777b8be0e39b'),
  ('25637ec6-1dbc-4a45-bf2c-0544286aac0a'),
  ('2897f138-119f-4e6d-85bb-56446d1785d8'),
  ('291e9092-bb5b-4a63-b58d-30ad01ae4753')
) as del(id)
where d.question_id = del.id::uuid;

delete from public.questions q
using (values
  ('fecc9d88-049f-419b-9837-3cb26476d151'),
  ('0122e884-25be-489a-a243-cc12ba80a3e7'),
  ('012aa897-e789-4e08-b7e5-54bc5c9b1db2'),
  ('01d9bbef-56fe-4cb3-92d7-7452eade098d'),
  ('0220968b-6648-4c31-a795-14ed2953e95e'),
  ('047b3061-e975-4cc4-a9ae-1bae31f511e2'),
  ('07c1209e-eb9b-4bfb-a7bc-658506464cef'),
  ('09aa5f38-6905-422e-b12f-086231eb571c'),
  ('0d84dc1a-0a33-4a91-8d4d-e03c43b180e2'),
  ('102eef52-02cb-4057-bc49-97ab0efe7a72'),
  ('13a2352e-e6fb-4118-8b3f-90c8a6c4f692'),
  ('146086e7-45cd-445c-a04f-af961cd7d085'),
  ('15190b24-d99d-41ba-aa8f-8cf665f1a57a'),
  ('15fdaea8-e17e-4961-a27f-5bcc0995b3bd'),
  ('1681e78a-d232-45e9-aa33-0aa54afa7fd7'),
  ('17ed929a-f40b-48b4-8912-42666e7ab47f'),
  ('19499321-12ba-4248-ad3c-2e9f2a20e963'),
  ('1bdf8e5b-f0d1-47fc-bf15-bd9007e32e2d'),
  ('1bfe41c0-14ef-44f2-ab0d-dd07c1a46e5e'),
  ('1faaf97b-1667-4862-8f69-bfc5efef114e'),
  ('244e48d2-400c-4fe5-9e28-777b8be0e39b'),
  ('25637ec6-1dbc-4a45-bf2c-0544286aac0a'),
  ('2897f138-119f-4e6d-85bb-56446d1785d8'),
  ('291e9092-bb5b-4a63-b58d-30ad01ae4753')
) as del(id)
where q.id = del.id::uuid;

with anchor as (select coalesce(max(publish_date), (now() at time zone 'utc')::date) as last_day from public.daily_questions),
pool as (select qq.id, (row_number() over (order by random()))::int as rn from public.questions qq
         where qq.is_active and not exists (select 1 from public.daily_questions d where d.question_id = qq.id))
insert into public.daily_questions (publish_date, question_id)
select (select last_day from anchor) + pool.rn, pool.id from pool;

-- Question text edits.
-- nr226
update public.question_translations set question_text = 'Czy powinieneś pozwolić 7-letniemu dziecku samemu chodzić do szkoły?' where question_id = '0fdb9a97-4e09-440b-93cf-522c2fc06d12' and locale = 'pl';
update public.question_translations set question_text = 'Should you let a 7-year-old walk to school alone?' where question_id = '0fdb9a97-4e09-440b-93cf-522c2fc06d12' and locale = 'en';
-- nr247
update public.question_translations set question_text = 'Czy każde dziecko powinno grać w jakiś sport drużynowy?' where question_id = '208d40e6-c120-403f-9eea-34aeef9408f8' and locale = 'pl';
update public.question_translations set question_text = 'Should every child play some team sport?' where question_id = '208d40e6-c120-403f-9eea-34aeef9408f8' and locale = 'en';

-- Smaczki rebuilds.
-- nr206: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '00f4ba3f-b62b-4e80-8a78-f82da71792d2');
delete from public.question_smaczki where question_id = '00f4ba3f-b62b-4e80-8a78-f82da71792d2';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('00f4ba3f-b62b-4e80-8a78-f82da71792d2',1,true),('00f4ba3f-b62b-4e80-8a78-f82da71792d2',2,true),('00f4ba3f-b62b-4e80-8a78-f82da71792d2',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Idealna ucieczka?'),(1,'en','A perfect escape?'),
  (2,'pl','Wakacje, reset'),(2,'en','A holiday, a reset'),
  (3,'pl','Wrócisz do życia, które olałeś'),(3,'en','You return to the life you left')
) as v(position, locale, text) on v.position = ins.position;

-- nr212: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '04a84a55-fadc-49ef-b011-bafd811c28fe');
delete from public.question_smaczki where question_id = '04a84a55-fadc-49ef-b011-bafd811c28fe';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('04a84a55-fadc-49ef-b011-bafd811c28fe',1,true),('04a84a55-fadc-49ef-b011-bafd811c28fe',2,true),('04a84a55-fadc-49ef-b011-bafd811c28fe',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Im ufasz najbardziej'),(1,'en','You trust them most'),
  (2,'pl','Babci nie zwolnisz'),(2,'en','No firing grandma'),
  (3,'pl','Święta staną się negocjacjami'),(3,'en','The holidays become negotiations')
) as v(position, locale, text) on v.position = ins.position;

-- nr213: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '050b706a-6739-475a-b9a6-2cfec20215be');
delete from public.question_smaczki where question_id = '050b706a-6739-475a-b9a6-2cfec20215be';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('050b706a-6739-475a-b9a6-2cfec20215be',1,true),('050b706a-6739-475a-b9a6-2cfec20215be',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Cel ponad środki?'),(1,'en','Ends over means?'),
  (2,'pl','Zwycięzców rzadko pytają o metody'),(2,'en','Winners are rarely asked how')
) as v(position, locale, text) on v.position = ins.position;

-- nr214: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '053d2c7d-51c4-4af4-bbd6-0c751b29311f');
delete from public.question_smaczki where question_id = '053d2c7d-51c4-4af4-bbd6-0c751b29311f';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('053d2c7d-51c4-4af4-bbd6-0c751b29311f',1,true),('053d2c7d-51c4-4af4-bbd6-0c751b29311f',2,true),('053d2c7d-51c4-4af4-bbd6-0c751b29311f',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Jedno ma się zmuszać?'),(1,'en','Should one of you force it?'),
  (2,'pl','Osoba z większym pociągiem i tak zdradzi?'),(2,'en','The one who wants it more will cheat anyway?'),
  (3,'pl','Seks bez chęci dwóch osób nie ma sensu'),(3,'en','Sex without both wanting it is pointless')
) as v(position, locale, text) on v.position = ins.position;

-- nr215: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '05578e3b-161a-495e-8763-496240330612');
delete from public.question_smaczki where question_id = '05578e3b-161a-495e-8763-496240330612';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('05578e3b-161a-495e-8763-496240330612',1,true),('05578e3b-161a-495e-8763-496240330612',2,true),('05578e3b-161a-495e-8763-496240330612',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Czysta karta?'),(1,'en','Fresh start?'),
  (2,'pl','Wymazujesz historię?'),(2,'en','Erasing your story?'),
  (3,'pl','Czy to ma jakieś znaczenie?'),(3,'en','Does it even matter?')
) as v(position, locale, text) on v.position = ins.position;

-- nr217: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '08040275-5fe3-4a30-acae-2cca190275ac');
delete from public.question_smaczki where question_id = '08040275-5fe3-4a30-acae-2cca190275ac';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('08040275-5fe3-4a30-acae-2cca190275ac',1,true),('08040275-5fe3-4a30-acae-2cca190275ac',2,true),('08040275-5fe3-4a30-acae-2cca190275ac',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Tradycja trzyma?'),(1,'en','Tradition holds?'),
  (2,'pl','Liczy się efekt'),(2,'en','The outcome is what counts'),
  (3,'pl','Czekasz na niego z powodu, którego nikt nie pamięta'),(3,'en','You wait on him for a reason no one remembers')
) as v(position, locale, text) on v.position = ins.position;

-- nr225: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '0e573e33-e62f-4009-ad37-eab49c4aefe4');
delete from public.question_smaczki where question_id = '0e573e33-e62f-4009-ad37-eab49c4aefe4';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('0e573e33-e62f-4009-ad37-eab49c4aefe4',1,true),('0e573e33-e62f-4009-ad37-eab49c4aefe4',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','To tylko przedmioty?'),(1,'en','Just objects?'),
  (2,'pl','Przedmiot niewinny, uczucie mniej'),(2,'en','The object''s innocent; the feeling less so')
) as v(position, locale, text) on v.position = ins.position;

-- nr226: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '0fdb9a97-4e09-440b-93cf-522c2fc06d12');
delete from public.question_smaczki where question_id = '0fdb9a97-4e09-440b-93cf-522c2fc06d12';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('0fdb9a97-4e09-440b-93cf-522c2fc06d12',1,true),('0fdb9a97-4e09-440b-93cf-522c2fc06d12',2,true),('0fdb9a97-4e09-440b-93cf-522c2fc06d12',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Uczy samodzielności?'),(1,'en','Builds independence?'),
  (2,'pl','Za dużo zagrożeń?'),(2,'en','Too many dangers?'),
  (3,'pl','Jest limit odległości?'),(3,'en','Is there a distance limit?')
) as v(position, locale, text) on v.position = ins.position;

-- nr229: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '11962158-eb0f-44b2-a393-1757dea565ba');
delete from public.question_smaczki where question_id = '11962158-eb0f-44b2-a393-1757dea565ba';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('11962158-eb0f-44b2-a393-1757dea565ba',1,true),('11962158-eb0f-44b2-a393-1757dea565ba',2,true),('11962158-eb0f-44b2-a393-1757dea565ba',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Żyj chwilą?'),(1,'en','Live for the moment?'),
  (2,'pl','Czekali na ciebie?'),(2,'en','They waited for you?'),
  (3,'pl','Powinieneś stawiać siebie na pierwszym miejscu'),(3,'en','You should put yourself first')
) as v(position, locale, text) on v.position = ins.position;

-- nr232: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '149c384e-54ce-4310-8b34-84e1937265cc');
delete from public.question_smaczki where question_id = '149c384e-54ce-4310-8b34-84e1937265cc';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('149c384e-54ce-4310-8b34-84e1937265cc',1,true),('149c384e-54ce-4310-8b34-84e1937265cc',2,true),('149c384e-54ce-4310-8b34-84e1937265cc',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Klucz do szczupłej sylwetki?'),(1,'en','The key to staying slim?'),
  (2,'pl','Marnowanie jedzenia'),(2,'en','Wasting food'),
  (3,'pl','Sytość spóźnia się o dwadzieścia minut'),(3,'en','Fullness arrives twenty minutes late')
) as v(position, locale, text) on v.position = ins.position;

-- nr233: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '14a5fbbd-83a3-44cb-aa16-7492eb21b51c');
delete from public.question_smaczki where question_id = '14a5fbbd-83a3-44cb-aa16-7492eb21b51c';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('14a5fbbd-83a3-44cb-aa16-7492eb21b51c',1,true),('14a5fbbd-83a3-44cb-aa16-7492eb21b51c',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Kto nie pyta, ten nie ma?'),(1,'en','Closed mouths starve?'),
  (2,'pl','Firma nie da ci więcej z dobroci'),(2,'en','The company won''t raise you out of kindness')
) as v(position, locale, text) on v.position = ins.position;

-- nr235: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '15efa68a-eea9-4870-a286-20fa509cf195');
delete from public.question_smaczki where question_id = '15efa68a-eea9-4870-a286-20fa509cf195';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('15efa68a-eea9-4870-a286-20fa509cf195',1,true),('15efa68a-eea9-4870-a286-20fa509cf195',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Koniec z oszustami?'),(1,'en','No more catfish?'),
  (2,'pl','Twoje zdjęcie sprzed pięciu lat to też oszustwo'),(2,'en','Your five-year-old photo is a lie too')
) as v(position, locale, text) on v.position = ins.position;

-- nr241: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '1b9f48d8-6752-495c-90e6-11af33f9c946');
delete from public.question_smaczki where question_id = '1b9f48d8-6752-495c-90e6-11af33f9c946';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('1b9f48d8-6752-495c-90e6-11af33f9c946',1,true),('1b9f48d8-6752-495c-90e6-11af33f9c946',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Nic się nie dzieje bez przyczyny'),(1,'en','Nothing happens without a reason'),
  (2,'pl','Emocje i impuls nie powinny decydować'),(2,'en','Emotion and impulse shouldn''t decide')
) as v(position, locale, text) on v.position = ins.position;

-- nr244: 2 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '1c808aeb-ec5a-404e-b6dc-6fc1a69cfd25');
delete from public.question_smaczki where question_id = '1c808aeb-ec5a-404e-b6dc-6fc1a69cfd25';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('1c808aeb-ec5a-404e-b6dc-6fc1a69cfd25',1,true),('1c808aeb-ec5a-404e-b6dc-6fc1a69cfd25',2,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Ślad wart zostawienia?'),(1,'en','A mark worth leaving?'),
  (2,'pl','Pomnik nie wie, że stoi'),(2,'en','A monument doesn''t know it stands')
) as v(position, locale, text) on v.position = ins.position;

-- nr247: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '208d40e6-c120-403f-9eea-34aeef9408f8');
delete from public.question_smaczki where question_id = '208d40e6-c120-403f-9eea-34aeef9408f8';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('208d40e6-c120-403f-9eea-34aeef9408f8',1,true),('208d40e6-c120-403f-9eea-34aeef9408f8',2,true),('208d40e6-c120-403f-9eea-34aeef9408f8',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Nauka współpracy?'),(1,'en','Learn teamwork?'),
  (2,'pl','Sport to zdrowie'),(2,'en','Sport means health'),
  (3,'pl','Przymus zabija to, co miał zaszczepić'),(3,'en','Force kills the very thing it meant to plant')
) as v(position, locale, text) on v.position = ins.position;

-- nr248: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '21242ee3-4925-4cac-a33b-3235ac4928a4');
delete from public.question_smaczki where question_id = '21242ee3-4925-4cac-a33b-3235ac4928a4';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('21242ee3-4925-4cac-a33b-3235ac4928a4',1,true),('21242ee3-4925-4cac-a33b-3235ac4928a4',2,true),('21242ee3-4925-4cac-a33b-3235ac4928a4',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Trzymasz opcje otwarte?'),(1,'en','Keeping options open?'),
  (2,'pl','Jeśli to ta osoba, to wiedziałbyś od razu'),(2,'en','If they were the one, you''d know right away'),
  (3,'pl','Opcje dla ciebie, ślepy zaułek dla nich'),(3,'en','Options for you, a dead end for them')
) as v(position, locale, text) on v.position = ins.position;

-- nr252: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '25a8a6f5-509b-43da-a048-6e40b3b12f31');
delete from public.question_smaczki where question_id = '25a8a6f5-509b-43da-a048-6e40b3b12f31';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('25a8a6f5-509b-43da-a048-6e40b3b12f31',1,true),('25a8a6f5-509b-43da-a048-6e40b3b12f31',2,true),('25a8a6f5-509b-43da-a048-6e40b3b12f31',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Hazard dla dzieci?'),(1,'en','Gambling for kids?'),
  (2,'pl','To ich kieszonkowe?'),(2,'en','Just their pocket money?'),
  (3,'pl','A jeśli to kiedyś przyniesie zysk?'),(3,'en','And if it pays off one day?')
) as v(position, locale, text) on v.position = ins.position;

-- nr257: 3 smaczki
delete from public.question_smaczki_translations where smaczek_id in (select id from public.question_smaczki where question_id = '2b04c3dd-a179-405f-a358-e452f889f745');
delete from public.question_smaczki where question_id = '2b04c3dd-a179-405f-a358-e452f889f745';
with ins as (insert into public.question_smaczki (question_id, position, is_active) values ('2b04c3dd-a179-405f-a358-e452f889f745',1,true),('2b04c3dd-a179-405f-a358-e452f889f745',2,true),('2b04c3dd-a179-405f-a358-e452f889f745',3,true) returning id, position)
insert into public.question_smaczki_translations (smaczek_id, locale, text)
select ins.id, v.locale, v.text from ins join (values
  (1,'pl','Czy kłamstwo wygodne dla rodzica jest w porządku?'),(1,'en','Is a lie that suits the parent okay?'),
  (2,'pl','Niech będą małe?'),(2,'en','Let them be little?'),
  (3,'pl','Kolega z podwórka i tak im powie'),(3,'en','The kid next door will tell them anyway')
) as v(position, locale, text) on v.position = ins.position;

commit;