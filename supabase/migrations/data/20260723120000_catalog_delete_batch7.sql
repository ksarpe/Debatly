-- ============================================================================
-- Catalog DELETE batch 7 (master diff, rows nr 321-438) — DELETES ONLY.
-- 55 questions removed (marked via empty PYTANIE(PL) or USUŃ). User did not
-- touch smaczki in this pass; 7 in-range content edits were held back.
-- Cascades translations/smaczki/seen/votes/favorites/seeds/user_daily.
-- daily_questions is RESTRICT -> free future calendar first, then rebuild.
-- Deleted rows backed up to *_batch7.backup.json.
-- ============================================================================
begin;

delete from public.daily_questions where publish_date > (now() at time zone 'utc')::date + 1;

delete from public.daily_questions d
using (values
  ('68e09d0a-bfb6-43f3-ac1b-59fe09dd2c33'),
  ('6bce7b67-9cd9-4ca9-a977-59d8bd4f3ef1'),
  ('6c6c6c67-82f1-4136-8d64-0e25acccd557'),
  ('6d225fe1-5897-48a8-b9c0-3deb27f27398'),
  ('6eb1f7f0-40ee-4cdb-a5b0-d5e2c884a523'),
  ('70c32aa4-24b6-4409-9e70-f76c36e6efed'),
  ('714d7c4b-5e91-4a90-862d-2e1b694f0306'),
  ('73899fa1-76f1-4dc2-becf-0a73b489cfca'),
  ('7a7c1313-2301-465b-9d1a-ca8c45c7ea45'),
  ('80907274-bacf-42e7-9038-4b2553fd193a'),
  ('81afc3b1-5f05-40d8-b8d8-b0ebd8ef492a'),
  ('82129f65-e2df-46b8-a517-bce40faa141b'),
  ('857618af-6afa-4dd1-a17e-038a5dda53bf'),
  ('8abaa183-9d36-441f-bd12-e4fb1e2cce86'),
  ('8aea226e-a754-46c0-9f52-648f6701338c'),
  ('903d6382-8dc4-4ccf-9d59-30ce3adc5800'),
  ('90eb692b-a480-4937-9313-16075f7a1b0b'),
  ('919f9474-6318-4031-a5ee-db2105408057'),
  ('939c15a3-8890-4997-9915-182babdecd9c'),
  ('93a19e42-6ea3-4853-9224-c00ae277801e'),
  ('93e66801-81a0-4c78-8420-886ec632a387'),
  ('94aed95e-7bcd-4767-8f99-8f487aced91a'),
  ('95cd379d-e03e-4243-bc76-9bbc7a9feca8'),
  ('982c3dea-2c26-4771-8a18-bdcf92f66fdc'),
  ('9c76dcda-ceeb-40cf-a86a-185743d2b928'),
  ('9ca7f743-3772-461f-8fc1-c0bafb29a2d1'),
  ('9d7a6658-cd8f-4e77-be09-b12250168634'),
  ('a3661ac8-922b-42d5-a1b5-63f31a0dd6bb'),
  ('a3e47ec1-0ba7-4185-9bc4-075ac8f05066'),
  ('a78807bf-f775-4055-8bf4-714aed7750c4'),
  ('a804169f-9045-4a8d-9578-cc69a6438dd8'),
  ('abf82a91-aca6-473e-b315-fee7ffa1637a'),
  ('ae9f59d8-2977-44ea-bc1a-3459ae2264ce'),
  ('afd2253b-0a8b-48b6-9c2d-43709456a674'),
  ('afd85002-d565-4993-98da-659dbb8db132'),
  ('b01c047b-38d4-4312-957c-1b036518b6b5'),
  ('b283445b-e820-4843-b039-fac5108f00f4'),
  ('b4d4798f-d858-4b63-8d09-37431cb87f6d'),
  ('b7575803-21f7-47d1-b068-432d239f7ea4'),
  ('b9ccce16-4045-416d-a611-012acc36c2ed'),
  ('bc8f0a85-e46c-48ae-8840-7f39b96a1780'),
  ('bd37f7b6-e56a-4b53-ab98-bfc8e48d0a85'),
  ('bd9a73a9-f7a1-4ad2-bcc6-046b79fa875c'),
  ('c0e3f63c-682a-4a57-83db-fbe3c998bce1'),
  ('c3ba6de4-d539-44b7-9d78-e3542f8bcbc3'),
  ('c4f87280-fa80-4cb6-9367-a640c393762a'),
  ('c6bb4459-efab-4873-bdd2-d981d9a54942'),
  ('c8f78afb-a595-4120-b1bb-be35e60e65d5'),
  ('cd7a42e5-45fc-4287-bf49-d3aba6aa6592'),
  ('ceee3d9a-3101-4f6f-9f6d-3dded15bc35e'),
  ('d29bdf7c-888b-41e5-8708-57f42b62aef6'),
  ('d9ffce96-6129-40a6-b894-77abbea9cdf9'),
  ('dcccffaf-164e-44ef-b554-f94baf31f4ea'),
  ('ded7fbd4-cde2-40f1-ad11-7ddb294b2cf0'),
  ('e243292f-b932-4077-a4c5-3a8a8b2ff7c9')
) as del(id)
where d.question_id = del.id::uuid;

delete from public.questions q
using (values
  ('68e09d0a-bfb6-43f3-ac1b-59fe09dd2c33'),
  ('6bce7b67-9cd9-4ca9-a977-59d8bd4f3ef1'),
  ('6c6c6c67-82f1-4136-8d64-0e25acccd557'),
  ('6d225fe1-5897-48a8-b9c0-3deb27f27398'),
  ('6eb1f7f0-40ee-4cdb-a5b0-d5e2c884a523'),
  ('70c32aa4-24b6-4409-9e70-f76c36e6efed'),
  ('714d7c4b-5e91-4a90-862d-2e1b694f0306'),
  ('73899fa1-76f1-4dc2-becf-0a73b489cfca'),
  ('7a7c1313-2301-465b-9d1a-ca8c45c7ea45'),
  ('80907274-bacf-42e7-9038-4b2553fd193a'),
  ('81afc3b1-5f05-40d8-b8d8-b0ebd8ef492a'),
  ('82129f65-e2df-46b8-a517-bce40faa141b'),
  ('857618af-6afa-4dd1-a17e-038a5dda53bf'),
  ('8abaa183-9d36-441f-bd12-e4fb1e2cce86'),
  ('8aea226e-a754-46c0-9f52-648f6701338c'),
  ('903d6382-8dc4-4ccf-9d59-30ce3adc5800'),
  ('90eb692b-a480-4937-9313-16075f7a1b0b'),
  ('919f9474-6318-4031-a5ee-db2105408057'),
  ('939c15a3-8890-4997-9915-182babdecd9c'),
  ('93a19e42-6ea3-4853-9224-c00ae277801e'),
  ('93e66801-81a0-4c78-8420-886ec632a387'),
  ('94aed95e-7bcd-4767-8f99-8f487aced91a'),
  ('95cd379d-e03e-4243-bc76-9bbc7a9feca8'),
  ('982c3dea-2c26-4771-8a18-bdcf92f66fdc'),
  ('9c76dcda-ceeb-40cf-a86a-185743d2b928'),
  ('9ca7f743-3772-461f-8fc1-c0bafb29a2d1'),
  ('9d7a6658-cd8f-4e77-be09-b12250168634'),
  ('a3661ac8-922b-42d5-a1b5-63f31a0dd6bb'),
  ('a3e47ec1-0ba7-4185-9bc4-075ac8f05066'),
  ('a78807bf-f775-4055-8bf4-714aed7750c4'),
  ('a804169f-9045-4a8d-9578-cc69a6438dd8'),
  ('abf82a91-aca6-473e-b315-fee7ffa1637a'),
  ('ae9f59d8-2977-44ea-bc1a-3459ae2264ce'),
  ('afd2253b-0a8b-48b6-9c2d-43709456a674'),
  ('afd85002-d565-4993-98da-659dbb8db132'),
  ('b01c047b-38d4-4312-957c-1b036518b6b5'),
  ('b283445b-e820-4843-b039-fac5108f00f4'),
  ('b4d4798f-d858-4b63-8d09-37431cb87f6d'),
  ('b7575803-21f7-47d1-b068-432d239f7ea4'),
  ('b9ccce16-4045-416d-a611-012acc36c2ed'),
  ('bc8f0a85-e46c-48ae-8840-7f39b96a1780'),
  ('bd37f7b6-e56a-4b53-ab98-bfc8e48d0a85'),
  ('bd9a73a9-f7a1-4ad2-bcc6-046b79fa875c'),
  ('c0e3f63c-682a-4a57-83db-fbe3c998bce1'),
  ('c3ba6de4-d539-44b7-9d78-e3542f8bcbc3'),
  ('c4f87280-fa80-4cb6-9367-a640c393762a'),
  ('c6bb4459-efab-4873-bdd2-d981d9a54942'),
  ('c8f78afb-a595-4120-b1bb-be35e60e65d5'),
  ('cd7a42e5-45fc-4287-bf49-d3aba6aa6592'),
  ('ceee3d9a-3101-4f6f-9f6d-3dded15bc35e'),
  ('d29bdf7c-888b-41e5-8708-57f42b62aef6'),
  ('d9ffce96-6129-40a6-b894-77abbea9cdf9'),
  ('dcccffaf-164e-44ef-b554-f94baf31f4ea'),
  ('ded7fbd4-cde2-40f1-ad11-7ddb294b2cf0'),
  ('e243292f-b932-4077-a4c5-3a8a8b2ff7c9')
) as del(id)
where q.id = del.id::uuid;

with anchor as (select coalesce(max(publish_date), (now() at time zone 'utc')::date) as last_day from public.daily_questions),
pool as (select qq.id, (row_number() over (order by random()))::int as rn from public.questions qq
         where qq.is_active and not exists (select 1 from public.daily_questions d where d.question_id = qq.id))
insert into public.daily_questions (publish_date, question_id)
select (select last_day from anchor) + pool.rn, pool.id from pool;

commit;