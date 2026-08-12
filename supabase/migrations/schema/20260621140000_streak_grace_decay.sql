-- ============================================================================
-- Streak GRACE / one-tier decay — replaces the "miss a day → reset to 0" rule.
--
-- OLD behaviour: the day after a missed daily, the display streak snapped to 0
-- and the next vote restarted at 1, so the rank fell straight to tier 0.
--
-- NEW behaviour (streak "freeze", like other games):
--   * Voting today or YESTERDAY keeps the streak fully intact (unchanged).
--   * The first FULL missed day starts a freeze counter. While the counter is
--     under GRACE (3) missed days, the streak is preserved — re-voting simply
--     continues it (the gap is forgiven).
--   * Every GRACE missed days the rank drops exactly ONE tier (the streak is
--     pulled down to that lower tier's threshold), and it keeps dropping one
--     tier per further GRACE days until it bottoms out at tier 0.
--
-- The decay is a PURE function of (stored streak, last_vote_date, server-UTC
-- today): both sync_user_state (display) and cast_daily_vote (the next vote's
-- baseline) run it, so it is idempotent and never double-counts — nothing is
-- eagerly persisted on a missed day. Still keyed on the SERVER UTC clock, so the
-- phone date can neither earn streak days nor dodge the decay.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) decayed_streak — the shared decay rule. Given the stored (peak) streak and
--    the last vote date, returns the streak value AFTER applying any tier drops
--    earned by missed days. GRACE missed days = one tier down; floors at 0.
-- ----------------------------------------------------------------------------
create or replace function public.decayed_streak(
  p_streak    int,
  p_last_vote date,
  p_today     date
)
returns int
language plpgsql stable security definer set search_path = public as $$
declare
  v_grace  constant int := 3;   -- full missed days that cost one tier
  v_missed int;
  v_drops  int;
  v_tier   int;
  v_target int;
  v_result int;
begin
  if p_last_vote is null then
    return 0;
  end if;

  -- Full days missed BEYOND "yesterday" (voting yesterday still keeps today's
  -- chance, so it does not count as missed). last_vote=today-2 → 1 missed day.
  v_missed := (p_today - p_last_vote) - 1;
  if v_missed <= 0 then
    return coalesce(p_streak, 0);            -- voted today / yesterday → intact
  end if;

  v_drops := v_missed / v_grace;             -- integer div: 3 missed = 1 drop
  if v_drops <= 0 then
    return coalesce(p_streak, 0);            -- still inside the first grace window
  end if;

  -- Resolve the current tier from the peak streak, step down v_drops tiers, and
  -- snap the streak to that tier's threshold.
  select r.tier into v_tier
  from public.ranks r
  where r.min_streak <= coalesce(p_streak, 0)
  order by r.min_streak desc
  limit 1;

  v_target := greatest(coalesce(v_tier, 0) - v_drops, 0);

  select r.min_streak into v_result
  from public.ranks r
  where r.tier = v_target;

  return coalesce(v_result, 0);
end;
$$;

revoke all on function public.decayed_streak(int, date, date) from public;
grant execute on function public.decayed_streak(int, date, date) to authenticated;

-- ----------------------------------------------------------------------------
-- 2) sync_user_state — recreated to (a) show the DECAYED streak/rank instead of
--    snapping to 0, and (b) return grace_days_left so the client can show the
--    freeze countdown. Return signature changes, so DROP + recreate.
-- ----------------------------------------------------------------------------
drop function if exists public.sync_user_state(text);

create function public.sync_user_state(p_locale text default 'pl')
returns table (
  current_streak      int,
  longest_streak      int,
  free_unlock_credits int,
  rank_tier           int,
  rank_name           text,
  next_rank_streak    int,
  grace_days_left     int,   -- days until the next one-tier drop, null when intact
  is_premium          boolean
)
language plpgsql security definer set search_path = public as $$
declare
  v_uid        uuid := auth.uid();
  v_today      date := (now() at time zone 'utc')::date;   -- SERVER clock only
  v_premium    boolean;
  v_streak     int;
  v_longest    int;
  v_last_vote  date;
  v_credits    int;
  v_last_cred  date;
  v_disp       int;     -- decayed display streak
  v_disp_tier  int;     -- rank tier resolved from the display streak
  v_missed     int;
  v_grace_left int;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  v_premium := public.is_premium(v_uid);

  -- Lock the profile row to serialize the credit top-up against itself.
  select p.current_streak, p.longest_streak, p.last_vote_date,
         p.free_unlock_credits, p.last_credit_date
    into v_streak, v_longest, v_last_vote, v_credits, v_last_cred
  from public.profiles p
  where p.id = v_uid
  for update;

  if not found then
    v_streak := 0; v_longest := 0; v_credits := 0;
  end if;

  -- Free-unlock credit: premium never has one; everyone else is topped up to
  -- exactly 1 once per UTC day (greatest() caps it, so holding one earns none).
  if v_premium then
    if coalesce(v_credits, 0) <> 0 then
      update public.profiles set free_unlock_credits = 0 where id = v_uid;
      v_credits := 0;
    end if;
  elsif v_last_cred is null or v_last_cred < v_today then
    v_credits := greatest(coalesce(v_credits, 0), 1);
    update public.profiles
       set free_unlock_credits = v_credits,
           last_credit_date     = v_today
     where id = v_uid;
  end if;

  -- Display streak: the decayed value (one tier per 3 missed days), NOT 0.
  v_disp := public.decayed_streak(v_streak, v_last_vote, v_today);

  -- Tier the display streak currently sits in.
  select r.tier into v_disp_tier
  from public.ranks r
  where r.min_streak <= v_disp
  order by r.min_streak desc
  limit 1;
  v_disp_tier := coalesce(v_disp_tier, 0);

  -- Freeze countdown: only while the user has started missing days AND still has
  -- a tier left to lose. Drops land at missed = 3, 6, 9, … so the gap to the
  -- next drop is 3 - (missed mod 3) (which is 3 right after a drop).
  if v_last_vote is not null and v_disp_tier > 0 then
    v_missed := (v_today - v_last_vote) - 1;
    if v_missed >= 1 then
      v_grace_left := 3 - (v_missed % 3);
    end if;
  end if;

  return query
  with cur as (
    select r.tier, r.name_pl, r.name_en
    from public.ranks r
    where r.min_streak <= v_disp
    order by r.min_streak desc
    limit 1
  ),
  nxt as (
    select min(r.min_streak) as next_streak
    from public.ranks r
    where r.min_streak > v_disp
  )
  select
    v_disp,
    coalesce(v_longest, 0),
    coalesce(v_credits, 0),
    cur.tier,
    case when p_locale = 'pl' then cur.name_pl else cur.name_en end,
    nxt.next_streak,
    v_grace_left,
    v_premium
  from cur cross join nxt;
end;
$$;

revoke all on function public.sync_user_state(text) from public;
grant execute on function public.sync_user_state(text) to authenticated;

-- ----------------------------------------------------------------------------
-- 3) cast_daily_vote — recreated so a vote extends from the DECAYED baseline
--    instead of resetting to 1. Same signature, body change only.
--
--    new_streak = decayed_streak(stored, last_vote, today) + 1:
--      * voted yesterday  → decayed == stored      → stored + 1 (as before)
--      * within grace gap → decayed == stored      → streak continues, gap forgiven
--      * past a grace gap → decayed == lower tier  → resume from that tier + 1
--      * first vote ever  → decayed == 0           → 1
-- ----------------------------------------------------------------------------
create or replace function public.cast_daily_vote(
  p_question_id uuid,
  p_choice      int,
  p_date        date default (now() at time zone 'utc')::date,
  p_locale      text default 'pl'
)
returns table (
  yes_count int,
  no_count  int,
  my_choice int
)
language plpgsql security definer set search_path = public as $$
declare
  v_uid       uuid := auth.uid();
  v_today     date := (now() at time zone 'utc')::date;
  v_is_daily  boolean;
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
  -- Only let the user vote on a question they may actually read.
  if not public.can_read_question_text(p_question_id, p_date) then
    raise exception 'question not readable';
  end if;

  -- Record / update the vote (changing your mind is allowed).
  insert into public.question_votes (user_id, question_id, choice)
  values (v_uid, p_question_id, p_choice::smallint)
  on conflict (user_id, question_id)
  do update set choice = excluded.choice, voted_at = now();

  -- The streak only moves for a CURRENT daily (within the UTC ±1 clamp).
  select exists (
    select 1 from public.daily_questions d
    where d.question_id = p_question_id
      and d.publish_date between v_today - 1 and v_today + 1
  ) into v_is_daily;

  if v_is_daily then
    select p.last_vote_date, p.current_streak, p.longest_streak
      into v_last_vote, v_streak, v_longest
    from public.profiles p
    where p.id = v_uid
    for update;

    -- At most once per UTC day: re-voting / changing choice the same day does
    -- not bump it again. Otherwise extend from the decayed baseline (which is
    -- the unchanged streak unless a grace window has fully elapsed).
    if v_last_vote is distinct from v_today then
      v_streak := public.decayed_streak(v_streak, v_last_vote, v_today) + 1;
      update public.profiles
         set current_streak = v_streak,
             longest_streak = greatest(coalesce(v_longest, 0), v_streak),
             last_vote_date = v_today
       where id = v_uid;
    end if;
  end if;

  return query
    select
      count(*) filter (where v.choice = 1)::int,
      count(*) filter (where v.choice = 2)::int,
      p_choice
    from public.question_votes v
    where v.question_id = p_question_id;
end;
$$;

revoke all on function public.cast_daily_vote(uuid, int, date, text) from public;
grant execute on function public.cast_daily_vote(uuid, int, date, text) to authenticated;
