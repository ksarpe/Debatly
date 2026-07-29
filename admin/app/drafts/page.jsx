'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { api } from '../../lib/api';
import Diff from '../../components/Diff';

export default function Drafts() {
  const router = useRouter();
  const [drafts, setDrafts] = useState([]);
  const [live, setLive] = useState({});      // question_id -> snapshot
  const [role, setRole] = useState(null);
  const [status, setStatus] = useState('pending');
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(null);
  const [err, setErr] = useState(null);
  const [msg, setMsg] = useState(null);

  useEffect(() => { api.me().then((m) => setRole(m?.role)).catch(() => {}); }, []);

  async function load(s) {
    setLoading(true); setErr(null);
    try {
      const rows = await api.listDrafts(s === 'all' ? null : s);
      setDrafts(rows ?? []);
      const map = {};
      await Promise.all((rows ?? [])
        .filter((d) => d.question_id)
        .map(async (d) => {
          try {
            const res = await api.getQuestion(d.question_id);
            map[d.question_id] = res?.question ?? null;
          } catch { /* deleted meanwhile */ }
        }));
      setLive(map);
    } catch (e) {
      setErr(e.friendly || e.message);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => { load(status); /* eslint-disable-next-line */ }, [status]);

  async function act(fn, d, okMsg) {
    setBusy(d.id); setErr(null); setMsg(null);
    try {
      await fn();
      setMsg(okMsg);
      await load(status);
    } catch (e) {
      setErr(e.friendly || e.message);
    } finally {
      setBusy(null);
    }
  }

  return (
    <>
      <h1 className="page-title">Do zatwierdzenia</h1>
      <p className="page-sub">
        Zmiany wchodzą na produkcję dopiero po zatwierdzeniu. Jeśli ktoś w międzyczasie
        zmienił to samo pytanie, zatwierdzenie zostanie odrzucone zamiast nadpisać jego pracę.
      </p>

      <div className="toolbar">
        {['pending', 'draft', 'rejected', 'approved', 'all'].map((s) => (
          <button key={s} className={`btn sm ${status === s ? 'primary' : ''}`}
                  onClick={() => setStatus(s)}>
            {{ pending: 'Oczekujące', draft: 'Robocze', rejected: 'Odrzucone', approved: 'Zatwierdzone', all: 'Wszystkie' }[s]}
          </button>
        ))}
      </div>

      {err && <div className="alert err">{err}</div>}
      {msg && <div className="alert ok">{msg}</div>}

      {loading ? (
        <div className="spin">Ładowanie…</div>
      ) : drafts.length === 0 ? (
        <div className="card"><div className="faint">Nic tutaj nie ma.</div></div>
      ) : (
        drafts.map((d) => (
          <div className="card" key={d.id}>
            <div className="toolbar" style={{ marginBottom: 12 }}>
              <span className={`badge ${d.status}`}>{d.status}</span>
              <span className="badge">{d.action}</span>
              {d.payload?.en_review && <span className="badge enreview">EN do weryfikacji</span>}
              <b>{d.title || '(bez tytułu)'}</b>
              <div style={{ flex: 1 }} />
              <span className="faint">{new Date(d.updated_at).toLocaleString('pl-PL')}</span>
            </div>

            <Diff
              before={d.question_id ? live[d.question_id] ?? null : null}
              after={d.action === 'delete' ? null : d.payload}
            />

            {d.review_note && (
              <div className="alert info" style={{ marginTop: 12 }}>
                Uwaga recenzenta: {d.review_note}
              </div>
            )}

            <div className="toolbar" style={{ marginTop: 14, marginBottom: 0 }}>
              {d.status === 'pending' && role === 'approver' && (
                <>
                  <button className="btn ok" disabled={busy === d.id}
                          onClick={() => act(() => api.approveDraft(d.id), d, 'Zatwierdzone i opublikowane.')}>
                    Zatwierdź
                  </button>
                  <button className="btn danger" disabled={busy === d.id}
                          onClick={() => {
                            const note = prompt('Powód odrzucenia (opcjonalnie):');
                            if (note !== null) act(() => api.rejectDraft(d.id, note || null), d, 'Odrzucone.');
                          }}>
                    Odrzuć
                  </button>
                </>
              )}
              {d.status === 'pending' && role !== 'approver' && (
                <span className="faint">Tylko rola „approver” może zatwierdzać.</span>
              )}
              {d.question_id && (
                <button className="btn ghost" onClick={() => router.push(`/q/${d.question_id}`)}>
                  Otwórz pytanie
                </button>
              )}
            </div>
          </div>
        ))
      )}
    </>
  );
}
