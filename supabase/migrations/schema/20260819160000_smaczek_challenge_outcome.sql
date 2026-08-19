-- ============================================================================
-- Smaczek challenge: the vote is final, the gate's outcome is data.
-- ----------------------------------------------------------------------------
-- 2026-08-19. Until now "HMM, JEDNAK NIE" in the post-vote gate re-cast the
-- vote for the other side. The argument attacks the side the user just picked,
-- so the pressure works both ways in proportion to each side's size and every
-- split drifts toward 50/50 (p' = p + f·(1−2p)): at 10% flips an 80/20
-- question reads 74/26, at 30% it reads 62/38. The sharper the question, the
-- more it loses — and "63% said TAK" quietly stops meaning "what people think".
--
-- WHAT THIS CHANGES
--   * The vote cast BEFORE the gate is final. The client no longer re-casts;
--     the gate's answer is recorded separately on the SAME vote row:
--       question_votes.challenge_smaczek_id   which argument was shown
--       question_votes.challenge_outcome      'held' | 'moved' | 'dismissed'
--       question_votes.challenge_dwell_ms     ms from argument landed → tap
--   * question_vote_counts gains challenge_held_count / challenge_moved_count,
--     bumped by record_smaczek_challenge — 'dismissed' (system back) is
--     recorded on the row but deliberately NOT counted: it is an exit, not an
--     answer, and must not pollute the resilience stat.
--   * New RPC record_smaczek_challenge(question, position, outcome, dwell):
--     first write wins (the challenge runs once per vote row), resolves the
--     smaczek id from (question_id, position) server-side so the
--     get_question_smaczki result shape stays untouched, and returns the same
--     row shape as get_daily_vote_state.
--   * get_daily_vote_state / cast_daily_vote return one extra column:
--       flip_pct int — round(moved·100 / (held+moved)), and NULL until the
--     question has at least 30 answered challenges (held+moved). Below the
--     threshold the number is noise, so the server withholds it entirely and
--     the client never has to know the threshold. Result-shape change =>
--     drop + recreate + re-grant; the ARGUMENTS are unchanged, so shipped app
--     versions keep working and simply ignore the new key.
--
-- Idempotent: guarded DDL + create or replace (the two functions whose result
-- shape changes are dropped first, as Postgres requires). Safe to re-run.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) The challenge columns on the vote row. One row per (user, question)
--    already exists and is the natural home — no second table.
-- ----------------------------------------------------------------------------
alter table public.question_votes
  add column if not exists challenge_smaczek_id uuid
    references public.question_smaczki(id) on delete set null,
  add column if not exists challenge_outcome text,
  add column if not exists challenge_dwell_ms int;

alter table public.question_votes
  drop constraint if exists question_votes_challenge_outcome_check;
alter table public.question_votes
  add constraint question_votes_challenge_outcome_check
  check (challenge_outcome is null
         or challenge_outcome in ('held', 'moved', 'dismissed'));

comment on column public.question_votes.challenge_smaczek_id is
  'The smaczek dropped on the user in the post-vote gate. NULL = no gate ran '
  '(offline, no smaczki, session cap) or the smaczek row was since rewritten.';
comment on column public.question_votes.challenge_outcome is
  'How the user answered the gate: held / moved / dismissed (system back). '
  'The vote itself is NEVER changed by the gate — this is a separate axis.';
comment on column public.question_votes.challenge_dwell_ms is
  'Milliseconds from the argument fully landing (buttons appear) to the tap. '
  'NULL when dismissed before the argument landed.';

-- Partial covering index for the FK: the column is NULL on the long tail of
-- rows, and the FK's ON DELETE SET NULL needs the lookup on admin rewrites.
create index if not exists question_votes_challenge_smaczek_id_idx
  on public.question_votes (challenge_smaczek_id)
  where challenge_smaczek_id is not null;

-- ----------------------------------------------------------------------------
-- 2) The counters. Same pattern as yes_count/no_count: reading the flip share
--    must stay a PK lookup, not an aggregate over question_votes.
-- ----------------------------------------------------------------------------
alter table public.question_vote_counts
  add column if not exists challenge_held_count  integer not null default 0,
  add column if not exists challenge_moved_count integer not null default 0;

comment on column public.question_vote_counts.challenge_held_count is
  'Gate answers "trzymam się" on this question. Maintained by '
  'record_smaczek_challenge; dismissed exits are not counted.';
comment on column public.question_vote_counts.challenge_moved_count is
  'Gate answers "to mnie ruszyło" on this question. The flip line''s '
  'numerator; held+moved is its denominator and its >=30 display threshold.';

-- ----------------------------------------------------------------------------
-- 3) The flip share, in one place. NULL below the 30-answer threshold — the
--    single point of truth for "when is this number real enough to show".
-- ----------------------------------------------------------------------------
create or replace function public.question_flip_pct(p_question_id uuid)
returns int
language sql stable security definer set search_path = public as $$
  select case
    when c.challenge_held_count + c.challenge_moved_count >= 30
    then round(c.challenge_moved_count * 100.0
               / (c.challenge_held_count + c.challenge_moved_count))::int
  end
  from public.question_vote_counts c
  where c.question_id = p_question_id;
$$;

revoke all on function public.question_flip_pct(uuid)
  from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 4) record_smaczek_challenge — the ONLY writer of the challenge columns.
--    First write wins: the gate runs once per vote row, and a repeated call
--    (client retry, replay) is a no-op that still returns the fresh state.
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
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if p_outcome not in ('held', 'moved', 'dismissed') then
    raise exception 'invalid outcome %', p_outcome;
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
         challenge_outcome    = p_outcome,
         challenge_dwell_ms   = case
           when p_dwell_ms is null then null
           else least(greatest(p_dwell_ms, 0), 600000)
         end
   where v.user_id = v_uid
     and v.question_id = p_question_id
     and v.challenge_outcome is null;
  v_claimed := found;

  -- Only real answers feed the flip stat; a dismissal is an exit, not data.
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
-- 5) get_daily_vote_state — base 20260815120000, plus flip_pct. Result shape
--    changes, so the old signature has to go first.
-- ----------------------------------------------------------------------------
drop function if exists public.get_daily_vote_state(uuid);

create function public.get_daily_vote_state(p_question_id uuid)
returns table (
  yes_count int,
  no_count  int,
  my_choice int,
  flip_pct  int
)
language sql stable security definer set search_path = public as $$
  select
    coalesce(c.yes_count, 0) + coalesce(sd.seed_yes, 0),
    coalesce(c.no_count,  0) + coalesce(sd.seed_no,  0),
    (select v2.choice::int
       from public.question_votes v2
      where v2.question_id = p_question_id
        and v2.user_id = auth.uid()),
    public.question_flip_pct(p_question_id)
  from (values (1)) as one(x)
  left join public.question_vote_counts c on c.question_id = p_question_id
  left join public.question_vote_seeds  sd on sd.question_id = p_question_id;
$$;

revoke all on function public.get_daily_vote_state(uuid) from public;
grant execute on function public.get_daily_vote_state(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 6) cast_daily_vote — base 20260815120000, plus flip_pct in the returned
--    row. Guard, upsert and streak logic are IDENTICAL; the arguments are
--    unchanged, so shipped versions keep calling it and ignore the new key.
-- ----------------------------------------------------------------------------
drop function if exists public.cast_daily_vote(uuid, int, date, text);

create function public.cast_daily_vote(
  p_question_id uuid,
  p_choice      int,
  p_date        date default (now() at time zone 'utc')::date,
  p_locale      text default 'pl'
)
returns table (
  yes_count int,
  no_count  int,
  my_choice int,
  flip_pct  int
)
language plpgsql security definer set search_path = public as $$
declare
  v_uid       uuid := auth.uid();
  v_today     date := (now() at time zone 'utc')::date;
  v_last_vote date;
  v_streak    int;
  v_longest   int;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if p_choice not in (1, 2) then
    raise exception 'invalid choice %', p_choice;
  end if;
  -- Votable = readable now (premium / own daily) OR actually shown via a paid
  -- reveal or a daily. 'view' stays excluded: it is an unpaid browse marker and
  -- would let a free user fabricate eligibility (see 20260712160000).
  if not (
    public.can_read_question_text(p_question_id, p_date)
    or exists (
      select 1 from public.question_seen s
      where s.user_id = v_uid
        and s.question_id = p_question_id
        and s.source in ('ad', 'free_credit', 'daily')
    )
  ) then
    raise exception 'question not readable';
  end if;

  -- Record / update the vote (changing your mind is allowed). The counter
  -- trigger turns this into a +1 / a side-swap / a no-op automatically.
  insert into public.question_votes (user_id, question_id, choice)
  values (v_uid, p_question_id, p_choice::smallint)
  on conflict (user_id, question_id)
  do update set choice = excluded.choice, voted_at = now();

  -- The streak: EVERY vote counts, at most once per UTC day. There is no
  -- daily-only branch anymore — "vote on anything today" is the streak rule in
  -- a feed where every question is votable, and it cannot be blocked by having
  -- already voted the served daily. Still keyed on the SERVER clock.
  select p.last_vote_date, p.current_streak, p.longest_streak
    into v_last_vote, v_streak, v_longest
  from public.profiles p
  where p.id = v_uid
  for update;

  if found and v_last_vote is distinct from v_today then
    v_streak := public.decayed_streak(v_streak, v_last_vote, v_today) + 1;
    update public.profiles
       set current_streak = v_streak,
           longest_streak = greatest(coalesce(v_longest, 0), v_streak),
           last_vote_date = v_today
     where id = v_uid;
  end if;

  return query
    select
      coalesce(c.yes_count, 0) + coalesce(sd.seed_yes, 0),
      coalesce(c.no_count,  0) + coalesce(sd.seed_no,  0),
      p_choice,
      public.question_flip_pct(p_question_id)
    from (values (1)) as one(x)
    left join public.question_vote_counts c on c.question_id = p_question_id
    left join public.question_vote_seeds  sd on sd.question_id = p_question_id;
end;
$$;

revoke all on function public.cast_daily_vote(uuid, int, date, text) from public;
grant execute on function public.cast_daily_vote(uuid, int, date, text) to authenticated;
