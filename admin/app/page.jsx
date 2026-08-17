'use client';

import { Fragment, useCallback, useEffect, useState } from 'react';
import { api } from '../lib/api';
import QuestionEditor from '../components/QuestionEditor';

const PAGE = 20;

/** Windowed page numbers: 1 … around current … last (0-based in, 0-based out). */
function pageWindow(current, pages) {
  const set = new Set([0, pages - 1]);
  for (let p = current - 2; p <= current + 2; p++) {
    if (p >= 0 && p < pages) set.add(p);
  }
  const sorted = [...set].sort((a, b) => a - b);
  const out = [];
  let prev = null;
  for (const p of sorted) {
    if (prev !== null && p - prev > 1) out.push('gap');
    out.push(p);
    prev = p;
  }
  return out;
}

export default function QuestionList() {
  const [rows, setRows] = useState([]);
  const [search, setSearch] = useState('');
  const [onlyActive, setOnlyActive] = useState(true);
  const [onlyEnReview, setOnlyEnReview] = useState(false);
  const [onlyFavorites, setOnlyFavorites] = useState(false);
  const [onlyUnverified, setOnlyUnverified] = useState(false);
  const [page, setPage] = useState(0);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState(null);
  const [expandedId, setExpandedId] = useState(null);
  const [editorDirty, setEditorDirty] = useState(false);

  const load = useCallback(async (q, active, enReview, favs, unverified, p, silent = false) => {
    if (!silent) setLoading(true);
    setErr(null);
    try {
      const data = await api.listQuestions({
        search: q.trim() === '' ? null : q.trim(),
        onlyActive: active,
        onlyEnReview: enReview,
        onlyFavorites: favs,
        onlyUnverified: unverified,
        limit: PAGE,
        offset: p * PAGE,
      });
      setRows(data ?? []);
      setTotal(data?.[0]?.total_count ?? 0);
    } catch (e) {
      setErr(e.friendly || e.message);
    } finally {
      if (!silent) setLoading(false);
    }
  }, []);

  // debounce search
  useEffect(() => {
    const t = setTimeout(() => { setPage(0); load(search, onlyActive, onlyEnReview, onlyFavorites, onlyUnverified, 0); }, 250);
    return () => clearTimeout(t);
  }, [search, onlyActive, onlyEnReview, onlyFavorites, onlyUnverified, load]);

  useEffect(() => { load(search, onlyActive, onlyEnReview, onlyFavorites, onlyUnverified, page); /* eslint-disable-next-line */ }, [page]);

  // Silent refresh after an inline save/publish — keeps the open editor mounted.
  const reload = useCallback(() => {
    load(search, onlyActive, onlyEnReview, onlyFavorites, onlyUnverified, page, true);
  }, [load, search, onlyActive, onlyEnReview, onlyFavorites, onlyUnverified, page]);

  const pages = Math.ceil(total / PAGE) || 1;

  const collapse = useCallback(() => { setExpandedId(null); setEditorDirty(false); }, []);

  function toggleRow(id) {
    // Zaznaczanie tekstu (kopiowanie treści) nie może otwierać edytora.
    if (window.getSelection?.()?.toString()) return;
    if (expandedId && expandedId !== id && editorDirty
        && !confirm('Masz niezapisane zmiany w otwartym pytaniu. Porzucić je?')) return;
    if (expandedId === id) {
      if (editorDirty && !confirm('Masz niezapisane zmiany. Zwinąć mimo to?')) return;
      collapse();
    } else {
      setExpandedId(id);
      setEditorDirty(false);
    }
  }

  async function toggleFav(r) {
    setRows((rs) => rs.map((x) => (x.id === r.id ? { ...x, is_favorite: !x.is_favorite } : x)));
    try {
      await api.toggleFavorite(r.id);
      if (onlyFavorites) reload();
    } catch (e) {
      setRows((rs) => rs.map((x) => (x.id === r.id ? { ...x, is_favorite: r.is_favorite } : x)));
      setErr(e.friendly || e.message);
    }
  }

  async function toggleVerified(r) {
    setRows((rs) => rs.map((x) => (x.id === r.id ? { ...x, is_verified: !x.is_verified } : x)));
    try {
      await api.toggleVerified(r.id);
      if (onlyUnverified) reload();
    } catch (e) {
      setRows((rs) => rs.map((x) => (x.id === r.id ? { ...x, is_verified: r.is_verified } : x)));
      setErr(e.friendly || e.message);
    }
  }

  function goToPage(p) {
    if (editorDirty && !confirm('Masz niezapisane zmiany w otwartym pytaniu. Porzucić je?')) return;
    collapse();
    setPage(p);
  }

  return (
    <>
      <h1 className="page-title">Pytania</h1>
      <p className="page-sub">
        {total} {onlyActive ? 'aktywnych' : 'wszystkich'} · kliknij wiersz, żeby rozwinąć edycję
      </p>

      <div className="toolbar">
        <input
          className="search"
          type="text"
          placeholder="Szukaj w treści PL lub EN…"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        <label className="faint" style={{ display: 'flex', gap: 7, alignItems: 'center' }}>
          <input type="checkbox" checked={onlyActive}
                 onChange={(e) => setOnlyActive(e.target.checked)} style={{ width: 'auto' }} />
          tylko aktywne
        </label>
        <label className="faint" style={{ display: 'flex', gap: 7, alignItems: 'center' }}>
          <input type="checkbox" checked={onlyEnReview}
                 onChange={(e) => setOnlyEnReview(e.target.checked)} style={{ width: 'auto' }} />
          🇬🇧 EN do weryfikacji
        </label>
        <label className="faint" style={{ display: 'flex', gap: 7, alignItems: 'center' }}>
          <input type="checkbox" checked={onlyFavorites}
                 onChange={(e) => setOnlyFavorites(e.target.checked)} style={{ width: 'auto' }} />
          ★ tylko ulubione
        </label>
        <label className="faint" style={{ display: 'flex', gap: 7, alignItems: 'center' }}>
          <input type="checkbox" checked={onlyUnverified}
                 onChange={(e) => setOnlyUnverified(e.target.checked)} style={{ width: 'auto' }} />
          ✓ ukryj zweryfikowane
        </label>
      </div>

      {err && <div className="alert err">{err}</div>}

      <div className="card" style={{ padding: 0, overflow: 'hidden' }}>
        {loading ? (
          <div className="spin">Ładowanie…</div>
        ) : rows.length === 0 ? (
          <div className="spin">Brak wyników</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th style={{ width: 36 }} title="Ulubione">★</th>
                <th style={{ width: 36 }} title="Zweryfikowane">✓</th>
                <th style={{ width: '46%' }}>Pytanie (PL)</th>
                <th>Kategoria</th>
                <th style={{ width: 70 }}>Smaczki</th>
                <th style={{ width: 140 }}>Status</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <Fragment key={r.id}>
                  <tr className={expandedId === r.id ? 'open' : ''} onClick={() => toggleRow(r.id)}>
                    <td className="star-cell" onClick={(e) => e.stopPropagation()}>
                      <button
                        className={`star-btn ${r.is_favorite ? 'on' : ''}`}
                        title={r.is_favorite ? 'Usuń z ulubionych' : 'Dodaj do ulubionych'}
                        onClick={() => toggleFav(r)}
                      >
                        {r.is_favorite ? '★' : '☆'}
                      </button>
                    </td>
                    <td className="check-cell" onClick={(e) => e.stopPropagation()}>
                      <button
                        className={`check-btn ${r.is_verified ? 'on' : ''}`}
                        title={r.is_verified ? 'Zweryfikowane (pytanie + smaczki) — kliknij, aby cofnąć' : 'Oznacz jako zweryfikowane (pytanie + smaczki)'}
                        onClick={() => toggleVerified(r)}
                      >
                        {r.is_verified ? '✔' : '○'}
                      </button>
                    </td>
                    <td className="q">
                      {r.pl}
                      <div className="en">{r.en}</div>
                    </td>
                    <td className="muted">{r.category}</td>
                    <td className="muted">{r.smaczki_count}</td>
                    <td>
                      {r.open_draft_id && <span className="badge draft">wersja robocza</span>}
                      {r.en_review_needed && <span className="badge enreview">EN do weryfikacji</span>}
                      {!r.is_active && <span className="badge">nieaktywne</span>}
                      {r.is_premium && <span className="badge premium">premium</span>}
                    </td>
                  </tr>
                  {expandedId === r.id && (
                    <tr className="editor-row">
                      <td colSpan={6}>
                        <QuestionEditor
                          inline
                          questionId={r.id}
                          onBack={collapse}
                          onAfterDelete={() => { collapse(); reload(); }}
                          onChanged={reload}
                          onDirtyChange={setEditorDirty}
                        />
                      </td>
                    </tr>
                  )}
                </Fragment>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {pages > 1 && (
        <div className="toolbar pager">
          <button className="btn sm" disabled={page === 0} onClick={() => goToPage(page - 1)}>
            ←
          </button>
          {pageWindow(page, pages).map((p, i) =>
            p === 'gap' ? (
              <span key={`gap-${i}`} className="faint">…</span>
            ) : (
              <button key={p} className={`btn sm ${p === page ? 'cur' : ''}`}
                      disabled={p === page} onClick={() => goToPage(p)}>
                {p + 1}
              </button>
            ),
          )}
          <button className="btn sm" disabled={page + 1 >= pages} onClick={() => goToPage(page + 1)}>
            →
          </button>
          <span className="faint">Strona {page + 1} z {pages}</span>
        </div>
      )}
    </>
  );
}
