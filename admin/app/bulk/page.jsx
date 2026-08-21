'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { api } from '../../lib/api';
import Diff from '../../components/Diff';
import {
  AGENT_PROMPT, buildBundle, buildPayload, copyText, mapLimit,
  parseBundle, payloadWarnings, shapeKey,
} from '../../lib/bulk';

/**
 * Hurtowa edycja: zaznacz N pytań → skopiuj je jednym JSON-em dla agenta →
 * wklej odpowiedź → obejrzyj różnice → opublikuj wszystko.
 *
 * Zapis NIE omija zwykłego flow: każde pytanie dostaje własny draft
 * (admin_save_draft → admin_submit_draft → admin_approve_draft), pobierany
 * tuż przed zapisem na świeżym snapshotcie — więc strażnik konfliktu, audyt
 * i automat „EN do weryfikacji" działają dokładnie tak jak przy pojedynczej
 * edycji. Błąd na jednym pytaniu nie przerywa reszty paczki.
 */

const PAGE_SIZES = [10, 20, 50];

export default function BulkPage() {
  const [role, setRole] = useState(null);
  const canApprove = role === 'approver';

  // ---- 1. wybór pytań -----------------------------------------------------
  const [search, setSearch] = useState('');
  const [onlyActive, setOnlyActive] = useState(true);
  const [onlyUntagged, setOnlyUntagged] = useState(false);
  const [onlyEnReview, setOnlyEnReview] = useState(false);
  const [onlyUnverified, setOnlyUnverified] = useState(false);
  const [onlyNeedsReview, setOnlyNeedsReview] = useState(false);
  const [onlyFavorites, setOnlyFavorites] = useState(false);
  const [size, setSize] = useState(10);
  const [page, setPage] = useState(0);
  const [rows, setRows] = useState([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState(null);
  const [picked, setPicked] = useState(() => new Set());

  const filters = useMemo(() => ({
    search: search.trim() === '' ? null : search.trim(),
    onlyActive, onlyEnReview, onlyFavorites, onlyUnverified, onlyNeedsReview, onlyUntagged,
  }), [search, onlyActive, onlyEnReview, onlyFavorites, onlyUnverified, onlyNeedsReview, onlyUntagged]);

  const load = useCallback(async (p) => {
    setLoading(true); setErr(null);
    try {
      const data = await api.listQuestions({ ...filters, limit: size, offset: p * size });
      setRows(data ?? []);
      setTotal(data?.[0]?.total_count ?? 0);
    } catch (e) {
      setErr(e.friendly || e.message);
    } finally {
      setLoading(false);
    }
  }, [filters, size]);

  useEffect(() => { api.me().then((m) => setRole(m?.role)).catch(() => {}); }, []);

  useEffect(() => {
    const t = setTimeout(() => { setPage(0); load(0); }, 250);
    return () => clearTimeout(t);
  }, [load]);

  const pages = Math.ceil(total / size) || 1;

  const toggle = (id) => setPicked((s) => {
    const next = new Set(s);
    if (next.has(id)) next.delete(id); else next.add(id);
    return next;
  });
  const pickPage = () => setPicked((s) => new Set([...s, ...rows.map((r) => r.id)]));
  const clearPicks = () => setPicked(new Set());

  // ---- 2. eksport ---------------------------------------------------------
  const [withPrompt, setWithPrompt] = useState(true);
  const [exportText, setExportText] = useState('');
  const [exporting, setExporting] = useState(false);
  const [copied, setCopied] = useState(false);

  async function makeExport() {
    if (picked.size === 0) return;
    setExporting(true); setErr(null); setCopied(false);
    try {
      const ids = [...picked];
      const snaps = await mapLimit(ids, 4, async (id) => (await api.getQuestion(id))?.question);
      const missing = snaps.filter((s) => !s).length;
      const bundle = buildBundle(snaps.filter(Boolean));
      const text = (withPrompt ? `${AGENT_PROMPT}\n\n` : '') + JSON.stringify(bundle, null, 2);
      setExportText(text);
      await copyText(text);
      setCopied(true);
      if (missing > 0) setErr(`${missing} zaznaczonych pytań już nie ma w bazie — pominięte.`);
    } catch (e) {
      setErr(e.friendly || e.message);
    } finally {
      setExporting(false);
    }
  }

  // ---- 3. import ----------------------------------------------------------
  const [pasteText, setPasteText] = useState('');
  const [parsing, setParsing] = useState(false);
  const [parseErr, setParseErr] = useState(null);
  const [items, setItems] = useState([]);
  const [busy, setBusy] = useState(false);
  const [progress, setProgress] = useState(null);
  const [summary, setSummary] = useState(null);

  const patch = (key, up) => setItems((list) => list.map((it) => (it.key === key ? { ...it, ...up } : it)));

  /** Wklejony JSON → podgląd: świeży snapshot z bazy + policzony payload. */
  async function checkPaste() {
    setParseErr(null); setSummary(null); setItems([]);
    let parsed;
    try {
      parsed = parseBundle(pasteText);
    } catch (e) {
      setParseErr(e.message);
      return;
    }
    if (parsed.length === 0) { setParseErr('Brak pytań w JSON-ie.'); return; }

    setParsing(true);
    try {
      const built = await mapLimit(parsed, 4, async (p, i) => {
        const it = {
          key: i, id: p.id, patch: p.patch,
          action: p.id ? 'update' : 'create',
          base: null, payload: null, warnings: [],
          error: null, blocked: null, noop: false,
          include: false, status: null, note: null,
        };
        try {
          if (p.id) {
            const res = await api.getQuestion(p.id);
            it.base = res?.question ?? null;
            if (!it.base) throw new Error('Nie ma takiego pytania (albo zostało usunięte).');
            if (res?.open_draft?.status === 'pending') {
              it.blocked = 'Czeka na zatwierdzenie — najpierw zatwierdź albo odrzuć wersję roboczą.';
            } else if (res?.open_draft) {
              it.note = 'Nadpisze otwartą wersję roboczą.';
            }
          }
          it.payload = buildPayload(it.base, p.patch);
          it.warnings = payloadWarnings(it.payload);
          it.noop = it.base ? shapeKey(it.base) === shapeKey(it.payload) : false;
          it.include = !it.noop && !it.blocked;
        } catch (e) {
          it.error = e.friendly || e.message;
        }
        return it;
      });
      setItems(built);
    } catch (e) {
      setParseErr(e.friendly || e.message);
    } finally {
      setParsing(false);
    }
  }

  const selected = items.filter((it) => it.include && !it.error && !it.blocked);

  /**
   * Publikacja paczki. Snapshot pobierany ponownie tuż przed zapisem —
   * podgląd mógł powstać kilka minut temu, a base_hash draftu musi opisywać
   * to, co jest na produkcji w chwili zapisu.
   */
  async function publishAll() {
    if (selected.length === 0) return;
    const label = canApprove ? 'opublikować' : 'zgłosić do zatwierdzenia';
    if (!confirm(`Na pewno ${label} ${selected.length} pytań?`)) return;

    setBusy(true); setSummary(null); setErr(null);
    let ok = 0; let failed = 0;
    for (let i = 0; i < selected.length; i++) {
      const it = selected[i];
      setProgress({ done: i, total: selected.length });
      patch(it.key, { status: 'busy', note: null });
      try {
        let base = null;
        let draftId = null;
        if (it.id) {
          const fresh = await api.getQuestion(it.id);
          base = fresh?.question ?? null;
          if (!base) throw new Error('Pytanie zniknęło z bazy.');
          const d = fresh.open_draft;
          if (d?.status === 'pending') throw new Error('Wersja robocza czeka na zatwierdzenie.');
          if (d && ['draft', 'rejected'].includes(d.status)) draftId = d.id;
        }
        const payload = buildPayload(base, it.patch);
        const dId = await api.saveDraft({
          action: it.id ? 'update' : 'create',
          payload,
          questionId: it.id,
          draftId,
          title: payload.pl.slice(0, 80),
        });
        await api.submitDraft(dId);
        // include: false po sukcesie — licznik przycisku spada, a drugie
        // kliknięcie nie zapisze tego samego pytania jeszcze raz. Wiersz
        // z błędem zostaje zaznaczony, żeby dało się go ponowić.
        if (canApprove) {
          await api.approveDraft(dId);
          patch(it.key, { status: 'done', include: false, note: 'Opublikowane.' });
        } else {
          patch(it.key, { status: 'done', include: false, note: 'Zgłoszone do zatwierdzenia.' });
        }
        ok += 1;
      } catch (e) {
        failed += 1;
        patch(it.key, { status: 'failed', note: e.friendly || e.message });
      }
    }
    setProgress(null);
    setBusy(false);
    setSummary({ ok, failed, approved: canApprove });
    load(page);
  }

  return (
    <>
      <h1 className="page-title">Hurtowo</h1>
      <p className="page-sub">
        Zaznacz pytania → skopiuj paczkę JSON dla agenta → wklej odpowiedź → obejrzyj różnice →
        opublikuj wszystko naraz. Każde pytanie zapisuje się osobnym draftem, więc historia zmian
        i flaga „EN do weryfikacji" działają jak zwykle.
      </p>

      {err && <div className="alert err">{err}</div>}

      {/* ---------- krok 1: wybór ---------- */}
      <div className="card">
        <div className="toolbar" style={{ marginBottom: 12 }}>
          <h3 style={{ margin: 0 }}><span className="step">1</span> Wybierz pytania</h3>
          <div style={{ flex: 1 }} />
          <span className="faint">zaznaczone: <b>{picked.size}</b></span>
          {picked.size > 0 && (
            <button className="btn sm ghost" onClick={clearPicks}>Wyczyść zaznaczenie</button>
          )}
        </div>

        <div className="toolbar">
          <input className="search" type="text" placeholder="Szukaj w treści PL lub EN…"
                 value={search} onChange={(e) => setSearch(e.target.value)} />
          <label className="faint pick-lbl">
            <input type="checkbox" checked={onlyActive} onChange={(e) => setOnlyActive(e.target.checked)} />
            tylko aktywne
          </label>
          <label className="faint pick-lbl" title="Worklista tagowania — pytania, w których choć jeden smaczek nie ma strony">
            <input type="checkbox" checked={onlyUntagged} onChange={(e) => setOnlyUntagged(e.target.checked)} />
            🎯 smaczki bez strony
          </label>
          <label className="faint pick-lbl">
            <input type="checkbox" checked={onlyEnReview} onChange={(e) => setOnlyEnReview(e.target.checked)} />
            🇬🇧 EN do weryfikacji
          </label>
          <label className="faint pick-lbl">
            <input type="checkbox" checked={onlyUnverified} onChange={(e) => setOnlyUnverified(e.target.checked)} />
            ✓ ukryj zweryfikowane
          </label>
          <label className="faint pick-lbl">
            <input type="checkbox" checked={onlyNeedsReview} onChange={(e) => setOnlyNeedsReview(e.target.checked)} />
            ⚑ tylko do weryfikacji
          </label>
          <label className="faint pick-lbl">
            <input type="checkbox" checked={onlyFavorites} onChange={(e) => setOnlyFavorites(e.target.checked)} />
            ★ ulubione
          </label>
          <select value={size} style={{ width: 'auto' }}
                  onChange={(e) => setSize(Number(e.target.value))}>
            {PAGE_SIZES.map((n) => <option key={n} value={n}>{n} na stronę</option>)}
          </select>
        </div>

        {loading ? (
          <div className="spin">Ładowanie…</div>
        ) : rows.length === 0 ? (
          <div className="spin">Brak wyników</div>
        ) : (
          <table className="bulk-table">
            <thead>
              <tr>
                <th style={{ width: 34 }}>
                  <input type="checkbox" title="Zaznacz całą stronę"
                         checked={rows.length > 0 && rows.every((r) => picked.has(r.id))}
                         onChange={(e) => (e.target.checked ? pickPage() : setPicked((s) => {
                           const next = new Set(s);
                           rows.forEach((r) => next.delete(r.id));
                           return next;
                         }))} />
                </th>
                <th>Pytanie (PL)</th>
                <th style={{ width: 110 }}>Kategoria</th>
                <th style={{ width: 90 }}>Smaczki</th>
                <th style={{ width: 130 }}>Status</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id} className={picked.has(r.id) ? 'open' : ''} onClick={() => toggle(r.id)}>
                  <td onClick={(e) => e.stopPropagation()}>
                    <input type="checkbox" checked={picked.has(r.id)} onChange={() => toggle(r.id)} />
                  </td>
                  <td className="q">
                    {r.pl}
                    <div className="en">{r.en}</div>
                  </td>
                  <td className="muted">{r.category}</td>
                  <td className="muted">
                    {r.smaczki_count}
                    {r.smaczki_untagged > 0 && (
                      <span className="badge enreview" style={{ marginLeft: 6 }}>🎯 {r.smaczki_untagged}</span>
                    )}
                  </td>
                  <td>
                    {r.open_draft_id && <span className="badge draft">wersja robocza</span>}
                    {r.en_review_needed && <span className="badge enreview">EN</span>}
                    {!r.is_active && <span className="badge">nieaktywne</span>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}

        <div className="toolbar pager" style={{ marginTop: 12, marginBottom: 0 }}>
          <button className="btn sm" disabled={page === 0 || loading}
                  onClick={() => { setPage(page - 1); load(page - 1); }}>←</button>
          <span className="faint">Strona {page + 1} z {pages} · {total} pytań</span>
          <button className="btn sm" disabled={page + 1 >= pages || loading}
                  onClick={() => { setPage(page + 1); load(page + 1); }}>→</button>
          <div style={{ flex: 1 }} />
          <button className="btn sm ghost" disabled={loading} onClick={pickPage}>
            Zaznacz tę stronę ({rows.length})
          </button>
        </div>
      </div>

      {/* ---------- krok 2: eksport ---------- */}
      <div className="card">
        <div className="toolbar" style={{ marginBottom: 10 }}>
          <h3 style={{ margin: 0 }}><span className="step">2</span> Kopiuj dla agenta</h3>
          <label className="faint pick-lbl" title="Dokleja nad JSON-em opis formatu odpowiedzi">
            <input type="checkbox" checked={withPrompt} onChange={(e) => setWithPrompt(e.target.checked)} />
            z instrukcją
          </label>
          <div style={{ flex: 1 }} />
          <button className="btn primary" disabled={picked.size === 0 || exporting} onClick={makeExport}>
            {exporting ? 'Pobieram…' : copied ? `Skopiowano ✓ (${picked.size})` : `📋 Kopiuj JSON (${picked.size})`}
          </button>
        </div>
        {picked.size === 0 && <div className="faint">Zaznacz najpierw pytania powyżej.</div>}
        {exportText && (
          <details className="sec" style={{ marginTop: 4 }}>
            <summary>Podgląd skopiowanego tekstu <span className="count">({exportText.length} zn.)</span></summary>
            <div className="body">
              <textarea className="mono" rows={12} readOnly value={exportText} />
            </div>
          </details>
        )}
      </div>

      {/* ---------- krok 3: wklejenie ---------- */}
      <div className="card">
        <div className="toolbar" style={{ marginBottom: 10 }}>
          <h3 style={{ margin: 0 }}><span className="step">3</span> Wklej odpowiedź agenta</h3>
          <div style={{ flex: 1 }} />
          <button className="btn" disabled={pasteText.trim() === '' || parsing || busy} onClick={checkPaste}>
            {parsing ? 'Sprawdzam…' : 'Sprawdź'}
          </button>
        </div>

        <textarea className="mono" rows={8} value={pasteText} disabled={busy}
                  placeholder={'{"questions":[{"id":"…","smaczki":[{"position":1,"side":"attacks_yes"}]}]}'}
                  onChange={(e) => { setPasteText(e.target.value); setParseErr(null); }} />

        <p className="faint" style={{ marginBottom: 0 }}>
          Dopasowanie po <code>id</code>. Pola nieobecne w JSON-ie zostają bez zmian, więc same
          {' "smaczki":[{"position":1,"side":"attacks_no"}] '} otaguje istniejący wiersz i nie ruszy reszty.
          Wiersz bez numeru pozycji = JSON jest całą listą smaczków. Kasowanie:
          {' {"position":3,"delete":true}'}. Pozycja bez <code>id</code> = nowe pytanie. Płot
          {' ```json '} i tekst dookoła są obcinane automatycznie.
        </p>

        {parseErr && <div className="alert err" style={{ marginTop: 12, marginBottom: 0 }}>{parseErr}</div>}
      </div>

      {/* ---------- krok 4: podgląd + publikacja ---------- */}
      {items.length > 0 && (
        <div className="card">
          <div className="toolbar" style={{ marginBottom: 10 }}>
            <h3 style={{ margin: 0 }}><span className="step">4</span> Podgląd zmian</h3>
            <span className="faint">
              {items.length} poz. · do zapisu: <b>{selected.length}</b>
              {items.some((i) => i.error) && ` · błędnych: ${items.filter((i) => i.error).length}`}
              {items.some((i) => i.noop) && ` · bez zmian: ${items.filter((i) => i.noop).length}`}
            </span>
            <div style={{ flex: 1 }} />
            {progress && <span className="faint">{progress.done}/{progress.total}…</span>}
            <button className="btn ok" disabled={busy || selected.length === 0} onClick={publishAll}>
              {busy ? 'Zapisuję…'
                : canApprove ? `Opublikuj wszystkie (${selected.length})`
                  : `Zgłoś wszystkie (${selected.length})`}
            </button>
          </div>

          {summary && (
            <div className={`alert ${summary.failed > 0 ? 'err' : 'ok'}`}>
              {summary.approved ? 'Opublikowano' : 'Zgłoszono'}: <b>{summary.ok}</b>
              {summary.failed > 0 && <> · nie udało się: <b>{summary.failed}</b> (szczegóły przy wierszach)</>}
            </div>
          )}

          {items.map((it) => (
            <div key={it.key}
                 className={`bulk-item${it.error || it.status === 'failed' ? ' bad' : ''}${it.status === 'done' ? ' done' : ''}`}>
              <div className="bulk-head">
                <input type="checkbox" checked={it.include} disabled={busy || !!it.error || !!it.blocked}
                       onChange={(e) => patch(it.key, { include: e.target.checked })} />
                <span className="t">
                  {it.payload?.pl || it.base?.pl || it.patch?.pl || <span className="faint">(bez treści)</span>}
                </span>
                {it.action === 'create' && <span className="badge premium">nowe</span>}
                {it.noop && <span className="badge">bez zmian</span>}
                {it.blocked && <span className="badge draft">zablokowane</span>}
                {it.status === 'busy' && <span className="badge pending">zapisuję…</span>}
                {it.status === 'done' && <span className="badge approved">✓</span>}
                {it.status === 'failed' && <span className="badge rejected">błąd</span>}
              </div>

              {it.error && <div className="alert err bulk-msg">{it.error}</div>}
              {it.blocked && <div className="alert info bulk-msg">{it.blocked}</div>}
              {it.note && (
                <div className={`alert ${it.status === 'failed' ? 'err' : it.status === 'done' ? 'ok' : 'info'} bulk-msg`}>
                  {it.note}
                </div>
              )}
              {it.warnings.length > 0 && (
                <div className="faint bulk-warn">⚠ {it.warnings.join(' · ')}</div>
              )}

              {it.payload && (
                <details className="sec bulk-diff">
                  <summary>Różnice <span className="count">— przed / po</span></summary>
                  <div className="body"><Diff before={it.base} after={it.payload} /></div>
                </details>
              )}
            </div>
          ))}
        </div>
      )}
    </>
  );
}
