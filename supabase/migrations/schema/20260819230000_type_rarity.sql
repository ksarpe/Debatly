-- ============================================================================
-- get_type_rarity — "Twój typ ma tylko X% użytkowników" (PRO).
-- ----------------------------------------------------------------------------
-- 2026-08-19, follow-up to 20260819210000_debate_profile.sql. The debate
-- profile's PRO depth trades the (English-labelled, hence removed from the
-- client) category breakdown for two personal hooks; this one needs a
-- cross-user aggregate, and the anon-key client has no path to other users'
-- votes except a SECURITY DEFINER RPC — hence a function, not client math.
--
-- One row: the share of UNLOCKED profiles (>= unlock_min votes AND
-- >= unlock_min qualifying gate answers, >= 1 decided vote — the same
-- definition recompute_profile_boundaries uses) that land in the caller's
-- 2×2 cell, plus the population size. rarity_pct is NULL when the number
-- would embarrass the feature instead of selling it: population < 20, or the
-- caller's own profile isn't unlocked — the client then hides the block.
--
-- Read-only, premium-gated ('premium required'), no table changes.
-- Idempotent: create or replace. Safe to re-run.
-- ============================================================================

create or replace function public.get_type_rarity()
returns table (rarity_pct int, population int)
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_dw numeric := public._profile_cfg('challenge_dwell_min_ms', 1500);
  v_un numeric := public._profile_cfg('profile_unlock_min', 6);
  v_cb numeric := public._profile_cfg('conformity_boundary', 0.65);
  v_rb numeric := public._profile_cfg('resilience_boundary', 0.15);
begin
  if not public.is_premium(v_uid) then
    raise exception 'premium required';
  end if;
  return query
  with per_user as (
    select
      v.user_id,
      count(*) as votes,
      count(*) filter (where t.yes_total <> t.no_total
                         and ((v.choice = 1 and t.yes_total > t.no_total)
                           or (v.choice = 2 and t.no_total > t.yes_total))) as maj,
      count(*) filter (where t.yes_total <> t.no_total
                         and ((v.choice = 1 and t.yes_total < t.no_total)
                           or (v.choice = 2 and t.no_total < t.yes_total))) as mino,
      count(*) filter (where v.challenge_outcome = 'held'
                         and coalesce(v.challenge_dwell_ms, 0) >= v_dw) as held,
      count(*) filter (where v.challenge_outcome = 'moved'
                         and coalesce(v.challenge_dwell_ms, 0) >= v_dw) as moved
    from public.question_votes v
    cross join lateral (
      select
        coalesce(c.yes_count, 0) + coalesce(sd.seed_yes, 0) as yes_total,
        coalesce(c.no_count,  0) + coalesce(sd.seed_no,  0) as no_total
      from (values (1)) as one(x)
      left join public.question_vote_counts c  on c.question_id  = v.question_id
      left join public.question_vote_seeds  sd on sd.question_id = v.question_id
    ) t
    group by v.user_id
  ),
  unlocked as (
    select
      p.user_id,
      (p.maj::numeric / (p.maj + p.mino) >= v_cb)     as with_crowd,
      (p.moved::numeric / (p.held + p.moved) >= v_rb) as movable
    from per_user p
    where p.votes >= v_un
      and (p.held + p.moved) >= v_un
      and (p.maj + p.mino) > 0
  ),
  me as (
    select u.with_crowd, u.movable from unlocked u where u.user_id = v_uid
  )
  select
    case
      when (select count(*) from unlocked) >= 20
       and exists (select 1 from me)
      then round(
        100.0 * (select count(*)
                   from unlocked u, me m
                  where u.with_crowd = m.with_crowd
                    and u.movable = m.movable)
              / (select count(*) from unlocked)
      )::int
    end,
    (select count(*)::int from unlocked);
end;
$$;

comment on function public.get_type_rarity() is
  'Share of unlocked debate profiles landing in the caller''s 2×2 cell, plus '
  'the population size. NULL rarity below 20 unlocked profiles or when the '
  'caller''s own profile is locked — the client hides the block then. '
  'Premium-gated; backs the PRO "type rarity" row in the profile panel.';

revoke all on function public.get_type_rarity() from public, anon;
grant execute on function public.get_type_rarity() to authenticated, service_role;
