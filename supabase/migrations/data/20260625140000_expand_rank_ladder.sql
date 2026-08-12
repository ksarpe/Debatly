-- ============================================================================
-- Expand the controversy-rank ladder — more tiers, smaller gaps.
--
-- The old ladder (0/3/7/14/30/60/100, 7 tiers) climbed too rarely: after the
-- first week the next promotion was 16, then 30, then 40 days away, so the
-- streak chip felt static for long stretches. This re-seeds a DENSER 13-tier
-- ladder, front-loaded so a new user ranks up roughly every few days early on
-- (2, 4, 7, 10, 14, 20 …) and still has far peaks to chase (140).
--
-- The ranks table is the single source of truth: sync_user_state, decayed_streak
-- and the client all resolve tiers dynamically from these rows, so retuning is a
-- pure data change — no function or signature touch. The seven original names
-- keep their icons; the six new tiers slot in between (and one new peak on top).
--
-- DELETE-then-INSERT rather than upsert: the new min_streak values reshuffle the
-- existing rows (e.g. tier 5 moves 60 → 14), which would trip the
-- `min_streak unique` constraint mid-statement on an ON CONFLICT update. Nothing
-- has a foreign key into ranks (rank is never stored, only resolved), so a clean
-- swap inside the migration transaction is safe.
-- ============================================================================

delete from public.ranks;

insert into public.ranks (tier, min_streak, name_pl, name_en, icon) values
  ( 0,   0, 'Amator kontrowersji',  'Controversy Amateur', 'seedling'),
  ( 1,   2, 'Prowokator',           'Provocateur',         'spark'),
  ( 2,   4, 'Podżegacz',            'Instigator',          'flame'),
  ( 3,   7, 'Buntownik',            'Rebel',               'megaphone'),
  ( 4,  10, 'Adwokat diabła',       'Devil''s Advocate',   'mask'),
  ( 5,  14, 'Mąciciel',             'Troublemaker',        'storm'),
  ( 6,  20, 'Wichrzyciel',          'Agitator',            'bolt'),
  ( 7,  28, 'Burzyciel spokoju',    'Peacebreaker',        'whatshot'),
  ( 8,  40, 'Mistrz prowokacji',    'Master Provocateur',  'shield'),
  ( 9,  55, 'Ikona kontrowersji',   'Controversy Icon',    'star'),
  (10,  75, 'Wirtuoz skandalu',     'Scandal Virtuoso',    'diamond'),
  (11, 100, 'Legenda kontrowersji', 'Controversy Legend',  'crown'),
  (12, 140, 'Mit kontrowersji',     'Controversy Myth',    'rocket');
