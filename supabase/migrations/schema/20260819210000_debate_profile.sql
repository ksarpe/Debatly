-- ============================================================================
-- Debate profile: the 2×2 personality grid under the conformity axis.
-- ----------------------------------------------------------------------------
-- 2026-08-19. Two axes over data the app already records:
--   * conformity — share of the caller's votes cast with the (seed-inclusive)
--     majority, same math as get_conformity_stats;
--   * resilience — share of QUALIFYING post-vote gates answered "to mnie
--     ruszyło" (moved / (held + moved)). Qualifying = outcome held/moved AND
--     dwell >= the configured minimum (default 1500 ms — the average smaczek
--     is ~46 chars, ~1.4 s at scanning speed; a faster tap measured tapping,
--     not resilience). 'dismissed' and no-gate rows never enter.
--
-- WHY THE BOUNDARIES ARE NOT 50%
--   A random voter lands in the majority with probability equal to that
--   majority's share; at typical 55–75% splits the EXPECTED conformity of an
--   average person is ~65%. A 50% boundary would file nearly everyone under
--   "conforming" and collapse the grid to 1×2. Both boundaries therefore live
--   in profile_config (defaults 0.65 / 0.15), changeable without an app
--   release, and recompute_profile_boundaries() re-derives them as medians of
--   the real population once >= 200 users have unlocked profiles (scheduled
--   weekly via pg_cron; a no-op below the threshold).
--
-- WHAT THIS CHANGES IN record_smaczek_challenge
--   A 'held' answered faster than the dwell minimum is now STORED as
--   'skipped_fast' on the vote row (nobody read the argument, so it must not
--   count as a defense). The QUESTION-level counters are deliberately
--   untouched: challenge_held_count still increments for every held tap, so
--   the "Kontra przewróciła X%" line under the split keeps exactly today's
--   arithmetic. skipped_fast only excludes the row from the PERSONAL
--   resilience axis (which filters on dwell anyway — the label makes the data
--   honest, not the filter work).
--
-- Idempotent: guarded DDL + create or replace. Safe to re-run.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Server-side configuration. No grants, no policies: only SECURITY DEFINER
--    functions read it, and writes happen via the SQL editor / service role.
-- ----------------------------------------------------------------------------
create table if not exists public.profile_config (
  key        text primary key,
  value      numeric not null,
  updated_at timestamptz not null default now()
);

alter table public.profile_config enable row level security;

comment on table public.profile_config is
  'Server-tunable knobs for the debate profile: axis boundaries, dwell '
  'minimum, unlock thresholds. Read only through SECURITY DEFINER RPCs, so '
  'changing a value ships to every client instantly, no app release.';

insert into public.profile_config (key, value) values
  ('conformity_boundary',    0.65),
  ('resilience_boundary',    0.15),
  ('challenge_dwell_min_ms', 1500),
  ('profile_unlock_min',     6),
  ('profile_full_min',       12)
on conflict (key) do nothing;

create or replace function public._profile_cfg(p_key text, p_default numeric)
returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select c.value from public.profile_config c where c.key = p_key),
    p_default
  );
$$;

revoke all on function public._profile_cfg(text, numeric)
  from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 2) 'skipped_fast' joins the outcome vocabulary (stored only — the client
--    still sends held/moved/dismissed and the server reclassifies).
-- ----------------------------------------------------------------------------
alter table public.question_votes
  drop constraint if exists question_votes_challenge_outcome_check;
alter table public.question_votes
  add constraint question_votes_challenge_outcome_check
  check (challenge_outcome is null
         or challenge_outcome in ('held', 'moved', 'dismissed', 'skipped_fast'));

comment on column public.question_votes.challenge_outcome is
  'How the user answered the gate: held / moved / dismissed (system back) / '
  'skipped_fast (tapped "held" below the dwell minimum — too fast to have '
  'read the argument; server-assigned, never sent by the client). The vote '
  'itself is NEVER changed by the gate — this is a separate axis.';

-- ----------------------------------------------------------------------------
-- 3) record_smaczek_challenge — base 20260819160000; the ONLY change is the
--    held→skipped_fast reclassification on the stored row. Counters, guards,
--    result shape: identical (see the header for why counters stay).
-- ----------------------------------------------------------------------------
create or replace function public.record_smaczek_challenge(
  p_question_id uuid,
  p_position    int,
  p_outcome     text,
  p_dwell_ms    int default null
)
returns table (
  yes_count int,
  no_count  int,
  my_choice int,
  flip_pct  int
)
language plpgsql security definer set search_path = public as $$
declare
  v_uid     uuid := auth.uid();
  v_smaczek uuid;
  v_claimed boolean;
  v_stored  text;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if p_outcome not in ('held', 'moved', 'dismissed') then
    raise exception 'invalid outcome %', p_outcome;
  end if;

  -- A "held" answered faster than anyone can read the argument is stored as
  -- skipped_fast: it stays out of the personal resilience axis. The question
  -- counters below still count it as held on purpose — the under-question
  -- flip line keeps today's arithmetic exactly.
  v_stored := p_outcome;
  if p_outcome = 'held'
     and coalesce(p_dwell_ms, 0) < public._profile_cfg('challenge_dwell_min_ms', 1500)
  then
    v_stored := 'skipped_fast';
  end if;

  -- Resolve the shown smaczek from its position. May legitimately be NULL —
  -- an admin save rewrites the smaczek rows wholesale — and the outcome is
  -- still worth recording without the fk.
  select s.id into v_smaczek
  from public.question_smaczki s
  where s.question_id = p_question_id
    and s.position = p_position
    and s.is_active
  limit 1;

  -- Claim the vote row's challenge slot. No row (never voted) or an already
  -- recorded outcome both leave v_claimed false — and the counters untouched,
  -- so a replay can never double-count.
  update public.question_votes v
     set challenge_smaczek_id = v_smaczek,
         challenge_outcome    = v_stored,
         challenge_dwell_ms   = case
           when p_dwell_ms is null then null
           else least(greatest(p_dwell_ms, 0), 600000)
         end
   where v.user_id = v_uid
     and v.question_id = p_question_id
     and v.challenge_outcome is null;
  v_claimed := found;

  -- Only real answers feed the flip stat; a dismissal is an exit, not data.
  -- Deliberately keyed on the CLIENT outcome, not v_stored: a fast held
  -- still counts as held here, so the flip line's inputs are unchanged.
  if v_claimed and p_outcome in ('held', 'moved') then
    update public.question_vote_counts c
       set challenge_held_count  = c.challenge_held_count
                                   + (p_outcome = 'held')::int,
           challenge_moved_count = c.challenge_moved_count
                                   + (p_outcome = 'moved')::int,
           updated_at            = now()
     where c.question_id = p_question_id;
  end if;

  return query
    select
      coalesce(c.yes_count, 0) + coalesce(sd.seed_yes, 0),
      coalesce(c.no_count,  0) + coalesce(sd.seed_no,  0),
      (select v2.choice::int
         from public.question_votes v2
        where v2.question_id = p_question_id
          and v2.user_id = v_uid),
      public.question_flip_pct(p_question_id)
    from (values (1)) as one(x)
    left join public.question_vote_counts c on c.question_id = p_question_id
    left join public.question_vote_seeds  sd on sd.question_id = p_question_id;
end;
$$;

revoke all on function public.record_smaczek_challenge(uuid, int, text, int)
  from public, anon;
grant execute on function public.record_smaczek_challenge(uuid, int, text, int)
  to authenticated;

-- ----------------------------------------------------------------------------
-- 4) get_debate_profile — one row: both axes' raw counts plus the live
--    configuration, so the client derives state (locked / provisional / full)
--    and type from server-owned numbers. Not premium-gated: like the
--    conformity axis it exposes only aggregates of the caller's own votes.
-- ----------------------------------------------------------------------------
create or replace function public.get_debate_profile()
returns table (
  total_votes         int,
  majority_votes      int,
  minority_votes      int,
  gate_held           int,
  gate_moved          int,
  conformity_boundary numeric,
  resilience_boundary numeric,
  unlock_min          int,
  full_min            int
)
language sql stable security definer set search_path = public as $$
  with cfg as materialized (
    select
      public._profile_cfg('conformity_boundary',    0.65) as cb,
      public._profile_cfg('resilience_boundary',    0.15) as rb,
      public._profile_cfg('challenge_dwell_min_ms', 1500) as dw,
      public._profile_cfg('profile_unlock_min',     6)    as un,
      public._profile_cfg('profile_full_min',       12)   as fu
  ),
  mine as (
    select
      v.choice,
      coalesce(c.yes_count, 0) + coalesce(sd.seed_yes, 0) as yes_total,
      coalesce(c.no_count,  0) + coalesce(sd.seed_no,  0) as no_total,
      v.challenge_outcome  as oc,
      v.challenge_dwell_ms as dwell
    from public.question_votes v
    left join public.question_vote_counts c  on c.question_id  = v.question_id
    left join public.question_vote_seeds  sd on sd.question_id = v.question_id
    where v.user_id = auth.uid()
  )
  select
    count(m.*)::int,
    count(m.*) filter (where m.yes_total <> m.no_total
                         and ((m.choice = 1 and m.yes_total > m.no_total)
                           or (m.choice = 2 and m.no_total > m.yes_total)))::int,
    count(m.*) filter (where m.yes_total <> m.no_total
                         and ((m.choice = 1 and m.yes_total < m.no_total)
                           or (m.choice = 2 and m.no_total < m.yes_total)))::int,
    count(m.*) filter (where m.oc = 'held'
                         and coalesce(m.dwell, 0) >= f.dw)::int,
    count(m.*) filter (where m.oc = 'moved'
                         and coalesce(m.dwell, 0) >= f.dw)::int,
    f.cb, f.rb, f.un::int, f.fu::int
  from cfg f
  left join mine m on true
  group by f.cb, f.rb, f.un, f.fu;
$$;

comment on function public.get_debate_profile() is
  'One row: conformity + resilience raw counts for the caller plus the live '
  'boundaries/thresholds from profile_config. Backs the 2×2 debate-profile '
  'grid under the conformity axis. Not premium-gated.';

revoke all on function public.get_debate_profile() from public, anon;
grant execute on function public.get_debate_profile() to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 5) The PRO depth: trend, categories, and the arguments that flipped you.
--    All three raise 'premium required' for a free caller — the type itself
--    stays free (see get_debate_profile), the depth is the upsell.
-- ----------------------------------------------------------------------------
create or replace function public.get_profile_trend()
returns table (
  month          date,
  total_votes    int,
  majority_votes int,
  minority_votes int,
  gate_held      int,
  gate_moved     int
)
language plpgsql stable security definer set search_path = public as $$
declare
  v_dw numeric := public._profile_cfg('challenge_dwell_min_ms', 1500);
begin
  if not public.is_premium(auth.uid()) then
    raise exception 'premium required';
  end if;
  return query
  select
    date_trunc('month', v.voted_at)::date,
    count(*)::int,
    count(*) filter (where t.yes_total <> t.no_total
                       and ((v.choice = 1 and t.yes_total > t.no_total)
                         or (v.choice = 2 and t.no_total > t.yes_total)))::int,
    count(*) filter (where t.yes_total <> t.no_total
                       and ((v.choice = 1 and t.yes_total < t.no_total)
                         or (v.choice = 2 and t.no_total < t.yes_total)))::int,
    count(*) filter (where v.challenge_outcome = 'held'
                       and coalesce(v.challenge_dwell_ms, 0) >= v_dw)::int,
    count(*) filter (where v.challenge_outcome = 'moved'
                       and coalesce(v.challenge_dwell_ms, 0) >= v_dw)::int
  from public.question_votes v
  cross join lateral (
    select
      coalesce(c.yes_count, 0) + coalesce(sd.seed_yes, 0) as yes_total,
      coalesce(c.no_count,  0) + coalesce(sd.seed_no,  0) as no_total
    from (values (1)) as one(x)
    left join public.question_vote_counts c  on c.question_id  = v.question_id
    left join public.question_vote_seeds  sd on sd.question_id = v.question_id
  ) t
  where v.user_id = auth.uid()
    and v.voted_at >= date_trunc('month', now()) - interval '11 months'
  group by 1
  order by 1;
end;
$$;

revoke all on function public.get_profile_trend() from public, anon;
grant execute on function public.get_profile_trend() to authenticated, service_role;

create or replace function public.get_profile_categories()
returns table (
  category       text,
  total_votes    int,
  majority_votes int,
  minority_votes int,
  gate_held      int,
  gate_moved     int
)
language plpgsql stable security definer set search_path = public as $$
declare
  v_dw numeric := public._profile_cfg('challenge_dwell_min_ms', 1500);
begin
  if not public.is_premium(auth.uid()) then
    raise exception 'premium required';
  end if;
  return query
  select
    q.category,
    count(*)::int,
    count(*) filter (where t.yes_total <> t.no_total
                       and ((v.choice = 1 and t.yes_total > t.no_total)
                         or (v.choice = 2 and t.no_total > t.yes_total)))::int,
    count(*) filter (where t.yes_total <> t.no_total
                       and ((v.choice = 1 and t.yes_total < t.no_total)
                         or (v.choice = 2 and t.no_total < t.yes_total)))::int,
    count(*) filter (where v.challenge_outcome = 'held'
                       and coalesce(v.challenge_dwell_ms, 0) >= v_dw)::int,
    count(*) filter (where v.challenge_outcome = 'moved'
                       and coalesce(v.challenge_dwell_ms, 0) >= v_dw)::int
  from public.question_votes v
  join public.questions q on q.id = v.question_id
  cross join lateral (
    select
      coalesce(c.yes_count, 0) + coalesce(sd.seed_yes, 0) as yes_total,
      coalesce(c.no_count,  0) + coalesce(sd.seed_no,  0) as no_total
    from (values (1)) as one(x)
    left join public.question_vote_counts c  on c.question_id  = v.question_id
    left join public.question_vote_seeds  sd on sd.question_id = v.question_id
  ) t
  where v.user_id = auth.uid()
  group by q.category
  order by count(*) desc, q.category
  limit 12;
end;
$$;

revoke all on function public.get_profile_categories() from public, anon;
grant execute on function public.get_profile_categories() to authenticated, service_role;

create or replace function public.get_moved_smaczki(p_locale text default 'pl')
returns table (
  question_text text,
  smaczek_text  text,
  moved_at      timestamptz
)
language plpgsql stable security definer set search_path = public as $$
declare
  v_dw numeric := public._profile_cfg('challenge_dwell_min_ms', 1500);
begin
  if not public.is_premium(auth.uid()) then
    raise exception 'premium required';
  end if;
  -- Only QUALIFYING moves (dwell >= minimum), matching the axis — and only
  -- smaczki whose row still exists (an admin rewrite nulls the fk).
  return query
  select
    coalesce(qt.question_text, qe.question_text),
    coalesce(st.text, se.text),
    v.voted_at
  from public.question_votes v
  join public.question_smaczki s on s.id = v.challenge_smaczek_id
  left join public.question_smaczki_translations st
    on st.smaczek_id = s.id and st.locale = p_locale
  left join public.question_smaczki_translations se
    on se.smaczek_id = s.id and se.locale = 'en'
  left join public.question_translations qt
    on qt.question_id = v.question_id and qt.locale = p_locale
  left join public.question_translations qe
    on qe.question_id = v.question_id and qe.locale = 'en'
  where v.user_id = auth.uid()
    and v.challenge_outcome = 'moved'
    and coalesce(v.challenge_dwell_ms, 0) >= v_dw
  order by v.voted_at desc
  limit 100;
end;
$$;

revoke all on function public.get_moved_smaczki(text) from public, anon;
grant execute on function public.get_moved_smaczki(text) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 6) Boundary recompute: medians of the unlocked population, no-op below 200
--    unlocked profiles. Scheduled weekly via pg_cron; also callable by hand
--    (service role / SQL editor) — it reports what it did either way.
-- ----------------------------------------------------------------------------
create or replace function public.recompute_profile_boundaries()
returns text
language plpgsql security definer set search_path = public as $$
declare
  v_dw numeric := public._profile_cfg('challenge_dwell_min_ms', 1500);
  v_un numeric := public._profile_cfg('profile_unlock_min', 6);
  v_n  int;
  v_cb numeric;
  v_rb numeric;
begin
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
      maj::numeric / (maj + mino)          as conformity_frac,
      moved::numeric / (held + moved)      as moved_frac
    from per_user
    where votes >= v_un
      and (held + moved) >= v_un
      and (maj + mino) > 0
  )
  select
    count(*),
    percentile_cont(0.5) within group (order by conformity_frac),
    percentile_cont(0.5) within group (order by moved_frac)
  into v_n, v_cb, v_rb
  from unlocked;

  if v_n < 200 then
    return format('skipped: only %s unlocked profiles (< 200)', v_n);
  end if;

  update public.profile_config
     set value = round(v_cb, 4), updated_at = now()
   where key = 'conformity_boundary';
  update public.profile_config
     set value = round(v_rb, 4), updated_at = now()
   where key = 'resilience_boundary';

  return format('updated from %s profiles: conformity_boundary=%s resilience_boundary=%s',
                v_n, round(v_cb, 4), round(v_rb, 4));
end;
$$;

revoke all on function public.recompute_profile_boundaries()
  from public, anon, authenticated;
grant execute on function public.recompute_profile_boundaries() to service_role;

-- Weekly, Monday 03:30 UTC. cron.schedule upserts by job name, so re-running
-- this migration just refreshes the same job.
create extension if not exists pg_cron;
select cron.schedule(
  'recompute-profile-boundaries',
  '30 3 * * 1',
  'select public.recompute_profile_boundaries()'
);
