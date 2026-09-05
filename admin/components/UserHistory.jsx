'use client';

import { useCallback, useEffect, useState } from 'react';
import { api } from '../lib/api';

/**
 * One account's story — "who just bought?". Takes a full UUID or the 8-char
 * prefix the Live page and the Telegram ping show, calls
 * admin_user_history() and splits the answer at the first real purchase:
 * what the account did BEFORE the money (the question the owner asks when a
 * ping lands) and what it looks like now. Read-only.
 *
 * `initial` is looked up on mount (the /users page feeds it from ?u=);
 * `onLookup` fires with the query so the page can mirror it in the URL.
 */

const nf = new Intl.NumberFormat('pl-PL');

const PRODUCT_LABELS = {
  liftime_pro: 'Lifetime',
  lifetime:    'Lifetime',
  monthly_pro: 'Miesięczna',
};

const STORES = { PLAY_STORE: 'Google Play', APP_STORE: 'App Store', PROMOTIONAL: 'RC promo' };

const EVENT_LABELS = {
  onboarding_started:        'onboarding start',
  onboarding_taste_shown:    'onboarding: pytanie testowe',
  onboarding_taste_voted:    'onboarding: odpowiedź',
  onboarding_taste_revoted:  'onboarding: zmiana odpowiedzi',
  onboarding_q_shown:        'onboarding: pytanie',
  onboarding_q_voted:        'onboarding: odpowiedź',
  onboarding_finished:       'onboarding koniec',
  onboarding_completed:      'onboarding ukończony',
  onboarding_skipped:        'onboarding pominięty',
  bridge_shown:              'most (bridge)',
  bridge_cta_primary:        'most: „Zacznij za darmo”',
  bridge_cta_secondary:      'most: CTA PRO',
  daily_vote_cast:           '🗳 głos (pytanie dnia)',
  daily_question_voted:      '🗳 głos (pytanie dnia)',
  question_vote_cast:        '🗳 głos',
  smaczek_challenge:         'brama (argument)',
  smaczek_challenge_skipped: 'brama pominięta',
  smaczki_sheet_opened:      'arkusz argumentów',
  wall_reached:              '🧱 ściana dnia',
  wall_link_tapped:          'ściana: link',
  wall_notify_shown:         'ściana: prośba o przypomnienie',
  wall_notify_enabled:       '🔔 przypomnienia włączone',
  wall_notify_declined:      'przypomnienia odrzucone',
  onboarding_notify_shown:   'prośba o przypomnienie',
  onboarding_notify_enabled: '🔔 przypomnienia włączone',
  onboarding_notify_declined:'przypomnienia odrzucone',
  reminder_scheduled:        'przypomnienie zaplanowane',
  paywall_shown:             '💳 paywall',
  paywall_dismissed:         'paywall zamknięty',
  paywall_plan_selected:     'paywall: wybór planu',
  paywall_purchase_started:  'paywall: start zakupu',
  paywall_purchase_abandoned:'paywall: zakup przerwany',
  paywall_purchase_failed:   'paywall: zakup nieudany',
  paywall_purchased:         '💰 ZAKUP',
  purchase_completed:        '💰 zakup potwierdzony',
  paywall_offer_shown:       'paywall: oferta',
  paywall_offer_unavailable: 'paywall: brak oferty',
  conformity_panel_opened:   'panel konformizmu',
  share_card_opened:         'karta share',
  review_prompt_requested:   'prośba o ocenę',
  install_attributed:        'instalacja (atrybucja)',
  modes_opened:              'tryby otwarte',
  mode_tile_tapped:          'tryb: kafelek',
  mode_selected:             'tryb wybrany',
  mode_cleared:              'tryb wyłączony',
  modes_hint_tapped:         'tryby: link',
  modes_showcase_shown:      'tryby: showcase',
  modes_showcase_closed:     'tryby: showcase zamknięty',
};

const fmtDate = (iso) => (iso ? new Date(iso).toLocaleDateString('pl-PL', { day: 'numeric', month: 'short' }) : '—');
const fmtDateTime = (iso) => (iso
  ? new Date(iso).toLocaleString('pl-PL', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })
  : '—');
const fmtTime = (iso) => (iso ? new Date(iso).toLocaleTimeString('pl-PL', { hour: '2-digit', minute: '2-digit', second: '2-digit' }) : '—');

function ago(minutes) {
  if (minutes == null) return '?';
  if (minutes < 1) return 'mniej niż minutę';
  if (minutes < 60) return `${Math.round(minutes)} min`;
  if (minutes < 48 * 60) return `${Math.round(minutes / 60)} h`;
  return `${Math.round(minutes / 1440)} dni`;
}

function productLabel(id) {
  if (!id) return '—';
  const base = id.split(':')[0];
  return PRODUCT_LABELS[base] || id;
}

export default function UserHistory({ initial = '', onLookup }) {
  const [query, setQuery] = useState(initial);
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState(null);

  const lookup = useCallback(async (q) => {
    const trimmed = (q || '').trim();
    if (!trimmed) return;
    setLoading(true);
    setErr(null);
    onLookup?.(trimmed);
    try {
      setData(await api.userHistory(trimmed));
    } catch (e) {
      setErr(e.friendly || e.message);
      setData(null);
    } finally {
      setLoading(false);
    }
  }, [onLookup]);

  useEffect(() => {
    if (initial) {
      setQuery(initial);
      lookup(initial);
    }
  }, [initial, lookup]);

  return (
    <div className="card">
      <h3>Sprawdź konto <span className="faint">(kto właśnie kupił?)</span></h3>
      <form className="toolbar" style={{ marginBottom: 10 }}
            onSubmit={(e) => { e.preventDefault(); lookup(query); }}>
        <input type="text" value={query} onChange={(e) => setQuery(e.target.value)}
               placeholder="UUID konta albo pierwsze 8 znaków (jak w Live / Telegramie)"
               style={{ flex: 1, minWidth: 260, fontFamily: 'ui-monospace, monospace' }} />
        <button className="btn sm primary" type="submit" disabled={loading || !query.trim()}>
          {loading ? '…' : 'Sprawdź'}
        </button>
      </form>

      {err && <div className="alert err">{err}</div>}

      {data && !data.found && (
        <div className="alert info">
          {data.too_short && 'Wpisz co najmniej 6 znaków identyfikatora.'}
          {data.ambiguous && `Ten prefiks pasuje do ${data.ambiguous} kont — wpisz więcej znaków.`}
          {!data.too_short && !data.ambiguous && 'Nie ma takiego konta.'}
        </div>
      )}

      {data?.found && <Story d={data} />}
    </div>
  );
}

function Story({ d }) {
  const a = d.account;
  const p = d.purchase;
  const b = d.before;
  const t = d.totals;
  const bought = !!p?.purchased_at;
  const isNew = bought && (b?.active_days ?? 0) <= 1;
  const votesAfter = bought ? t.votes - (b?.votes ?? 0) : null;

  return (
    <>
      <div className={`alert ${bought ? 'ok' : 'info'}`} style={{ marginBottom: 12 }}>
        {!bought && (
          <>
            <b>Bez zakupu</b> — konto {p?.tier === 'granted' ? 'PRO z grantu' : 'free'}.{' '}
            {nf.format(t.votes)} głosów w {nf.format(t.active_days)} dni w apce, streak {nf.format(t.live_streak)}
            {t.paywall_shown > 0 && <>, paywall {nf.format(t.paywall_shown)}×</>}.
            {' '}Pierwsze uruchomienie {fmtDateTime(t.first_seen_at)}.
          </>
        )}
        {bought && isNew && (
          <>
            🆕 <b>Nowy klient</b> — kupił <b>{ago(b.minutes_to_purchase)}</b> po pierwszym uruchomieniu
            ({fmtDateTime(t.first_seen_at)}), {nf.format(b.votes)} {b.votes === 1 ? 'głos' : 'głosów'} wcześniej
            {b.onboarding_finished ? ', po onboardingu' : ', bez ukończonego onboardingu'}.
            {' '}Chciał mieć wszystko od razu.
          </>
        )}
        {bought && !isNew && (
          <>
            🎮 <b>Grał wcześniej</b> — <b>{nf.format(b.active_days)} dni</b> w apce przed zakupem
            (od {fmtDate(t.first_seen_at)}), <b>{nf.format(b.votes)} głosów</b>, streak {nf.format(b.streak_at_purchase)} w dniu
            zakupu, paywall widział {nf.format(b.paywall_shown)}×
            {b.wall_reached > 0 && <>, ścianę dnia {nf.format(b.wall_reached)}×</>}.
            {' '}Kupił po {ago(b.minutes_to_purchase)} od pierwszego uruchomienia.
          </>
        )}
      </div>

      <div className="stat-grid">
        <Tile label="Konto"
              value={a.has_account ? 'z kontem' : 'anonim'}
              note={<>
                <code className="uid" title={a.user_id}>{a.user_id.slice(0, 8)}</code>
                {a.provider && <> · {a.provider}</>}
                {a.locale && <> · {a.locale}</>}
                <br />założone {fmtDateTime(a.created_at)}
                {t.installs > 1 && <><br /><span className="warn-cell">{t.installs} urządzenia</span></>}
              </>} />
        <Tile label="Zakup"
              value={bought ? productLabel(p.product_id) : (p?.tier === 'granted' ? 'grant' : 'brak')}
              note={bought ? <>
                {p.price != null && <>{nf.format(p.price)} {p.currency} · </>}
                {STORES[p.store] || p.store}{p.country && <> · {p.country}</>}
                <br />{fmtDateTime(p.purchased_at)}
                <br />
                {p.pro_live ? <span className="ok-cell">PRO aktywne</span> : <span className="warn-cell">PRO wygasło</span>}
                {p.period_end && <> · do {fmtDate(p.period_end)}</>}
                {p.sub_status === 'CANCELLATION' && <span className="warn-cell"> · anulował auto-odnowienie</span>}
                {p.sub_status !== 'CANCELLATION' && p.will_renew === false && p.period_end && <> · bez odnowienia</>}
                {p.sandbox_events > 0 && <><br /><span className="badge draft">sandbox: {p.sandbox_events}</span></>}
              </> : <>
                paywall {nf.format(t.paywall_shown)}× · ściana {nf.format(t.wall_reached)}×
                {p?.tier === 'granted' && <><br />PRO z grantu (promo / tester)</>}
              </>} />
        {bought && (
          <Tile label="Przed zakupem"
                value={`${nf.format(b.votes)} głosów`}
                note={<>
                  {nf.format(b.active_days)} dni · {nf.format(b.vote_days)} dni z głosem · streak {nf.format(b.streak_at_purchase)}
                  <br />bramy {nf.format(b.gates_answered)} (ruszyło {nf.format(b.gates_moved)})
                  <br />paywall {nf.format(b.paywall_shown)}× · zamknął {nf.format(b.paywall_dismissed)}×
                  {b.purchase_abandoned > 0 && <> · przerwał zakup {nf.format(b.purchase_abandoned)}×</>}
                  {b.last_paywall_source && <><br />ostatni paywall: {b.last_paywall_source}</>}
                </>} />
        )}
        <Tile label={bought ? 'Po zakupie / teraz' : 'Aktywność'}
              value={bought ? `${nf.format(votesAfter)} głosów` : `${nf.format(t.votes)} głosów`}
              note={<>
                {bought && <>łącznie {nf.format(t.votes)} · </>}
                {nf.format(t.active_days)} dni w apce
                <br />streak {nf.format(t.live_streak)}
                {t.rank_name && <> ({t.rank_name})</>}
                {t.streak_alive ? <span className="ok-cell"> · żywy</span> : <span className="warn-cell"> · zgasł</span>}
                {' '}· rekord {nf.format(t.longest_streak)}
                <br />bramy: trzymał {nf.format(t.gates_held)} · ruszyło {nf.format(t.gates_moved)}
                {t.gates_fast > 0 && <> · za szybko {nf.format(t.gates_fast)}</>}
                <br />ostatnio {fmtDateTime(t.last_seen_at)}
                {t.reminder_enabled && <> · 🔔 przypomnienia</>}
                {t.favorites > 0 && <> · ⭐ {nf.format(t.favorites)}</>}
              </>} />
      </div>

      <h3 style={{ marginTop: 6 }}>Dzień po dniu <span className="faint">(doba Europe/Warsaw, najnowsze na górze)</span></h3>
      <div className="tbl-scroll">
        <table className="stats-table">
          <thead>
            <tr>
              <th>Dzień</th><th></th>
              <th className="num">Zdarzenia</th><th className="num">Głosy</th>
              <th className="num">Bramy</th><th className="num">Paywall</th><th className="num">Ściana</th>
            </tr>
          </thead>
          <tbody>
            {d.days.length === 0 && <tr><td colSpan={7} className="muted">Brak zdarzeń</td></tr>}
            {d.days.map((r) => (
              <tr key={r.day} style={r.purchased
                ? { background: 'color-mix(in srgb, var(--ok) 12%, transparent)' }
                : undefined}>
                <td>{new Date(r.day).toLocaleDateString('pl-PL', { weekday: 'short', day: 'numeric', month: 'short' })}</td>
                <td className="muted">
                  {r.purchased && '💰 zakup'}
                  {!r.purchased && bought && (r.before_purchase ? 'przed' : 'PRO')}
                </td>
                <td className="num">{nf.format(r.events)}</td>
                <td className={`num ${r.votes > 0 ? 'ok-cell' : ''}`}>{r.votes || '—'}</td>
                <td className="num">{r.gates ? <>{r.gates}{r.moved > 0 && <span className="faint"> (ruszyło {r.moved})</span>}</> : '—'}</td>
                <td className="num">{r.paywall_shown || '—'}</td>
                <td className="num">{r.wall_reached || '—'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <details style={{ marginTop: 12 }}>
        <summary className="faint" style={{ cursor: 'pointer' }}>
          Ostatnie zdarzenia ({d.recent.length}{d.recent.length === 80 ? ', ucięte do 80' : ''})
        </summary>
        <div className="tbl-scroll">
          <table className="stats-table">
            <thead><tr><th>Kiedy</th><th>Zdarzenie</th><th>Szczegóły</th></tr></thead>
            <tbody>
              {d.recent.map((e, i) => {
                const day = new Date(e.at);
                const prev = i > 0 ? new Date(d.recent[i - 1].at) : null;
                const newDay = !prev || prev.toDateString() !== day.toDateString();
                return (
                  <tr key={`${e.at}-${i}`}>
                    <td className="muted" style={{ whiteSpace: 'nowrap' }}>
                      {newDay ? fmtDate(e.at) + ' ' : ''}{fmtTime(e.at)}
                    </td>
                    <td>{EVENT_LABELS[e.event] || e.event}</td>
                    <td className="faint">
                      {[e.source && `source: ${e.source}`,
                        e.trigger && `trigger: ${e.trigger}`,
                        e.outcome && `wynik: ${e.outcome}`,
                        e.plan && `plan: ${e.plan}`,
                        e.day_number != null && `dzień ${e.day_number}`,
                        e.status && `status: ${e.status}`,
                        e.utm_source && `utm: ${e.utm_source}`,
                      ].filter(Boolean).join(' · ')}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </details>

      <p className="faint" style={{ margin: '10px 0 0' }}>
        „Nowy” = zakup w pierwszym dniu, w którym konto pojawiło się w apce. „Grał wcześniej” = co najmniej
        drugi dzień. Streak w dniu zakupu = ciąg kolejnych dób UTC z głosem do dnia zakupu włącznie.
        Stan z {new Date(d.generated_at).toLocaleTimeString('pl-PL')}.
      </p>
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
