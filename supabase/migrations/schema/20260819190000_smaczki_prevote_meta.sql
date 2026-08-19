-- ============================================================================
-- Smaczki: no readable text before the vote + the free slot must actually
-- attack the caller.
-- ----------------------------------------------------------------------------
-- 2026-08-19, follow-up to 20260819120000_smaczek_side.sql.
--
-- TWO LEAKS THIS CLOSES
--   1) Pre-vote text. The client prefetches get_question_smaczki while the
--      user is still reading the question. Before the vote the caller has no
--      side, the relevance ranking collapses to position order, and the free
--      slot unlocked position 1 — its full text landed on the device. When
--      the user then voted the OTHER way, the post-vote refetch unlocked the
--      argument aimed at them: two readable smaczki on a free device instead
--      of one. Arguments are vote-gated by product rule (read pre-vote they
--      pollute the reflex the split measures), so a non-premium caller who
--      has NOT voted on the question now gets no readable text at all. The
--      layout data the prefetch actually needed (how many arguments, roughly
--      how long) moves to a new metadata-only RPC, get_question_smaczki_meta.
--   2) The free slot on a question whose only tagged rows attack the OTHER
--      side. The top-ranked row was unlocked unconditionally, so a free user
--      could read an argument DEFENDING their answer — agreement served as
--      the challenge. The free slot now unlocks only an argument that can be
--      aimed at the caller: one attacking their actual side, or a neutral /
--      untagged one. Nothing qualifying = nothing readable (the client
--      already skips the gate and shows the split straight away).
--
-- SHIPPED-VERSION IMPACT, ACCEPTED KNOWINGLY: pre-freemium app versions let a
-- free user open the smaczki sheet before voting and read row 1 (including
-- the anon calendar-daily teaser). Those callers now see that row only after
-- their vote lands — degraded, not broken: the locked placeholders render as
-- always and the text unlocks on the refetch after the vote. That is the
-- price of closing the leak at the API, not just in the new client.
--
-- Result shape and arguments of get_question_smaczki are UNCHANGED (plain
-- create or replace, grants re-asserted). Idempotent: safe to re-run.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) get_question_smaczki — same shape, stricter free slot.
-- ----------------------------------------------------------------------------
create or replace function public.get_question_smaczki(
  p_question_id uuid,
  p_locale      text default 'pl'
)
returns table ("position" smallint, is_locked boolean, text text, side text)
language sql stable security definer set search_path to 'public'
as $$
  with prem as materialized (
    -- MATERIALIZED is load-bearing: without it the planner is free to inline
    -- this CTE into both reference sites and call is_premium() twice.
    select public.is_premium(auth.uid()) as full_smaczki
  ),
  mine as materialized (
    -- The caller's own vote on this question, if any. 1 = TAK, 2 = NIE.
    -- Zero rows before they vote — which both collapses the ordering to
    -- author order AND locks every row for a free caller (see `readable`).
    select v.choice
    from public.question_votes v
    where v.user_id = auth.uid() and v.question_id = p_question_id
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
        -- Legacy calendar branch: still matches a real row every day (the
        -- table is seeded out to 2027), so pre-freemium app versions keep
        -- their sheet. See 20260815170000.
        or exists (
          select 1 from public.daily_questions d
          where d.question_id = p_question_id
            and d.publish_date between (now() at time zone 'utc')::date - 1
                                   and (now() at time zone 'utc')::date + 1
        )
      ) as can_access
    from prem p
  ),
  ranked as (
    select
      s.id,
      s.position,
      s.side,
      a.full_smaczki,
      m.choice as my_choice,
      row_number() over (
        order by
          case
            -- No vote yet (or anon): nothing to aim at, keep author order.
            when m.choice is null                            then 1
            when m.choice = 1 and s.side = 'attacks_yes'     then 0
            when m.choice = 2 and s.side = 'attacks_no'      then 0
            when s.side is null or s.side = 'neutral'        then 1
            else 2
          end,
          s.position
      ) as rel
    from access a
    join public.question_smaczki s
      on s.question_id = p_question_id and s.is_active
    left join mine m on true
    where a.can_access
  ),
  readable as (
    select
      r.*,
      (
        r.full_smaczki
        -- The free slot: only once the caller's vote exists (no pre-vote
        -- text — see header), only the top-ranked row, and only when that
        -- row can be aimed at them: their side's attacker, a neutral, or an
        -- untagged one (served as neutral). A row that merely DEFENDS their
        -- answer stays locked — agreement is not a challenge, and reading
        -- the defense is exactly what PRO is sold on.
        or (
          r.rel = 1
          and r.my_choice is not null
          and (
            r.side is null
            or r.side = 'neutral'
            or (r.my_choice = 1 and r.side = 'attacks_yes')
            or (r.my_choice = 2 and r.side = 'attacks_no')
          )
        )
      ) as can_read
    from ranked r
  )
  select
    r.position,
    not r.can_read as is_locked,
    case when r.can_read then coalesce(tr.text, en.text) end as text,
    r.side
  from readable r
  left join public.question_smaczki_translations tr
    on tr.smaczek_id = r.id and tr.locale = p_locale
  left join public.question_smaczki_translations en
    on en.smaczek_id = r.id and en.locale = 'en'
  order by r.rel;
$$;

-- anon stays on the list (matches prod): an unauthenticated caller has no
-- vote row, so since this migration it can no longer read ANY text — only the
-- locked placeholders of the calendar daily. Kept callable so old clients get
-- an empty-handed answer instead of an error.
revoke all on function public.get_question_smaczki(uuid, text) from public;
grant execute on function public.get_question_smaczki(uuid, text) to anon, authenticated;

-- ----------------------------------------------------------------------------
-- 2) get_question_smaczki_meta — the pre-vote prefetch. Positions and rough
--    lengths only: enough for the client to lay out the sheet's placeholder
--    cards and know whether a gate is even possible, useless for
--    reconstructing content. Same access gate as the full RPC.
-- ----------------------------------------------------------------------------
create or replace function public.get_question_smaczki_meta(
  p_question_id uuid,
  p_locale      text default 'pl'
)
returns table ("position" smallint, approx_len int)
language sql stable security definer set search_path to 'public'
as $$
  with prem as materialized (
    select public.is_premium(auth.uid()) as full_smaczki
  ),
  access as (
    select (
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
    -- Rounded to the nearest 10 characters: plausible space reservation,
    -- not a fingerprint of the sentence.
    (round(coalesce(char_length(coalesce(tr.text, en.text)), 0) / 10.0) * 10)::int
      as approx_len
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

comment on function public.get_question_smaczki_meta(uuid, text) is
  'Pre-vote smaczki prefetch: positions + text lengths rounded to 10 chars, '
  'never any text. The full get_question_smaczki is for after the vote.';

revoke all on function public.get_question_smaczki_meta(uuid, text) from public;
grant execute on function public.get_question_smaczki_meta(uuid, text) to anon, authenticated;
