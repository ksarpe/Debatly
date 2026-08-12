-- ============================================================================
-- Seed: controversial dilemmas of humanity (PL + EN)
-- Adds 17 bilingual questions so the catalog has ~20 for testing, then assigns
-- the still-unscheduled questions to the next free calendar dates.
--
-- Idempotent-ish: each question is keyed on its EN text, so re-running will
-- skip rows that already exist (no duplicate translations).
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- 1) Insert questions + both translations, one row at a time so the freshly
--    generated question id maps to the right PL/EN pair (INSERT ... RETURNING
--    does not guarantee row order, so we cannot batch it safely).
-- ----------------------------------------------------------------------------
do $$
declare
  r   record;
  qid uuid;
begin
  for r in
    select * from (values
      ('Society', false,
       'Should an obese person have to pay for two seats on an airplane?',
       'Czy osoba otyła powinna płacić za dwa miejsca w samolocie?'),
      ('Justice', true,
       'Should the death penalty exist for the most heinous crimes?',
       'Czy kara śmierci powinna istnieć za najcięższe zbrodnie?'),
      ('Ethics', true,
       'Should terminally ill people have the right to choose euthanasia?',
       'Czy nieuleczalnie chorzy powinni mieć prawo do eutanazji?'),
      ('Society', false,
       'Should voting in elections be mandatory for every citizen?',
       'Czy udział w wyborach powinien być obowiązkowy dla każdego obywatela?'),
      ('Family', true,
       'Should people need a license before they are allowed to have children?',
       'Czy ludzie powinni potrzebować licencji, zanim będą mogli mieć dzieci?'),
      ('Money', false,
       'Should it be possible to become a billionaire while others starve?',
       'Czy powinno być możliwe zostanie miliarderem, podczas gdy inni głodują?'),
      ('Ethics', true,
       'Is it morally wrong to eat meat when plant-based food is available?',
       'Czy jedzenie mięsa jest moralnie złe, skoro dostępne jest jedzenie roślinne?'),
      ('Society', false,
       'Should social media be banned for everyone under sixteen?',
       'Czy media społecznościowe powinny być zakazane dla osób poniżej szesnastego roku życia?'),
      ('Technology', true,
       'Should we spend billions colonizing Mars while Earth has unsolved problems?',
       'Czy powinniśmy wydawać miliardy na kolonizację Marsa, gdy Ziemia ma nierozwiązane problemy?'),
      ('Money', false,
       'Should every citizen receive an unconditional basic income?',
       'Czy każdy obywatel powinien otrzymywać bezwarunkowy dochód podstawowy?'),
      ('Technology', true,
       'Should we be allowed to genetically edit babies to remove diseases?',
       'Czy powinniśmy móc genetycznie modyfikować dzieci, by usunąć choroby?'),
      ('Society', false,
       'Should countries open their borders and allow anyone to immigrate freely?',
       'Czy kraje powinny otworzyć granice i pozwolić każdemu na swobodną imigrację?'),
      ('Ethics', true,
       'Is it ethical to keep wild animals in zoos for human entertainment?',
       'Czy etyczne jest trzymanie dzikich zwierząt w zoo dla ludzkiej rozrywki?'),
      ('Technology', false,
       'Should an AI be allowed to make life-or-death medical decisions?',
       'Czy sztuczna inteligencja powinna móc podejmować decyzje medyczne na temat życia i śmierci?'),
      ('Justice', true,
       'Should people who never use a car pay the same road taxes as drivers?',
       'Czy osoby, które nigdy nie korzystają z samochodu, powinny płacić takie same podatki drogowe jak kierowcy?'),
      ('Environment', false,
       'Should private cars be completely banned from city centers?',
       'Czy prywatne samochody powinny być całkowicie zakazane w centrach miast?'),
      ('Justice', true,
       'Should a soldier be punished for refusing an order they consider immoral?',
       'Czy żołnierz powinien być karany za odmowę wykonania rozkazu, który uważa za niemoralny?')
    ) as s(category, is_premium, en, pl)
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
  end loop;
end $$;

-- ----------------------------------------------------------------------------
-- 2) Schedule every still-unscheduled active question onto the next free dates,
--    starting from today. Keeps Strategy A (unique question_id) intact.
-- ----------------------------------------------------------------------------
insert into public.daily_questions (publish_date, question_id)
select dates.d::date, q.id
from (
  select d, row_number() over (order by d) rn
  from generate_series(current_date, current_date + 729, '1 day'::interval) d
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
