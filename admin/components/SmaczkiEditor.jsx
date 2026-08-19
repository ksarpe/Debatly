'use client';

import Counter from './Counter';
import { LIMITS, SIDES } from '../lib/api';

/**
 * Compact editor: one row per smaczek, PL above EN with the language flag inline
 * on the left, so a 3-smaczek question fits on screen without scrolling.
 * The DB renumbers to 1..N on save.
 *
 * Each row also carries its SIDE — which answer the argument attacks. That is
 * what the app serves on: after a vote it shows the smaczek aimed at the side
 * the user actually picked, and for a free user that one is the readable one.
 * An untagged row (side = null) is served as if neutral, so nothing breaks —
 * it just stops being personal, which is the whole point of the tag.
 */
export default function SmaczkiEditor({ items, onChange, disabled = false }) {
  const set = (i, key, val) =>
    onChange(items.map((s, idx) => (idx === i ? { ...s, [key]: val } : s)));
  const add = () => onChange([...items, { pl: '', en: '', side: null }]);
  const remove = (i) => onChange(items.filter((_, idx) => idx !== i));
  const move = (i, dir) => {
    const j = i + dir;
    if (j < 0 || j >= items.length) return;
    const next = [...items];
    [next[i], next[j]] = [next[j], next[i]];
    onChange(next);
  };

  const untagged = items.filter((s) => (s.pl ?? '').trim() !== '' && !s.side).length;

  return (
    <div className="card">
      <div className="toolbar" style={{ marginBottom: 10 }}>
        <h3 style={{ margin: 0 }}>Smaczki</h3>
        <span className="faint">
          serwowane pod głos użytkownika — darmowy jest ten, który go atakuje
        </span>
        {untagged > 0 && (
          <span className="badge enreview" title="Nieotagowany smaczek trafia do wszystkich tak samo — bez strony argument przestaje być osobisty">
            bez strony: {untagged}
          </span>
        )}
        <div style={{ flex: 1 }} />
        {!disabled && <button type="button" className="btn sm" onClick={add}>+ Dodaj</button>}
      </div>

      {items.length === 0 && <div className="faint">Brak smaczków.</div>}

      {items.map((s, i) => (
        <div className={`sm-row${s.side ? '' : ' untagged'}`} key={i}>
          <div className="sm-num" title={`pozycja ${i + 1}`}>{i + 1}</div>

          <div className="sm-fields">
            <div className="fx">
              <span className="flag" title="polski">🇵🇱</span>
              <input type="text" value={s.pl ?? ''} disabled={disabled}
                     placeholder="treść smaczka"
                     onChange={(e) => set(i, 'pl', e.target.value)} />
              <Counter value={s.pl} limit={LIMITS.smaczek} />
            </div>
            <div className="fx">
              <span className="flag" title="angielski">🇬🇧</span>
              <input type="text" value={s.en ?? ''} disabled={disabled}
                     placeholder="tłumaczenie"
                     onChange={(e) => set(i, 'en', e.target.value)} />
              <Counter value={s.en} limit={LIMITS.smaczek} />
            </div>
            <div className="fx">
              <span className="flag" title="kogo ten argument atakuje">🎯</span>
              <select value={s.side ?? ''} disabled={disabled} style={{ width: 'auto' }}
                      onChange={(e) => set(i, 'side', e.target.value === '' ? null : e.target.value)}>
                <option value="">— nie ustawiono —</option>
                {SIDES.map((o) => (
                  <option key={o.value} value={o.value}>{o.label}</option>
                ))}
              </select>
              <span className="faint" style={{ fontSize: 12 }}>
                {SIDES.find((o) => o.value === s.side)?.hint ?? 'trafia do wszystkich tak samo'}
              </span>
            </div>
          </div>

          {!disabled && (
            <div className="sm-acts">
              <button type="button" title="w górę" onClick={() => move(i, -1)} disabled={i === 0}>↑</button>
              <button type="button" title="w dół" onClick={() => move(i, 1)} disabled={i === items.length - 1}>↓</button>
              <button type="button" className="x" title="usuń" onClick={() => remove(i)}>✕</button>
            </div>
          )}
        </div>
      ))}
    </div>
  );
}
