'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { api } from '../../lib/api';

/**
 * Dziennik marketingowy: jeden wiersz na dzień, wszystko wpisywane ręcznie —
 * jaki filmik promujący poszedł, ile zrobił wyświetleń, ile było wejść do
 * sklepu i ile pobrań z Google Play / App Store. Długi spis wierszy + sumy.
 */

const nf = new Intl.NumberFormat('pl-PL');
const DOW = ['nd', 'pn', 'wt', 'śr', 'cz', 'pt', 'sb'];

const todayLocal = () => {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};

// Puste pole = NULL ("nie wpisałem"), a nie 0 — DB rozróżnia to celowo.
const toInt = (s) => {
  const t = String(s ?? '').replace(/[\s ]/g, '');
  if (t === '') return null;
  const n = Number.parseInt(t, 10);
  return Number.isFinite(n) && n >= 0 ? n : null;
};

const emptyForm = (day) => ({
  day, video: '', video_views: '', store_visits: '',
  downloads_google: '', downloads_appstore: '', notes: '',
});

const rowToForm = (r) => ({
  day: r.day,
  video: r.video ?? '',
  video_views: r.video_views ?? '',
  store_visits: r.store_visits ?? '',
  downloads_google: r.downloads_google ?? '',
  downloads_appstore: r.downloads_appstore ?? '',
  notes: r.notes ?? '',
});

export default function MarketingPage() {
  const [rows, setRows] = useState(null);
  const [err, setErr] = useState(null);
  const [editing, setEditing] = useState(null); // day edytowanego wiersza
  const [adding, setAdding] = useState(false);
  const [form, setForm] = useState(emptyForm(todayLocal()));
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setErr(null);
    try {
      setRows(await api.listMarketing());
    } catch (e) {
      setErr(e.friendly || e.message);
      setRows([]);
    }
  }, []);

  useEffect(() => { load(); }, [load]);

  const totals = useMemo(() => {
    const sum = (k) => (rows ?? []).reduce((a, r) => a + (r[k] ?? 0), 0);
    return {
      views: sum('video_views'),
      visits: sum('store_visits'),
      google: sum('downloads_google'),
      appstore: sum('downloads_appstore'),
    };
  }, [rows]);

  function startAdd() {
    // Domyślnie dzisiaj; jeśli dzisiejszy wpis już jest — edytuj go zamiast dublować.
    const today = todayLocal();
    const existing = rows?.find((r) => r.day === today);
    if (existing) { startEdit(existing); return; }
    setForm(emptyForm(today));
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
    // Nowy wpis pod datą, która już istnieje, nadpisałby tamten dzień po cichu.
    if (adding && rows?.some((r) => r.day === form.day)) {
      setErr(`Dzień ${form.day} ma już wpis — kliknij ✎ przy tamtym wierszu, żeby go edytować.`);
      return;
    }
    setBusy(true); setErr(null);
    try {
      await api.upsertMarketingDay({
        day: form.day,
        video: form.video || null,
        videoViews: toInt(form.video_views),
        storeVisits: toInt(form.store_visits),
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
      <NumCell value={form.store_visits} onChange={(v) => setForm({ ...form, store_visits: v })} />
      <NumCell value={form.downloads_google} onChange={(v) => setForm({ ...form, downloads_google: v })} />
      <NumCell value={form.downloads_appstore} onChange={(v) => setForm({ ...form, downloads_appstore: v })} />
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
        Dziennik promocji — wpisujesz ręcznie: jaki filmik poszedł, ile zrobił wyświetleń,
        ile było wejść do sklepu i pobrań (Google Play / App Store). Puste pole = brak danych, nie zero.
      </p>

      <div className="stat-grid">
        <Tile label="Dni z wpisem" value={rows ? nf.format(rows.length) : '…'} />
        <Tile label="Wyświetlenia filmików" value={nf.format(totals.views)} note="suma ze wszystkich wpisów" />
        <Tile label="Wejścia do sklepu" value={nf.format(totals.visits)} />
        <Tile label="Pobrania Google Play" value={nf.format(totals.google)} />
        <Tile label="Pobrania App Store" value={nf.format(totals.appstore)} />
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
              <thead>
                <tr>
                  <th>Data</th>
                  <th>Filmik promujący</th>
                  <th className="num">Wyśw. filmiku</th>
                  <th className="num">Wejścia sklep</th>
                  <th className="num">Google Play</th>
                  <th className="num">App Store</th>
                  <th className="num">Σ pobrań</th>
                  <th>Notatki</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {adding && editorRow}
                {rows.length === 0 && !adding && (
                  <tr><td colSpan={9} className="muted">Pusto — kliknij „+ Dodaj dzień”, żeby zacząć dziennik.</td></tr>
                )}
                {rows.map((r) => (editing === r.day ? (
                  <EditorRowKeyed key={r.day}>{editorRow}</EditorRowKeyed>
                ) : (
                  <DisplayRow key={r.day} r={r} onEdit={() => startEdit(r)} busy={busy} />
                )))}
              </tbody>
              {rows.length > 0 && (
                <tfoot>
                  <tr>
                    <td colSpan={2}>Suma</td>
                    <td className="num">{nf.format(totals.views)}</td>
                    <td className="num">{nf.format(totals.visits)}</td>
                    <td className="num">{nf.format(totals.google)}</td>
                    <td className="num">{nf.format(totals.appstore)}</td>
                    <td className="num">{nf.format(totals.google + totals.appstore)}</td>
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

function DisplayRow({ r, onEdit, busy }) {
  const total = (r.downloads_google ?? 0) + (r.downloads_appstore ?? 0);
  const hasDownloads = r.downloads_google != null || r.downloads_appstore != null;
  const dow = DOW[new Date(`${r.day}T12:00:00`).getDay()];
  return (
    <tr>
      <td className="day-cell">{r.day}<span className="dow">{dow}</span></td>
      <td className="mkt-video">{renderVideo(r.video)}</td>
      <td className="num">{fmt(r.video_views)}</td>
      <td className="num">{fmt(r.store_visits)}</td>
      <td className="num">{fmt(r.downloads_google)}</td>
      <td className="num">{fmt(r.downloads_appstore)}</td>
      <td className={`num ${total > 0 ? 'ok-cell' : ''}`}>{hasDownloads ? nf.format(total) : '—'}</td>
      <td className="mkt-notes">{r.notes || ''}</td>
      <td className="mkt-acts">
        <button className="btn sm ghost" onClick={onEdit} disabled={busy} title="Edytuj">✎</button>
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
