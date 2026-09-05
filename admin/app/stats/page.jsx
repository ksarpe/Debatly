'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { api } from '../../lib/api';

/**
 * Product dashboard: funnels, paywall, landing, suspects — everything the
 * SQL-editor views knew, in one admin_dashboard_stats() call. Read-only.
 *
 * Vocabulary (the same one the RPC uses, 20260902120000):
 *   instalacja  = one install_id — a UUID the app mints on its first launch
 *                 and keeps in SharedPreferences. Reinstall = new id. The web
 *                 landing page writes to the same table with a per-browser id
 *                 and is NOT an install; the RPC keeps it apart.
 *   nowa        = the install's FIRST app event falls inside the window.
 *   aktywna     = ≥1 app event inside the window (new + returning).
 *   doba        = Europe/Warsaw, the owner's clock (same as /live).
 */

const STEP_LABELS = {
  onboarding_started: 'Ekran powitalny',
  onboarding_taste_shown: 'Pytanie „na smak” pokazane',
  onboarding_taste_voted: 'Tapnięcie „na smak” (opcjonalne)',
  bridge_shown: 'Ekran wyboru free/PRO (bridge)',
  onboarding_finished: 'Onboarding ukończony',
  daily_vote_cast: 'Pierwszy prawdziwy głos = aktywacja',
};
// Steps a user can legitimately skip — drawn lighter so a dip there does not
// read as a leak.
const SOFT_STEPS = new Set(['onboarding_taste_voted', 'bridge_shown']);

const PAYWALL_SOURCES = {
  wall: 'Ściana dnia (day wall)',
  bridge: 'Bridge po onboardingu',
  smaczki: 'Zablokowany smaczek',
  favorites: 'Ulubione (gwiazdka)',
  history: 'Historia głosów',
  profile: 'Profil debatanta',
  settings: 'Ustawienia',
  general: 'Ogólny',
  hardWall: 'Twardy paywall (wersje sprzed freemium)',
  readingLimit: 'Limit czytania (stare wersje)',
  adLimit: 'Limit reklam (stare wersje)',
  '(none)': '(brak źródła)',
};

// Plan, jaki konto miało W MOMENCIE oddania głosu (admin_user_pro_window):
// "grant" to konto testowe/promo — jego wolumen jest oczekiwany, nie podejrzany.
const TIERS = {
  paid:    { label: 'PRO (kupione)', cls: 'badge premium' },
  granted: { label: 'PRO (grant)',   cls: 'badge draft' },
  free:    { label: 'free',          cls: 'badge' },
};

const REVEAL_SOURCES = {
  daily: 'Pytanie dnia',
  free_credit: 'Darmowy kredyt (stare wersje)',
  ad: 'Reklama (stare wersje)',
  view: 'Przeglądanie (PRO)',
};

const nf = new Intl.NumberFormat('pl-PL');
const pct = (num, den) => (den > 0 ? `${Math.round((100 * num) / den)}%` : '—');

// Konwersja instalacja → zakup siedzi w okolicach 1–5%, gdzie zaokrąglenie do
// pełnych procent zlepia 1,4% z 2,4% — czyli dwie zupełnie różne kampanie.
const pct1 = (num, den) =>
  den > 0 ? `${(Math.round((1000 * num) / den) / 10).toLocaleString('pl-PL')}%` : '—';

const fmtDay = (iso) =>
  new Date(`${iso}T12:00:00`).toLocaleDateString('pl-PL', { weekday: 'short', day: 'numeric', month: 'short' });

export default function StatsPage() {
  const [days, setDays] = useState(30);
  const [includeInternal, setIncludeInternal] = useState(false);
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState(null);

  const load = useCallback(async (d, internal) => {
    setLoading(true);
    setErr(null);
    try {
      setData(await api.dashboardStats(d, internal));
    } catch (e) {
      setErr(e.friendly || e.message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { load(days, includeInternal); }, [days, includeInternal, load]);

  const t = data?.totals;
  const windowLabel = days == null
    ? `od ${data?.tracking_since ?? 'startu telemetrii'}`
    : `ostatnie ${days} dni`;

  // Głosy wg pytania: dzisiejsze i wczorajsze pytanie dnia na wierzchu, reszta
  // (katalog, po którym chodzą PRO) zwinięta pod "pokaż więcej".
  const velocityPicks = useMemo(() => (data?.velocity ?? []).filter((v) => v.is_recent_pick), [data]);
  const velocityRest = useMemo(() => (data?.velocity ?? []).filter((v) => !v.is_recent_pick), [data]);

  return (
    <>
      <h1 className="page-title">Statystyki</h1>
      <p className="page-sub">
        Własna analityka (app_events + głosy + subskrypcje + RevenueCat) — bez konsoli Google/Apple.
        {data && <> Telemetria od {data.tracking_since}, doba = {data.timezone}. Wygenerowano: {new Date(data.generated_at).toLocaleString('pl-PL')}.</>}
      </p>

      <div className="toolbar">
        {[[7, '7 dni'], [30, '30 dni'], [null, 'Od początku']].map(([d, label]) => (
          <button key={label} className={`btn sm ${days === d ? 'primary' : ''}`}
                  disabled={days === d} onClick={() => setDays(d)}>
            {label}
          </button>
        ))}
        <label className="faint" style={{ display: 'flex', gap: 7, alignItems: 'center' }}>
          <input type="checkbox" checked={includeInternal}
                 onChange={(e) => setIncludeInternal(e.target.checked)} style={{ width: 'auto' }} />
          pokaż też nasze konta
        </label>
        <span className="faint">
          okres liczy kafelki i lejki; wykres dzienny zawsze ≤ 90 dni
          {data && data.internal_excluded && data.internal_installs > 0 && (
            <> · wycięto {data.internal_installs} nasze instalacje</>
          )}
        </span>
      </div>

      {err && <div className="alert err">{err}</div>}
      {loading && <div className="spin">Ładowanie…</div>}

      {!loading && data && (
        <>
          <div className="stat-grid">
            <Tile label="Nowe instalacje" value={nf.format(t.installs_new)}
                  note={`pierwsze uruchomienie apki, ${windowLabel}`} />
            <Tile label="Aktywne instalacje" value={nf.format(t.installs_active)}
                  note="≥1 zdarzenie apki w okresie (nowe + powracające)" />
            <Tile label="Aktywacja" value={pct(t.activated, t.installs_new)}
                  note={`${nf.format(t.activated)} z ${nf.format(t.installs_new)} nowych oddało głos`} />
            <Tile label="Głosy" value={nf.format(t.votes)}
                  note={`${nf.format(t.voters)} głosujących`
                    + ` · PRO ${nf.format(t.votes_pro ?? 0)} / free ${nf.format(t.votes_free ?? 0)}`} />
            <Tile label="Głosy z kont PRO" value={pct(t.votes_pro ?? 0, t.votes)}
                  note={`${nf.format(t.votes_pro ?? 0)} głosów od ${nf.format(t.voters_pro ?? 0)} kont PRO`
                    + ` · free: ${nf.format(t.votes_free ?? 0)} od ${nf.format(t.voters_free ?? 0)}`} />
            <Tile label="Free ponad limit" value={nf.format(t.free_multi_vote_days ?? 0)}
                  warn={(t.free_multi_vote_days ?? 0) > 0}
                  note={`dni, w których konto free oddało >1 głos (rekord: ${nf.format(t.free_max_votes_in_day ?? 0)}/dzień)`} />
            <Tile label="Zakupy PRO" value={nf.format(t.purchases_paid)}
                  note={`${nf.format(t.active_subs)} aktywnych subskrypcji`
                    + (t.purchases !== t.purchases_paid ? ` · apka zgłosiła ${nf.format(t.purchases)}` : '')} />
            <Tile label="Konwersja PRO" value={pct1(t.purchases_paid, t.installs_new)}
                  note={`${nf.format(t.purchases_paid)} zakupów na ${nf.format(t.installs_new)} nowych instalacji`} />
            <Tile label="Landing (link z bio)" value={nf.format(t.landing_views)}
                  note={`${nf.format(t.landing_votes)} zagłosowało na stronie · to nie są instalacje`} />
            <Tile label="Podejrzane konta" value={nf.format(t.suspects)} warn={t.suspects > 0}
                  note={`${nf.format(t.suspect_votes)} ich głosów (heurystyki, all-time)`} />
          </div>

          <details className="card how-counted">
            <summary>Jak to jest liczone (przeczytaj raz)</summary>
            <ul>
              <li>
                <b>Instalacja</b> = jeden <code>install_id</code>: UUID, który apka losuje przy
                pierwszym uruchomieniu i trzyma w SharedPreferences. Reinstalacja lub nowy telefon
                = nowy id. To nasza telemetria, więc liczy od {data.tracking_since}; wcześniejsze
                instalacje widzą tylko konsole sklepów i RevenueCat (stąd RevenueCat pokazuje więcej).
              </li>
              <li>
                <b>Nowa</b> = pierwsze zdarzenie apki tego urządzenia wpadło w okres.
                <b> Aktywna</b> = urządzenie miało ≥1 zdarzenie w okresie, obojętnie kiedy powstało.
                W widoku „od początku” obie liczby są równe.
              </li>
              <li>
                <b>Landing</b> (strona z linku w bio TikToka) pisze do tej samej tabeli, ale z id
                przeglądarki — do 2.09 każde wejście liczyło się jako instalacja i kafelek pokazywał
                429 zamiast 212. Teraz landing ma osobny kafelek i osobną tabelę niżej.
              </li>
              <li>
                <b>Aktywacja</b> i <b>lejek onboardingu</b> liczą kohortę: tylko instalacje NOWE w
                okresie i to, co one zrobiły kiedykolwiek. Powracający stary użytkownik nie
                „aktywuje się” drugi raz.
              </li>
              <li>
                <b>Zakupy PRO</b> = realne pierwsze zakupy z webhooka RevenueCat (bez sandboxa, bez
                grantów promo) — ta sama definicja co na /live. Liczba „apka zgłosiła” to zdarzenie
                klienta i pojawia się tylko, gdy się różni.
              </li>
              <li>
                <b>Głosy PRO vs free</b> = plan, jaki konto miało <b>w chwili oddania głosu</b>, nie
                dziś: liczymy od pierwszego prawdziwego zakupu (bez sandboxa i bez promo) do końca
                znanego okresu abonamentu. Konto z grantem promo/testowym nie ma daty startu, więc
                wszystkie jego głosy liczą się jako PRO — w tabeli „Kto zużywa głosy” ma osobną
                etykietę. Konto free może oddać jeden głos na dobę, więc kafelek
                <b> Free ponad limit</b> powinien stale pokazywać 0; cokolwiek innego to skrypt albo
                błąd, nie użytkownik.
              </li>
              <li>
                <b>Doba</b> = Europe/Warsaw, jak na /live. Nasze konta
                (maile firmowe + każdy, kto kiedykolwiek kupił w sandboxie) są wycięte, chyba że
                zaznaczysz „pokaż też nasze konta”.
              </li>
            </ul>
          </details>

          <DailyChart daily={data.daily} tz={data.timezone} />

          <div className="two-col">
            <div className="card">
              <h3>Onboarding → aktywacja <span className="faint">(kohorta nowych instalacji)</span></h3>
              <Funnel steps={data.onboarding} />
              <p className="faint" style={{ marginBottom: 0 }}>
                Jaśniejsze kroki da się pominąć (tapnięcie „na smak” nie oddaje głosu; bridge
                omija skip). Spadek na nich nie jest wyciekiem.
              </p>
            </div>

            <div className="card">
              <h3>Landing z linku w bio</h3>
              <div className="tbl-scroll">
                <table className="stats-table">
                  <thead>
                    <tr>
                      <th>Wariant (v)</th><th>Pytanie (slug)</th>
                      <th className="num">Wejścia</th><th className="num">Głosy</th><th className="num">CR głos</th>
                    </tr>
                  </thead>
                  <tbody>
                    {data.landing.length === 0 && (
                      <tr><td colSpan={5} className="muted">Brak wejść na landing w tym okresie</td></tr>
                    )}
                    {data.landing.map((l) => (
                      <tr key={`${l.variant}|${l.slug}`}>
                        <td>{l.variant}</td>
                        <td className="muted">{l.slug}</td>
                        <td className="num">{nf.format(l.views)}</td>
                        <td className="num">{nf.format(l.votes)}</td>
                        <td className="num">{pct(l.votes, l.views)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              <p className="faint" style={{ marginBottom: 0 }}>
                Wejście = unikalna przeglądarka. Ile z nich poszło dalej do sklepu, widać tylko w
                Install Referrer (Android) — wiersze <code>landing</code> / <code>tiktok*</code> w
                tabeli „Akwizycja” niżej.
              </p>
            </div>
          </div>

          <div className="card">
            <h3>Paywall według punktu wejścia <span className="faint">(unikalne instalacje)</span></h3>
            <div className="tbl-scroll">
              <table className="stats-table">
                <thead>
                  <tr>
                    <th>Źródło</th>
                    <th className="num">Pokazany</th>
                    <th className="num">Wybór planu</th>
                    <th className="num">Start zakupu</th>
                    <th className="num">Kupione</th>
                    <th className="num">Konwersja</th>
                    <th className="num">Porzucone</th>
                    <th className="num">Błąd</th>
                    <th className="num">Zamknięte</th>
                    <th className="num">⚠ Brak oferty</th>
                  </tr>
                </thead>
                <tbody>
                  {data.paywall.map((p) => (
                    <tr key={p.source}>
                      <td>{PAYWALL_SOURCES[p.source] || p.source}</td>
                      <td className="num">{nf.format(p.shown)}</td>
                      <td className="num">{nf.format(p.plan_selected)}</td>
                      <td className="num">{nf.format(p.purchase_started)}</td>
                      <td className={`num ${p.purchased > 0 ? 'ok-cell' : ''}`}>{nf.format(p.purchased)}</td>
                      <td className="num">{pct1(p.purchased, p.shown)}</td>
                      <td className="num">{nf.format(p.abandoned)}</td>
                      <td className={`num ${p.failed > 0 ? 'warn-cell' : ''}`}>{nf.format(p.failed)}</td>
                      <td className="num">{nf.format(p.dismissed)}</td>
                      <td className={`num ${p.offer_unavailable > 0 ? 'warn-cell' : ''}`}>
                        {nf.format(p.offer_unavailable)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <p className="faint" style={{ marginBottom: 0 }}>
              Zdarzenia klienta (zakup tu = apka zgłosiła sukces, kafelek u góry liczy z RevenueCat).
              „Brak oferty” = paywall otworzył się, ale nie pobrał cen z RevenueCat — ten użytkownik
              nie miał jak kupić. „Twardy paywall” to wersje sprzed freemium — wygasa razem z nimi.
            </p>
          </div>

          <div className="two-col">
            <div className="card">
              <h3>Akwizycja (Install Referrer, dane od 13.08)</h3>
              <div className="tbl-scroll">
                <table className="stats-table">
                  <thead>
                    <tr>
                      <th>Źródło</th><th>Kampania</th>
                      <th className="num">Instalacje</th><th className="num">Onboarding</th>
                      <th className="num">Głos</th><th className="num">Paywall</th><th className="num">Zakup</th>
                      <th className="num">Konwersja</th>
                    </tr>
                  </thead>
                  <tbody>
                    {data.acquisition.map((a) => (
                      <tr key={`${a.source}|${a.campaign}`}>
                        <td>{a.source}</td>
                        <td className="muted">{a.campaign}</td>
                        <td className="num">{nf.format(a.installs)}</td>
                        <td className="num">{nf.format(a.onboarded)}</td>
                        <td className="num">{nf.format(a.voted)}</td>
                        <td className="num">{nf.format(a.saw_paywall)}</td>
                        <td className={`num ${a.purchased > 0 ? 'ok-cell' : ''}`}>{nf.format(a.purchased)}</td>
                        <td className="num">{pct1(a.purchased, a.installs)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              <p className="faint" style={{ marginBottom: 0 }}>
                Zawsze all-time (zdarzenie atrybucji jest jednorazowe). Kampanie z UTM
                pojawią się tu jako osobne wiersze. <b>Tylko Android</b> — Install
                Referrer to mechanizm Google Play, więc instalacje z App Store nie
                trafiają do tej tabeli i suma „Instalacje” jest tu niższa niż w kafelku
                u góry. <code>google-play</code> = wejście do sklepu bez linku (wyszukiwarka,
                polecane).
              </p>
            </div>

            <div className="card">
              <h3>Głosy wg pytania <span className="faint">(pytanie dnia: dziś i wczoraj)</span></h3>
              <VelocityTable rows={velocityPicks} today={data.daily.at(-1)?.day}
                             empty="Na dziś i wczoraj nie ma pytania dnia w kalendarzu" />
              {velocityRest.length > 0 && (
                <details className="more-rows">
                  <summary>Pokaż więcej — pozostałe pytania z ostatnich 7 dni ({velocityRest.length})</summary>
                  <VelocityTable rows={velocityRest} today={data.daily.at(-1)?.day} />
                </details>
              )}
              <p className="faint" style={{ marginBottom: 0 }}>
                Głosy z ostatnich 7 dni (doba {data.timezone}). Pytanie dnia pokazuje się nawet z zerem —
                to zero jest informacją. Reszta to katalog, po którym chodzą konta PRO; data przy
                pytaniu to dzień, w którym jest albo będzie pytaniem dnia.
              </p>
            </div>
          </div>

          <div className="card">
            <h3>
              Kto zużywa głosy <span className="faint">(20 najaktywniejszych kont w okresie)</span>
            </h3>
            <div className="tbl-scroll">
              <table className="stats-table">
                <thead>
                  <tr>
                    <th>Konto</th><th>Plan przy głosowaniu</th>
                    <th className="num">Głosy</th><th className="num">w tym PRO</th>
                    <th className="num">Dni</th><th className="num">Max/dzień</th>
                    <th>Ostatni głos</th>
                  </tr>
                </thead>
                <tbody>
                  {(data.top_voters ?? []).length === 0 && (
                    <tr><td colSpan={7} className="muted">Brak głosów w tym okresie</td></tr>
                  )}
                  {(data.top_voters ?? []).map((v) => (
                    <tr key={v.user_id}>
                      <td>
                        <code className="uid">{v.user_id.slice(0, 8)}</code>
                        {v.is_anonymous && <span className="badge" style={{ marginLeft: 6 }}>anonim</span>}
                      </td>
                      <td>
                        <span className={TIERS[v.tier]?.cls || 'badge'}>
                          {TIERS[v.tier]?.label || v.tier}
                        </span>
                      </td>
                      <td className="num">{nf.format(v.votes)}</td>
                      <td className="num">{nf.format(v.votes_pro)}</td>
                      <td className="num">{nf.format(v.active_days)}</td>
                      {/* Konto free ma prawo do 1 głosu na dobę — wszystko powyżej
                          podświetlamy, ale tylko dla free: dla PRO to normalna sesja. */}
                      <td className={`num ${v.tier === 'free' && v.max_votes_in_one_day > 1 ? 'warn-cell' : ''}`}>
                        {nf.format(v.max_votes_in_one_day)}
                      </td>
                      <td className="muted">{new Date(v.last_vote_at).toLocaleString('pl-PL')}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <p className="faint" style={{ marginBottom: 0 }}>
              „PRO (kupione)” = konto z prawdziwym zakupem w RevenueCat, liczone od momentu zakupu
              (a po wygaśnięciu abonamentu jego głosy znowu liczą się jako free). „PRO (grant)” =
              konto z promo/testowym dostępem — jego wolumen jest oczekiwany, nie jest sygnałem
              nadużycia. Podświetlone „Max/dzień” przy koncie <b>free</b> to jedyny twardy sygnał na
              tej tabeli: darmowy plan może wygenerować tylko jeden wiersz głosu dziennie.
            </p>
          </div>

          <div className="two-col">
            <div className="card">
              <h3>Odkrycia pytań wg źródła</h3>
              <table className="stats-table">
                <thead>
                  <tr><th>Źródło</th><th className="num">Odkrycia</th><th className="num">Użytkownicy</th></tr>
                </thead>
                <tbody>
                  {data.reveals.map((r) => (
                    <tr key={r.source}>
                      <td>{REVEAL_SOURCES[r.source] || r.source}</td>
                      <td className="num">{nf.format(r.reveals)}</td>
                      <td className="num">{nf.format(r.users)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
              <p className="faint" style={{ marginBottom: 0 }}>
                „Reklama” i „Darmowy kredyt” = odkrycia w wersjach sprzed freemium —
                nowe wersje nie mają już reklam ani kredytów.
              </p>
            </div>

            <div className="card">
              <h3>Podejrzane konta (heurystyki, nie wyroki) — {nf.format(t.suspects)} all-time, ostatnie 25</h3>
              <div className="tbl-scroll">
                <table className="stats-table">
                  <thead>
                    <tr>
                      <th>Konto</th><th>Sygnały</th>
                      <th className="num">Głosy</th><th className="num">Max/dzień</th>
                      <th className="num">Do 1. głosu</th><th>Ostatni głos</th>
                    </tr>
                  </thead>
                  <tbody>
                    {data.suspects.length === 0 && (
                      <tr><td colSpan={6} className="muted">Czysto — żadne konto nie łapie się na heurystyki</td></tr>
                    )}
                    {data.suspects.map((s) => (
                      <tr key={s.user_id}>
                        <td>
                          <code className="uid">{s.user_id.slice(0, 8)}</code>
                          {s.is_anonymous && <span className="badge" style={{ marginLeft: 6 }}>anonim</span>}
                          {s.is_premium && <span className="badge premium" style={{ marginLeft: 6 }}>premium</span>}
                        </td>
                        <td>
                          {s.no_app_events && <span className="badge rejected">bez zdarzeń appki</span>}{' '}
                          {s.instant_first_vote && <span className="badge draft">głos &lt; 5 s</span>}{' '}
                          {s.over_free_budget && <span className="badge rejected">ponad budżet free</span>}
                        </td>
                        <td className="num">{nf.format(s.vote_count)}</td>
                        <td className="num">{nf.format(s.max_votes_in_one_day)}</td>
                        <td className="num">{formatSecs(s.secs_to_first_vote)}</td>
                        <td className="muted">{new Date(s.last_vote_at).toLocaleString('pl-PL')}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              <p className="faint" style={{ marginBottom: 0 }}>
                „Głos &lt; 5 s” to próg poniżej ludzkiej sesji (przeczytaj → zdecyduj → tapnięcie) —
                wciąż jednak sygnał, nie wyrok: patrz na kombinacje sygnałów i liczbę głosów.
              </p>
            </div>
          </div>
        </>
      )}
    </>
  );
}

function VelocityTable({ rows, today, empty }) {
  return (
    <div className="tbl-scroll">
      <table className="stats-table">
        <thead>
          <tr>
            <th>Pytanie</th><th className="num">Głosy</th>
            <th className="num">TAK/NIE</th><th className="num">Suspect %</th>
          </tr>
        </thead>
        <tbody>
          {rows.length === 0 && (
            <tr><td colSpan={4} className="muted">{empty ?? 'Brak głosów w ostatnich 7 dniach'}</td></tr>
          )}
          {rows.map((v) => (
            <tr key={v.question_id}>
              <td className="q-cell">
                {v.pick_date && (
                  <span className={`badge ${v.is_recent_pick ? 'pending' : ''}`}
                        style={{ marginRight: 6 }}
                        title={v.pick_date > today ? 'w kalendarzu pytań dnia' : 'było pytaniem dnia'}>
                    {v.pick_date === today ? 'dziś' : fmtDay(v.pick_date)}
                  </span>
                )}
                {v.question_text_pl}
              </td>
              <td className="num">{nf.format(v.votes)}</td>
              <td className="num">{v.yes_votes}/{v.no_votes}</td>
              <td className={`num ${v.suspect_pct >= 50 ? 'warn-cell' : ''}`}>
                {v.suspect_pct != null ? `${v.suspect_pct}%` : '—'}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function Tile({ label, value, note, warn = false }) {
  return (
    <div className={`card stat-tile ${warn ? 'warn' : ''}`}>
      <div className="stat-label">{label}</div>
      <div className="stat-value">{value}</div>
      {note && <div className="faint">{note}</div>}
    </div>
  );
}

function Funnel({ steps }) {
  const base = Math.max(...steps.map((s) => s.installs), 1);
  return (
    <div className="funnel">
      {steps.map((s, i) => {
        // "poprz." compares against the last MANDATORY step — a soft step can
        // be skipped, so measuring against it made "finished" read as 219%.
        const prevStep = steps.slice(0, i).reverse().find((p) => !SOFT_STEPS.has(p.event));
        const prev = prevStep ? prevStep.installs : null;
        return (
          <div className="funnel-row" key={s.event}
               title={`${STEP_LABELS[s.event] || s.event}: ${s.installs}`}>
            <span className="funnel-name">{STEP_LABELS[s.event] || s.event}</span>
            <span className="funnel-track">
              <span className={`funnel-bar ${SOFT_STEPS.has(s.event) ? 'soft' : ''}`}
                    style={{ width: `${Math.max((100 * s.installs) / base, 1)}%` }} />
            </span>
            <span className="funnel-num">
              {nf.format(s.installs)} <span className="faint">{pct(s.installs, base)}</span>
              {prev != null && !SOFT_STEPS.has(s.event) && (
                <span className="faint funnel-step"> · {pct(s.installs, prev)} poprz.</span>
              )}
            </span>
          </div>
        );
      })}
    </div>
  );
}

/**
 * Daily activity. Bars = votes, split by the plan the account held WHEN it
 * voted (free at the bottom, PRO stacked on top — together they are the same
 * bar the chart drew before); lines = installs (new / active); dots = paid
 * purchases; the landing series is off by default (it lives on another
 * scale). Hovering a day pins its numbers above the chart — the SVG <title>
 * tooltip was too slow and named nothing.
 */
const SERIES = [
  { key: 'votes_free',      label: 'głosy free',         kind: 'bar',  cls: 'bar',       on: true },
  { key: 'votes_pro',       label: 'głosy PRO',          kind: 'bar',  cls: 'bar-pro',   on: true },
  { key: 'new_installs',    label: 'nowe instalacje',    kind: 'line', cls: 'line-new',  on: true },
  { key: 'active_installs', label: 'aktywne instalacje', kind: 'line', cls: 'line',      on: true },
  { key: 'landing_views',   label: 'wejścia na landing', kind: 'line', cls: 'line-land', on: false },
];
const BARS = SERIES.filter((s) => s.kind === 'bar');

function DailyChart({ daily: rawDaily, tz }) {
  const W = 900; const H = 190; const PAD_L = 34; const PAD_R = 6; const PAD_T = 8; const PAD_B = 22;
  const [on, setOn] = useState(() => Object.fromEntries(SERIES.map((s) => [s.key, s.on])));
  const [hover, setHover] = useState(null);

  // Zanim wjedzie nowa wersja RPC (albo gdy ktoś patrzy na starą odpowiedź z
  // cache) mamy tylko `votes` — wtedy cały słupek jest "free", zamiast zniknąć.
  const daily = useMemo(() => rawDaily.map((d) => ({
    ...d,
    votes_free: d.votes_free ?? d.votes,
    votes_pro: d.votes_pro ?? 0,
  })), [rawDaily]);
  const n = daily.length;

  // Słupki się sumują (stack), linie nie — skala musi znać sumę włączonych
  // serii słupkowych, inaczej stos wychodzi poza wykres.
  const max = useMemo(() => Math.max(1, ...daily.map((d) =>
    Math.max(
      BARS.filter((s) => on[s.key]).reduce((a, s) => a + (d[s.key] || 0), 0),
      ...SERIES.filter((s) => s.kind === 'line' && on[s.key]).map((s) => d[s.key] || 0),
    ))), [daily, on]);

  if (!n) return null;

  const innerW = W - PAD_L - PAD_R;
  const innerH = H - PAD_T - PAD_B;
  const bw = innerW / n;
  const x = (i) => PAD_L + bw * i + bw / 2;
  const y = (v) => PAD_T + innerH - (innerH * v) / max;
  const path = (key) => daily.map((d, i) => `${x(i).toFixed(1)},${y(d[key] || 0).toFixed(1)}`).join(' ');
  const gridVals = [0, Math.round(max / 2), max];
  const labelEvery = n > 45 ? 7 : n > 20 ? 5 : n > 10 ? 2 : 1;
  const h = hover != null ? daily[hover] : null;
  const totals = SERIES.map((s) => [s.key, daily.reduce((a, d) => a + (d[s.key] || 0), 0)]);
  const purchasesTotal = daily.reduce((a, d) => a + (d.purchases || 0), 0);

  return (
    <div className="card">
      <h3>
        Aktywność dzienna (ostatnie {n} dni, doba {tz})
        <span className="legend">
          {SERIES.map((s) => (
            <button key={s.key} type="button"
                    className={`legend-toggle ${on[s.key] ? '' : 'off'}`}
                    onClick={() => setOn((o) => ({ ...o, [s.key]: !o[s.key] }))}
                    title={on[s.key] ? 'kliknij, żeby ukryć' : 'kliknij, żeby pokazać'}>
              <span className={`swatch ${s.cls}`} /> {s.label}
            </button>
          ))}
          <span className="legend-static"><span className="swatch dot" /> zakup PRO</span>
        </span>
      </h3>

      <div className="chart-readout">
        {h ? (
          <>
            <b>{fmtDay(h.day)}</b>
            <span>nowe instalacje <b>{nf.format(h.new_installs)}</b></span>
            <span>aktywne <b>{nf.format(h.active_installs)}</b></span>
            <span>głosy <b>{nf.format(h.votes)}</b> <span className="faint">
              (PRO {nf.format(h.votes_pro)} · free {nf.format(h.votes_free)})
            </span></span>
            <span>zakupy PRO <b>{nf.format(h.purchases)}</b></span>
            <span>landing <b>{nf.format(h.landing_views)}</b></span>
          </>
        ) : (
          <>
            <b>Suma {n} dni</b>
            {totals.map(([k, v]) => (
              <span key={k}>{SERIES.find((s) => s.key === k).label} <b>{nf.format(v)}</b></span>
            ))}
            <span>zakupy PRO <b>{nf.format(purchasesTotal)}</b></span>
            <span className="faint">— najedź na dzień</span>
          </>
        )}
      </div>

      <svg viewBox={`0 0 ${W} ${H}`} className="daily-chart" role="img"
           aria-label="Wykres dziennej aktywności" onMouseLeave={() => setHover(null)}>
        {gridVals.map((v) => (
          <g key={v}>
            <line x1={PAD_L} x2={W - PAD_R} y1={y(v)} y2={y(v)} className="grid" />
            <text x={PAD_L - 5} y={y(v) + 3.5} className="axis" textAnchor="end">{nf.format(v)}</text>
          </g>
        ))}

        {daily.map((d, i) => {
          let base = 0;
          return BARS.filter((s) => on[s.key]).map((s) => {
            const v = d[s.key] || 0;
            const top = base + v;
            const rect = v > 0 && (
              <rect key={`${s.key}-${d.day}`}
                    x={(PAD_L + bw * i + bw * 0.2).toFixed(1)} y={y(top).toFixed(1)}
                    width={(bw * 0.6).toFixed(1)} height={(y(base) - y(top)).toFixed(1)}
                    className={`${s.cls} ${hover === i ? 'hot' : ''}`} />
            );
            base = top;
            return rect;
          });
        })}
        {on.landing_views && <polyline points={path('landing_views')} className="line-land" />}
        {on.active_installs && <polyline points={path('active_installs')} className="line" />}
        {on.new_installs && <polyline points={path('new_installs')} className="line-new" />}

        {daily.map((d, i) => d.purchases > 0 && (
          <circle key={`p-${d.day}`} cx={x(i).toFixed(1)} cy={(PAD_T + innerH - 5).toFixed(1)}
                  r={3 + Math.min(d.purchases, 4)} className="dot-purchase" />
        ))}

        {hover != null && (
          <line x1={x(hover)} x2={x(hover)} y1={PAD_T} y2={PAD_T + innerH} className="cursor" />
        )}

        {daily.map((d, i) => (i % labelEvery === 0 || i === n - 1) && (
          <text key={`x-${d.day}`} x={x(i)} y={H - 6} className="axis" textAnchor="middle">
            {d.day.slice(8, 10)}.{d.day.slice(5, 7)}
          </text>
        ))}

        {/* hit areas on top: one per day, full height */}
        {daily.map((d, i) => (
          <rect key={`h-${d.day}`} x={(PAD_L + bw * i).toFixed(1)} y={PAD_T}
                width={bw.toFixed(1)} height={innerH} className="hit"
                onMouseEnter={() => setHover(i)} />
        ))}
      </svg>
      <p className="faint" style={{ marginBottom: 0 }}>
        <b>Nowe</b> = urządzenia, które tego dnia pierwszy raz odpaliły apkę. <b>Aktywne</b> = urządzenia
        z ≥1 zdarzeniem apki tego dnia (nowe + powracające), więc linia nigdy nie schodzi poniżej „nowych”.
        Słupek głosów jest podzielony na plan, jaki konto miało <b>w chwili głosowania</b>: dół = free,
        góra = PRO. Konto free może w ciągu doby oddać dokładnie jeden głos (rewizja pytania dnia nadpisuje
        ten sam wiersz), więc wysoka część „free” to zawsze wielu ludzi, a nie jeden — wysoka część „PRO”
        to zwykle kilku abonentów przerabiających katalog. Zielona kropka = dzień z realnym
        zakupem (RevenueCat), im większa, tym więcej. Landing jest domyślnie wyłączony, bo skala jest inna —
        kliknij w legendzie. Kliknięcie serii chowa ją i przeskalowuje wykres.
      </p>
    </div>
  );
}

function formatSecs(s) {
  if (s == null) return '—';
  if (s < 60) return `${s} s`;
  if (s < 3600) return `${Math.round(s / 60)} min`;
  if (s < 86400) return `${Math.round(s / 3600)} h`;
  return `${Math.round(s / 86400)} dni`;
}
