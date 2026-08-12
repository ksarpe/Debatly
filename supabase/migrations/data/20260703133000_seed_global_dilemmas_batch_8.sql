-- ============================================================================
-- Seed batch 8: 17 globally-applicable debate questions (PL + EN) + smaczki
-- ----------------------------------------------------------------------------
-- Generated 2026-07-03. Final file of the 268-question drop (126 + 125 + 17)
-- that brings the catalog from 732 to exactly 1000. Same rules and mechanics
-- as batches 6-7 (see 20260703130000): universal dilemmas, ~50/50 splits,
-- variable smaczki (nullable a2/a3 pairs). Deduplicated against all 750
-- historical EN texts + batches 6-7. Idempotent: keyed on EN text.
-- Topics in this file: Ethics (2), Culture (3), Society (2), Family (2),
-- Money (2), Work (2), Technology (1), Health (1), Friendship (1),
-- Lifestyle (1).
-- ============================================================================

begin;

do $$
declare
  r   record;
  qid uuid;
  s1  uuid;
  s2  uuid;
  s3  uuid;
begin
  for r in
    select * from (values
      ('Ethics', false,
       'Is mercy to the cruel cruelty to the kind?',
       'Czy litość dla okrutnych to okrucieństwo wobec dobrych?',
       'Mercy can reload the gun', 'Litość potrafi przeładować broń',
       'Mercy is never wasted', 'Miłosierdzie nigdy nie idzie na marne',
       null, null),
      ('Ethics', false,
       'Is letting someone win an argument to save the evening dishonest?',
       'Czy odpuszczenie komuś wygranej w sporze dla ratowania wieczoru to nieszczerość?',
       'Peace bought with silence', 'Pokój kupiony milczeniem',
       'Not every hill needs your flag', 'Nie każde wzgórze potrzebuje twojej flagi',
       null, null),
      ('Culture', false,
       'Is a silence in conversation something that needs fixing?',
       'Czy cisza w rozmowie to coś, co trzeba naprawiać?',
       'Silence is where trust lives', 'W ciszy mieszka zaufanie',
       'Dead air suffocates', 'Martwa cisza dusi',
       null, null),
      ('Culture', false,
       'Does someone''s music taste tell you who they really are?',
       'Czy gust muzyczny mówi, kim ktoś naprawdę jest?',
       'Playlists don''t lie', 'Playlisty nie kłamią',
       'Taste is weather, not climate', 'Gust to pogoda, nie klimat',
       null, null),
      ('Culture', false,
       'Is being proud of where you''re from irrational?',
       'Czy duma z miejsca pochodzenia jest irracjonalna?',
       'You didn''t choose your cradle', 'Nie wybrałeś swojej kołyski',
       'Belonging needs no logic', 'Przynależność nie potrzebuje logiki',
       null, null),
      ('Society', false,
       'Should your hobby be taken as seriously as your job?',
       'Czy twoje hobby powinno być traktowane równie poważnie jak praca?',
       'Passion is the real résumé', 'Pasja to prawdziwe CV',
       'Rent is due either way', 'Czynsz i tak trzeba zapłacić',
       null, null),
      ('Society', false,
       'Should you write your will while young and healthy?',
       'Czy spisać testament, będąc młodym i zdrowym?',
       'Death doesn''t check calendars', 'Śmierć nie zagląda w kalendarz',
       'Tempting fate is a real fear', 'Kuszenie losu to realny strach',
       null, null),
      ('Family', false,
       'Should children get a vote in big family decisions?',
       'Czy dzieci powinny mieć głos w wielkich rodzinnych decyzjach?',
       'It''s their life too', 'To także ich życie',
       'A ship needs a captain', 'Statek potrzebuje kapitana',
       null, null),
      ('Family', false,
       'Would you be happy if your child turned out exactly like you?',
       'Czy byłbyś szczęśliwy, gdyby twoje dziecko wyrosło dokładnie na ciebie?',
       'The highest compliment there is', 'Największy możliwy komplement',
       'You know your own cracks', 'Znasz własne pęknięcia',
       null, null),
      ('Money', false,
       'Should kids hear "we can''t afford it" straight?',
       'Czy dzieci powinny słyszeć wprost „nie stać nas"?',
       'Reality is a teacher', 'Rzeczywistość to nauczycielka',
       'Little shoulders, heavy loads', 'Małe ramiona, ciężki bagaż',
       null, null),
      ('Money', false,
       'Is checkout charity — rounding up at the till — real giving?',
       'Czy dobroczynność przy kasie — zaokrąglanie rachunku — to prawdziwe dawanie?',
       'Painless pennies add up', 'Bezbolesne grosze się sumują',
       'Giving should cost a thought', 'Dawanie powinno kosztować choć myśl',
       null, null),
      ('Work', false,
       'Is treating your job as a calling a setup for exploitation?',
       'Czy traktowanie pracy jak powołania to prosta droga do bycia wykorzystywanym?',
       'Callings don''t clock out', 'Powołanie nie wybija karty',
       'Meaning is the best perk', 'Sens to najlepszy benefit',
       null, null),
      ('Work', false,
       'Do you owe more loyalty to your coworkers than to the company?',
       'Czy jesteś winien więcej lojalności współpracownikom niż firmie?',
       'The company can''t love you back', 'Firma nie odwzajemni twojej miłości',
       'The paycheck has a sender', 'Wypłata ma nadawcę',
       null, null),
      ('Technology', false,
       'Would you ride in a car with no steering wheel at all?',
       'Czy wsiadłbyś do auta zupełnie pozbawionego kierownicy?',
       'Humans crash more often', 'Ludzie rozbijają się częściej',
       'Hands want a wheel', 'Ręce chcą mieć kierownicę',
       null, null),
      ('Health', false,
       'Is canceling plans because of rain perfectly legitimate?',
       'Czy odwołanie planów z powodu deszczu jest w pełni uprawnione?',
       'Comfort is a valid vote', 'Wygoda to ważny głos',
       'Plans are promises', 'Plany to obietnice',
       null, null),
      ('Friendship', false,
       'Is living with your best friend the fastest way to lose them?',
       'Czy zamieszkanie z najlepszym przyjacielem to najszybszy sposób, by go stracić?',
       'Bills reveal characters', 'Rachunki odsłaniają charaktery',
       'Who better to share walls with?', 'Z kim lepiej dzielić ściany?',
       null, null),
      ('Lifestyle', false,
       'Is it better to leave childhood places unvisited?',
       'Czy miejsca z dzieciństwa lepiej zostawić nieodwiedzone?',
       'Memory keeps them golden', 'Pamięć trzyma je w złocie',
       'Roots like to be touched', 'Korzenie lubią dotyk',
       null, null)
    ) as s(category, is_premium, en, pl, a1en, a1pl, a2en, a2pl, a3en, a3pl)
  loop
    -- skip if this EN text was already seeded
    if exists (
      select 1 from public.question_translations
      where locale = 'en' and question_text = r.en
    ) then
      continue;
    end if;

    insert into public.questions (category, is_premium)
    values (r.category, r.is_premium)
    returning id into qid;

    insert into public.question_translations (question_id, locale, question_text)
    values (qid, 'en', r.en),
           (qid, 'pl', r.pl);

    -- smaczek 1 (free teaser) -- always present
    insert into public.question_smaczki (question_id, position, is_active)
    values (qid, 1, true)
    returning id into s1;
    insert into public.question_smaczki_translations (smaczek_id, locale, text)
    values (s1, 'en', r.a1en),
           (s1, 'pl', r.a1pl);

    -- smaczek 2 (premium) -- most questions
    if r.a2en is not null then
      insert into public.question_smaczki (question_id, position, is_active)
      values (qid, 2, true)
      returning id into s2;
      insert into public.question_smaczki_translations (smaczek_id, locale, text)
      values (s2, 'en', r.a2en),
             (s2, 'pl', r.a2pl);
    end if;

    -- smaczek 3 (premium) -- only where a third angle genuinely deepens it
    if r.a3en is not null then
      insert into public.question_smaczki (question_id, position, is_active)
      values (qid, 3, true)
      returning id into s3;
      insert into public.question_smaczki_translations (smaczek_id, locale, text)
      values (s3, 'en', r.a3en),
             (s3, 'pl', r.a3pl);
    end if;
  end loop;
end $$;

-- ----------------------------------------------------------------------------
-- Schedule every still-unscheduled active question onto the next free dates.
-- Keeps Strategy A (unique question_id) intact.
-- ----------------------------------------------------------------------------
insert into public.daily_questions (publish_date, question_id)
select dates.d::date, q.id
from (
  select d, row_number() over (order by d) rn
  from generate_series(current_date, current_date + 1499, '1 day'::interval) d
  where d::date not in (select publish_date from public.daily_questions)
) dates
join (
  select id, row_number() over (order by random()) rn
  from public.questions
  where is_active
    and id not in (select question_id from public.daily_questions)
) q on q.rn = dates.rn
on conflict do nothing;

commit;
