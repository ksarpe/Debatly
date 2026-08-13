'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { api, CATEGORIES, LIMITS } from '../../../lib/api';
import SmaczkiEditor from '../../../components/SmaczkiEditor';
import Counter from '../../../components/Counter';
import Diff from '../../../components/Diff';

const empty = {
  category: 'Reflection', is_premium: false, is_active: true,
  pl: '', en: '', smaczki: [{ pl: '', en: '' }],
  en_review: null, // null = automatycznie; true/false = ręczna decyzja
};

const HIST_LABEL = {
  create: 'create', update: 'update', delete: 'delete',
  en_review: 'EN do weryfikacji', en_verified: 'EN zweryfikowany',
};
const HIST_BADGE = {
  delete: 'rejected', en_review: 'enreview', en_verified: 'approved',
};

/** Shape-only comparison, so "dirty" ignores whitespace and empty smaczki. */
const norm = (q) => JSON.stringify({
  category: q?.category ?? null,
  is_premium: !!q?.is_premium,
  is_active: q?.is_active !== false,
  pl: (q?.pl ?? '').trim(),
  en: (q?.en ?? '').trim(),
  smaczki: (q?.smaczki ?? [])
    .map((s) => ({ pl: (s.pl ?? '').trim(), en: (s.en ?? '').trim() }))
    .filter((s) => s.pl !== ''),
});

export default function QuestionEditor() {
  const { id } = useParams();
  const router = useRouter();
  const isNew = id === 'new';

  const [live, setLive] = useState(null);       // snapshot currently on prod
  const [enReview, setEnReview] = useState(false); // live "EN do weryfikacji" flag
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
        setEnReview(res?.en_review_needed ?? false);
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
          en_review: src?.en_review ?? null,
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

  const refresh = useCallback(async () => {
    const fresh = await api.getQuestion(id);
    setLive(fresh.question);
    setDraft(fresh.open_draft);
    setEnReview(fresh.en_review_needed ?? false);
    setForm((f) => ({ ...f, en_review: null }));
    api.history(id).then((h) => setHistory(h ?? [])).catch(() => {});
  }, [id]);

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

  // Auto-propozycja flagi "EN do weryfikacji": zmieniono coś po polsku,
  // a angielski został nietknięty. Serwer liczy to samo przy zatwierdzaniu,
  // checkbox pozwala ręcznie nadpisać (np. literówka bez wpływu na EN).
  const autoEnReview = useMemo(() => {
    if (!live) return payload.en === '';
    const glue = String.fromCharCode(1); // separator smaczkow, nie wystapi w tresci
    const plChanged = (live.pl ?? '').trim() !== payload.pl
      || (live.smaczki ?? []).map((s) => (s.pl ?? '').trim()).join(glue)
         !== payload.smaczki.map((s) => s.pl).join(glue);
    const enChanged = (live.en ?? '').trim() !== payload.en
      || (live.smaczki ?? []).map((s) => (s.en ?? '').trim()).join(glue)
         !== payload.smaczki.map((s) => s.en).join(glue);
    if (enChanged) return false;
    if (plChanged) return true;
    return enReview;
  }, [live, payload, enReview]);

  const effEnReview = form.en_review ?? autoEnReview;
  const fullPayload = useMemo(() => ({ ...payload, en_review: effEnReview }),
    [payload, effEnReview]);

  const pending = draft?.status === 'pending';
  const canApprove = role === 'approver';
  const isDeleteDraft = draft?.action === 'delete';

  // Unpublished edits sitting in the form only. Drives the beforeunload guard —
  // easy to lose an hour of work otherwise when you edit dozens in a row.
  const dirty = useMemo(() => {
    if (pending) return false;
    if (isNew) return payload.pl !== '' || payload.en !== '' || payload.smaczki.length > 0;
    if (!live) return false;
    return norm(payload) !== norm(live);
  }, [pending, isNew, live, payload]);

  useEffect(() => {
    if (!dirty) return undefined;
    const h = (e) => { e.preventDefault(); e.returnValue = ''; };
    window.addEventListener('beforeunload', h);
    return () => window.removeEventListener('beforeunload', h);
  }, [dirty]);

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

  /** Save (reusing an editable draft when there is one) and return its id. */
  async function stageDraft() {
    const action = isNew ? 'create' : 'update';
    const common = {
      action, payload: fullPayload,
      questionId: isNew ? null : id,
      title: payload.pl.slice(0, 80),
    };
    const reusable = draft && ['draft', 'rejected'].includes(draft.status) ? draft.id : null;
    const dId = await api.saveDraft({ ...common, draftId: reusable });
    return reusable ?? dId;
  }

  const saveDraft = () => run(async () => {
    const dId = await stageDraft();
    if (isNew) setDraft({ id: dId, status: 'draft' });
    else { const fresh = await api.getQuestion(id); setDraft(fresh.open_draft); }
    return dId;
  }, 'Wersja robocza zapisana.');

  const submit = () => run(async () => {
    const dId = await stageDraft();
    await api.submitDraft(dId);
    setDraft({ ...(draft ?? {}), id: dId, status: 'pending' });
    return dId;
  }, 'Zgłoszone do zatwierdzenia.');

  // Approver shortcut: draft → submit → apply in one click, so routine edits
  // don't need the two-step review ceremony meant for multiple people.
  const publish = () => run(async () => {
    const dId = await stageDraft();
    await api.submitDraft(dId);
    const res = await api.approveDraft(dId);
    if (isNew) { router.replace(`/q/${res.question_id}`); return res; }
    await refresh();
    return res;
  }, 'Opublikowane.');

  const approve = () => run(async () => {
    const res = await api.approveDraft(draft.id);
    if (res.action === 'delete') { router.replace('/'); return res; }
    if (isNew && res.question_id) { router.replace(`/q/${res.question_id}`); return res; }
    await refresh();
    return res;
  }, 'Zatwierdzone i opublikowane.');

  // Bezpośredni toggle flagi na żywej wersji (bez draftu).
  const setFlag = (flag) => run(async () => {
    await api.setEnReview(id, flag);
    setEnReview(flag);
    setForm((f) => ({ ...f, en_review: null }));
    api.history(id).then((h) => setHistory(h ?? [])).catch(() => {});
  }, flag ? 'Oznaczone: EN do weryfikacji.' : 'Flaga zdjęta — EN zweryfikowany.');

  const requestDelete = () => run(async () => {
    const dId = await api.saveDraft({
      action: 'delete', payload: null, questionId: id,
      title: 'Usunięcie: ' + (live?.pl ?? '').slice(0, 60),
    });
    await api.submitDraft(dId);
    setDraft({ id: dId, status: 'pending', action: 'delete' });
    return dId;
  }, 'Usunięcie zgłoszone do zatwierdzenia.');

  // Ctrl/Cmd+S fires whatever the big button does. Held in a ref so the
  // listener registers once and still sees current state.
  const primaryRef = useRef(null);
  primaryRef.current = () => {
    if (busy || loading || isDeleteDraft) return;
    if (pending) { if (canApprove) approve(); return; }
    if (!payload.pl) return;
    if (canApprove) publish(); else submit();
  };
  useEffect(() => {
    const h = (e) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 's') {
        e.preventDefault();
        primaryRef.current?.();
      }
    };
    window.addEventListener('keydown', h);
    return () => window.removeEventListener('keydown', h);
  }, []);

  if (loading) return <div className="spin">Ładowanie…</div>;

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
                <Counter value={form.pl} limit={LIMITS.question} />
              </div>
              <div className="fx">
                <span className="flag" title="angielski">🇬🇧</span>
                <textarea rows={2} value={form.en} disabled={pending}
                          placeholder="tłumaczenie"
                          onChange={(e) => setForm({ ...form, en: e.target.value })} />
                <Counter value={form.en} limit={LIMITS.question} />
              </div>
            </div>

            {!isNew && (
              <div style={{ display: 'flex', gap: 10, alignItems: 'center', flexWrap: 'wrap', marginBottom: 12 }}>
                {enReview ? (
                  <>
                    <span className="badge enreview">EN do weryfikacji</span>
                    {canApprove ? (
                      <button className="btn sm ok" disabled={busy} onClick={() => setFlag(false)}>
                        EN zweryfikowany ✓
                      </button>
                    ) : (
                      <span className="faint">flagę zdejmuje approver po weryfikacji tłumaczenia</span>
                    )}
                  </>
                ) : (
                  <button className="btn sm ghost" disabled={busy} onClick={() => setFlag(true)}
                          title="Oznacz od razu, bez wersji roboczej">
                    🇬🇧 Oznacz EN do weryfikacji
                  </button>
                )}
              </div>
            )}

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
              <label className="faint" style={{ display: 'flex', gap: 6, alignItems: 'center' }}
                     title="Po zatwierdzeniu pytanie dostanie flagę „EN do weryfikacji”. Zaznacza się samo, gdy zmieniasz tylko polski tekst.">
                <input type="checkbox" checked={effEnReview} disabled={pending} style={{ width: 'auto' }}
                       onChange={(e) => setForm({ ...form, en_review: e.target.checked })} />
                🇬🇧 EN do weryfikacji
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
        {pending ? (
          canApprove && (
            <button className="btn ok" onClick={approve} disabled={busy}>
              {isDeleteDraft ? 'Zatwierdź usunięcie' : 'Zatwierdź i opublikuj'}
            </button>
          )
        ) : (
          <>
            {canApprove ? (
              <>
                <button className="btn ok" onClick={publish} disabled={busy || !payload.pl}>
                  Zapisz i opublikuj
                </button>
                <button className="btn ghost" onClick={saveDraft} disabled={busy || !payload.pl}>
                  Wersja robocza
                </button>
              </>
            ) : (
              <>
                <button className="btn" onClick={saveDraft} disabled={busy || !payload.pl}>
                  Zapisz wersję roboczą
                </button>
                <button className="btn primary" onClick={submit} disabled={busy || !payload.pl}>
                  Zgłoś do zatwierdzenia
                </button>
              </>
            )}
            <span className="kbd-hint">Ctrl+S</span>
            {dirty && <span className="dirty">● niezapisane</span>}
          </>
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
                <span className={`badge ${HIST_BADGE[h.action] ?? 'approved'}`}>{HIST_LABEL[h.action] ?? h.action}</span>{' '}
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
