'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { api } from '../../lib/api';

/**
 * Dziennik marketingowy: jeden wiersz na dzień. Ręcznie wpisujesz to, co widać
 * tylko w konsolach (filmik, jego wyświetlenia, wejścia na stronę sklepu,
 * pobrania z Google Play / App Store). Instalacje, zakupy i przychód dnia
 * dokłada baza sama (admin_list_marketing_stats) — z nich liczą się konwersje:
 *
 *   CR sklep  = pobrania / wejścia na stronę sklepu   (czy karta sklepu sprzedaje)
 *   CR zakup  = zakupy / instalacje tego dnia          (czy apka monetyzuje)
 *
 * Dni, które mają tylko dane automatyczne (jeszcze bez wpisu), też są na liście —
 * sprzedaż nigdy nie chowa się przed adminem.
 */

const nf = new Intl.NumberFormat('pl-PL');
const mf = new Intl.NumberFormat('pl-PL', { style: 'currency', currency: 'PLN' });
const DOW = ['nd', 'pn', 'wt', 'śr', 'cz', 'pt', 'sb'];

// Data w kolumnie skraca się do dd.mm (pełna zostaje w tooltipie) — pełne ISO
// zjadałoby szerokość potrzebną kolumnom z liczbami.
const shortDay = (iso) => `${iso.slice(8, 10)}.${iso.slice(5, 7)}`;

const todayLocal = () => {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};

// Puste pole = NULL ("nie wpisałem"), a nie 0 — DB rozróżnia to celowo.
const toInt = (s) => {
  const t = String(s ?? '').replace(/[\s ]/g, '');
  if (t === '') return null;
  const n = Number.parseInt(t, 10);
  return Number.isFinite(n) && n >= 0 ? n : null;
};

/** Suma pól, które mogą być NULL-em; null gdy żadne nie jest wpisane. */
const sumOrNull = (...v) =>
  v.every((x) => x == null) ? null : v.reduce((a, x) => a + (x ?? 0), 0);

/** Procent z zabezpieczeniem przed dzieleniem przez 0 / brakiem danych. */
const pct = (part, whole) =>
  part == null || !whole ? null : (part / whole) * 100;

const fmtPct = (p) => (p == null ? null : `${p.toFixed(p < 10 ? 1 : 0)}%`);

const emptyForm = (day) => ({
  day, video: '', video_views: '', store_visits_google: '', store_visits_appstore: '',
  downloads_google: '', downloads_appstore: '', notes: '',
});

const rowToForm = (r) => ({
  day: r.day,
  video: r.video ?? '',
  video_views: r.video_views ?? '',
  store_visits_google: r.store_visits_google ?? '',
  store_visits_appstore: r.store_visits_appstore ?? '',
  downloads_google: r.downloads_google ?? '',
  downloads_appstore: r.downloads_appstore ?? '',
  notes: r.notes ?? '',
});

export default function MarketingPage() {
  const [rows, setRows] = useState(null);
  const [trackingSince, setTrackingSince] = useState(null);
  const [err, setErr] = useState(null);
  const [editing, setEditing] = useState(null); // day edytowanego wiersza
  const [adding, setAdding] = useState(false);
  const [form, setForm] = useState(emptyForm(todayLocal()));
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setErr(null);
    try {
      const res = await api.listMarketing();
      setRows(res?.rows ?? []);
      setTrackingSince(res?.tracking_since ?? null);
    } catch (e) {
      setErr(e.friendly || e.message);
      setRows([]);
    }
  }, []);

  useEffect(() => { load(); }, [load]);

  const totals = useMemo(() => {
    const list = rows ?? [];
    const sum = (k) => list.reduce((a, r) => a + (r[k] ?? 0), 0);
    const downloads = sum('downloads_google') + sum('downloads_appstore');
    const visits = sum('store_visits_google') + sum('store_visits_appstore');
    const installs = sum('installs_tracked');
    const purchases = sum('purchases');
    return {
      views: sum('video_views'),
      visits,
      downloads,
      installs,
      purchases,
      revenue: list.reduce((a, r) => a + Number(r.revenue_pln ?? 0), 0),
      crStore: pct(downloads, visits),
      crBuy: pct(purchases, installs),
    };
  }, [rows]);

  function startAdd() {
    // Domyślnie dzisiaj; jeśli dzisiejszy wpis już jest — edytuj go zamiast dublować.
    const today = todayLocal();
    const existing = rows?.find((r) => r.day === today);
    if (existing?.has_entry) { startEdit(existing); return; }
    setForm(existing ? rowToForm(existing) : emptyForm(today));
    setAdding(true);
    setEditing(null);
  }

  function startEdit(r) {
    setForm(rowToForm(r));
    setEditing(r.day);
    setAdding(false);
  }

  function cancel() {
    setAdding(false);
    setEditing(null);
  }

  async function save() {
    if (!form.day) { setErr('Podaj datę.'); return; }
    // Nowy wpis pod datą, która ma już wpis, nadpisałby tamten dzień po cichu.
    // (Dzień widoczny tylko dzięki danym automatycznym nie jest wpisem.)
    if (adding && rows?.some((r) => r.day === form.day && r.has_entry)) {
      setErr(`Dzień ${form.day} ma już wpis — kliknij ✎ przy tamtym wierszu, żeby go edytować.`);
      return;
    }
    setBusy(true); setErr(null);
    try {
      await api.upsertMarketingDay({
        day: form.day,
        video: form.video || null,
        videoViews: toInt(form.video_views),
        storeVisitsGoogle: toInt(form.store_visits_google),
        storeVisitsAppstore: toInt(form.store_visits_appstore),
        downloadsGoogle: toInt(form.downloads_google),
        downloadsAppstore: toInt(form.downloads_appstore),
        notes: form.notes || null,
      });
      cancel();
      await load();
    } catch (e) {
      setErr(e.friendly || e.message);
    } finally {
      setBusy(false);
    }
  }

  async function remove(day) {
    if (!window.confirm(`Usunąć wpis z dnia ${day}? Tego nie da się cofnąć.`)) return;
    setBusy(true); setErr(null);
    try {
      await api.deleteMarketingDay(day);
      cancel();
      await load();
    } catch (e) {
      setErr(e.friendly || e.message);
    } finally {
      setBusy(false);
    }
  }

  // Liczby automatyczne edytowanego dnia — pokazywane, ale nieedytowalne.
  const autoOfForm = rows?.find((r) => r.day === form.day);

  const editorRow = (
    <tr className="editor-row">
      <td>
        <input type="date" value={form.day} disabled={!adding}
               onChange={(e) => setForm({ ...form, day: e.target.value })} />
      </td>
      <td className="mkt-video">
        <input type="text" value={form.video} placeholder="np. TikTok „5 pytań na pierwszą randkę” + link"
               onChange={(e) => setForm({ ...form, video: e.target.value })} />
      </td>
      <NumCell value={form.video_views} onChange={(v) => setForm({ ...form, video_views: v })} />
      <NumCell value={form.store_visits_google} onChange={(v) => setForm({ ...form, store_visits_google: v })} />
      <NumCell value={form.store_visits_appstore} onChange={(v) => setForm({ ...form, store_visits_appstore: v })} />
      <NumCell value={form.downloads_google} onChange={(v) => setForm({ ...form, downloads_google: v })} />
      <NumCell value={form.downloads_appstore} onChange={(v) => setForm({ ...form, downloads_appstore: v })} />
      <td className="num muted">—</td>
      <td className="num muted">—</td>
      <td className="num auto-cell">{fmt(autoOfForm?.installs_tracked)}</td>
      <td className="num auto-cell">{fmt(autoOfForm?.purchases)}</td>
      <td className="num muted">—</td>
      <td className="mkt-notes">
        <input type="text" value={form.notes} placeholder="notatki"
               onChange={(e) => setForm({ ...form, notes: e.target.value })} />
      </td>
      <td className="mkt-acts">
        <button className="btn sm primary" disabled={busy} onClick={save}>Zapisz</button>
        <button className="btn sm ghost" disabled={busy} onClick={cancel}>Anuluj</button>
        {editing && (
          <button className="btn sm ghost" disabled={busy} title="Usuń wpis"
                  onClick={() => remove(editing)}>🗑</button>
        )}
      </td>
    </tr>
  );

  return (
    <>
      <h1 className="page-title">Marketing</h1>
      <p className="page-sub">
        Dziennik promocji — wiersz to jeden dzień. Ręcznie wpisujesz tylko to, co
        widać wyłącznie w konsolach sklepów; instalacje, zakupy i przychód dnia
        baza dokłada sama, a z nich liczą się konwersje. Puste pole = brak danych, nie zero.
      </p>

      <HelpBox />

      <div className="stat-grid">
        <Tile label="Wyświetlenia filmików" value={nf.format(totals.views)} note="ręcznie" />
        <Tile label="Wejścia na stronę sklepu" value={nf.format(totals.visits)} note="ręcznie, GP + AS" />
        <Tile label="Pobrania (konsole)" value={nf.format(totals.downloads)} note="ręcznie, GP + AS" />
        <Tile label="Instalacje (auto)" value={nf.format(totals.installs)} note="pierwsze uruchomienia apki" />
        <Tile label="Zakupy (auto)" value={nf.format(totals.purchases)} note={mf.format(totals.revenue)} />
        <Tile label="CR sklep" value={fmtPct(totals.crStore) ?? '—'} note="pobrania / wejścia" />
        <Tile label="CR zakup" value={fmtPct(totals.crBuy) ?? '—'} note="zakupy / instalacje" />
      </div>

      <div className="toolbar">
        <button className="btn primary" onClick={startAdd} disabled={adding || busy}>
          + Dodaj dzień
        </button>
        <span className="faint">wiersz = jeden dzień; kliknij ✎, żeby poprawić liczby</span>
      </div>

      {err && <div className="alert err">{err}</div>}
      {rows === null && <div className="spin">Ładowanie…</div>}

      {rows !== null && (
        <div className="card">
          <div className="tbl-scroll">
            <table className="stats-table mkt-table">
              {/* Procenty + table-layout: fixed (globals.css) = tabela nigdy nie
                  wychodzi poza okno, więc nie ma poziomego scrolla. */}
              <colgroup>
                <col style={{ width: '7%' }} />
                <col style={{ width: '17%' }} />
                <col style={{ width: '6%' }} />
                <col style={{ width: '6.5%' }} />
                <col style={{ width: '6.5%' }} />
                <col style={{ width: '6.5%' }} />
                <col style={{ width: '6.5%' }} />
                <col style={{ width: '5.5%' }} />
                <col style={{ width: '6%' }} />
                <col style={{ width: '6.5%' }} />
                <col style={{ width: '6%' }} />
                <col style={{ width: '6%' }} />
                <col style={{ width: '8.5%' }} />
                <col style={{ width: '6%' }} />
              </colgroup>
              <thead>
                <tr>
                  <th>Data</th>
                  <th>Filmik promujący</th>
                  <th className="num" title="Wyświetlenia filmiku (TikTok / Reels / Shorts)">Wyśw. filmiku</th>
                  <th className="num" title="Play Console → Pozyskiwanie użytkowników → wyświetlenia strony w Sklepie">Wejścia Play</th>
                  <th className="num" title="App Store Connect → Analityka → Product Page Views">Wejścia App&nbsp;St.</th>
                  <th className="num" title="Play Console → instalacje (unikalni użytkownicy)">Pobrania Play</th>
                  <th className="num" title="App Store Connect → Total Downloads">Pobrania App&nbsp;St.</th>
                  <th className="num">Σ pobrań</th>
                  <th className="num" title="Σ pobrań / Σ wejść na stronę sklepu">CR sklep</th>
                  <th className="num" title="Auto: ile urządzeń pierwszy raz odpaliło apkę tego dnia (nasza telemetria, bez opóźnienia konsol)">Instalacje ⚙</th>
                  <th className="num" title="Auto: realne zakupy tego dnia (bez sandboxa, bez promo z RevenueCat)">Zakupy ⚙</th>
                  <th className="num" title="Zakupy / instalacje tego dnia">CR zakup</th>
                  <th>Notatki</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {adding && editorRow}
                {rows.length === 0 && !adding && (
                  <tr><td colSpan={14} className="muted">Pusto — kliknij „+ Dodaj dzień”, żeby zacząć dziennik.</td></tr>
                )}
                {rows.map((r) => (editing === r.day ? (
                  <EditorRowKeyed key={r.day}>{editorRow}</EditorRowKeyed>
                ) : (
                  <DisplayRow key={r.day} r={r} trackingSince={trackingSince}
                              onEdit={() => startEdit(r)} busy={busy} />
                )))}
              </tbody>
              {rows.length > 0 && (
                <tfoot>
                  <tr>
                    <td colSpan={2}>Suma</td>
                    <td className="num">{nf.format(totals.views)}</td>
                    <td className="num" colSpan={2}>{nf.format(totals.visits)}</td>
                    <td className="num" colSpan={2}>{nf.format(totals.downloads)}</td>
                    <td className="num">{nf.format(totals.downloads)}</td>
                    <td className="num">{fmtPct(totals.crStore) ?? '—'}</td>
                    <td className="num">{nf.format(totals.installs)}</td>
                    <td className="num">{nf.format(totals.purchases)}</td>
                    <td className="num">{fmtPct(totals.crBuy) ?? '—'}</td>
                    <td colSpan={2} />
                  </tr>
                </tfoot>
              )}
            </table>
          </div>
        </div>
      )}
    </>
  );
}

/** Ściąga „co tu wpisywać” — zwinięta, bo czyta się ją raz na miesiąc. */
function HelpBox() {
  return (
    <details className="sec card mkt-help">
      <summary>Skąd brać te liczby? (ściąga)</summary>
      <div className="body">
        <p>
          <b>Wejścia GP / Wejścia AS</b> — ile osób <i>zobaczyło kartę apki w sklepie</i>,
          czyli kliknęło w link i wylądowało na stronie Debatly, ale niekoniecznie pobrało.
          To mianownik konwersji sklepu.
        </p>
        <ul>
          <li>
            <b>Google Play</b> → Play Console → <i>Statystyki / Pozyskiwanie użytkowników</i> →
            metryka „Wyświetlenia strony w Sklepie” (Store listing visitors), widok dzienny.
          </li>
          <li>
            <b>App Store</b> → App Store Connect → <i>Analityka → Wskaźniki</i> →
            „Wyświetlenia strony produktu” (Product Page Views), widok dzienny.
          </li>
        </ul>
        <p>
          <b>Pobrania GP / Pobrania AS</b> — ile z tych wejść skończyło się instalacją.
          Google Play: „Instalacje (unikalni użytkownicy)”. App Store: „Pobrania” (Total Downloads).
          Ten sam ekran, wiersz niżej niż wejścia.
        </p>
        <p>
          <b>Instal. ⚙ i Zakupy ⚙</b> liczy baza — nic tu nie wpisujesz.
          Instalacje to urządzenia, które <i>pierwszy raz odpaliły apkę</i> tego dnia
          (nasza telemetria — jest od ręki, bez 1–2 dni opóźnienia konsol; nie liczy
          ponownej instalacji na tym samym telefonie). Zakupy to realne transakcje
          z RevenueCat — bez sandboxa, bez grantów promo i bez naszych własnych kont.
        </p>
        <p className="faint">
          Uwaga na doby: nasze liczby są liczone wg <b>Europe/Warsaw</b>, a konsole
          raportują we własnej strefie (Play — czas pacyficzny, App Store Connect — UTC),
          więc dzienne pobrania z konsoli i instalacje z telemetrii mogą się różnić
          o kilka procent i o dzień przy filmiku, który poszedł wieczorem. To normalne —
          trend jest ważniejszy niż zgodność co do sztuki.
        </p>
      </div>
    </details>
  );
}

// Fragmentu nie można kluczować w mapie — cienki wrapper przekazuje <tr> dalej.
function EditorRowKeyed({ children }) { return children; }

function NumCell({ value, onChange }) {
  return (
    <td className="num">
      <input type="text" inputMode="numeric" className="num-input" value={value}
             placeholder="—" onChange={(e) => onChange(e.target.value)} />
    </td>
  );
}

function DisplayRow({ r, trackingSince, onEdit, busy }) {
  const downloads = sumOrNull(r.downloads_google, r.downloads_appstore);
  const visits = sumOrNull(r.store_visits_google, r.store_visits_appstore);
  const crStore = pct(downloads, visits);
  // Mianownik konwersji zakupu: pobrania z konsol, gdy są wpisane (to prawdziwe
  // instalacje ze sklepu), inaczej nasza telemetria — tytuł mówi, co poszło.
  const buyBase = downloads ?? r.installs_tracked;
  const crBuy = pct(r.purchases, buyBase);
  const tracked = trackingSince && r.day >= trackingSince;
  const dow = DOW[new Date(`${r.day}T12:00:00`).getDay()];
  return (
    <tr className={r.has_entry ? '' : 'auto-only'}>
      <td className="day-cell" title={r.day}>{shortDay(r.day)}<span className="dow">{dow}</span></td>
      <td className="mkt-video" title={r.video || undefined}>{renderVideo(r.video)}</td>
      <td className="num">{fmt(r.video_views)}</td>
      <td className="num">{fmt(r.store_visits_google)}</td>
      <td className="num">{fmt(r.store_visits_appstore)}</td>
      <td className="num">{fmt(r.downloads_google)}</td>
      <td className="num">{fmt(r.downloads_appstore)}</td>
      <td className="num">{fmt(downloads)}</td>
      <td className="num" title={visits ? `${downloads ?? 0} pobrań / ${visits} wejść` : 'brak wejść — wpisz je, żeby policzyć'}>
        {fmtPct(crStore) ?? <span className="muted">—</span>}
      </td>
      <td className="num auto-cell">
        {tracked ? nf.format(r.installs_tracked) : <span className="muted" title="przed startem telemetrii">—</span>}
      </td>
      <td className={`num auto-cell ${r.purchases > 0 ? 'ok-cell' : ''}`}
          title={Number(r.revenue_pln) > 0 ? `${mf.format(r.revenue_pln)} tego dnia` : undefined}>
        {r.purchases > 0 ? nf.format(r.purchases) : <span className="muted">0</span>}
      </td>
      <td className={`num ${crBuy ? 'ok-cell' : ''}`}
          title={buyBase ? `${r.purchases} zakupów / ${buyBase} ${downloads != null ? 'pobrań z konsol' : 'instalacji z telemetrii'}` : undefined}>
        {fmtPct(crBuy) ?? <span className="muted">—</span>}
      </td>
      <td className="mkt-notes" title={r.notes || undefined}>{r.notes || ''}</td>
      <td className="mkt-acts">
        <button className="btn sm ghost" onClick={onEdit} disabled={busy}
                title={r.has_entry ? 'Edytuj' : 'Dodaj wpis do tego dnia'}>
          {r.has_entry ? '✎' : '+'}
        </button>
      </td>
    </tr>
  );
}

function fmt(v) { return v == null ? <span className="muted">—</span> : nf.format(v); }

/** Linki w polu „filmik” stają się klikalne; reszta zostaje tekstem. */
function renderVideo(video) {
  if (!video) return <span className="muted">—</span>;
  const parts = video.split(/(https?:\/\/\S+)/g);
  return parts.map((p, i) =>
    /^https?:\/\//.test(p)
      ? <a key={i} href={p} target="_blank" rel="noreferrer">{p}</a>
      : <span key={i}>{p}</span>
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
