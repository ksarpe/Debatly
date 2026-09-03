# Kategoria `Intimacy` (etykieta w apce: „+18”) — partia 1, 2026-09-02

47 pytań TAK/NIE o seksie, ciele i bliskości w związku. Ton dojrzały, bez
dosłowności; smaczki ostre, do czytelnika przez „ty”. Wszystkie pytania:
`category = 'Intimacy'`, `is_premium = true`, `is_active = true`,
`seed_total = 0`. **Tylko dla PRO, poza pytaniem dnia** (decyzja
właściciela 2026-09-02): kategoria wykluczona z `daily_picks`, z osobistego
losowania zastępczego w `get_daily_question` i z zajawki `peek_next_question`
— do zrobienia migracją razem z INSERT-ami.

Układ smaczków: 1 = kontra do „oczywistej” odpowiedzi, 2 = kontra do kontry,
3 = na czytelnika / na praktykę. Kolumna `side` to `question_smaczki.side`:
`attacks_yes` uderza w tego, kto zagłosował TAK, `attacks_no` w tego, kto
zagłosował NIE, `neutral` w oboje.

Sprawdzone pod kątem bliźniaków (2026-09-02): w katalogu istnieją i NIE są
tu powtórzone: „różny apetyt na seks — kompromis”, „poczekać kilka randek
przed łóżkiem”, „treści dla dorosłych to zdrada”, „prostytucja
zalegalizowana”, „hasła”, „czytanie telefonu”, „20 lat różnicy”, „zazdrość
o przeszłość”, „każdy szczegół miłosnej przeszłości”, „jeden pocałunek”,
„usunąć zdjęcia byłego”, „podrasowane zdjęcia na profilu”.

Limity: pytanie PL ≤ 100 (tu 39–85), EN ≤ 90; smaczek PL ≤ 67, EN ≤ 73.

SQL INSERT (schemat z `references/sql.md` + kolumna `side`) generuję po
akceptacji listy.

---

## 1. Czy udawanie orgazmu, żeby nie ranić partnera, to oszustwo?
**EN:** Is faking an orgasm to spare your partner a lie?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Jedna miła nieprawda kontra jego zraniona duma — serio oszustwo? | One kind untruth against his wounded pride — really a lie? |
| 2 | attacks_no | Każde udane raz to instrukcja, jak robić to źle dalej | Every fake is a lesson in keeping on doing it wrong |
| 3 | attacks_no | Chciałbyś wiedzieć, że twój partner udaje od lat? | Would you want to know your partner has been faking for years? |

## 2. Czy seks bez ochoty, tylko dla partnera, to jeszcze bliskość?
**EN:** Is sex you don't feel like, done for your partner, still intimacy?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Bliskość, w której jedno liczy minuty do końca? | Closeness where one of you is counting the minutes? |
| 2 | attacks_no | Odmawiasz, aż przestanie pytać — i wtedy będzie lepiej? | Say no until they stop asking — and that will be better? |
| 3 | neutral | Ile razy w tym roku poszedłeś do łóżka z uprzejmości? | How many times this year did you go to bed out of politeness? |

## 3. Czy pół roku bez seksu w związku to problem, a nie faza?
**EN:** Is six months without sex a problem, not just a phase?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Chory rodzic, noworodek, zwolnienie — faza ma swoje powody | A sick parent, a newborn, a layoff — phases have reasons |
| 2 | attacks_no | Faza, która trwa dłużej niż wasz najlepszy rok razem | A phase that lasts longer than your best year together |
| 3 | attacks_no | Wiesz w ogóle, kiedy był ostatni raz? | Do you even know when the last time was? |

## 4. Czy szczerość o tym, co nie działa w łóżku, jest ważniejsza niż czyjeś ego?
**EN:** Does honesty about what fails in bed matter more than someone's ego?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Powiesz, i od tej pory każde zbliżenie będzie egzaminem | Say it, and every night after becomes an exam |
| 2 | attacks_no | Milczysz z litości i skazujesz oboje na lata udawania | Silence out of pity sentences you both to years of pretending |
| 3 | neutral | Ty byś wolał usłyszeć prawdę czy nigdy się nie dowiedzieć? | Would you rather hear it, or never know? |

## 5. Czy kłopoty partnera z erekcją to wasz wspólny problem, nie tylko jego?
**EN:** Are your partner's erection problems your problem too, not just his?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Twoja troska brzmi jak presja, a presja pogarsza sprawę | Your concern sounds like pressure, and pressure makes it worse |
| 2 | attacks_no | Zostawiasz go z tym samego i dziwisz się, że milczy | You leave him alone with it and wonder why he goes quiet |
| 3 | attacks_no | Gdyby to ciało zawiodło ciebie, chciałbyś słyszeć: to twój problem? | If it were your body failing, would you want to hear: your problem? |

## 6. Czy powinno się pytać nowego partnera o liczbę poprzednich?
**EN:** Should you ask a new partner how many came before you?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Usłyszysz liczbę i co z nią zrobisz — poza porównywaniem się? | You get a number, and what do you do with it but compare? |
| 2 | attacks_no | Nie pytasz, bo szanujesz, czy bo boisz się odpowiedzi? | You don't ask out of respect, or out of fear of the answer? |
| 3 | neutral | Podałbyś prawdziwą liczbę, gdyby spytali ciebie? | Would you give the real number if they asked you? |

## 7. Czy zabawki w sypialni to sygnał, że partner nie wystarcza?
**EN:** Are toys in the bedroom a sign your partner isn't enough?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Nikt nie mówi, że książka kucharska obraża kucharza | Nobody says a cookbook is an insult to the cook |
| 2 | attacks_no | Jeśli to nic nie znaczy, czemu leży schowane na dnie szuflady? | If it means nothing, why is it hidden at the back of the drawer? |
| 3 | neutral | Wolałbyś nie wiedzieć, jak twój partner radzi sobie bez ciebie? | Would you rather not know how your partner manages without you? |

## 8. Czy wspólne oglądanie filmów dla dorosłych zbliża parę?
**EN:** Does watching adult films together bring a couple closer?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Zbliża was do ekranu, nie do siebie | It brings you closer to the screen, not to each other |
| 2 | attacks_no | Wolisz, żeby oglądał sam i o tym nie mówił? | Would you rather they watched alone and never mentioned it? |
| 3 | neutral | Kto wybiera film — i czy drugie naprawdę chce go oglądać? | Who picks the film — and does the other really want to watch? |

## 9. Czy masturbacja w stałym związku to prywatna sprawa, o której partner nie musi wiedzieć?
**EN:** Is solo sex in a steady relationship private, none of your partner's business?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Prywatne bywa to, czego się wstydzisz — a czego tu się wstydzić? | Private is what you're ashamed of — and what is there to be ashamed of? |
| 2 | attacks_no | Chcesz raport z każdego prysznica? | Do you want a report from every shower? |
| 3 | neutral | Zapytałbyś o to partnera wprost — i uwierzył w odpowiedź? | Would you ask your partner outright — and believe the answer? |

## 10. Czy nagie zdjęcie wysłane partnerowi to normalna część bliskości?
**EN:** Is a nude sent to your partner a normal part of intimacy?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Bliskość kończy się na rozstaniu, zdjęcie zostaje w telefonie | Intimacy ends with the breakup; the photo stays on a phone |
| 2 | attacks_no | Ufasz mu z całym życiem, ale nie z jednym zdjęciem? | You trust them with your whole life, but not with one photo? |
| 3 | attacks_yes | Wysłałbyś, gdyby jutro miał to zobaczyć ktoś trzeci? | Would you send it if a third person might see it tomorrow? |

## 11. Czy fantazjowanie o kimś innym w łóżku z partnerem to zdrada?
**EN:** Is fantasising about someone else in bed with your partner cheating?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Zdrada bez dotyku, bez wiadomości, bez spotkania — czego dokładnie? | Cheating with no touch, no message, no meeting — of what exactly? |
| 2 | attacks_no | Ciałem jesteś tu, głową z kimś innym — kto właśnie leży obok? | Body here, mind with someone else — who is lying next to them? |
| 3 | attacks_no | Wolałbyś to wiedzieć czy nigdy się nie dowiedzieć? | Would you rather know, or never find out? |

## 12. Czy otwarty związek może być tak samo poważny jak wierność?
**EN:** Can an open relationship be as serious as a faithful one?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Poważny związek, w którym każde ma plan B pod ręką? | A serious relationship where each keeps a plan B handy? |
| 2 | attacks_no | Wierność z nudów i strachu to poważniejszy fundament? | Is fidelity out of boredom and fear a sturdier foundation? |
| 3 | attacks_yes | Ty byś zniósł jego wieczór z kimś innym? | Could you stomach their evening with someone else? |

## 13. Czy propozycja trójkąta od partnera to powód do niepokoju?
**EN:** Is a threesome proposal from your partner a reason to worry?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Niepokoi cię pomysł czy to, że nie przyszedł od ciebie? | Is it the idea that worries you, or that it wasn't yours? |
| 2 | attacks_no | Ktoś, kto tęskni za trzecią osobą, mówi ci coś o dwójce | Someone missing a third person is telling you something about the two |
| 3 | attacks_no | Zgodziłbyś się, żeby nie wyjść na nudnego? | Would you say yes just to not seem boring? |

## 14. Czy młodzi rodzice powinni wpisywać seks do kalendarza?
**EN:** Should new parents put sex in the calendar?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Wtorek 21:30, po kąpieli małego — romantycznie? | Tuesday, 9.30 pm, after the baby's bath — romantic? |
| 2 | attacks_no | Bez wpisu w kalendarzu wygrywa sen, co noc, przez rok | Without the entry, sleep wins — every night, for a year |
| 3 | attacks_no | Kiedy ostatnio spontanicznie zrobiliście cokolwiek? | When did the two of you last do anything spontaneously? |

## 15. Czy spanie w osobnych łóżkach to początek końca związku?
**EN:** Are separate beds the beginning of the end?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Wyspani ludzie kłócą się rzadziej niż ci, co dzielą kołdrę | Rested people fight less than the ones sharing a duvet |
| 2 | attacks_no | Ostatnia rzecz, którą jeszcze robiliście razem, właśnie odpadła | The last thing you still did together just went |
| 3 | attacks_no | Chrapanie to powód czy wygodna wymówka? | Is the snoring the reason, or a convenient excuse? |

## 16. Czy seks z byłym po rozstaniu to błąd, nawet gdy oboje są wolni?
**EN:** Is sex with an ex a mistake, even when you're both single?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Dwoje wolnych ludzi, którzy się znają — co tu jest błędem? | Two single people who know each other — what's the mistake? |
| 2 | attacks_no | Wracasz do kogoś, z kim nie dało się żyć, na jedną noc | You go back to someone you couldn't live with — for one night |
| 3 | attacks_no | Rano będzie prościej czy będziecie zaczynać od nowa? | Will the morning be simpler, or will you be starting over? |

## 17. Czy przyjaźń z seksem bez zobowiązań może zostać przyjaźnią?
**EN:** Can friends with benefits go back to being just friends?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Jedno z was zawsze chce więcej — tylko się nie przyznaje | One of you always wants more — they just don't say it |
| 2 | attacks_no | Dorośli ludzie nie potrafią umówić się na zasady? | Can't two adults agree on rules? |
| 3 | attacks_yes | Zniesiesz, gdy przyjaciel przedstawi ci swoją nową dziewczynę? | Could you take your friend introducing his new girlfriend? |

## 18. Czy przygoda na jedną noc mówi coś o czyimś charakterze?
**EN:** Does a one-night stand say anything about someone's character?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Jedna noc mówi tyle, co jeden posiłek o twojej diecie | One night says as much as one meal says about your diet |
| 2 | attacks_no | Ludzie w jedną noc pokazują dokładnie, jak traktują obcych | In one night people show exactly how they treat strangers |
| 3 | neutral | Oceniałbyś tak samo kobietę i mężczyznę? | Would you judge a woman and a man the same way? |

## 19. Czy płatny seks singla to wyłącznie jego prywatna sprawa?
**EN:** Is a single person paying for sex nobody's business but theirs?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Ktoś po drugiej stronie tej prywatności nie wybrał tego zawodu z marzeń | Someone on the other side of that privacy didn't dream of this job |
| 2 | attacks_no | Osądzasz zakup tego, co sam rozdajesz za kolację i komplementy? | You judge buying what you trade for dinner and compliments? |
| 3 | attacks_yes | Powiedziałbyś o tym nowej partnerce? | Would you tell a new partner about it? |

## 20. Czy dobry seks bez uczuć jest wart mniej niż przeciętny z miłością?
**EN:** Is great sex without feelings worth less than average sex with love?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Twoje ciało nie sprawdza, czy ktoś je kocha | Your body doesn't check whether it's loved |
| 2 | attacks_no | Pamiętasz czyjeś imię z tych wielkich nocy bez uczuć? | Do you remember a name from those great, loveless nights? |
| 3 | neutral | Zamieniłbyś jedno na drugie, gdybyś mógł wybrać na resztę życia? | Would you swap one for the other, for the rest of your life? |

## 21. Czy seks według stałego schematu po latach to porażka pary?
**EN:** Is sex by the same routine after years a couple's failure?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Schemat, który działa, to nie porażka, to wiedza o sobie | A routine that works isn't failure — it's knowing each other |
| 2 | attacks_no | Nazywasz to sprawdzonym, bo boisz się zaproponować cokolwiek | You call it tried-and-tested because you're scared to suggest anything |
| 3 | attacks_no | Kiedy ostatnio zrobiliście coś pierwszy raz? | When did you last do something for the first time? |

## 22. Czy seks na zgodę to dobry sposób na zakończenie kłótni?
**EN:** Is make-up sex a good way to end a fight?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Kłótnia nie zniknęła, tylko poszła spać obok was | The fight didn't end — it just went to sleep beside you |
| 2 | attacks_no | Wolisz trzy dni cichych dni od jednej dobrej nocy? | Would you rather three days of silence than one good night? |
| 3 | attacks_yes | Kto z was wtedy przeprasza — i czy to w ogóle przeprosiny? | Who apologises then — and is it even an apology? |

## 23. Czy w porządku jest powiedzieć partnerowi, że jego ciało przestało cię pociągać?
**EN:** Is it fair to tell your partner their body no longer attracts you?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Usłyszy to raz, a będzie słyszeć przy każdym rozbieraniu | They hear it once and will hear it every time they undress |
| 2 | attacks_no | Wolisz, żeby domyślił się z twojego odwracania wzroku? | Would you rather they guessed from you looking away? |
| 3 | neutral | Ty chciałbyś to usłyszeć czy dalej udawać, że nie widzisz? | Would you want to hear it, or keep pretending not to notice? |

## 24. Czy prośba partnera o depilację to w porządku?
**EN:** Is it okay for a partner to ask you to shave?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Twoje ciało ma spełniać czyjeś wymagania jak strój do pracy? | Your body meeting someone's requirements, like a work uniform? |
| 2 | attacks_no | Prosi, bo to lubi — ty też masz swoje drobne życzenia | They ask because they like it — you have small wishes too |
| 3 | neutral | Odwróć role: poprosiłbyś o to samo? | Swap roles: would you ask for the same? |

## 25. Czy nagość na plaży to zdrowa normalność?
**EN:** Is nudity on a beach a healthy normality?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Normalność, na którą reszta plaży nie wyraziła zgody | A normality the rest of the beach never agreed to |
| 2 | attacks_no | Wstydzisz się ciała, które ma każdy, i nazywasz to kulturą | Ashamed of a body everyone has, and calling it culture |
| 3 | attacks_yes | Rozebrałbyś się tam, gdyby obok leżał ktoś z pracy? | Would you strip there with a colleague on the next towel? |

## 26. Czy para po pięćdziesiątce powinna walczyć o seks, a nie się z nim żegnać?
**EN:** Should a couple past fifty fight for sex rather than wave it goodbye?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Walka o coś, na co żadne z was nie ma już ochoty? | Fighting for something neither of you feels like any more? |
| 2 | attacks_no | Żegnasz się z nim w wieku, w którym twoi rodzice zaczęli od nowa | You give it up at the age your parents started over |
| 3 | attacks_no | Kto pierwszy przestał proponować — i czy drugie to zauważyło? | Who stopped suggesting first — and did the other notice? |

## 27. Czy wizyta u seksuologa to przyznanie, że związek się sypie?
**EN:** Is seeing a sex therapist an admission the relationship is failing?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Nikt nie mówi, że wizyta u dentysty to przyznanie się do próchnicy | Nobody calls a trip to the dentist an admission of decay |
| 2 | attacks_no | Pary, u których wszystko gra, nie szukają obcego w sypialni | Couples where it all works don't invite a stranger into the bedroom |
| 3 | neutral | Poszedłbyś, gdyby to partner zaproponował, czy poczuł się oskarżony? | Would you go if your partner suggested it, or feel accused? |

## 28. Czy opowiadanie przyjaciółkom o seksie z partnerem to zdrada jego prywatności?
**EN:** Is telling your friends about sex with your partner a breach of his privacy?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Twoje życie to też twoja historia, nie tylko jego | Your life is your story too, not just his |
| 2 | attacks_no | Jego kumple przy piwie znają cię lepiej, niż myślisz | His mates at the pub know you better than you think |
| 3 | attacks_no | Powiedziałbyś partnerowi dokładnie to, co mówisz przyjaciółkom? | Would you tell your partner exactly what you tell your friends? |

## 29. Czy inicjatywa w łóżku powinna wychodzić po równo od obojga?
**EN:** Should initiative in bed come equally from both of you?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Liczysz, kto zaczął, zamiast cieszyć się, że w ogóle | Counting who started instead of being glad it happened |
| 2 | attacks_no | Jedno wciąż prosi, drugie wciąż łaskawie się zgadza | One keeps asking, the other keeps graciously agreeing |
| 3 | neutral | Kiedy ty ostatnio zacząłeś pierwszy? | When did you last make the first move? |

## 30. Czy odmawianie seksu za karę to manipulacja?
**EN:** Is withholding sex as punishment manipulation?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Nie masz ochoty na kogoś, kto cię właśnie zranił — to kara? | You don't want someone who just hurt you — is that punishment? |
| 2 | attacks_no | Ciało jako nagroda za dobre sprawowanie — jak u psa | The body as a reward for good behaviour — like a dog's treat |
| 3 | neutral | Skąd partner ma wiedzieć, czy to kara, czy brak ochoty? | How is your partner to know it's punishment, not just no desire? |

## 31. Czy szczęśliwa para musi kochać się co najmniej raz w tygodniu?
**EN:** Does a happy couple need to make love at least once a week?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Szczęście z licznikiem to raczej abonament | Happiness with a counter sounds more like a subscription |
| 2 | attacks_no | Bez żadnej miary nie zauważysz, kiedy przestaliście | With no measure at all, you won't notice when you stopped |
| 3 | neutral | Ile wam wyszło w tym miesiącu — i czy któreś liczy? | How many this month — and is either of you counting? |

## 32. Czy zaniżenie liczby byłych partnerów to nieszkodliwe kłamstwo?
**EN:** Is rounding down your number of past partners a harmless lie?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Kłamstwo, które utrzymujesz do końca życia, jest nieszkodliwe? | A lie you keep up for the rest of your life — harmless? |
| 2 | attacks_no | Prawdziwa liczba nic nie zmienia, tylko zapada w pamięć | The real number changes nothing; it just sticks in the memory |
| 3 | neutral | Jaką liczbę podałbyś dziś, gdyby spytał ktoś nowy? | What number would you give today if someone new asked? |

## 33. Czy poprosiłbyś nową osobę o wyniki badań przed pierwszym razem?
**EN:** Would you ask someone new for test results before the first time?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Nastrój, świece i prośba o zaświadczenie | The mood, the candles, and a request for paperwork |
| 2 | attacks_no | Ufasz zdrowiu obcego bardziej niż własnemu rozsądkowi | You trust a stranger's health more than your own sense |
| 3 | attacks_yes | Sam byś je miał pod ręką, gdyby ktoś poprosił? | Would you have yours to hand if they asked? |

## 34. Czy romans z kimś z pracy to zawsze zły pomysł?
**EN:** Is a fling with a colleague always a bad idea?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Spędzasz tam osiem godzin dziennie — gdzie indziej masz szukać? | You spend eight hours a day there — where else would you look? |
| 2 | attacks_no | Po rozstaniu dalej macie wspólny kalendarz i jedną kuchnię | After the breakup you still share a calendar and a kitchen |
| 3 | attacks_no | Kto z was zmieni pracę, gdy się skończy? | Which of you changes jobs when it ends? |

## 35. Czy powinno się mówić nowemu partnerowi, że to twój pierwszy raz?
**EN:** Should you tell a new partner it's your first time?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Powiesz, i zamiast partnera masz nauczyciela z misją | Say it and you get a teacher on a mission instead of a partner |
| 2 | attacks_no | Będzie się domyślać i tak, tylko bez szansy, by być delikatnym | They'll guess anyway, just without the chance to be gentle |
| 3 | neutral | Chciałbyś wiedzieć, że jesteś czyimś pierwszym? | Would you want to know you're someone's first? |

## 36. Czy intymne zdjęcia byłego trzeba skasować w dniu rozstania?
**EN:** Must intimate photos of an ex be deleted the day you split?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | To także twoje wspomnienie, nie tylko jego ciało | It's your memory too, not just their body |
| 2 | attacks_no | Trzymasz cudze ciało w telefonie, na który nikt nie wyraził zgody | You keep someone's body on a phone they never agreed to |
| 3 | attacks_no | Chciałbyś, żeby były miał twoje zdjęcia jeszcze za rok? | Would you want an ex to still have yours a year from now? |

## 37. Czy seks jest częścią umowy małżeńskiej?
**EN:** Is sex part of the marriage deal?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Umowa, którą egzekwujesz w łóżku, to już nie małżeństwo | A contract enforced in bed isn't a marriage any more |
| 2 | attacks_no | Ślubowałeś wierność — komu, jeśli nie dzielicie łóżka? | You vowed fidelity — to whom, if you no longer share a bed? |
| 3 | attacks_yes | Co byś powiedział, gdyby to partner powołał się na umowę? | What would you say if your partner invoked the deal? |

## 38. Czy partner powinien znać wszystkie twoje fantazje?
**EN:** Should your partner know all your fantasies?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Niektóre rzeczy istnieją tylko dlatego, że nikt ich nie zna | Some things exist only because nobody knows them |
| 2 | attacks_no | Ukrywasz je przed osobą, z którą mógłbyś je spełnić | You hide them from the one person you could live them out with |
| 3 | neutral | Zniósłbyś każdą jego fantazję bez zmiany spojrzenia? | Could you hear every one of theirs without looking at them differently? |

## 39. Czy bielizna w prezencie od partnera to prezent dla niego, nie dla ciebie?
**EN:** Is lingerie from your partner a gift for him, not for you?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Prezent, przez który czujesz się pożądana, jest tylko dla niego? | A gift that makes you feel desired is only for him? |
| 2 | attacks_no | Rozmiar z wyobraźni, wzór z jego ulubionej strony | Size from his imagination, style from his favourite site |
| 3 | neutral | Co ty kupiłbyś jemu, żeby wyjść na równo? | What would you buy him to call it even? |

## 40. Czy seks u rodziców, gdy śpią za ścianą, jest w porządku?
**EN:** Is sex at your parents' place, with them asleep next door, okay?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Twoja mama też ma uszy i pamięć | Your mother has ears too — and a memory |
| 2 | attacks_no | Jesteś dorosły, a wciąż prosisz rodziców o pozwolenie | You're an adult and still asking your parents' permission |
| 3 | attacks_yes | A gdyby to twoje dorosłe dziecko było za tą ścianą? | And if it were your grown child behind that wall? |

## 41. Czy przed ślubem trzeba sprawdzić dopasowanie w łóżku?
**EN:** Should you test how you match in bed before marrying?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Sprawdzasz jak auto przed zakupem — i jak długo trwa jazda próbna? | Testing like a car before buying — and how long is the test drive? |
| 2 | attacks_no | Ślubujesz na całe życie coś, czego nie znasz | You vow a lifetime to something you've never known |
| 3 | attacks_yes | Odwołałbyś ślub, gdyby wyszło słabo? | Would you call off the wedding if it went badly? |

## 42. Czy partner ma prawo zabronić ci konta na OnlyFans?
**EN:** Does your partner get a veto on your OnlyFans account?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Twoje ciało, twoje konto — od kiedy trzeba mieć pozwolenie? | Your body, your account — since when do you need permission? |
| 2 | attacks_no | Obcy płacą za to, co on dostaje w domu — i ma milczeć? | Strangers pay for what he gets at home — and he should stay quiet? |
| 3 | attacks_yes | Zamieniłbyś się z nim miejscami bez słowa? | Would you swap places with him and say nothing? |

## 43. Czy dobry seks może uratować zły związek?
**EN:** Can good sex save a bad relationship?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Ratujesz dom, w którym działa tylko jedna sypialnia | Saving a house where only one room still works |
| 2 | attacks_no | Wiele par przetrwało lata dzięki temu jednemu pokojowi | Plenty of couples got through years on that one room |
| 3 | attacks_yes | Zostałbyś dla łóżka z kimś, z kim nie da się rozmawiać? | Would you stay for the bed with someone you can't talk to? |

## 44. Czy zły seks to wystarczający powód do rozstania?
**EN:** Is bad sex reason enough to break up?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Rzucasz kogoś za coś, czego nigdy nie próbowaliście naprawić | Leaving someone over something you never tried to fix |
| 2 | attacks_no | Zostajesz i planujesz czterdzieści lat zaciskania zębów | Stay, and plan forty years of gritting your teeth |
| 3 | attacks_yes | Powiedziałeś mu w ogóle, co jest nie tak? | Have you actually told them what's wrong? |

## 45. Czy związek na odległość przetrwa rok bez fizycznej bliskości?
**EN:** Can a long-distance couple last a year with no physical closeness?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Rok rozmów z ekranem, a ciało pamięta, że go nie ma | A year of talking to a screen while the body remembers |
| 2 | attacks_no | Pary za ścianą rozpadają się szybciej niż te za oceanem | Couples next door fall apart faster than ones across an ocean |
| 3 | attacks_yes | Ile wieczorów minie, zanim ktoś w pobliżu zacznie kusić? | How many evenings before someone nearby starts to tempt? |

## 46. Czy nagość przy partnerze na co dzień zabija pożądanie?
**EN:** Does everyday nudity around your partner kill desire?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Pożądanie, które ginie od widoku, nie było mocne | Desire that dies at the sight of you was never strong |
| 2 | attacks_no | Tajemnica skończyła się razem z zamykaniem drzwi łazienki | The mystery ended along with closing the bathroom door |
| 3 | attacks_no | Kiedy ostatnio rozbierałeś się dla partnera, a nie tylko przed nim? | When did you last undress for your partner, not just in front of them? |

## 47. Czy telewizor w sypialni to cichy zabójca seksu?
**EN:** Is a TV in the bedroom a quiet killer of sex?

| # | side | PL | EN |
|---|---|---|---|
| 1 | attacks_yes | Nie telewizor kładzie was do łóżka o innych porach | It isn't the TV putting you to bed at different hours |
| 2 | attacks_no | Ostatnie pół godziny dnia oddajesz serialowi, nie partnerowi | The last half hour of the day goes to a series, not a partner |
| 3 | attacks_no | Wyniósłbyś go na miesiąc, żeby sprawdzić? | Would you move it out for a month to find out? |

---

## Świadomie pominięte

- Wszystko, co ociera się o zgodę po alkoholu, ból, ciążę, antykoncepcję i
  leczenie: czyta się jak poradę medyczną albo prawną, a nie jak spór.
- Nastolatki i edukacja seksualna: zasada „nic o dzieciach w kontekście
  seksualnym”.
- Czekanie z seksem do ślubu: w praktyce spór o religię.
- Seks w miejscu publicznym: pytanie o prawo, nie o ocenę.

## Co dalej

1. Twoje OK (albo lista numerów do wycięcia / poprawy) → generuję jeden plik
   SQL z 47 blokami INSERT (`questions` + tłumaczenia + smaczki z `side` +
   `question_vote_seeds`), do wklejenia w SQL editorze.
2. Osobno: piąty tryb „+18” w kliencie (`QuestionMode.intimacy`, wiersz na
   ekranie trybów w miejscu kreskowanego „Kolejny tryb”, ARB) — kilkanaście
   linii, robię po wgraniu pytań.
3. Przed publikacją buildu: kwestionariusze wieku w App Store Connect i Play
   Console (treści seksualne „infrequent/mild”).
