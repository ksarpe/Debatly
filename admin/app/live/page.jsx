'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import { api } from '../../lib/api';

/**
 * Live sales — "cha-ching" dashboard. Polls admin_live_sales() and, when a new
 * MONEY event shows up (real purchase/renewal, not sandbox, not a promo grant),
 * plays a sound and highlights the row.
 *
 * The server returns REAL money only: sandbox receipts, RevenueCat dashboard
 * tests and manual promo grants are filtered out of the feed and never touch
 * the counters. "Podgląd testowych" re-fetches with p_include_test = true —
 * the rows come back flagged, for debugging only.
 */

const POLL_MS = 20_000;

const MONEY_TYPES = new Set(['INITIAL_PURCHASE', 'NON_RENEWING_PURCHASE', 'RENEWAL']);

const TYPE_META = {
  INITIAL_PURCHASE:      { label: '💰 Nowa subskrypcja', cls: 'approved' },
  NON_RENEWING_PURCHASE: { label: '💎 Lifetime',          cls: 'approved' },
  RENEWAL:               { label: '🔄 Odnowienie',        cls: 'pending' },
  UNCANCELLATION:        { label: 'Cofnięte anulowanie',  cls: 'approved' },
  PRODUCT_CHANGE:        { label: 'Zmiana planu',         cls: 'pending' },
  SUBSCRIPTION_EXTENDED: { label: 'Przedłużenie',         cls: 'pending' },
  CANCELLATION:          { label: 'Anulowanie (auto-off)', cls: 'rejected' },
  BILLING_ISSUE:         { label: 'Problem z płatnością', cls: 'rejected' },
  EXPIRATION:            { label: 'Wygaśnięcie',          cls: 'rejected' },
  SUBSCRIPTION_PAUSED:   { label: 'Pauza',                cls: 'rejected' },
  TRANSFER:              { label: 'Transfer konta',       cls: '' },
  TEST:                  { label: 'Test (dashboard)',     cls: 'draft' },
};

const PRODUCT_LABELS = {
  // 'liftime_pro' is the REAL product id in the stores (typo and all).
  liftime_pro: 'Lifetime 69,99 zł',
  monthly_pro: 'Miesięczna',
};

const nf = new Intl.NumberFormat('pl-PL');

const isPromo = (e) => (e.product_id || '').startsWith('rc_promo');
// is_test is the server's whole verdict (sandbox + promo + tester-account
// membership); the two extra checks are belt-and-braces for old cached rows.
// Without it, "Pokaż testowe" + sound rings the bell for PRODUCTION-flagged
// rows of sandbox users — test debris dinging like real money.
const isMoney = (e) => MONEY_TYPES.has(e.type) && !e.is_test && !e.is_sandbox && !isPromo(e);

/** Short E6→G6→C7 arpeggio via WebAudio — no asset file, works offline. */
let audioCtx = null;
function playChaChing() {
  try {
    audioCtx = audioCtx || new (window.AudioContext || window.webkitAudioContext)();
    const ctx = audioCtx;
    if (ctx.state === 'suspended') ctx.resume();
    const t0 = ctx.currentTime + 0.02;
    [[1318.5, 0], [1568.0, 0.09], [2093.0, 0.18]].forEach(([freq, dt]) => {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = 'triangle';
      osc.frequency.value = freq;
      gain.gain.setValueAtTime(0.0001, t0 + dt);
      gain.gain.exponentialRampToValueAtTime(0.35, t0 + dt + 0.012);
      gain.gain.exponentialRampToValueAtTime(0.0001, t0 + dt + 0.6);
      osc.connect(gain).connect(ctx.destination);
      osc.start(t0 + dt);
      osc.stop(t0 + dt + 0.65);
    });
  } catch { /* no audio = no drama */ }
}

export default function LivePage() {
  const [data, setData] = useState(null);
  const [err, setErr] = useState(null);
  const [soundOn, setSoundOn] = useState(false);
  const [showTest, setShowTest] = useState(false);
  const [freshIds, setFreshIds] = useState(() => new Set());
  const [lastPing, setLastPing] = useState(null); // the newest money event that dinged

  // Known money-event ids; null until the first successful load (baseline —
  // nothing that existed before the page opened should ring the bell).
  const knownIds = useRef(null);
  const soundOnRef = useRef(false);
  const showTestRef = useRef(false);

  useEffect(() => {
    setSoundOn(localStorage.getItem('live_sound') === '1');
    setShowTest(localStorage.getItem('live_show_test') === '1');
  }, []);
  useEffect(() => { soundOnRef.current = soundOn; }, [soundOn]);
  useEffect(() => { showTestRef.current = showTest; }, [showTest]);

  const load = useCallback(async () => {
    try {
      const d = await api.liveSales(showTestRef.current);
      setErr(null);
      const money = (d.events || []).filter(isMoney);
      if (knownIds.current === null) {
        knownIds.current = new Set(money.map((e) => e.id));
      } else {
        const fresh = money.filter((e) => !knownIds.current.has(e.id));
        if (fresh.length > 0) {
          fresh.forEach((e) => knownIds.current.add(e.id));
          setFreshIds((prev) => new Set([...prev, ...fresh.map((e) => e.id)]));
          setLastPing(fresh[0]);
          if (soundOnRef.current) playChaChing();
        }
      }
      setData(d);
    } catch (e) {
      setErr(e.friendly || e.message);
    }
  }, []);

  useEffect(() => {
    load();
    const t = setInterval(load, POLL_MS);
    const onFocus = () => load();
    window.addEventListener('focus', onFocus);
    return () => { clearInterval(t); window.removeEventListener('focus', onFocus); };
  }, [load]);

  function toggleTest() {
    const next = !showTest;
    setShowTest(next);
    showTestRef.current = next;
    localStorage.setItem('live_show_test', next ? '1' : '0');
    load();
  }

  function toggleSound() {
    const next = !soundOn;
    setSoundOn(next);
    localStorage.setItem('live_sound', next ? '1' : '0');
    // Enabling counts as the user gesture that unlocks audio — and doubles
    // as the sound test.
    if (next) playChaChing();
  }

  const c = data?.counters;

  return (
    <>
      <h1 className="page-title">Live 💰</h1>
      <p className="page-sub">
        Sprzedaże i odnowienia na żywo (webhook RevenueCat → billing_events).
        Odświeża się co {POLL_MS / 1000} s. Tylko prawdziwe pieniądze — sandbox,
        testy z dashboardu i ręczne granty promo są odfiltrowane.
        {data && <> Stan z: {new Date(data.generated_at).toLocaleTimeString('pl-PL')}.</>}
      </p>

      <div className="toolbar">
        <button className={`btn sm ${soundOn ? 'primary' : ''}`} onClick={toggleSound}>
          {soundOn ? '🔔 Dźwięk włączony' : '🔕 Dźwięk wyłączony'}
        </button>
        <button className={`btn sm ${showTest ? 'primary' : ''}`} onClick={toggleTest}>
          {showTest ? '🧪 Testowe widoczne' : '🧪 Pokaż testowe'}
        </button>
        <span className="faint">
          włączenie dźwięku od razu gra próbkę — zostaw kartę otwartą, przy nowym zakupie zadzwoni
        </span>
      </div>

      {err && <div className="alert err">{err}</div>}
      {!data && !err && <div className="spin">Ładowanie…</div>}

      {lastPing && (
        <div className="alert ok">
          💰 {TYPE_META[lastPing.type]?.label || lastPing.type}:{' '}
          {productLabel(lastPing)} {money(lastPing)} —{' '}
          {new Date(lastPing.received_at).toLocaleTimeString('pl-PL')}
        </div>
      )}

      {data && (
        <>
          <div className="stat-grid">
            <Tile label="Aktywne subskrypcje" value={nf.format(c.active_subs)}
                  note={`${nf.format(c.will_renew)} z auto-odnowieniem`
                        + (c.cancelling ? ` · ${nf.format(c.cancelling)} po anulowaniu` : '')
                        + (c.promo_grants ? ` · ${nf.format(c.promo_grants)} grantów promo (nieliczone)` : '')} />
            <Tile label="Sprzedaże dziś" value={nf.format(c.sales_today)}
                  note={`+ ${nf.format(c.renewals_today)} odnowień · doba wg Warszawy`} />
            <Tile label="Sprzedaże 7 dni" value={nf.format(c.sales_7d)} />
            <Tile label="Sprzedaże 30 dni" value={nf.format(c.sales_30d)}
                  note={`+ ${nf.format(c.renewals_30d)} odnowień`} />
            <Tile label="Sprzedaże łącznie" value={nf.format(c.sales_total)}
                  note="nowe suby + lifetime, bez odnowień" />
          </div>

          <div className="card">
            <h3>Przychód (ceny ze sklepu, bez przeliczeń walut i prowizji)</h3>
            {data.revenue.length === 0 && <p className="muted">Jeszcze nic — będzie 💪</p>}
            {data.revenue.length > 0 && (
              <table className="stats-table">
                <thead>
                  <tr><th>Waluta</th><th className="num">Dziś</th><th className="num">30 dni</th></tr>
                </thead>
                <tbody>
                  {data.revenue.map((r) => (
                    <tr key={r.currency}>
                      <td>{r.currency}</td>
                      <td className="num">{amount(r.total_today)}</td>
                      <td className="num">{amount(r.total_30d)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>

          <div className="card">
            <h3>
              Ostatnie zdarzenia ({data.events.length})
              {!showTest && data.hidden_test > 0 && (
                <span className="faint" style={{ marginLeft: 8, fontWeight: 400 }}>
                  ukryto {data.hidden_test} testowych
                </span>
              )}
            </h3>
            <div className="tbl-scroll">
              <table className="stats-table">
                <thead>
                  <tr>
                    <th>Kiedy</th><th>Zdarzenie</th><th>Produkt</th>
                    <th className="num">Kwota</th><th>Kraj</th><th>Sklep</th><th>Konto</th>
                  </tr>
                </thead>
                <tbody>
                  {data.events.length === 0 && (
                    <tr><td colSpan={7} className="muted">
                      {!showTest && data.hidden_test > 0
                        ? 'Cisza — żadnych prawdziwych zdarzeń (same testowe)'
                        : 'Cisza — jeszcze żadnych zdarzeń'}
                    </td></tr>
                  )}
                  {data.events.map((e) => {
                    const meta = TYPE_META[e.type] || { label: e.type, cls: '' };
                    return (
                      <tr key={e.id} style={freshIds.has(e.id)
                        ? { background: 'color-mix(in srgb, var(--ok) 12%, transparent)' }
                        : undefined}>
                        <td className="muted">{when(e.received_at)}</td>
                        <td>
                          <span className={`badge ${meta.cls}`}>{meta.label}</span>
                          {e.is_sandbox && <span className="badge draft" style={{ marginLeft: 6 }}>sandbox</span>}
                          {isPromo(e) && <span className="badge draft" style={{ marginLeft: 6 }}>promo</span>}
                          {e.is_test && !e.is_sandbox && !isPromo(e) && (
                            /* flagged only via tester-account membership — without
                               a badge these rows are indistinguishable from money */
                            <span className="badge draft" style={{ marginLeft: 6 }}>test</span>
                          )}
                        </td>
                        <td>{productLabel(e)}</td>
                        <td className={`num ${isMoney(e) && e.price > 0 ? 'ok-cell' : ''}`}>{money(e)}</td>
                        <td>{e.country || '—'}</td>
                        <td className="muted">{store(e.store)}</td>
                        <td>
                          {e.user_id
                            ? <Link href={`/users?u=${e.user_id}`}
                                    title="historia konta — grał wcześniej czy kupił od razu?">
                                <code className="uid">{e.user_id.slice(0, 8)}</code>
                              </Link>
                            : '—'}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
            <p className="faint" style={{ marginBottom: 0 }}>
              {showTest
                ? '„Sandbox” = zakup testowy ze sklepu, „promo” = grant z dashboardu RevenueCat — '
                  + 'widoczne tylko w tym podglądzie, nieliczone w kafelkach i bez dźwięku.'
                : 'Widać wyłącznie prawdziwe zakupy, odnowienia i anulowania. Sandbox, testy '
                  + 'z dashboardu i ręczne granty promo są ukryte — „Pokaż testowe”, żeby zajrzeć. '
                  + 'Kliknij konto, żeby zobaczyć, co robiło przed zakupem.'}
            </p>
          </div>
        </>
      )}
    </>
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

function productLabel(e) {
  if (!e.product_id) return '—';
  if (isPromo(e)) {
    return e.product_id.includes('lifetime') ? 'Promo: lifetime' : 'Promo: miesiąc';
  }
  const base = e.product_id.split(':')[0];
  return PRODUCT_LABELS[base] || e.product_id;
}

function money(e) {
  if (e.price == null) return '—';
  if (e.price === 0) return '0';
  return `${nf.format(e.price)} ${e.currency || ''}`.trim();
}

function amount(v) {
  return v == null ? '—' : nf.format(v);
}

function store(s) {
  if (!s) return '—';
  return { PLAY_STORE: 'Google Play', APP_STORE: 'App Store', PROMOTIONAL: 'RC promo' }[s] || s;
}

function when(iso) {
  const d = new Date(iso);
  const today = new Date().toDateString() === d.toDateString();
  return today
    ? d.toLocaleTimeString('pl-PL', { hour: '2-digit', minute: '2-digit' })
    : d.toLocaleString('pl-PL', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
}
