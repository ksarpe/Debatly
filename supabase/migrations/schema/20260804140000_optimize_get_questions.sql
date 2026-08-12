-- ============================================================================
-- Optimize get_questions: identical result, ~3 scans instead of thousands of
-- per-row function calls.
--
-- The previous definition (20260622120000) called can_read_question_text()
-- TWICE per row (the text CASE + `locked`). That helper is SECURITY DEFINER —
-- not inlinable — and itself runs is_premium() (a profiles probe) plus an
-- EXISTS probe on user_daily_questions, so one full-catalog call (~1000 rows)
-- executed ~4000 hidden sub-queries, plus a correlated EXISTS on question_seen
-- per row. This rewrite:
--
--   * computes is_premium(auth.uid()) ONCE in a materialized one-row CTE
--     (materialized so the planner cannot inline it back to per-row calls);
--   * replaces the readability probe with a LEFT JOIN on user_daily_questions
--     (PK (user_id, assigned_on), fixed to assigned_on = p_date → no fan-out);
--   * replaces the seen EXISTS with a LEFT JOIN on question_seen
--     (PK (user_id, question_id) → no fan-out).
--
-- The readability rule is preserved verbatim from the CURRENT
-- can_read_question_text (20260713120000, personal daily):
--   premium OR (own user_daily_questions assignment for p_date, with the
--   client-supplied p_date clamped to the UTC ±1-day window).
-- can_read_question_text itself is untouched — the single-row RPCs still use it.
--
-- CREATE OR REPLACE keeps the signature and return type, so existing grants
-- (anon + authenticated; PUBLIC revoked in 20260622170000) carry over; they
-- are re-asserted below anyway so this file stands on its own.
-- ============================================================================
create or replace function public.get_questions(
  p_locale text default 'pl',
  p_date   date default (now() at time zone 'utc')::date
)
returns table (
  id            uuid,
  category      text,
  is_premium    boolean,
  question_text text,
  locked        boolean,
  teaser        text,
  seen          boolean
)
language sql stable security definer set search_path = public as $$
  with me as materialized (
    select auth.uid() as uid, public.is_premium(auth.uid()) as premium
  )
  select
    q.id,
    q.category,
    q.is_premium,
    case when me.premium or ud.question_id is not null
         then coalesce(tr.question_text, en.question_text)
         else null end                             as question_text,
    not (me.premium or ud.question_id is not null) as locked,
    array_to_string(
      (regexp_split_to_array(
         btrim(coalesce(tr.question_text, en.question_text)), '\s+'))[1:2],
      ' '
    )                                              as teaser,
    (s.question_id is not null)                    as seen
  from public.questions q
  cross join me
  left join public.question_translations tr
         on tr.question_id = q.id and tr.locale = p_locale
  left join public.question_translations en
         on en.question_id = q.id and en.locale = 'en'
  -- The caller's personal-daily assignment for p_date — the only way a
  -- non-premium caller can read a catalog row's text. Same window clamp as
  -- can_read_question_text.
  left join public.user_daily_questions ud
         on ud.user_id = me.uid
        and ud.question_id = q.id
        and ud.assigned_on = p_date
        and p_date between (now() at time zone 'utc')::date - 1
                       and (now() at time zone 'utc')::date + 1
  left join public.question_seen s
         on s.user_id = me.uid and s.question_id = q.id
  where q.is_active
  order by q.created_at, q.id;
$$;

revoke all on function public.get_questions(text, date) from public;
grant execute on function public.get_questions(text, date) to anon, authenticated;
