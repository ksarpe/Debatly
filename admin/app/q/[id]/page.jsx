'use client';

import { useEffect, useMemo, useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { api, CATEGORIES } from '../../../lib/api';
import SmaczkiEditor from '../../../components/SmaczkiEditor';
import Diff from '../../../components/Diff';

const empty = {
  category: 'Reflection', is_premium: false, is_active: true,
  pl: '', en: '', smaczki: [{ pl: '', en: '' }],
};

export default function QuestionEditor() {
  const { id } = useParams();
  const router = useRouter();
  const isNew = id === 'new';

  const [live, setLive] = useState(null);       // snapshot currently on prod
  const [draft, setDraft] = useState(null);     // open draft row, if any
  const [form, setForm] = useState(empty);
  const [role, setRole] = useState(null);
  const [history, setHistory] = useState([]);
  const [loading, setLoading] = useState(!isNew);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState(null);
  const [msg, setMsg] = useState(null);

  useEffect(() => { api.me().then((m) => setRole(m?.role)).catch(() => {}); }, []);

  useEffect(() => {
    if (isNew) { setForm(empty); setLoading(false); return; }
    let cancelled = false;
    (async () => {
      setLoading(true); setErr(null);
      try {
        const res = await api.getQuestion(id);
        if (cancelled) return;
        const q = res?.question ?? null;
        const d = res?.open_draft ?? null;
        setLive(q);
        setDraft(d);
        // Continue an existing editable draft, otherwise start from the live text.
        const src = d && d.payload && ['draft', 'rejected'].includes(d.status) ? d.payload : q;
        setForm({
          category: src?.category ?? q?.category ?? 'Reflection',
          is_premium: src?.is_premium ?? q?.is_premium ?? false,
          is_active: src?.is_active ?? q?.is_active ?? true,
          pl: src?.pl ?? '',
          en: src?.en ?? '',
          smaczki: (src?.smaczki ?? []).map((s) => ({ pl: s.pl ?? '', en: s.en ?? '' })),
        });
        api.history(id).then((h) => !cancelled && setHistory(h ?? [])).catch(() => {});
      } catch (e) {
        if (!cancelled) setErr(e.friendly || e.message);
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => { cancelled = true; };
  }, [id, isNew]);

  const payload = useMemo(() => ({
    category: form.category,
    is_premium: form.is_premium,
    is_active: form.is_active,
    pl: form.pl.trim(),
    en: form.en.trim(),
    smaczki: form.smaczki
      .filter((s) => (s.pl ?? '').trim() !== '')
      .map((s) => ({ pl: s.pl.trim(), en: (s.en ?? '').trim() })),
  }), [form]);

  const pending = draft?.status === 'pending';
  const canApprove = role === 'approver';

  async function run(fn, okMsg) {
    setBusy(true); setErr(null); setMsg(null);
    try {
      const r = await fn();
      setMsg(okMsg);
      return r;
    } catch (e) {
      setErr(e.friendly || e.message);
      return null;
    } finally {
      setBusy(false);
    }
  }

  const saveDraft = () => run(async () => {
    const draftId = await api.saveDraft({
      action: isNew ? 'create' : 'update',
      payload,
      questionId: isNew ? null : id,
      draftId: draft && ['draft', 'rejected'].includes(draft.status) ? draft.id : null,
      title: payload.pl.slice(0, 80),
    });
    const fresh = isNew ? null : await api.getQuestion(id);
    if (fresh) setDraft(fresh.open_draft);
    else setDraft({ id: draftId, status: 'draft' });
    return draftId;
  }, 'Wersja robocza zapisana.');

  const submit = () => run(async () => {
    let dId = draft?.id;
    if (!dId || !['draft', 'rejected'].includes(draft?.status)) {
      dId = await api.saveDraft({
        action: isNew ? 'create' : 'update',
        payload,
        questionId: isNew ? null : id,
        draftId: null,
        title: payload.pl.slice(0, 80),
      });
    } else {
      await api.saveDraft({
        action: isNew ? 'create' : 'update',
        payload, questionId: isNew ? null : id, draftId: dId,
        title: payload.pl.slice(0, 80),
      });
    }
    await api.submitDraft(dId);
    setDraft({ ...(draft ?? {}), id: dId, status: 'pending' });
    return dId;
  }, 'Zgłoszone do zatwierdzenia.');

  const approve = () => run(async () => {
    const res = await api.approveDraft(draft.id);
    if (isNew && res?.question_id) router.replace(`/q/${res.question_id}`);
    else {
      const fresh = await api.getQuestion(id);
      setLive(fresh.question); setDraft(fresh.open_draft);
      api.history(id).then((h) => setHistory(h ?? [])).catch(() => {});
    }
    return res;
  }, 'Zatwierdzone i opublikowane.');

  const requestDelete = () => run(async () => {
    const dId = await api.saveDraft({
      action: 'delete', payload: null, questionId: id,
      title: 'Usunięcie: ' + (live?.pl ?? '').slice(0, 60),
    });
    await api.submitDraft(dId);
    setDraft({ id: dId, status: 'pending', action: 'delete' });
    return dId;
  }, 'Usunięcie zgłoszone do zatwierdzenia.');

  if (loading) return <div className="spin">Ładowanie…</div>;

  const isDeleteDraft = draft?.action === 'delete';

  return (
    <>
      <h1 className="page-title">{isNew ? 'Nowe pytanie' : 'Edycja pytania'}</h1>
      <p className="page-sub">
        {isNew ? 'Zostanie dodane po zatwierdzeniu.' : <code className="faint">{id}</code>}
      </p>

      {err && <div className="alert err">{err}</div>}
      {msg && <div className="alert ok">{msg}</div>}

      {pending && (
        <div className="alert info">
          <b>Czeka na zatwierdzenie.</b> Wersja robocza jest zablokowana do edycji.
          {canApprove && ' Możesz ją zatwierdzić poniżej.'}
        </div>
      )}

      {!isDeleteDraft && (
        <>
          <div className="card">
            <h3>Pytanie</h3>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 6, marginBottom: 12 }}>
              <div className="fx">
                <span className="flag" title="polski">🇵🇱</span>
                <textarea rows={2} value={form.pl} disabled={pending}
                          placeholder="treść pytania"
                          onChange={(e) => setForm({ ...form, pl: e.target.value })} />
              </div>
              <div className="fx">
                <span className="flag" title="angielski">🇬🇧</span>
                <textarea rows={2} value={form.en} disabled={pending}
                          placeholder="tłumaczenie"
                          onChange={(e) => setForm({ ...form, en: e.target.value })} />
              </div>
            </div>

            <div className="toolbar" style={{ marginBottom: 0 }}>
              <select value={form.category} disabled={pending} style={{ width: 'auto' }}
                      onChange={(e) => setForm({ ...form, category: e.target.value })}>
                {CATEGORIES.map((c) => <option key={c} value={c}>{c}</option>)}
              </select>
              <label className="faint" style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
                <input type="checkbox" checked={form.is_active} disabled={pending} style={{ width: 'auto' }}
                       onChange={(e) => setForm({ ...form, is_active: e.target.checked })} />
                aktywne
              </label>
              <label className="faint" style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
                <input type="checkbox" checked={form.is_premium} disabled={pending} style={{ width: 'auto' }}
                       onChange={(e) => setForm({ ...form, is_premium: e.target.checked })} />
                premium
              </label>
            </div>
          </div>

          <SmaczkiEditor items={form.smaczki} disabled={pending}
                         onChange={(s) => setForm({ ...form, smaczki: s })} />
        </>
      )}

      <details className="sec" open={isDeleteDraft}>
        <summary>Podgląd zmian <span className="count">— przed / po</span></summary>
        <div className="body">
          <Diff before={live} after={isDeleteDraft ? null : payload} />
        </div>
      </details>

      <div className="sticky-actions">
        {!pending && !isDeleteDraft && (
          <>
            <button className="btn" onClick={saveDraft} disabled={busy}>Zapisz wersję roboczą</button>
            <button className="btn primary" onClick={submit} disabled={busy || !payload.pl}>
              Zgłoś do zatwierdzenia
            </button>
          </>
        )}
        {pending && canApprove && (
          <button className="btn ok" onClick={approve} disabled={busy}>
            Zatwierdź i opublikuj
          </button>
        )}
        <div className="spacer" />
        {!isNew && !pending && (
          <button className="btn danger" disabled={busy}
                  onClick={() => {
                    if (confirm('Zgłosić to pytanie do usunięcia? Po zatwierdzeniu zniknie razem ze smaczkami i głosami.')) requestDelete();
                  }}>
            Usuń pytanie…
          </button>
        )}
        <button className="btn ghost" onClick={() => router.push('/')}>Wróć</button>
      </div>

      {!isNew && (
        <details className="sec">
          <summary>Historia zmian <span className="count">({history.length})</span></summary>
          <div className="body">
            {history.length === 0 && <div className="faint">Brak zapisanych zmian.</div>}
            {history.map((h) => (
              <div className="hist" key={h.id}>
                <span className={`badge ${h.action === 'delete' ? 'rejected' : 'approved'}`}>{h.action}</span>{' '}
                <span className="faint">{new Date(h.at).toLocaleString('pl-PL')}</span>
                {h.before?.pl && h.after?.pl && h.before.pl !== h.after.pl && (
                  <div className="faint" style={{ marginTop: 4 }}>
                    „{h.before.pl}” → „{h.after.pl}”
                  </div>
                )}
              </div>
            ))}
          </div>
        </details>
      )}
    </>
  );
}
