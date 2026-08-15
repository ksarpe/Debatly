-- ============================================================================
-- get_question_smaczki: evaluate is_premium() ONCE per call.
--
-- THE PROBLEM
--   The live definition names public.is_premium(auth.uid()) twice inside the
--   same `access` CTE — once as the full_smaczki flag, once as a disjunct of
--   can_access. They are two separate expressions, so the planner has no reason
--   to fold them: is_premium is STABLE, not IMMUTABLE, and every call re-reads
--   subscriptions. Two lookups per smaczki fetch, on the hottest read of the
--   question screen.
--
-- THE FIX
--   Hoist the call into its own MATERIALIZED CTE, so it is evaluated exactly
--   once and every later reference reads the stored boolean, and let
--   can_access reuse that column instead of calling the function again. The OR
--   is reordered cheapest-first (premium flag, then the caller's own
--   question_seen row, then the calendar) so the common PRO path short-circuits
--   before touching either table.
--
-- WHAT IS *NOT* CHANGED, AND WHY
--   The daily_questions branch stays. It looks like dead legacy — the global
--   calendar is no longer written to since the personal-daily pivot — but the
--   table was seeded ahead of time and still holds 495 future rows out to
--   2027-12-22, so the ±1-day window matches a real row EVERY day. Deleting the
--   branch would therefore not be a no-op: it would strip free access to
--   smaczek #1 on the daily question from pre-hard-paywall app versions, which
--   are exactly the clients this RPC is being kept alive for. Retiring it is a
--   catalog decision (stop seeding / truncate the forward calendar), not a
--   function edit, and it is not made here.
--
--   Result shape, argument list, volatility, security and grants are all
--   unchanged; this is a pure evaluation-count change.
-- ============================================================================

create or replace function public.get_question_smaczki(
  p_question_id uuid,
  p_locale      text default 'pl'
)
returns table ("position" smallint, is_locked boolean, text text)
language sql stable security definer set search_path to 'public'
as $$
  with prem as materialized (
    -- MATERIALIZED is load-bearing: without it the planner is free to inline
    -- this CTE into both reference sites and call is_premium() twice again.
    select public.is_premium(auth.uid()) as full_smaczki
  ),
  access as (
    select
      p.full_smaczki,
      (
        p.full_smaczki
        or exists (
          select 1 from public.question_seen u
          where u.user_id = auth.uid() and u.question_id = p_question_id
        )
        or exists (
          select 1 from public.daily_questions d
          where d.question_id = p_question_id
            and d.publish_date between (now() at time zone 'utc')::date - 1
                                   and (now() at time zone 'utc')::date + 1
        )
      ) as can_access
    from prem p
  )
  select
    s.position,
    not (a.full_smaczki or s.position = 1) as is_locked,
    case
      when a.full_smaczki or s.position = 1
        then coalesce(tr.text, en.text)
      else null
    end as text
  from access a
  join public.question_smaczki s
    on s.question_id = p_question_id and s.is_active
  left join public.question_smaczki_translations tr
    on tr.smaczek_id = s.id and tr.locale = p_locale
  left join public.question_smaczki_translations en
    on en.smaczek_id = s.id and en.locale = 'en'
  where a.can_access
  order by s.position;
$$;

-- CREATE OR REPLACE keeps the existing ACL; re-asserted here so the file is
-- self-contained. anon is intentionally on the list (matches prod): an
-- unauthenticated caller gets auth.uid() = null, so is_premium is false and no
-- question_seen row matches — it can only ever read smaczek #1 of the calendar
-- daily, which is the public teaser.
revoke all on function public.get_question_smaczki(uuid, text) from public;
grant execute on function public.get_question_smaczki(uuid, text) to anon, authenticated;
