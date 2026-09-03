'use client';

import { Fragment, useCallback, useEffect, useState } from 'react';
import { api } from '../../lib/api';

const DAYS = 45;

/** 'YYYY-MM-DD' → Date w strefie lokalnej (new Date(iso) cofa o dzień na zachód). */
function parseDay(iso) {
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(y, m - 1, d);
}

function isoAdd(iso, n) {
  const d = parseDay(iso);
  d.setDate(d.getDate() + n);
  const p = (x) => String(x).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

const FMT_DAY = new Intl.DateTimeFormat('pl-PL', { weekday: 'short', day: 'numeric', month: 'short' });

/** Dziś/jutro przychodzą z serwera (liczone w UTC); pojutrze wynika z pierwszego edytowalnego dnia. */
function dayTag(r) {
  if (r.day_label === 'past') return 'było';
  if (r.day_label === 'today') return 'dziś';
  if (r.day_label === 'tomorrow') return 'jutro';
  if (r.publish_date === r.cal_first_editable) return 'pojutrze';
  return null;
}

function q(text) {
  return `„${text}”`;
}

function resultMessage(res) {
  switch (res.action) {
    case 'swap':
      return `${res.date} → ${q(res.question_pl)}. Zamienione miejscami: ${q(res.previous_pl)} stoi teraz na ${res.swapped_from}.`;
    case 'replace':
      return `${res.date} → ${q(res.question_pl)}. Dotychczasowe pytanie (${q(res.previous_pl)}) trafiło na koniec kalendarza, na ${res.displaced_to}.`;
    case 'moved':
      return `${res.date} → ${q(res.question_pl)} (przeniesione z ${res.swapped_from}). Uwaga: ${res.gap_left_at} został pusty, więc nocne porządkowanie ściągnie późniejsze pytania o dzień.`;
    case 'insert':
      return `${res.date} → ${q(res.question_pl)} (ten dzień nie miał wcześniej pytania).`;
    case 'noop':
      return 'To pytanie już tam stało — nic nie zmieniono.';
    default:
      return JSON.stringify(res);
  }
}

export default function DailyCalendar() {
  const [from, setFrom] = useState(null);          // null = serwerowe „dziś” (UTC)
  const [rows, setRows] = useState([]);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState(null);
  const [ok, setOk] = useState(null);
  const [selected, setSelected] = useState(null);  // 'YYYY-MM-DD'
  const [role, setRole] = useState(null);
  const [busy, setBusy] = useState(false);

  const canEdit = role === 'approver';

  const load = useCallback(async (f) => {
    setLoading(true);
    setErr(null);
    try {
      const data = await api.listDailyPicks(f, DAYS);
      setRows(data ?? []);
    } catch (e) {
      setErr(e.friendly || e.message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { load(from); }, [from, load]);
  useEffect(() => { api.me().then((m) => setRole(m?.role ?? null)).catch(() => {}); }, []);

  const reload = useCallback(() => load(from), [load, from]);

  const cal = rows[0] ?? {};
  const windowStart = rows[0]?.publish_date ?? null;

  async function compact() {
    if (!confirm(
      'Uporządkować kalendarz teraz?\n\n'
      + 'To samo, co robi cron o 02:47 UTC: usuwa przyszłe wpisy z nieaktywnymi '
      + 'pytaniami i ściąga resztę na kolejne dni. Daty późniejszych pytań się '
      + 'przesuną — dlatego lepiej zrobić to teraz i dopiero potem przypinać '
      + 'pytanie do konkretnego dnia.'
    )) return;
    setBusy(true); setErr(null); setOk(null);
    try {
      const res = await api.compactDailyPicks();
      setOk(`Uporządkowane: ${res}`);
      setSelected(null);
      await reload();
    } catch (e) {
      setErr(e.friendly || e.message);
    } finally {
      setBusy(false);
    }
  }

  async function swap(row, cand) {
    const lines = [];
    if (cand.scheduled_on && row.question_id) {
      lines.push('Zamiana miejscami:', '',
        `${row.publish_date} → ${q(cand.pl)}`,
        `${cand.scheduled_on} → ${q(row.pl)}`);
    } else if (row.question_id) {
      lines.push('Podmiana:', '',
        `${row.publish_date} → ${q(cand.pl)}`, '',
        `Dotychczasowe pytanie (${q(row.pl)}) trafi na koniec kalendarza — nie znika z rotacji.`);
    } else if (cand.scheduled_on) {
      lines.push(`${row.publish_date} nie ma przypisanego pytania.`, '',
        `Przenieść tu ${q(cand.pl)} z ${cand.scheduled_on}?`, '',
        `Uwaga: ${cand.scheduled_on} zrobi się pusty, a nocne porządkowanie ściągnie wtedy późniejsze pytania o dzień.`);
    } else {
      lines.push(`${row.publish_date} nie ma przypisanego pytania.`, '',
        `Ustawić ${q(cand.pl)}?`);
    }
    if (!confirm(lines.join('\n'))) return;

    setBusy(true); setErr(null); setOk(null);
    try {
      // Dla zajętego dnia zamek to id pytania z ekranu; dla pustego — flaga
      // "ma być nadal pusty". Bez niej dwóch approverów wypełniających tę samą
      // dziurę nadpisywało sobie nawzajem świeży wpis bez ostrzeżenia.
      const res = await api.setDailyPick(
        row.publish_date, cand.id, row.question_id, !row.question_id,
      );
      setOk(resultMessage(res));
      setSelected(null);
      await reload();
    } catch (e) {
      setErr(e.friendly || e.message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <h1 className="page-title">Pytania dnia</h1>
      <p className="page-sub">
        Kalendarz <code>daily_picks</code> — jedno pytanie na dzień dla całego świata.
        {cal.cal_future != null && (
          <> {cal.cal_future} pytań w przód, ostatnie na {cal.cal_last_date}.</>
        )}
      </p>

      <div className="alert info">
        <b>Dziś i jutro są zablokowane.</b> Dzisiejsze pytanie jest już na ekranach,
        a jutrzejsze poszło w zapowiedź na ścianie dnia i w powiadomienia zaplanowane
        na telefonach. Pierwszy dzień, który można zmienić, to <b>pojutrze</b>
        {cal.cal_first_editable ? ` (${cal.cal_first_editable})` : ''}.
        <div className="faint" style={{ marginTop: 6 }}>
          Zmiana najbliższych kilku dni może rozminąć się z zapowiedzią, którą ktoś ma
          już wpisaną w zaplanowane powiadomienie — aplikacja przestawia je przy każdym
          uruchomieniu, więc dla aktywnych naprawia się samo.
        </div>
      </div>

      {cal.cal_inactive_future > 0 && (
        <div className="alert err">
          <b>{cal.cal_inactive_future} przyszłych pytań jest nieaktywnych.</b> Nocne
          porządkowanie usunie je i ściągnie wszystkie późniejsze pytania o {cal.cal_inactive_future} dni.
          Przypięcie pytania do konkretnej daty ma sens dopiero po tym przesunięciu.
          {canEdit && (
            <div style={{ marginTop: 8 }}>
              <button className="btn sm" disabled={busy} onClick={compact}>
                Uporządkuj teraz
              </button>
            </div>
          )}
        </div>
      )}

      {!canEdit && role && (
        <div className="alert info">
          Podmiana pytania dnia wymaga roli <b>approver</b> — Twoja rola to <b>{role}</b>.
          Listę widzisz w całości.
        </div>
      )}

      {err && <div className="alert err">{err}</div>}
      {ok && <div className="alert ok">{ok}</div>}

      <div className="toolbar">
        <button className="btn sm" disabled={loading || !windowStart}
                onClick={() => { setSelected(null); setFrom(isoAdd(windowStart, -DAYS)); }}>
          ← wcześniej
        </button>
        <button className="btn sm" disabled={loading || !from}
                onClick={() => { setSelected(null); setFrom(null); }}>
          dziś
        </button>
        <button className="btn sm" disabled={loading || !windowStart}
                onClick={() => { setSelected(null); setFrom(isoAdd(windowStart, DAYS)); }}>
          później →
        </button>
        <label className="faint" style={{ display: 'flex', gap: 7, alignItems: 'center' }}>
          skocz do dnia
          <input type="date" style={{ width: 'auto' }} value={windowStart ?? ''}
                 onChange={(e) => { setSelected(null); setFrom(e.target.value || null); }} />
        </label>
      </div>

      <div className="card" style={{ padding: 0, overflow: 'hidden' }}>
        {loading ? (
          <div className="spin">Ładowanie…</div>
        ) : rows.length === 0 ? (
          <div className="spin">Brak dni</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th style={{ width: 34 }} title="Wybierz dzień do podmiany" />
                <th style={{ width: 150 }}>Dzień</th>
                <th style={{ width: '44%' }}>Pytanie (PL)</th>
                <th>Kategoria</th>
                <th style={{ width: 70 }} title="Smaczki">Smaczki</th>
                <th style={{ width: 70 }} title="Ile osób już na to zagłosowało — tyle zobaczy od razu wyniki, nie przyciski">Głosy</th>
                <th style={{ width: 130 }} />
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => {
                const tag = dayTag(r);
                const isSel = selected === r.publish_date;
                return (
                  <Fragment key={r.publish_date}>
                    <tr
                      className={`${isSel ? 'open' : ''} ${r.locked ? 'day-locked' : ''}`}
                      onClick={() => {
                        if (r.locked || !canEdit) return;
                        if (window.getSelection?.()?.toString()) return;
                        setSelected(isSel ? null : r.publish_date);
                      }}
                    >
                      <td className="check-cell">
                        {r.locked ? (
                          <span className="faint" title="Dzień już opublikowany — nie do zmiany">🔒</span>
                        ) : (
                          <input type="radio" readOnly checked={isSel} disabled={!canEdit}
                                 style={{ width: 'auto' }} />
                        )}
                      </td>
                      <td>
                        <b style={{ fontVariantNumeric: 'tabular-nums' }}>{r.publish_date}</b>
                        <div className="faint">
                          {FMT_DAY.format(parseDay(r.publish_date))}
                          {tag && <> · <b>{tag}</b></>}
                        </div>
                      </td>
                      <td className="q">
                        {r.pl ?? <span className="faint">— brak wpisu: tego dnia każdy dostaje losowanie osobiste —</span>}
                        {r.en && <div className="en">{r.en}</div>}
                      </td>
                      <td className="muted">{r.category}</td>
                      <td className="muted" title={r.smaczki_untagged > 0 ? `${r.smaczki_untagged} bez ustawionej strony` : ''}>
                        {r.question_id ? r.smaczki_count : ''}
                        {r.smaczki_untagged > 0 && (
                          <span className="badge enreview" style={{ marginLeft: 6 }}>🎯 {r.smaczki_untagged}</span>
                        )}
                      </td>
                      <td className={r.votes >= 5 ? 'warn-num' : 'muted'}
                          title="Tylu użytkowników już zagłosowało na to pytanie — zobaczą wyniki zamiast przycisków">
                        {r.question_id ? r.votes : ''}
                      </td>
                      <td>
                        {r.is_favorite && <span className="badge premium">★</span>}
                        {r.is_verified && <span className="badge approved">✓</span>}
                        {r.question_id && !r.is_active && <span className="badge rejected">nieaktywne</span>}
                      </td>
                    </tr>
                    {isSel && (
                      <tr className="editor-row">
                        <td colSpan={7}>
                          <SwapPanel row={r} busy={busy}
                                     onPick={(cand) => swap(r, cand)}
                                     onClose={() => setSelected(null)} />
                        </td>
                      </tr>
                    )}
                  </Fragment>
                );
              })}
            </tbody>
          </table>
        )}
      </div>
    </>
  );
}

/**
 * Wyszukiwarka pytania do podstawienia pod wybrany dzień. Pytanie, które ma już
 * swoją datę, zamienia się z nią miejscami; pytanie spoza kalendarza wchodzi na
 * dzień, a dotychczasowe ląduje na końcu kalendarza (żeby nie zrobić dziury —
 * dziura przesuwa wszystkie późniejsze daty przy nocnym porządkowaniu).
 */
function SwapPanel({ row, busy, onPick, onClose }) {
  const [search, setSearch] = useState('');
  const [onlyFavorites, setOnlyFavorites] = useState(false);
  const [onlyUnscheduled, setOnlyUnscheduled] = useState(false);
  const [hits, setHits] = useState([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState(null);

  useEffect(() => {
    let cancelled = false;
    const t = setTimeout(async () => {
      setLoading(true); setErr(null);
      try {
        const data = await api.searchDailyCandidates({
          search: search.trim() === '' ? null : search.trim(),
          onlyFavorites,
          onlyUnscheduled,
          limit: 30,
        });
        if (cancelled) return;
        setHits(data ?? []);
        setTotal(data?.[0]?.total_count ?? 0);
      } catch (e) {
        if (!cancelled) setErr(e.friendly || e.message);
      } finally {
        if (!cancelled) setLoading(false);
      }
    }, 250);
    return () => { cancelled = true; clearTimeout(t); };
  }, [search, onlyFavorites, onlyUnscheduled]);

  return (
    <div onClick={(e) => e.stopPropagation()}>
      <div className="toolbar" style={{ marginBottom: 10 }}>
        <b>Podmień pytanie na {row.publish_date}</b>
        <div className="spacer" style={{ flex: 1 }} />
        <button className="btn sm ghost" onClick={onClose}>Anuluj</button>
      </div>

      <div className="toolbar">
        <input className="search" type="text" autoFocus
               placeholder="Szukaj pytania w treści PL lub EN…"
               value={search} onChange={(e) => setSearch(e.target.value)} />
        <label className="faint" style={{ display: 'flex', gap: 7, alignItems: 'center' }}>
          <input type="checkbox" checked={onlyFavorites} style={{ width: 'auto' }}
                 onChange={(e) => setOnlyFavorites(e.target.checked)} />
          ★ tylko ulubione
        </label>
        <label className="faint" style={{ display: 'flex', gap: 7, alignItems: 'center' }}
               title="Ukryj pytania, które mają już swój dzień w kalendarzu">
          <input type="checkbox" checked={onlyUnscheduled} style={{ width: 'auto' }}
                 onChange={(e) => setOnlyUnscheduled(e.target.checked)} />
          tylko spoza kalendarza
        </label>
      </div>

      {err && <div className="alert err">{err}</div>}

      {loading ? (
        <div className="spin">Szukam…</div>
      ) : hits.length === 0 ? (
        <div className="spin">Brak wyników</div>
      ) : (
        <>
          <p className="faint" style={{ marginTop: 0 }}>
            {hits.length < total ? `Pokazane ${hits.length} z ${total} — dopisz słowo, żeby zawęzić.` : `${total} pytań`}
          </p>
          <div className="cand-list">
            {hits.map((c) => (
              <div key={c.id} className="cand">
                <div className="cand-main">
                  <div className="cand-q">{c.pl}</div>
                  <div className="faint">
                    {c.category}
                    {' · '}{c.smaczki_count} smaczki
                    {c.smaczki_untagged > 0 && <> (🎯 {c.smaczki_untagged} bez strony)</>}
                    {' · '}
                    <span className={c.votes >= 5 ? 'warn-num' : ''}>{c.votes} głosów</span>
                    {c.is_favorite && ' · ★'}
                    {c.is_verified && ' · ✓'}
                  </div>
                </div>
                <div className="cand-side">
                  {c.scheduled_on ? (
                    <span className="badge" title="To pytanie ma już swój dzień — zamienią się miejscami">
                      w kalendarzu: {c.scheduled_on}
                    </span>
                  ) : (
                    <span className="badge approved" title="Pytanie spoza kalendarza">wolne</span>
                  )}
                  <button className="btn sm primary" disabled={busy || c.id === row.question_id}
                          onClick={() => onPick(c)}>
                    {c.scheduled_on ? 'Zamień' : 'Wstaw'}
                  </button>
                </div>
              </div>
            ))}
          </div>
        </>
      )}
    </div>
  );
}
