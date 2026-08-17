'use client';

import { useCallback, useEffect, useState } from 'react';
import { api } from '../../lib/api';

/**
 * Product dashboard: funnels, ads, suspects — everything the SQL-editor views
 * knew, in one admin_dashboard_stats() call. Read-only.
 */

const STEP_LABELS = {
  onboarding_started: 'Start onboardingu',
  onboarding_taste_shown: 'Pytanie „na smak”',
  onboarding_taste_voted: 'Głos „na smak” (opcjonalny)',
  onboarding_notify_shown: 'Ekran powiadomień',
  onboarding_choice_shown: 'Ekran wyboru konta',
  onboarding_finished: 'Onboarding ukończony',
  daily_vote_cast: 'Pierwszy głos (aktywacja)',
};

const PAYWALL_SOURCES = {
  readingLimit: 'Limit czytania',
  smaczki: 'Smaczki',
  general: 'Ogólny (ustawienia)',
  favorites: 'Ulubione',
  history: 'Historia głosów',
  adLimit: 'Limit reklam',
  '(none)': '(brak źródła)',
};

const REVEAL_SOURCES = {
  daily: 'Pytanie dnia',
  free_credit: 'Darmowy kredyt',
  ad: 'Reklama (reveal)',
  view: 'Przeglądanie (PRO)',
};

const nf = new Intl.NumberFormat('pl-PL');
const pct = (num, den) => (den > 0 ? `${Math.round((100 * num) / den)}%` : '—');

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

  return (
    <>
      <h1 className="page-title">Statystyki</h1>
      <p className="page-sub">
        Własna analityka (app_events + głosy + reklamy + subskrypcje) — bez konsoli Google/Apple.
        {data && <> Wygenerowano: {new Date(data.generated_at).toLocaleString('pl-PL')}.</>}
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
          okres liczy funnel i sumy; wykres dzienny zawsze ≤ 90 dni
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
            <Tile label="Instalacje" value={nf.format(t.installs)} note="z ≥1 zdarzeniem w okresie" />
            <Tile label="Aktywacja" value={pct(t.activated, t.installs)}
                  note={`${nf.format(t.activated)} z ${nf.format(t.installs)} oddało głos`} />
            <Tile label="Głosy" value={nf.format(t.votes)} note={`${nf.format(t.voters)} głosujących`} />
            <Tile label="Zakupy PRO" value={nf.format(t.purchases)}
                  note={`${nf.format(t.active_subs)} aktywnych subskrypcji`} />
            <Tile label="Podejrzane konta" value={nf.format(t.suspects)} warn={t.suspects > 0}
                  note={`${nf.format(t.suspect_votes)} ich głosów (heurystyki, all-time)`} />
          </div>

          <DailyChart daily={data.daily} />

          <div className="two-col">
            <div className="card">
              <h3>Onboarding → aktywacja</h3>
              <Funnel steps={data.onboarding} />
            </div>

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
                „Reklama” = odkrycia po rewarded ad w starych wersjach aplikacji —
                nowe wersje nie mają już reklam.
              </p>
            </div>
          </div>

          <div className="card">
            <h3>Paywall według punktu wejścia</h3>
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
                      <td className="num">{pct(p.purchased, p.shown)}</td>
                      <td className="num">{nf.format(p.abandoned)}</td>
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
              „Brak oferty” = paywall otworzył się, ale nie pobrał cen z RevenueCat — ten
              użytkownik nie miał jak kupić.
            </p>
          </div>

          <div className="two-col">
            <div className="card">
              <h3>Akwizycja (Install Referrer, od 29.07)</h3>
              <div className="tbl-scroll">
                <table className="stats-table">
                  <thead>
                    <tr>
                      <th>Źródło</th><th>Kampania</th>
                      <th className="num">Instalacje</th><th className="num">Onboarding</th>
                      <th className="num">Głos</th><th className="num">Paywall</th><th className="num">Zakup</th>
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
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              <p className="faint" style={{ marginBottom: 0 }}>
                Zawsze all-time (zdarzenie atrybucji jest jednorazowe). Kampanie z UTM
                pojawią się tu jako osobne wiersze.
              </p>
            </div>

            <div className="card">
              <h3>Głosy wg pytania — ostatnie 7 dni</h3>
              <div className="tbl-scroll">
                <table className="stats-table">
                  <thead>
                    <tr>
                      <th>Pytanie</th><th className="num">Głosy</th>
                      <th className="num">TAK/NIE</th><th className="num">Suspect %</th>
                    </tr>
                  </thead>
                  <tbody>
                    {data.velocity.length === 0 && (
                      <tr><td colSpan={4} className="muted">Brak głosów w ostatnich 7 dniach</td></tr>
                    )}
                    {data.velocity.map((v) => (
                      <tr key={v.question_id}>
                        <td className="q-cell">{v.question_text_pl}</td>
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
            </div>
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
                        {s.instant_first_vote && <span className="badge draft">głos &lt; 60 s</span>}{' '}
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
              „Głos &lt; 60 s” sam w sobie jest słabym sygnałem (szybki człowiek też tak umie) —
              patrz na kombinacje sygnałów i liczbę głosów.
            </p>
          </div>
        </>
      )}
    </>
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
      {steps.map((s) => {
        const optional = s.event === 'onboarding_taste_voted';
        return (
          <div className="funnel-row" key={s.event}
               title={`${STEP_LABELS[s.event] || s.event}: ${s.installs}`}>
            <span className="funnel-name">{STEP_LABELS[s.event] || s.event}</span>
            <span className="funnel-track">
              <span className={`funnel-bar ${optional ? 'soft' : ''}`}
                    style={{ width: `${Math.max((100 * s.installs) / base, 1)}%` }} />
            </span>
            <span className="funnel-num">
              {nf.format(s.installs)} <span className="faint">{pct(s.installs, base)}</span>
            </span>
          </div>
        );
      })}
    </div>
  );
}

/** Dzienna aktywność: słupki = głosy, linia = aktywne instalacje. Czysty SVG. */
function DailyChart({ daily }) {
  const W = 900; const H = 150; const PAD = 6;
  const n = daily.length;
  if (!n) return null;
  const max = Math.max(...daily.map((d) => Math.max(d.votes, d.active_installs)), 1);
  const bw = (W - PAD * 2) / n;
  const y = (v) => H - PAD - ((H - PAD * 2) * v) / max;
  const line = daily
    .map((d, i) => `${(PAD + bw * i + bw / 2).toFixed(1)},${y(d.active_installs).toFixed(1)}`)
    .join(' ');
  return (
    <div className="card">
      <h3>
        Aktywność dzienna (ostatnie {n} dni)
        <span className="legend">
          <span className="swatch bar" /> głosy
          <span className="swatch line" /> aktywne instalacje
        </span>
      </h3>
      <svg viewBox={`0 0 ${W} ${H}`} className="daily-chart" role="img"
           aria-label="Wykres dziennej aktywności">
        {daily.map((d, i) => (
          <rect key={d.day}
                x={(PAD + bw * i + bw * 0.15).toFixed(1)} y={y(d.votes).toFixed(1)}
                width={(bw * 0.7).toFixed(1)} height={(H - PAD - y(d.votes)).toFixed(1)}
                className="bar">
            <title>{`${d.day} — głosy: ${d.votes}, aktywne: ${d.active_installs}, nowe: ${d.new_installs}, zakupy: ${d.purchases}`}</title>
          </rect>
        ))}
        <polyline points={line} className="line" />
        {daily.map((d, i) => d.purchases > 0 && (
          <circle key={`p-${d.day}`} cx={(PAD + bw * i + bw / 2).toFixed(1)}
                  cy={y(d.votes) - 6} r="3.5" className="dot-purchase">
            <title>{`${d.day} — zakupy PRO: ${d.purchases}`}</title>
          </circle>
        ))}
      </svg>
      <p className="faint" style={{ marginBottom: 0 }}>
        Zielona kropka = dzień z zakupem PRO. Najedź na słupek, żeby zobaczyć szczegóły dnia.
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
