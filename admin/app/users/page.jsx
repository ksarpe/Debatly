'use client';

import { useCallback, useEffect, useState } from 'react';
import { api } from '../../lib/api';
import UserHistory from '../../components/UserHistory';

/**
 * Top users — the appreciation board. /stats has "Kto zużywa głosy" for abuse
 * review; this page answers the other question: who are the best players?
 * One admin_top_users() call, all-time, the same internal-account filter as
 * /stats. Read-only.
 *
 * Every board gets the same row shape from the server, so one <Board/>
 * renders them all — the board only decides which column is the headline.
 */

const TIERS = {
  paid:    { label: 'PRO',        cls: 'badge premium' },
  granted: { label: 'PRO (grant)', cls: 'badge draft' },
  free:    { label: 'free',       cls: 'badge' },
};

const nf = new Intl.NumberFormat('pl-PL');
const fmtDate = (iso) => (iso ? new Date(iso).toLocaleDateString('pl-PL', { day: 'numeric', month: 'short' }) : '—');
const fmtDateTime = (iso) => (iso ? new Date(iso).toLocaleString('pl-PL', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }) : '—');

const LIMITS = [3, 5, 10];

export default function UsersPage() {
  const [limit, setLimit] = useState(3);
  const [includeInternal, setIncludeInternal] = useState(false);
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState(null);
  // Account lookup: seeded from ?u= (the Live page and the Telegram ping
  // link here), mirrored back into the URL so a result can be shared.
  const [lookup, setLookup] = useState('');

  useEffect(() => {
    const u = new URLSearchParams(window.location.search).get('u');
    if (u) setLookup(u);
  }, []);

  const onLookup = useCallback((q) => {
    const url = new URL(window.location.href);
    url.searchParams.set('u', q);
    window.history.replaceState(null, '', url);
  }, []);

  const load = useCallback(async (n, internal) => {
    setLoading(true);
    setErr(null);
    try {
      setData(await api.topUsers(internal, n));
    } catch (e) {
      setErr(e.friendly || e.message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { load(limit, includeInternal); }, [limit, includeInternal, load]);

  const s = data?.summary;
  const pick = useCallback((id) => {
    setLookup(id);
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }, []);

  return (
    <>
      <h1 className="page-title">Top userzy</h1>
      <p className="page-sub">
        Najlepsi gracze od początku. Streak liczony tak, jak widzi go użytkownik w apce (doba UTC,
        z zamrożeniem i spadkiem rang); głosy PRO = oddane w czasie, gdy konto miało PRO.
        {data && <> Wygenerowano: {new Date(data.generated_at).toLocaleString('pl-PL')}.</>}
      </p>

      <div className="toolbar">
        {LIMITS.map((n) => (
          <button key={n} className={`btn sm ${limit === n ? 'primary' : ''}`}
                  disabled={limit === n} onClick={() => setLimit(n)}>
            top {n}
          </button>
        ))}
        <label className="faint" style={{ display: 'flex', gap: 7, alignItems: 'center' }}>
          <input type="checkbox" checked={includeInternal}
                 onChange={(e) => setIncludeInternal(e.target.checked)} style={{ width: 'auto' }} />
          pokaż też nasze konta
        </label>
      </div>

      <UserHistory initial={lookup} onLookup={onLookup} />

      {err && <div className="alert err">{err}</div>}
      {loading && <div className="spin">Ładowanie…</div>}

      {!loading && data && (
        <>
          <div className="stat-grid">
            <Tile label="Głosujący" value={nf.format(s.voters)}
                  note={`${nf.format(s.votes)} głosów all-time · ${nf.format(s.accounts)} z kontem`} />
            <Tile label="Głosowali dziś" value={nf.format(s.voted_today)}
                  note="doba Europe/Warsaw" />
            <Tile label="Żywy streak ≥ 3" value={nf.format(s.streak_alive_3)}
                  note={`≥7: ${nf.format(s.streak_alive_7)} · ≥14: ${nf.format(s.streak_alive_14)} (głos dziś lub wczoraj UTC)`} />
            <Tile label="PRO aktywne" value={nf.format(s.pro_live)}
                  note={`kupione, wciąż ważne · ${nf.format(s.pro_granted)} grantów · ${nf.format(s.votes_pro)} głosów PRO`} />
            <Tile label="Bramy odpowiedziane" value={nf.format(s.gates_answered)}
                  note={s.moved_pct != null
                    ? `kontra przewróciła ${s.moved_pct}% (${nf.format(s.gates_moved)})`
                    : 'brak zaliczonych bram'} />
          </div>

          <div className="two-col">
            <Board onPick={pick} title="Największy streak" sub="żywy streak (po spadkach rang), jak w apce"
                   rows={data.streaks} empty="Nikt nie ma żywego streaka"
                   headline={(r) => `${nf.format(r.live_streak)} dni`}
                   detail={(r) => (
                     <>
                       {r.rank_name && <span className="badge" style={{ marginRight: 6 }}>{r.rank_name}</span>}
                       rekord {nf.format(r.longest_streak)}
                       {r.streak_alive
                         ? <span className="ok-cell"> · aktywny</span>
                         : <span className="warn-cell"> · ostatni głos {fmtDate(r.last_vote_date)}</span>}
                     </>
                   )} />

            <Board onPick={pick} title="Rekord streaka" sub="najdłuższy streak kiedykolwiek"
                   rows={data.records} empty="Brak danych"
                   headline={(r) => `${nf.format(r.longest_streak)} dni`}
                   detail={(r) => <>teraz {nf.format(r.live_streak)} · {nf.format(r.votes)} głosów</>} />
          </div>

          <div className="two-col">
            <Board onPick={pick} title="PRO — najwięcej głosów" sub="głosy oddane, gdy konto miało PRO"
                   rows={data.pro} empty="Żadne konto PRO jeszcze nie głosowało"
                   headline={(r) => `${nf.format(r.votes_pro)} głosów`}
                   detail={(r) => (
                     <>
                       {nf.format(r.active_days)} dni aktywnych · streak {nf.format(r.live_streak)}
                       {r.pro_since && <> · PRO od {fmtDate(r.pro_since)}</>}
                       {r.tier === 'paid' && !r.pro_live && <span className="warn-cell"> · wygasło</span>}
                     </>
                   )} />

            <Board onPick={pick} title="Free — najwierniejsi" sub="głosy free = dni z pytaniem dnia (1 głos / dobę)"
                   rows={data.free} empty="Brak głosów free"
                   headline={(r) => `${nf.format(r.votes_free)} dni`}
                   detail={(r) => (
                     <>
                       streak {nf.format(r.live_streak)} (rekord {nf.format(r.longest_streak)})
                       {r.votes_free > r.active_days && (
                         <span className="warn-cell"> · {nf.format(r.votes_free)} głosów w {nf.format(r.active_days)} dni</span>
                       )}
                     </>
                   )} />
          </div>

          <div className="two-col">
            <Board onPick={pick} title="Najbardziej otwarci" sub="najwięcej bram zakończonych „To mnie ruszyło”"
                   rows={data.movers} empty="Kontra nikogo jeszcze nie przewróciła"
                   headline={(r) => `${nf.format(r.gates_moved)} ×`}
                   detail={(r) => <>z {nf.format(r.gates_qualifying)} zaliczonych bram ({r.flip_pct}%) · trzymał się {nf.format(r.gates_held)} ×</>} />

            <Board onPick={pick} title="Czytelnicy argumentów" sub="najwięcej zaliczonych bram (trzymam się + ruszyło)"
                   rows={data.readers} empty="Nikt nie zaliczył jeszcze bramy"
                   headline={(r) => `${nf.format(r.gates_qualifying)} bram`}
                   detail={(r) => (
                     <>
                       ruszyło {nf.format(r.gates_moved)} · trzymał się {nf.format(r.gates_held)}
                       {r.gates_fast > 0 && <> · za szybko {nf.format(r.gates_fast)}</>}
                       {r.gates_dismissed > 0 && <> · cofnął {nf.format(r.gates_dismissed)}</>}
                     </>
                   )} />
          </div>

          <details className="card how-counted">
            <summary>Jak to jest liczone</summary>
            <ul>
              <li>
                <b>All-time</b>: konto trafia na listy, jeśli oddało kiedykolwiek choć jeden głos — te same
                dane co „Od początku” w /stats. <b>Rekord streaka</b> to liczba z profilu użytkownika.
              </li>
              <li>
                <b>Żywy streak</b> = ta sama funkcja, którą apka pokazuje użytkownikowi: głos dziś lub wczoraj
                (UTC) trzyma streak w całości, potem co 3 dni bez głosu spada o jedną rangę. „Aktywny” = głos
                dziś lub wczoraj; inaczej pokazujemy datę ostatniego głosu.
              </li>
              <li>
                <b>PRO</b> = plan, jaki konto miało <b>w chwili głosu</b> (od realnego zakupu do końca znanego
                okresu). „PRO (grant)” = promo/tester — jego wolumen jest oczekiwany. Free może oddać jeden głos
                na dobę, więc u free liczba głosów = liczba dni; podświetlona rozbieżność to sygnał do
                sprawdzenia w /stats.
              </li>
              <li>
                <b>Bramy</b> = odpowiedzi na argument po głosie. Zaliczone = „trzymam się” lub „to mnie ruszyło”
                z czasem czytania ≥ 1,5 s (te liczą się do profilu debatanta). „Za szybko” i „cofnął” są
                pokazane, ale nie liczą się do rankingu.
              </li>
              <li>
                Nasze konta (maile firmowe + każdy z zakupem sandbox) są wycięte, chyba że zaznaczysz
                „pokaż też nasze konta”. Identyfikator to pierwsze 8 znaków UUID — pełny w tytule po najechaniu,
                kliknięcie otwiera historię konta u góry strony.
              </li>
            </ul>
          </details>
        </>
      )}
    </>
  );
}

function Tile({ label, value, note }) {
  return (
    <div className="card stat-tile">
      <div className="stat-label">{label}</div>
      <div className="stat-value">{value}</div>
      {note && <div className="faint">{note}</div>}
    </div>
  );
}

const MEDALS = ['🥇', '🥈', '🥉'];

function Board({ title, sub, rows, empty, headline, detail, onPick }) {
  return (
    <div className="card">
      <h3>{title} {sub && <span className="faint">({sub})</span>}</h3>
      {rows.length === 0 && <p className="muted" style={{ margin: 0 }}>{empty}</p>}
      {rows.length > 0 && (
        <ol className="top-list">
          {rows.map((r, i) => (
            <li key={r.user_id} className="top-row">
              <span className="top-pos">{MEDALS[i] ?? `${i + 1}.`}</span>
              <span className="top-main">
                <span className="top-headline">{headline(r)}</span>
                <span className="top-detail faint">{detail(r)}</span>
              </span>
              <span className="top-who">
                <code className="uid" title={`${r.user_id} — kliknij, żeby zobaczyć historię`}
                      style={{ cursor: 'pointer' }} onClick={() => onPick?.(r.user_id)}>
                  {r.user_id.slice(0, 8)}
                </code>
                <span className={TIERS[r.tier]?.cls || 'badge'}>{TIERS[r.tier]?.label || r.tier}</span>
                {r.is_anonymous && <span className="badge">anonim</span>}
                {r.has_account && <span className="badge approved">konto</span>}
                <span className="faint top-last" title="ostatni głos">{fmtDateTime(r.last_vote_at)}</span>
              </span>
            </li>
          ))}
        </ol>
      )}
    </div>
  );
}
