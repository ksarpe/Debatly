'use client';

import { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { api } from '../lib/api';

const PAGE = 50;

export default function QuestionList() {
  const router = useRouter();
  const [rows, setRows] = useState([]);
  const [search, setSearch] = useState('');
  const [onlyActive, setOnlyActive] = useState(true);
  const [onlyEnReview, setOnlyEnReview] = useState(false);
  const [page, setPage] = useState(0);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState(null);

  const load = useCallback(async (q, active, enReview, p) => {
    setLoading(true); setErr(null);
    try {
      const data = await api.listQuestions({
        search: q.trim() === '' ? null : q.trim(),
        onlyActive: active,
        onlyEnReview: enReview,
        limit: PAGE,
        offset: p * PAGE,
      });
      setRows(data ?? []);
      setTotal(data?.[0]?.total_count ?? 0);
    } catch (e) {
      setErr(e.friendly || e.message);
    } finally {
      setLoading(false);
    }
  }, []);

  // debounce search
  useEffect(() => {
    const t = setTimeout(() => { setPage(0); load(search, onlyActive, onlyEnReview, 0); }, 250);
    return () => clearTimeout(t);
  }, [search, onlyActive, onlyEnReview, load]);

  useEffect(() => { load(search, onlyActive, onlyEnReview, page); /* eslint-disable-next-line */ }, [page]);

  const pages = Math.ceil(total / PAGE) || 1;

  return (
    <>
      <h1 className="page-title">Pytania</h1>
      <p className="page-sub">
        {total} {onlyActive ? 'aktywnych' : 'wszystkich'} · kliknij wiersz, żeby edytować
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
                <th style={{ width: '46%' }}>Pytanie (PL)</th>
                <th>Kategoria</th>
                <th style={{ width: 70 }}>Smaczki</th>
                <th style={{ width: 140 }}>Status</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id} onClick={() => router.push(`/q/${r.id}`)}>
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
              ))}
            </tbody>
          </table>
        )}
      </div>

      {pages > 1 && (
        <div className="toolbar">
          <button className="btn sm" disabled={page === 0} onClick={() => setPage((p) => p - 1)}>
            ← Poprzednia
          </button>
          <span className="faint">Strona {page + 1} z {pages}</span>
          <button className="btn sm" disabled={page + 1 >= pages} onClick={() => setPage((p) => p + 1)}>
            Następna →
          </button>
        </div>
      )}
    </>
  );
}
