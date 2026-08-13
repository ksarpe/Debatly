'use client';

import Counter from './Counter';
import { LIMITS } from '../lib/api';

/**
 * Compact editor: one row per smaczek, PL above EN with the language flag inline
 * on the left, so a 3-smaczek question fits on screen without scrolling.
 * Position 1 is the free teaser (highlighted); the DB renumbers to 1..N on save.
 */
export default function SmaczkiEditor({ items, onChange, disabled = false }) {
  const set = (i, key, val) =>
    onChange(items.map((s, idx) => (idx === i ? { ...s, [key]: val } : s)));
  const add = () => onChange([...items, { pl: '', en: '' }]);
  const remove = (i) => onChange(items.filter((_, idx) => idx !== i));
  const move = (i, dir) => {
    const j = i + dir;
    if (j < 0 || j >= items.length) return;
    const next = [...items];
    [next[i], next[j]] = [next[j], next[i]];
    onChange(next);
  };

  return (
    <div className="card">
      <div className="toolbar" style={{ marginBottom: 10 }}>
        <h3 style={{ margin: 0 }}>Smaczki</h3>
        <span className="faint">1 = darmowy, reszta PRO</span>
        <div style={{ flex: 1 }} />
        {!disabled && <button type="button" className="btn sm" onClick={add}>+ Dodaj</button>}
      </div>

      {items.length === 0 && <div className="faint">Brak smaczków.</div>}

      {items.map((s, i) => (
        <div className={`sm-row${i === 0 ? ' free' : ''}`} key={i}>
          <div className="sm-num" title={i === 0 ? 'darmowy teaser' : 'tylko PRO'}>{i + 1}</div>

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
