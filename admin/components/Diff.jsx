'use client';

import { wordDiff, isChanged } from '../lib/wordDiff';
import { SIDES } from '../lib/api';

/** Human label for `question_smaczki.side`, so the diff reads as words. */
const sideLabel = (v) => SIDES.find((o) => o.value === v)?.label ?? 'nie ustawiono';

/**
 * Shows ONLY what changed, with the change highlighted in place:
 * removed words struck through in red, added words in green.
 * Unchanged fields are collapsed into a one-line note so the reviewer's eye
 * goes straight to the edit.
 */
export default function Diff({ before, after }) {
  if (!before && !after) return null;

  // Whole-question delete
  if (after === null) {
    return (
      <div className="alert err" style={{ marginBottom: 0 }}>
        <b>Usunięcie pytania.</b> Zniknie ze smaczkami, tłumaczeniami i oddanymi głosami.
        <div style={{ marginTop: 6 }}><del>{before?.pl}</del></div>
      </div>
    );
  }

  const rows = [];
  rows.push({ label: 'Pytanie PL', a: before?.pl, b: after.pl });
  rows.push({ label: 'Pytanie EN', a: before?.en, b: after.en });

  const sa = before?.smaczki ?? [];
  const sb = after?.smaczki ?? [];
  const max = Math.max(sa.length, sb.length);
  for (let i = 0; i < max; i++) {
    rows.push({ label: `Smaczek ${i + 1} PL`, a: sa[i]?.pl, b: sb[i]?.pl });
    rows.push({ label: `Smaczek ${i + 1} EN`, a: sa[i]?.en, b: sb[i]?.en });
    rows.push({
      label: `Smaczek ${i + 1} strona`,
      a: sa[i] ? sideLabel(sa[i].side) : undefined,
      b: sb[i] ? sideLabel(sb[i].side) : undefined,
    });
  }

  const changed = rows.filter((r) => isChanged(r.a, r.b));
  const sameCount = rows.length - changed.length;

  if (!before) {
    // brand new question — nothing to compare against
    return (
      <div>
        <div className="faint" style={{ marginBottom: 8 }}>Nowe pytanie — cała treść jest nowa.</div>
        {rows.filter((r) => (r.b ?? '').trim() !== '').map((r) => (
          <div className="drow" key={r.label}>
            <span className="dlabel">{r.label}</span>
            <span className="d-ins">{r.b}</span>
          </div>
        ))}
      </div>
    );
  }

  if (changed.length === 0) {
    return <div className="faint">Brak zmian względem wersji na produkcji.</div>;
  }

  return (
    <div>
      {changed.map((r) => (
        <div className="drow" key={r.label}>
          <span className="dlabel">{r.label}</span>
          <span className="dtext">
            {wordDiff(r.a, r.b).map((p, i) =>
              p.type === 'same' ? (
                <span key={i}>{p.text}</span>
              ) : p.type === 'del' ? (
                <del className="d-del" key={i}>{p.text}</del>
              ) : (
                <ins className="d-ins" key={i}>{p.text}</ins>
              )
            )}
          </span>
        </div>
      ))}
      {sameCount > 0 && (
        <div className="faint" style={{ marginTop: 8 }}>
          + {sameCount} {sameCount === 1 ? 'pole' : 'pól'} bez zmian
        </div>
      )}
      <div className="dlegend">
        <span className="d-del">usunięte</span>
        <span className="d-ins">dodane</span>
      </div>
    </div>
  );
}
