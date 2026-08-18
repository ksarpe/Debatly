'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { api } from '../../lib/api';

/**
 * Propozycje pytań i smaczków od użytkowników — skrzynka wejściowa z aplikacji
 * ("Zaproponuj pytanie" w ustawieniach + zaczepka po drugim głosie; smaczki
 * z „Zaproponuj własny" w panelu Argumentów, z podpiętym pytaniem).
 * Przyjęcie ("bierzemy") niczego nie publikuje: przyjęty pomysł przepisuje się
 * na porządne pytanie PL/EN + smaczki przez „+ Nowe pytanie" / edycję pytania.
 */

const STATUS = {
  new:      { label: 'Nowa',      cls: 'pending'  },
  accepted: { label: 'Przyjęta',  cls: 'approved' },
  rejected: { label: 'Odrzucona', cls: 'rejected' },
};

const FILTERS = [
  { key: null,       label: 'Wszystkie' },
  { key: 'new',      label: 'Nowe' },
  { key: 'accepted', label: 'Przyjęte' },
  { key: 'rejected', label: 'Odrzucone' },
];

const fmtDate = (ts) =>
  new Date(ts).toLocaleString('pl-PL', {
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit',
  });

export default function SuggestionsPage() {
  const [rows, setRows] = useState(null); // zawsze pełna lista; filtr jest kliencki
  const [filter, setFilter] = useState('new');
  const [err, setErr] = useState(null);
  const [busyId, setBusyId] = useState(null);

  const load = useCallback(async () => {
    setErr(null);
    try {
      setRows(await api.listSuggestions());
    } catch (e) {
      setErr(e.friendly || e.message);
      setRows([]);
    }
  }, []);

  useEffect(() => { load(); }, [load]);

  const counts = useMemo(() => {
    const c = { total: rows?.length ?? 0, new: 0, accepted: 0, rejected: 0 };
    for (const r of rows ?? []) c[r.status] = (c[r.status] ?? 0) + 1;
    return c;
  }, [rows]);

  const visible = useMemo(
    () => (rows ?? []).filter((r) => filter === null || r.status === filter),
    [rows, filter],
  );

  async function setStatus(r, status) {
    // Odrzucenie może dostać powód — trafia do admin_note (pusty = bez notatki).
    let note = null;
    if (status === 'rejected') {
      note = window.prompt('Powód odrzucenia (opcjonalnie):', r.admin_note ?? '');
      if (note === null) return; // anulowano dialog = anulowano odrzucenie
    }
    setBusyId(r.id); setErr(null);
    try {
      const updated = await api.setSuggestionStatus(r.id, status, note);
      // Merge zamiast podmiany: RPC statusu zwraca goły wiersz tabeli, bez
      // doklejanego przez listę question_text — nadpisanie by go zgubiło.
      setRows((prev) => prev.map((x) => (x.id === r.id ? { ...x, ...updated } : x)));
    } catch (e) {
      setErr(e.friendly || e.message);
    } finally {
      setBusyId(null);
    }
  }

  async function remove(r) {
    if (!window.confirm('Usunąć tę propozycję na stałe? Tego nie da się cofnąć.')) return;
    setBusyId(r.id); setErr(null);
    try {
      await api.deleteSuggestion(r.id);
      setRows((prev) => prev.filter((x) => x.id !== r.id));
    } catch (e) {
      setErr(e.friendly || e.message);
    } finally {
      setBusyId(null);
    }
  }

  async function copyText(r) {
    try {
      await navigator.clipboard.writeText(r.suggestion);
    } catch {
      window.prompt('Skopiuj ręcznie:', r.suggestion);
    }
  }

  return (
    <>
      <h1 className="page-title">Propozycje pytań</h1>
      <p className="page-sub">
        Pomysły przysłane z aplikacji. „Przyjęta&rdquo; = bierzemy do katalogu — samo w sobie
        niczego nie publikuje; przepisz pomysł na pytanie przez „+ Nowe pytanie&rdquo;.
      </p>

      <div className="stat-grid">
        <Tile label="Wszystkie" value={rows ? counts.total : '…'} />
        <Tile label="Nowe" value={counts.new} />
        <Tile label="Przyjęte" value={counts.accepted} />
        <Tile label="Odrzucone" value={counts.rejected} />
      </div>

      <div className="toolbar">
        {FILTERS.map((f) => (
          <button key={f.label}
                  className={`btn sm ${filter === f.key ? 'primary' : 'ghost'}`}
                  onClick={() => setFilter(f.key)}>
            {f.label}
          </button>
        ))}
        <span className="faint">
          użytkownicy mają limit 10 propozycji na dobę; anonimowe konta też mogą wysyłać
        </span>
      </div>

      {err && <div className="alert err">{err}</div>}
      {rows === null && <div className="spin">Ładowanie…</div>}

      {rows !== null && (
        <div className="card">
          <div className="tbl-scroll">
            <table className="stats-table">
              <thead>
                <tr>
                  <th>Data</th>
                  <th>Typ</th>
                  <th>Propozycja</th>
                  <th>Język</th>
                  <th>Status</th>
                  <th>Notatka</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {visible.length === 0 && (
                  <tr>
                    <td colSpan={7} className="muted">
                      {filter === 'new'
                        ? 'Brak nowych propozycji — skrzynka czysta.'
                        : 'Nic tu nie ma.'}
                    </td>
                  </tr>
                )}
                {visible.map((r) => {
                  const st = STATUS[r.status] ?? { label: r.status, cls: '' };
                  const busy = busyId === r.id;
                  return (
                    <tr key={r.id}>
                      <td className="day-cell" title={r.user_id ? `user: ${r.user_id}` : 'konto usunięte'}>
                        {fmtDate(r.created_at)}
                      </td>
                      <td>
                        <span className={`badge ${r.kind === 'smaczek' ? 'approved' : ''}`}>
                          {r.kind === 'smaczek' ? 'Smaczek' : 'Pytanie'}
                        </span>
                      </td>
                      <td className="q-cell" style={{ whiteSpace: 'pre-wrap' }}>
                        {r.suggestion}
                        {r.kind === 'smaczek' && (
                          <div className="faint" style={{ marginTop: 4 }}>
                            do pytania: {r.question_text ?? (r.question_id ?? '—')}
                          </div>
                        )}
                      </td>
                      <td className="muted">{r.locale ?? '—'}</td>
                      <td><span className={`badge ${st.cls}`}>{st.label}</span></td>
                      <td className="muted" style={{ maxWidth: 220 }}>{r.admin_note ?? ''}</td>
                      <td className="mkt-acts" style={{ whiteSpace: 'nowrap' }}>
                        {r.status !== 'accepted' && (
                          <button className="btn sm ok" disabled={busy}
                                  title="Bierzemy do katalogu"
                                  onClick={() => setStatus(r, 'accepted')}>✓</button>
                        )}
                        {r.status !== 'rejected' && (
                          <button className="btn sm danger" disabled={busy}
                                  title="Odrzuć (z opcjonalnym powodem)"
                                  onClick={() => setStatus(r, 'rejected')}>✗</button>
                        )}
                        {r.status !== 'new' && (
                          <button className="btn sm ghost" disabled={busy}
                                  title="Przywróć do nowych"
                                  onClick={() => setStatus(r, 'new')}>↺</button>
                        )}
                        <button className="btn sm ghost" disabled={busy}
                                title="Kopiuj tekst propozycji"
                                onClick={() => copyText(r)}>⧉</button>
                        <button className="btn sm ghost" disabled={busy}
                                title="Usuń na stałe (spam)"
                                onClick={() => remove(r)}>🗑</button>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </>
  );
}

function Tile({ label, value }) {
  return (
    <div className="card stat-tile">
      <div className="stat-label">{label}</div>
      <div className="stat-value">{value}</div>
    </div>
  );
}
