'use client';

import { CATEGORIES, LIMITS, SIDES } from './api';

/**
 * Hurtowa edycja: eksport paczki pytań dla agenta i sparsowanie tego, co agent
 * odeśle. Czysta logika, bez Reacta i bez sieci — używa jej strona /bulk oraz
 * pojedyncze „Wklej" w QuestionEditorze, żeby obie ścieżki rozumiały dokładnie
 * ten sam format.
 *
 * Nic tu nie pisze do bazy. Zapis idzie zwykłym flow draft → submit → approve,
 * jedno pytanie na raz, więc hurt nie omija ani strażnika konfliktów, ani
 * audytu, ani flagi „EN do weryfikacji" (liczy ją serwer, gdy payload nie
 * niesie klucza `en_review` — dlatego go tu NIE ustawiamy).
 */

const SIDE_VALUES = SIDES.map((o) => o.value);
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Goły JSON z tego, w co agent go opakował (płot ```json, zdanie obok). */
export function extractJson(text) {
  let t = String(text ?? '').trim();
  const fence = t.match(/```(?:json)?\s*([\s\S]*?)```/i);
  if (fence) t = fence[1].trim();
  if (t.startsWith('{') || t.startsWith('[')) return t;
  const starts = [t.indexOf('{'), t.indexOf('[')].filter((i) => i >= 0);
  if (starts.length === 0) return t;
  const from = Math.min(...starts);
  const close = t[from] === '{' ? '}' : ']';
  const to = t.lastIndexOf(close);
  return to > from ? t.slice(from, to + 1) : t.slice(from);
}

/**
 * Tag smaczka: kanonicznie „side", alias „type". Brak klucza = zostaje obecny
 * tag, jawny null/"" = zdejmij, nieznana wartość = twardy błąd. Baza zapisałaby
 * literówkę jako NULL i nikt by nie zauważył, że tagowanie nie zadziałało.
 */
export function readSide(src, current, label) {
  const key = 'side' in src ? 'side' : ('type' in src ? 'type' : null);
  if (!key) return current ?? null;
  const raw = src[key];
  if (raw === null) return null;
  const v = String(raw).trim().toLowerCase();
  if (v === '' || v === 'null' || v === 'brak') return null;
  if (!SIDE_VALUES.includes(v)) {
    throw new Error(`${label}: nieznana wartość "${key}": "${raw}". `
      + `Dozwolone: ${SIDE_VALUES.join(', ')} albo null.`);
  }
  return v;
}

const ORDER_KEYS = ['position', 'pos', 'n', 'nr', 'index', 'id'];

/** Numer wiersza, jeśli agent go podał — inaczej null (liczy się kolejność). */
function orderKey(s) {
  for (const k of ORDER_KEYS) {
    const v = s[k];
    if (typeof v === 'number' && Number.isInteger(v)) return v;
    if (typeof v === 'string' && /^\d+$/.test(v.trim())) return Number(v);
  }
  return null;
}

const isDrop = (s) => s.delete === true || s.remove === true || s.pl === null;
const strip = ({ pl, en, side }) => ({ pl, en, side });

function patchRow(cur, src, label) {
  if (isDrop(src)) return { _drop: true };
  const c = cur ?? {};
  return {
    pl: typeof src.pl === 'string' ? src.pl : String(c.pl ?? ''),
    en: typeof src.en === 'string' ? src.en : String(c.en ?? ''),
    side: readSide(src, c.side, label),
  };
}

/**
 * Nakłada smaczki z JSON-a na te, które pytanie ma dziś. Dwa tryby, wybierane
 * automatycznie:
 *
 *  - KAŻDY wiersz ma numer (position/n/id) → patch punktowy: wiersz nr 2
 *    trafia w drugi smaczek, a te, o których JSON milczy, zostają nietknięte.
 *    Tego chce przebieg tagujący, który odsyła same `side`.
 *  - choć jeden wiersz bez numeru → liczy się kolejność tablicy, a JSON jest
 *    całą listą (wiersze poza jego długością znikają).
 *
 * Skasowanie wiersza w trybie numerowanym: {"position":3,"delete":true} albo
 * "pl": null.
 */
export function mergeSmaczki(baseRows, patchList, label = 'Smaczek') {
  const base = (baseRows ?? []).map((s) => ({
    pl: s.pl ?? '', en: s.en ?? '', side: s.side ?? null,
  }));
  const patches = (patchList ?? []).map(
    (s) => (s && typeof s === 'object' && !Array.isArray(s) ? s : {}),
  );
  const keys = patches.map(orderKey);
  const keyed = patches.length > 0 && keys.every((k) => k !== null);

  if (!keyed) {
    return patches
      .map((src, i) => patchRow(base[i], src, `${label} ${i + 1}`))
      .filter((s) => !s._drop)
      .map(strip);
  }

  // 0 w numeracji = agent liczył od zera; inaczej pozycje są 1..N jak w bazie.
  const zeroBased = keys.some((k) => k === 0);
  const out = base.map((s) => ({ ...s }));
  const extras = [];
  patches.forEach((src, i) => {
    const idx = keys[i] - (zeroBased ? 0 : 1);
    const human = `${label} ${keys[i]}`;
    if (idx >= 0 && idx < out.length) out[idx] = patchRow(out[idx], src, human);
    else extras.push(patchRow(undefined, src, human));
  });
  return [...out, ...extras].filter((s) => !s._drop).map(strip);
}

/**
 * Snapshot pytania + patch z JSON-a → payload dla admin_save_draft.
 * `base` = null dla nowego pytania. Rzuca na błędach, których nie wolno
 * przepuścić po cichu (zła kategoria, zły tag, smaczek bez PL — bazowy
 * _admin_write_smaczki wyrzuciłby taki wiersz bez słowa).
 */
export function buildPayload(base, patch) {
  const q = patch.question && typeof patch.question === 'object' ? patch.question : patch;

  const out = {
    category: base?.category ?? 'Reflection',
    is_premium: !!base?.is_premium,
    is_active: base?.is_active !== false,
    pl: base?.pl ?? '',
    en: base?.en ?? '',
    smaczki: (base?.smaczki ?? []).map((s) => ({
      pl: s.pl ?? '', en: s.en ?? '', side: s.side ?? null,
    })),
  };

  if (typeof q.pl === 'string') out.pl = q.pl;
  if (typeof q.en === 'string') out.en = q.en;

  const cat = typeof patch.category === 'string' ? patch.category
    : (typeof q.category === 'string' ? q.category : null);
  if (cat) {
    if (!CATEGORIES.includes(cat)) {
      throw new Error(`Nieznana kategoria "${cat}". Dozwolone: ${CATEGORIES.join(', ')}.`);
    }
    out.category = cat;
  }
  if (typeof patch.is_premium === 'boolean') out.is_premium = patch.is_premium;
  if (typeof patch.is_active === 'boolean') out.is_active = patch.is_active;

  const sm = Array.isArray(patch.smaczki) ? patch.smaczki
    : (Array.isArray(q.smaczki) ? q.smaczki : null);
  if (sm) out.smaczki = mergeSmaczki(out.smaczki, sm);

  out.pl = out.pl.trim();
  out.en = out.en.trim();
  out.smaczki = out.smaczki.map((s) => ({
    pl: (s.pl ?? '').trim(), en: (s.en ?? '').trim(), side: s.side ?? null,
  }));
  out.smaczki.forEach((s, i) => {
    if (s.pl === '' && s.en !== '') {
      throw new Error(`Smaczek ${i + 1}: jest EN, brak PL — baza zapisuje wiersz tylko z tekstem PL.`);
    }
  });
  out.smaczki = out.smaczki.filter((s) => s.pl !== '');

  if (out.pl === '') throw new Error('Puste pytanie PL.');
  return out;
}

/** Miękkie ostrzeżenia (limity długości, braki) — nie blokują zapisu. */
export function payloadWarnings(payload) {
  const w = [];
  if (payload.pl.length > LIMITS.question) w.push(`pytanie PL ${payload.pl.length} zn. (~${LIMITS.question})`);
  if (payload.en.length > LIMITS.question) w.push(`pytanie EN ${payload.en.length} zn. (~${LIMITS.question})`);
  if (payload.en === '') w.push('brak tłumaczenia EN');
  payload.smaczki.forEach((s, i) => {
    if (s.pl.length > LIMITS.smaczek) w.push(`smaczek ${i + 1} PL ${s.pl.length} zn. (~${LIMITS.smaczek})`);
    if (s.en.length > LIMITS.smaczek) w.push(`smaczek ${i + 1} EN ${s.en.length} zn. (~${LIMITS.smaczek})`);
    if (s.en === '') w.push(`smaczek ${i + 1} bez EN`);
  });
  const untagged = payload.smaczki.filter((s) => !s.side).length;
  if (untagged > 0) w.push(`${untagged} smaczk. bez strony`);
  return w;
}

/** Porównanie kształtu (jak w QuestionEditorze) — do wykrycia „bez zmian". */
export function shapeKey(q) {
  return JSON.stringify({
    category: q?.category ?? null,
    is_premium: !!q?.is_premium,
    is_active: q?.is_active !== false,
    pl: (q?.pl ?? '').trim(),
    en: (q?.en ?? '').trim(),
    smaczki: (q?.smaczki ?? [])
      .map((s) => ({ pl: (s.pl ?? '').trim(), en: (s.en ?? '').trim(), side: s.side ?? null }))
      .filter((s) => s.pl !== ''),
  });
}

/** Paczka do skopiowania agentowi. */
export function buildBundle(snapshots) {
  return {
    questions: snapshots.map((q) => ({
      id: q.id,
      category: q.category,
      pl: q.pl ?? '',
      en: q.en ?? '',
      smaczki: (q.smaczki ?? []).map((s, i) => ({
        position: s.position ?? i + 1,
        pl: s.pl ?? '',
        en: s.en ?? '',
        side: s.side ?? null,
      })),
    })),
  };
}

/** Instrukcja doklejana nad paczką — opisuje format odpowiedzi. */
export const AGENT_PROMPT = [
  'Poniżej paczka pytań z Debatly (JSON). Popraw / uzupełnij i odeślij WYŁĄCZNIE JSON.',
  '',
  'Format odpowiedzi:',
  '{"questions":[{"id":"<ten sam id z wejścia>","pl":"…","en":"…",',
  '  "smaczki":[{"position":1,"pl":"…","en":"…","side":"attacks_yes"}]}]}',
  '',
  'Zasady:',
  '- `id` pytania musi zostać bez zmian — po nim trafiam z powrotem w ten wiersz.',
  '- Pola, których nie podasz, zostają bez zmian. Chcesz tylko otagować? odeślij',
  '  "smaczki":[{"position":1,"side":"attacks_no"},{"position":2,"side":"neutral"}].',
  '- `position` to numer smaczka z wejścia. Nowy smaczek = position o 1 większy',
  '  niż ostatni. Kasowanie wiersza: {"position":3,"delete":true}.',
  `- side: ${SIDE_VALUES.join(' | ')} albo null (nieotagowany jest serwowany jak neutralny).`,
  '  attacks_yes dostaje ktoś, kto zagłosował TAK; attacks_no — ktoś, kto zagłosował NIE.',
  `- Limity: pytanie ~${LIMITS.question} znaków, smaczek ~${LIMITS.smaczek}. PL jest wymagany, EN nie zostawiaj pustego.`,
  `- Kategorie: ${CATEGORIES.join(', ')}.`,
  '- Nowe pytanie (bez id) też przyjmę: {"pl":"…","en":"…","category":"Ethics","smaczki":[…]}.',
].join('\n');

/**
 * Cokolwiek agent odesłał → lista {id, patch}. Przyjmuje {"questions":[…]},
 * gołą tablicę i pojedynczy obiekt. Brak id = nowe pytanie.
 */
export function parseBundle(text) {
  const raw = extractJson(text);
  if (raw.trim() === '') throw new Error('Pusty tekst.');
  let json;
  try {
    json = JSON.parse(raw);
  } catch (e) {
    throw new Error('Nieprawidłowy JSON: ' + e.message);
  }

  let items = null;
  if (Array.isArray(json)) items = json;
  else if (json && typeof json === 'object') {
    for (const k of ['questions', 'items', 'pytania']) {
      if (Array.isArray(json[k])) { items = json[k]; break; }
    }
    if (!items && (json.id || json.question || json.smaczki || typeof json.pl === 'string')) {
      items = [json];
    }
  }
  if (!items) throw new Error('Oczekiwano tablicy pytań — {"questions":[…]} albo […].');

  return items.map((it, i) => {
    if (!it || typeof it !== 'object' || Array.isArray(it)) {
      throw new Error(`Pozycja ${i + 1}: oczekiwano obiektu.`);
    }
    const rawId = typeof it.id === 'string' ? it.id.trim()
      : (typeof it.question_id === 'string' ? it.question_id.trim() : '');
    if (rawId !== '' && !UUID_RE.test(rawId)) {
      throw new Error(`Pozycja ${i + 1}: "id" nie jest UUID pytania („${rawId}").`);
    }
    return { id: rawId === '' ? null : rawId, patch: it };
  });
}

/** Równolegle, ale nie 50 zapytań naraz — kolejność wyniku = kolejność wejścia. */
export async function mapLimit(items, limit, fn) {
  const out = new Array(items.length);
  let next = 0;
  const worker = async () => {
    for (;;) {
      const i = next++;
      if (i >= items.length) return;
      out[i] = await fn(items[i], i);
    }
  };
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
  return out;
}

/** Schowek z fallbackiem na http bez TLS / starsze przeglądarki. */
export async function copyText(text) {
  try {
    await navigator.clipboard.writeText(text);
  } catch {
    const ta = document.createElement('textarea');
    ta.value = text;
    document.body.appendChild(ta);
    ta.select();
    document.execCommand('copy');
    ta.remove();
  }
}
