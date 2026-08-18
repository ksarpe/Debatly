'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { api } from '../../lib/api';

/**
 * Live sales — "cha-ching" dashboard. Polls admin_live_sales() and, when a new
 * MONEY event shows up (real purchase/renewal, not sandbox, not a promo grant),
 * plays a sound and highlights the row. Counters exclude sandbox + promo on the
 * server; the feed shows everything, flagged.
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
const isMoney = (e) => MONEY_TYPES.has(e.type) && !e.is_sandbox && !isPromo(e);

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
  const [freshIds, setFreshIds] = useState(() => new Set());
  const [lastPing, setLastPing] = useState(null); // the newest money event that dinged

  // Known money-event ids; null until the first successful load (baseline —
  // nothing that existed before the page opened should ring the bell).
  const knownIds = useRef(null);
  const soundOnRef = useRef(false);

  useEffect(() => {
    setSoundOn(localStorage.getItem('live_sound') === '1');
  }, []);
  useEffect(() => { soundOnRef.current = soundOn; }, [soundOn]);

  const load = useCallback(async () => {
    try {
      const d = await api.liveSales();
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
        Odświeża się co {POLL_MS / 1000} s; liczniki pomijają sandbox i granty promo.
        {data && <> Stan z: {new Date(data.generated_at).toLocaleTimeString('pl-PL')}.</>}
      </p>

      <div className="toolbar">
        <button className={`btn sm ${soundOn ? 'primary' : ''}`} onClick={toggleSound}>
          {soundOn ? '🔔 Dźwięk włączony' : '🔕 Dźwięk wyłączony'}
        </button>
        <span className="faint">
          włączenie od razu gra próbkę — zostaw kartę otwartą, przy nowym zakupie zadzwoni
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
                  note={`${nf.format(c.will_renew)} z włączonym auto-odnowieniem`} />
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
            <h3>Ostatnie zdarzenia ({data.events.length})</h3>
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
                    <tr><td colSpan={7} className="muted">Cisza — jeszcze żadnych zdarzeń</td></tr>
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
                        </td>
                        <td>{productLabel(e)}</td>
                        <td className={`num ${isMoney(e) && e.price > 0 ? 'ok-cell' : ''}`}>{money(e)}</td>
                        <td>{e.country || '—'}</td>
                        <td className="muted">{store(e.store)}</td>
                        <td>{e.user_id ? <code className="uid">{e.user_id.slice(0, 8)}</code> : '—'}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
            <p className="faint" style={{ marginBottom: 0 }}>
              „Sandbox" = zakup testowy ze sklepu, „promo" = grant z dashboardu RevenueCat —
              oba widoczne tutaj, ale nieliczone w kafelkach i bez dźwięku.
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
