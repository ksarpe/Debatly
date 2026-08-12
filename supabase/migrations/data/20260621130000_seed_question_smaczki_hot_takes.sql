-- Reseed question_smaczki with short "hot take" discussion angles.
--
-- Smaczki are meant to be "krótkie strzały" — short, punchy, controversial
-- angles that objectively matter when judging the case (e.g. for "should an
-- obese person pay for two seats?" → "Limit wagi?", "A choroba?"). The old
-- seed only had three generic reflection prompts on a single question; this
-- wipes those and gives every question four angles in PL + EN.
--
-- The get_question_smaczki RPC shows position 1 free and gates positions 2-4
-- behind premium, so position 1 is the strongest free teaser for each question.
--
-- Questions are matched by a unique keyword (ilike) rather than by hardcoded
-- generated UUIDs, so this stays portable across environments.

delete from question_smaczki_translations;
delete from question_smaczki;

with src(qkey, position, pl, en) as (
  values
    -- Prostytucja zalegalizowana wszędzie?
    ('%prostytucja%', 1, 'Przymus czy wybór?', 'Coercion or choice?'),
    ('%prostytucja%', 2, 'A handel ludźmi?', 'What about trafficking?'),
    ('%prostytucja%', 3, 'Kontrola zdrowia?', 'Health regulation?'),
    ('%prostytucja%', 4, 'Bezpieczeństwo kobiet?', 'Women''s safety?'),
    -- Zghostować po 3 miesiącach randkowania?
    ('%randkujesz%', 1, 'Byliście już intymni?', 'Were you already intimate?'),
    ('%randkujesz%', 2, 'Chodzi o bezpieczeństwo?', 'Is it about safety?'),
    ('%randkujesz%', 3, 'Jedna wiadomość boli?', 'Would one message hurt?'),
    ('%randkujesz%', 4, 'Kto się wycofał?', 'Who pulled away first?'),
    -- Miliarderzy bardziej opodatkowani?
    ('%opodatkowani%', 1, 'Uciekną z kapitałem?', 'Will capital flee?'),
    ('%opodatkowani%', 2, 'Kto tworzy miejsca pracy?', 'Who creates the jobs?'),
    ('%opodatkowani%', 3, 'Majątek czy dochód?', 'Wealth or income?'),
    ('%opodatkowani%', 4, 'Państwo wyda lepiej?', 'Will the state spend it better?'),
    -- Jedzenie mięsa moralnie złe?
    ('%mięsa%', 1, 'Cierpienie zwierząt?', 'Animal suffering?'),
    ('%mięsa%', 2, 'A ubodzy rolnicy?', 'What about poor farmers?'),
    ('%mięsa%', 3, 'Tradycja i kultura?', 'Tradition and culture?'),
    ('%mięsa%', 4, 'Ślad węglowy?', 'Carbon footprint?'),
    -- Eutanazja dla nieuleczalnie chorych?
    ('%eutanazji%', 1, 'Presja na słabych?', 'Pressure on the vulnerable?'),
    ('%eutanazji%', 2, 'Depresja czy decyzja?', 'Depression or decision?'),
    ('%eutanazji%', 3, 'Kto orzeka?', 'Who decides eligibility?'),
    ('%eutanazji%', 4, 'Sprzeciw lekarza?', 'Doctor''s right to refuse?'),
    -- Otwarte granice dla każdego?
    ('%granice%', 1, 'Wydolność usług?', 'Can public services cope?'),
    ('%granice%', 2, 'Kontrola przestępców?', 'Screening criminals?'),
    ('%granice%', 3, 'Płace w dół?', 'Wages pushed down?'),
    ('%granice%', 4, 'Kto się integruje?', 'Who integrates?'),
    -- Bezwarunkowy dochód podstawowy?
    ('%dochód podstawowy%', 1, 'Kto za to zapłaci?', 'Who pays for it?'),
    ('%dochód podstawowy%', 2, 'Po co pracować?', 'Why work then?'),
    ('%dochód podstawowy%', 3, 'Inflacja w górę?', 'Will prices rise?'),
    ('%dochód podstawowy%', 4, 'Też dla bogatych?', 'Even for the rich?'),
    -- Kara śmierci za najcięższe zbrodnie?
    ('%kara śmierci%', 1, 'A pomyłka sądowa?', 'What about wrongful conviction?'),
    ('%kara śmierci%', 2, 'Naprawdę odstrasza?', 'Does it really deter?'),
    ('%kara śmierci%', 3, 'Kto wykonuje wyrok?', 'Who carries it out?'),
    ('%kara śmierci%', 4, 'Tańsze niż dożywocie?', 'Cheaper than life in prison?'),
    -- Dzikie zwierzęta w zoo dla rozrywki?
    ('%zoo%', 1, 'Ratują gatunki?', 'Do they save species?'),
    ('%zoo%', 2, 'A życie na wolności?', 'What about life in the wild?'),
    ('%zoo%', 3, 'Edukacja dzieci?', 'Educating children?'),
    ('%zoo%', 4, 'Wielkość wybiegu?', 'Size of the enclosure?'),
    -- Niekorzystający z auta - te same podatki drogowe?
    ('%podatki drogowe%', 1, 'Towary jadą drogami?', 'Goods travel those roads too?'),
    ('%podatki drogowe%', 2, 'Karetka dla wszystkich?', 'Ambulances for everyone?'),
    ('%podatki drogowe%', 3, 'Kto liczy użycie?', 'Who measures usage?'),
    ('%podatki drogowe%', 4, 'Rowerzysta nie płaci?', 'Should cyclists pay nothing?'),
    -- Żołnierz karany za odmowę niemoralnego rozkazu?
    ('%żołnierz%', 1, 'Kto ocenia moralność?', 'Who judges morality?'),
    ('%żołnierz%', 2, 'Rozpad dyscypliny?', 'Discipline collapses?'),
    ('%żołnierz%', 3, 'Pamiętasz Norymbergę?', 'Remember Nuremberg?'),
    ('%żołnierz%', 4, 'Wymówka tchórza?', 'A coward''s excuse?'),
    -- Miliardy na Marsa, gdy Ziemia ma problemy?
    ('%Marsa%', 1, 'Plan B dla ludzkości?', 'Humanity''s plan B?'),
    ('%Marsa%', 2, 'Czyje to miliardy?', 'Whose billions are they?'),
    ('%Marsa%', 3, 'Technologia wraca na Ziemię?', 'Does the tech come back to Earth?'),
    ('%Marsa%', 4, 'Ziemia poczeka?', 'Can Earth wait?'),
    -- Można zostać miliarderem, gdy inni głodują?
    ('%miliarderem%', 1, 'Skąd ten majątek?', 'How was it earned?'),
    ('%miliarderem%', 2, 'Tort się powiększa?', 'Does the pie grow?'),
    ('%miliarderem%', 3, 'Zasługa czy szczęście?', 'Merit or luck?'),
    ('%miliarderem%', 4, 'Ile to za dużo?', 'How much is too much?'),
    -- Media społecznościowe zakazane poniżej 16 lat?
    ('%społecznościowe%', 1, 'Zdrowie psychiczne?', 'Mental health?'),
    ('%społecznościowe%', 2, 'Jak sprawdzić wiek?', 'How to verify age?'),
    ('%społecznościowe%', 3, 'Rola rodzica?', 'The parent''s role?'),
    ('%społecznościowe%', 4, 'Wykluczy z grupy?', 'Social exclusion?'),
    -- Głosowanie obowiązkowe dla każdego?
    ('%wyborach%', 1, 'Głos z przymusu?', 'A forced vote?'),
    ('%wyborach%', 2, 'Niedoinformowani głosują?', 'Uninformed voters?'),
    ('%wyborach%', 3, 'Kara za absencję?', 'Punish no-shows?'),
    ('%wyborach%', 4, 'Wyższa legitymacja?', 'Stronger legitimacy?'),
    -- Licencja na posiadanie dzieci?
    ('%licencji%', 1, 'Kto wydaje licencję?', 'Who issues the license?'),
    ('%licencji%', 2, 'Eugenika tylnymi drzwiami?', 'Eugenics by the back door?'),
    ('%licencji%', 3, 'A ciąża bez zgody?', 'And unlicensed pregnancies?'),
    ('%licencji%', 4, 'Dobro dziecka?', 'The child''s welfare?'),
    -- Genetyczna modyfikacja dzieci, by usunąć choroby?
    ('%genetycznie%', 1, 'Gdzie postawić granicę?', 'Where is the line?'),
    ('%genetycznie%', 2, 'Tylko dla bogatych?', 'Only for the rich?'),
    ('%genetycznie%', 3, 'Projektowane dzieci?', 'Designer babies?'),
    ('%genetycznie%', 4, 'Zgoda dziecka?', 'The child''s consent?'),
    -- Otyła osoba płaci za dwa miejsca?
    ('%otyła%', 1, 'Limit wagi?', 'A weight limit?'),
    ('%otyła%', 2, 'A choroba?', 'What if it is a medical condition?'),
    ('%otyła%', 3, 'Komfort sąsiada?', 'The neighbor''s comfort?'),
    ('%otyła%', 4, 'Bilet od kilograma?', 'Price by the kilo?'),
    -- AI podejmuje decyzje życia i śmierci?
    ('%inteligencja%', 1, 'Kto ponosi winę?', 'Who is to blame?'),
    ('%inteligencja%', 2, 'Uprzedzenia w danych?', 'Bias in the data?'),
    ('%inteligencja%', 3, 'Bez emocji lepiej?', 'Better without emotion?'),
    ('%inteligencja%', 4, 'Lekarz myli się częściej?', 'Do doctors err more often?'),
    -- Prywatne samochody zakazane w centrach miast?
    ('%prywatne samochody%', 1, 'A niepełnosprawni?', 'What about the disabled?'),
    ('%prywatne samochody%', 2, 'Dostawy i rzemieślnicy?', 'Deliveries and tradespeople?'),
    ('%prywatne samochody%', 3, 'Komunikacja gotowa?', 'Is public transit ready?'),
    ('%prywatne samochody%', 4, 'Czystsze powietrze?', 'Cleaner air?')
),
resolved as (
  select s.position, s.pl, s.en, q.id as question_id
  from src s
  join question_translations t
    on t.locale = 'pl' and t.question_text ilike s.qkey
  join questions q on q.id = t.question_id
),
ins as (
  insert into question_smaczki (question_id, position, is_active)
  select question_id, position::smallint, true from resolved
  returning id, question_id, position
)
insert into question_smaczki_translations (smaczek_id, locale, text)
select i.id, v.locale, v.txt
from ins i
join resolved r on r.question_id = i.question_id and r.position = i.position
cross join lateral (values ('pl', r.pl), ('en', r.en)) as v(locale, txt);
