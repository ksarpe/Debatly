-- Trim smaczki to a maximum of two per question.
--
-- The 20260621130000 seed gave every question four "hot take" angles
-- (positions 1-4). Product decision (2026-06-23): keep at most two per
-- question -- position 1 (free teaser) and position 2 (premium) -- and drop
-- the rest. A third may be added back manually later.
--
-- Hard delete: translations first (FK references question_smaczki.id), then
-- the smaczki rows. Positions 1 and 2 are untouched.

delete from question_smaczki_translations
where smaczek_id in (
  select id from question_smaczki where position > 2
);

delete from question_smaczki where position > 2;
