'use client';

/**
 * Character count for a text field. Amber near the soft limit, red past it —
 * both are hints, never a block, because the limits are editorial rather than
 * enforced by the schema (see LIMITS in lib/api.js).
 */
export default function Counter({ value, limit }) {
  const n = (value ?? '').trim().length;
  if (n === 0) return null;
  const cls = n > limit ? 'over' : n > limit - 12 ? 'near' : '';
  return (
    <span className={`cnt ${cls}`} title={`${n} / ~${limit} znaków`}>
      {n}
    </span>
  );
}
