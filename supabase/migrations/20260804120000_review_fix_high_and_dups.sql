-- ============================================================================
-- Review 2026-08-04 — fix the 6 HIGH findings + remove the 8 semantic duplicates
-- (full report: exports/review_pytan_2026-08-04.md)
--
-- HIGH fixes (question_translations updates, guarded by current prod text so a
-- partial/repeated apply can never clobber anything):
--   c05d6e2e  PL+EN  alternative "czy…, czy…" -> single yes/no question (tipping)
--   74e30dde  PL+EN  alternative "blessing or curse" -> "more of a curse than…"
--   b666cdbd  EN     "punished for crimes" -> "held responsible for actions" (=PL)
--   5f63e9e9  EN     "Should it be possible…" -> "Is it okay that…" (=PL)
--   c4fbed60  EN     "should you?" -> "would you?" (=PL "czy byś chciał")
--   e0fdf1a3  PL     "Czy powinniśmy … który ci się nie podoba" -> "Czy powinieneś…"
--
-- Duplicate deletes (kept twin in parentheses):
--   49a38dba  potwierdzanie tożsamości w sieci      (kept 8aae5029 anonimowość)
--   0303b05c  mówić prawdę, która przyniesie ból    (kept eda0e56c kłamstwo ochronne)
--   96eb43da  pocieszające kłamstwa o świecie       (kept ea9f2a4b bolesna prawda dziecku)
--   773f1b9c  druga szansa po złym rozstaniu        (kept 1b9f48d8 byli w złości)
--   1ac184ba  zabrać wszystko z ogrodu              (kept 868e181d znalazca skarbu)
--   1f056bfe  szef czyta wiadomości                 (kept fff55253 śledzenie wszystkiego)
--   73f9fec9  zemsta gdy masz przewagę              (kept 5cc0a51e zemsta usprawiedliwiona)
--   3db0b12c  życie w samym wypoczynku              (kept cc82a0ca pensja za nicnierobienie)
--
-- Deleted rows (translations + CURRENT prod smaczki + seeds) are snapshotted to
-- public.catalog_review_20260804_deleted_backup before the delete — the pod-włos
-- smaczki live only on prod, so an in-DB backup is the only faithful one.
--
-- BEFORE applying, optionally check what user data cascades away:
--   select q.id,
--          (select count(*) from question_votes v where v.question_id = q.id)     as votes,
--          (select count(*) from question_favorites f where f.question_id = q.id) as favorites,
--          (select count(*) from user_daily_questions u where u.question_id = q.id) as personal_daily
--   from questions q where q.id in (
--     '49a38dba-981a-46a1-b6db-dd11b0108aee','0303b05c-a9b7-483b-b4e0-1f50b5ebce7e',
--     '96eb43da-38e1-4b33-bacc-7763d0fe6de3','773f1b9c-e69b-4abf-8a23-5246c538f474',
--     '1ac184ba-5d97-4cd3-a3ba-c0d0ecd0b1d6','1f056bfe-b249-4356-bd32-6fb63a3dd515',
--     '73f9fec9-df59-43cf-a449-e77a5852a6c0','3db0b12c-a7b7-4fc0-ad79-db0c2ffb63c7');
--
-- AFTER applying, review by hand (this file cannot see prod smaczki):
--   1) smaczki of c05d6e2e and 74e30dde — the question wording changed, and for
--      74e30dde the new wording gives TAK a fixed meaning (TAK = przekleństwo);
--      slot-2/slot-3 camps may need swapping.
--   2) question_vote_seeds of 74e30dde — if a curated seed exists, its
--      seed_yes_pct may need flipping for the same reason.
--
-- Idempotent: guarded updates are no-ops on re-run; deletes are by id; the
-- backup table is insert-once (on conflict do nothing), so a re-run after the
-- delete cannot wipe the snapshot taken by the first run.
-- ============================================================================
begin;

-- ----------------------------------------------------------------------------
-- 1) HIGH fixes — guarded updates.
-- ----------------------------------------------------------------------------
-- c05d6e2e — napiwki: pytanie alternatywne -> jedno TAK/NIE
update public.question_translations
   set question_text = 'Czy zamiast oczekiwania napiwku cena powinna po prostu obejmować wszystko?'
 where question_id = 'c05d6e2e-4fa3-4512-9a93-974d89fbd4d9' and locale = 'pl'
   and question_text = 'Czy napiwek powinien być oczekiwany, czy cena powinna po prostu obejmować wszystko?';
update public.question_translations
   set question_text = 'Should the price simply cover everything instead of expecting a tip?'
 where question_id = 'c05d6e2e-4fa3-4512-9a93-974d89fbd4d9' and locale = 'en'
   and question_text = 'Should tipping be expected, or should the price simply cover everything?';

-- 74e30dde — życie wieczne: alternatywa -> "raczej przekleństwem niż błogosławieństwem"
update public.question_translations
   set question_text = 'Czy życie wieczne byłoby raczej przekleństwem niż błogosławieństwem?'
 where question_id = '74e30dde-61f9-4995-99ba-9a8a22eaa75d' and locale = 'pl'
   and question_text = 'Czy życie wieczne byłoby raczej błogosławieństwem czy przekleństwem?';
update public.question_translations
   set question_text = 'Would living forever be more of a curse than a blessing?'
 where question_id = '74e30dde-61f9-4995-99ba-9a8a22eaa75d' and locale = 'en'
   and question_text = 'Would living forever be more of a blessing or a curse?';

-- b666cdbd — EN dorównany do PL ("odpowiadać za czyny", nie "kara za przestępstwa")
update public.question_translations
   set question_text = 'Should parents be held responsible for their children''s actions?'
 where question_id = 'b666cdbd-3956-4fd8-805a-fb4cb0385ed4' and locale = 'en'
   and question_text = 'Should parents be punished for crimes their children commit?';

-- 5f63e9e9 — EN dorównany do PL (ocena moralna stanu, nie pytanie systemowe)
update public.question_translations
   set question_text = 'Is it okay that some people become billionaires while others starve?'
 where question_id = '5f63e9e9-4b46-49dc-9b4d-290d7b936de5' and locale = 'en'
   and question_text = 'Should it be possible to become a billionaire while others starve?';

-- c4fbed60 — EN dorównany do PL (chęć, nie powinność)
update public.question_translations
   set question_text = 'If you could stay physically thirty forever, would you?'
 where question_id = 'c4fbed60-ab48-4f03-831f-0d2ec937e739' and locale = 'en'
   and question_text = 'If you could stay physically thirty forever, should you?';

-- e0fdf1a3 — niezgodność podmiotów PL (powinniśmy/ci)
update public.question_translations
   set question_text = 'Czy powinieneś udawać zachwyt prezentem, który ci się nie podoba?'
 where question_id = 'e0fdf1a3-2103-45b7-b9cc-6b9327623c9a' and locale = 'pl'
   and question_text = 'Czy powinniśmy udawać zachwyt prezentem, który ci się nie podoba?';

-- Assert: every target row now carries the NEW text. A failed guard (prod text
-- drifted / hand-paste mangled a character) aborts the whole transaction instead
-- of silently applying half the fixes.
do $$
declare bad int;
begin
  select count(*) into bad from (values
    ('c05d6e2e-4fa3-4512-9a93-974d89fbd4d9'::uuid, 'pl', 'Czy zamiast oczekiwania napiwku cena powinna po prostu obejmować wszystko?'),
    ('c05d6e2e-4fa3-4512-9a93-974d89fbd4d9'::uuid, 'en', 'Should the price simply cover everything instead of expecting a tip?'),
    ('74e30dde-61f9-4995-99ba-9a8a22eaa75d'::uuid, 'pl', 'Czy życie wieczne byłoby raczej przekleństwem niż błogosławieństwem?'),
    ('74e30dde-61f9-4995-99ba-9a8a22eaa75d'::uuid, 'en', 'Would living forever be more of a curse than a blessing?'),
    ('b666cdbd-3956-4fd8-805a-fb4cb0385ed4'::uuid, 'en', 'Should parents be held responsible for their children''s actions?'),
    ('5f63e9e9-4b46-49dc-9b4d-290d7b936de5'::uuid, 'en', 'Is it okay that some people become billionaires while others starve?'),
    ('c4fbed60-ab48-4f03-831f-0d2ec937e739'::uuid, 'en', 'If you could stay physically thirty forever, would you?'),
    ('e0fdf1a3-2103-45b7-b9cc-6b9327623c9a'::uuid, 'pl', 'Czy powinieneś udawać zachwyt prezentem, który ci się nie podoba?')
  ) as expected(question_id, locale, question_text)
  where not exists (
    select 1 from public.question_translations t
    where t.question_id = expected.question_id
      and t.locale = expected.locale
      and t.question_text = expected.question_text);
  if bad > 0 then
    raise exception 'HIGH-fix verification failed for % row(s) — prod text does not match the expected old/new state; aborting', bad;
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- 2) Duplicate deletes — snapshot first, then delete (FK cascades take
--    translations, smaczki, seeds, votes, favorites, seen, personal dailies).
-- ----------------------------------------------------------------------------
create temporary table _del_rev20260804 (id uuid) on commit drop;
insert into _del_rev20260804 (id) select unnest(array[
  '49a38dba-981a-46a1-b6db-dd11b0108aee',
  '0303b05c-a9b7-483b-b4e0-1f50b5ebce7e',
  '96eb43da-38e1-4b33-bacc-7763d0fe6de3',
  '773f1b9c-e69b-4abf-8a23-5246c538f474',
  '1ac184ba-5d97-4cd3-a3ba-c0d0ecd0b1d6',
  '1f056bfe-b249-4356-bd32-6fb63a3dd515',
  '73f9fec9-df59-43cf-a449-e77a5852a6c0',
  '3db0b12c-a7b7-4fc0-ad79-db0c2ffb63c7'
]::uuid[]);

create table if not exists public.catalog_review_20260804_deleted_backup (
  question_id  uuid primary key,
  translations jsonb,
  smaczki      jsonb,
  seed         jsonb,
  backed_up_at timestamptz not null default now()
);
insert into public.catalog_review_20260804_deleted_backup (question_id, translations, smaczki, seed)
select q.id as question_id,
       (select jsonb_object_agg(t.locale, t.question_text)
          from public.question_translations t where t.question_id = q.id)             as translations,
       (select jsonb_agg(jsonb_build_object('position', s.position, 'locale', st.locale, 'text', st.text)
                         order by s.position, st.locale)
          from public.question_smaczki s
          join public.question_smaczki_translations st on st.smaczek_id = s.id
         where s.question_id = q.id)                                                  as smaczki,
       (select to_jsonb(v) - 'question_id'
          from public.question_vote_seeds v where v.question_id = q.id)               as seed
from public.questions q
join _del_rev20260804 d on d.id = q.id
on conflict (question_id) do nothing;

delete from public.daily_questions where publish_date > (now() at time zone 'utc')::date + 1;
delete from public.daily_questions d using _del_rev20260804 t where d.question_id = t.id;
delete from public.questions qq using _del_rev20260804 t where qq.id = t.id;

-- Rebuild the (legacy fallback) calendar tail, same as every catalog batch.
with anchor as (select coalesce(max(publish_date), (now() at time zone 'utc')::date) as last_day from public.daily_questions),
pool as (select q2.id, (row_number() over (order by random()))::int as rn from public.questions q2
         where q2.is_active and not exists (select 1 from public.daily_questions d where d.question_id = q2.id))
insert into public.daily_questions (publish_date, question_id)
select (select last_day from anchor) + pool.rn, pool.id from pool;

commit;

-- Post-apply sanity (expected: 542 active questions, 8 backup rows):
--   select count(*) from questions where is_active;                       -- 542
--   select count(*) from catalog_review_20260804_deleted_backup;          -- 8
