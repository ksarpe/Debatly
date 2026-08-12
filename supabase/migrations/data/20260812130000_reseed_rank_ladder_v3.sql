-- ============================================================================
-- Re-seed the controversy-rank ladder, v3 — denser, renamed, 16 tiers.
--
-- The v2 ladder (13 tiers, first promotion at streak 2) still left the first
-- day unrewarded and had a 40-day dead zone between 100 and 140. v3 promotes
-- after the very first vote (streak 1), packs 4 promotions into week one
-- (1/3/5/7) and 9 into the first month, and caps the longest wait at 30 days
-- (100 → 130). Names are a fresh escalation arc: innocence → mischief
-- (Zadziora, Mąciciel, Podpalacz debaty) → status (Mistrz … Nieśmiertelny).
--
-- Every new threshold is <= its old counterpart, so existing users can only
-- stay or move UP a tier — nobody demotes on deploy.
--
-- The ranks table is the single source of truth: sync_user_state,
-- decayed_streak and the client resolve tiers dynamically from these rows, so
-- this is a pure data change. Three new icon keys (wind, medal, trophy) ship
-- in the same app release that maps them (rankIcon in rank_sheet.dart); older
-- clients fall back to the default glyph for unknown keys.
--
-- DELETE-then-INSERT (not upsert) for the same reason as v2: reshuffled
-- min_streak values would trip the unique constraint mid-statement, and
-- nothing has a foreign key into ranks (rank is resolved, never stored).
-- ============================================================================

delete from public.ranks;

insert into public.ranks (tier, min_streak, name_pl, name_en, icon) values
  ( 0,   0, 'Niewiniątko',          'The Innocent',        'seedling'),
  ( 1,   1, 'Pierwsza iskra',       'First Spark',         'spark'),
  ( 2,   3, 'Zadziora',             'Firebrand',           'flame'),
  ( 3,   5, 'Prowokator',           'Provocateur',         'megaphone'),
  ( 4,   7, 'Adwokat diabła',       'Devil''s Advocate',   'mask'),
  ( 5,  10, 'Mąciciel',             'Troublemaker',        'storm'),
  ( 6,  14, 'Burzyciel spokoju',    'Peacebreaker',        'bolt'),
  ( 7,  18, 'Podpalacz debaty',     'Debate Arsonist',     'whatshot'),
  ( 8,  23, 'Wichrzyciel',          'Agitator',            'wind'),
  ( 9,  30, 'Nieugięty',            'The Unshaken',        'shield'),
  (10,  40, 'Mistrz prowokacji',    'Master Provocateur',  'medal'),
  (11,  50, 'Wirtuoz skandalu',     'Scandal Virtuoso',    'star'),
  (12,  65, 'Ikona kontrowersji',   'Controversy Icon',    'diamond'),
  (13,  80, 'Legenda kontrowersji', 'Controversy Legend',  'crown'),
  (14, 100, 'Mit kontrowersji',     'Controversy Myth',    'trophy'),
  (15, 130, 'Nieśmiertelny',        'The Immortal',        'rocket');
