-- ============================================================================
-- Denormalised per-question vote counters — the TODO left in 20260712190000.
--
-- THE PROBLEM
--   Every place that shows a community split recomputes it from scratch:
--
--     get_daily_vote_state  count(*) filter (...) over question_votes  -- EVERY
--                                                                     -- panel
--     cast_daily_vote       same aggregate, on EVERY vote
--     get_vote_history      one grouped pass over the votes of <=1000 questions
--     get_daily_history     a correlated lateral aggregate PER history row
--
--   The work is O(votes on that question), so it grows with popularity: today a
--   question has a handful of votes and the aggregate is free, at 10k users a
--   popular question has thousands and every single panel open pays for all of
--   them again. The index question_votes(question_id) makes it an index scan
--   rather than a seq scan, but an index scan of N rows is still N rows — you
--   cannot count what you do not read.
--
-- THE FIX
--   question_vote_counts (question_id pk, yes_count, no_count), maintained by a
--   row trigger on question_votes. Reading a split becomes ONE primary-key
--   lookup — O(1), independent of vote volume — instead of an aggregate.
--   Writing a vote costs one extra single-row UPDATE, which is O(1) too.
--
-- WHAT IS **NOT** CHANGED
--   * Signatures, return shapes, premium gates and grants of all four RPCs:
--     identical. No client change, no shipped-version break.
--   * The seed baseline (20260713160000) still lives in question_vote_seeds and
--     is still added on read. Only the REAL half of the tally moves.
--   * question_votes itself: same columns, same RLS, same indexes. It stays the
--     source of truth; the counters are a cache that can be rebuilt from it at
--     any time (see rebuild_question_vote_counts below).
--   * The admin dashboard / farming views keep aggregating question_votes
--     directly — they slice by day and by internal-user filter, which a
--     per-question counter cannot answer.
--
-- TRADE-OFF (accepted deliberately)
--   All votes on one question now serialise on that question's counter row for
--   the tail of the vote transaction (~1 ms). That is the standard cost of a
--   denormalised counter and is irrelevant at any realistic Debatly write rate;
--   if a single question ever sustains hundreds of votes/second, the escape
--   hatch is delta rows + periodic rollup, not going back to count(*).
--
-- DRIFT CHECK (should always return zero rows)
--   select c.question_id, c.yes_count, c.no_count, t.yes_count, t.no_count
--   from public.question_vote_counts c
--   left join (
--     select question_id,
--            count(*) filter (where choice = 1)::int as yes_count,
--            count(*) filter (where choice = 2)::int as no_count
--     from public.question_votes group by question_id) t
--     on t.question_id = c.question_id
--   where c.yes_count is distinct from coalesce(t.yes_count, 0)
--      or c.no_count  is distinct from coalesce(t.no_count, 0);
--   Repair: select public.rebuild_question_vote_counts();
--
-- Idempotent: guarded DDL, create-or-replace, drop-then-create triggers, and a
-- rebuild that is an absolute assignment (never a delta).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) The counter table. Server-side only: RLS on with no policies and no client
--    grants — clients read splits through the security-definer RPCs, exactly as
--    before, and question_vote_seeds is locked down the same way.
-- ----------------------------------------------------------------------------
create table if not exists public.question_vote_counts (
  question_id uuid primary key references public.questions(id) on delete cascade,
  yes_count   integer     not null default 0,
  no_count    integer     not null default 0,
  updated_at  timestamptz not null default now()
);

comment on table public.question_vote_counts is
  'Denormalised real vote tally per question, maintained by the trigger on '
  'question_votes. A cache: question_votes is the source of truth and '
  'rebuild_question_vote_counts() restores this table from it. Does NOT '
  'include the question_vote_seeds baseline — the RPCs add that on read.';

alter table public.question_vote_counts enable row level security;
revoke all on public.question_vote_counts from public, anon, authenticated;
-- service_role bypasses RLS but still needs GRANTs (see 2026-07-05 lesson).
grant all on public.question_vote_counts to service_role;

-- ----------------------------------------------------------------------------
-- 2) The delta applier. Split out of the trigger so the two-question case
--    (a vote moved between questions) is one call per side.
--    Counts are floored at 0: a counter that somehow drifted negative would
--    render as a nonsense split, and the drift check + rebuild is the cure.
-- ----------------------------------------------------------------------------
create or replace function public.apply_question_vote_delta(
  p_question_id uuid,
  p_yes_delta   int,
  p_no_delta    int
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_yes_delta = 0 and p_no_delta = 0 then
    return;
  end if;

  update public.question_vote_counts
     set yes_count  = greatest(yes_count + p_yes_delta, 0),
         no_count   = greatest(no_count  + p_no_delta,  0),
         updated_at = now()
   where question_id = p_question_id;

  if found then
    return;
  end if;

  -- No counter row yet (a question inserted while this migration was mid-flight,
  -- or a row hand-deleted). Create it — but ONLY while the question still
  -- exists, so that deleting a question, which cascades into question_votes and
  -- fires this trigger per vote, cannot resurrect a counter for it.
  insert into public.question_vote_counts as c (question_id, yes_count, no_count)
  select p_question_id, greatest(p_yes_delta, 0), greatest(p_no_delta, 0)
  where exists (select 1 from public.questions q where q.id = p_question_id)
  on conflict (question_id) do update
     set yes_count  = greatest(c.yes_count + greatest(p_yes_delta, 0), 0),
         no_count   = greatest(c.no_count  + greatest(p_no_delta,  0), 0),
         updated_at = now();
end;
$$;

revoke all on function public.apply_question_vote_delta(uuid, int, int)
  from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 3) The trigger on question_votes. SECURITY DEFINER (owner postgres) so it can
--    write the counter table no matter which role wrote the vote: today that is
--    always the definer RPCs, but a service_role fixup or a cascade delete must
--    keep the counters honest too.
--
--    cast_daily_vote upserts with `do update set choice = excluded.choice,
--    voted_at = now()`, so an UPDATE fires even when the user re-picks the SAME
--    side. That case is a no-op here.
-- ----------------------------------------------------------------------------
create or replace function public.question_votes_sync_counts()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    perform public.apply_question_vote_delta(
      new.question_id,
      (new.choice = 1)::int,
      (new.choice = 2)::int);

  elsif tg_op = 'DELETE' then
    perform public.apply_question_vote_delta(
      old.question_id,
      - (old.choice = 1)::int,
      - (old.choice = 2)::int);

  else -- UPDATE
    if old.question_id = new.question_id then
      -- Re-vote on the same side: only voted_at moved, the tally did not.
      if old.choice = new.choice then
        return null;
      end if;
      perform public.apply_question_vote_delta(
        new.question_id,
        (new.choice = 1)::int - (old.choice = 1)::int,
        (new.choice = 2)::int - (old.choice = 2)::int);
    else
      -- A vote row changing question_id never happens in the app; handled so
      -- that a manual fixup cannot silently rot both counters.
      perform public.apply_question_vote_delta(
        old.question_id,
        - (old.choice = 1)::int,
        - (old.choice = 2)::int);
      perform public.apply_question_vote_delta(
        new.question_id,
        (new.choice = 1)::int,
        (new.choice = 2)::int);
    end if;
  end if;

  return null;
end;
$$;

revoke all on function public.question_votes_sync_counts() from public, anon, authenticated;

drop trigger if exists question_votes_sync_counts on public.question_votes;
create trigger question_votes_sync_counts
  after insert or update or delete on public.question_votes
  for each row execute function public.question_votes_sync_counts();

-- ----------------------------------------------------------------------------
-- 4) Every question gets a counter row from birth, so the hot path in (2) is a
--    plain single-row UPDATE and never has to probe for existence first.
-- ----------------------------------------------------------------------------
create or replace function public.questions_seed_vote_counts()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.question_vote_counts (question_id)
  values (new.id)
  on conflict (question_id) do nothing;
  return null;
end;
$$;

revoke all on function public.questions_seed_vote_counts() from public, anon, authenticated;

drop trigger if exists questions_seed_vote_counts on public.questions;
create trigger questions_seed_vote_counts
  after insert on public.questions
  for each row execute function public.questions_seed_vote_counts();

-- ----------------------------------------------------------------------------
-- 5) Rebuild from the source of truth. Absolute assignment, so it is both the
--    initial backfill and the repair tool. Returns the number of rows written.
-- ----------------------------------------------------------------------------
create or replace function public.rebuild_question_vote_counts()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_rows integer;
begin
  insert into public.question_vote_counts as c (question_id, yes_count, no_count, updated_at)
  select q.id,
         coalesce(t.yes_count, 0),
         coalesce(t.no_count, 0),
         now()
  from public.questions q
  left join (
    select v.question_id,
           count(*) filter (where v.choice = 1)::int as yes_count,
           count(*) filter (where v.choice = 2)::int as no_count
    from public.question_votes v
    group by v.question_id
  ) t on t.question_id = q.id
  on conflict (question_id) do update
     set yes_count  = excluded.yes_count,
         no_count   = excluded.no_count,
         updated_at = now();

  get diagnostics v_rows = row_count;
  return v_rows;
end;
$$;

comment on function public.rebuild_question_vote_counts() is
  'Recomputes question_vote_counts from question_votes (absolute, not delta). '
  'Safe to run any time; use it after a manual vote fixup or if the drift '
  'check in 20260815120000 returns rows.';

revoke all on function public.rebuild_question_vote_counts() from public, anon, authenticated;
grant execute on function public.rebuild_question_vote_counts() to service_role;

-- The initial backfill. Runs AFTER the trigger exists: a vote committed by a
-- concurrent session before this statement is included in the snapshot, and one
-- committed after it waits on the row lock and then applies its delta on top —
-- so no vote is double-counted or lost either way.
do $$ begin perform public.rebuild_question_vote_counts(); end $$;

-- ----------------------------------------------------------------------------
-- 6) get_daily_vote_state — base 20260713160000. Same signature, same single
--    row (the `from (values (1))` keeps the "always exactly one row, my_choice
--    null when not voted" contract that the aggregate gave for free), same
--    seed baseline. Only the real tally now comes from the counter table.
-- ----------------------------------------------------------------------------
create or replace function public.get_daily_vote_state(p_question_id uuid)
returns table (
  yes_count int,
  no_count  int,
  my_choice int
)
language sql stable security definer set search_path = public as $$
  select
    coalesce(c.yes_count, 0) + coalesce(sd.seed_yes, 0),
    coalesce(c.no_count,  0) + coalesce(sd.seed_no,  0),
    (select v2.choice::int
       from public.question_votes v2
      where v2.question_id = p_question_id
        and v2.user_id = auth.uid())
  from (values (1)) as one(x)
  left join public.question_vote_counts c on c.question_id = p_question_id
  left join public.question_vote_seeds  sd on sd.question_id = p_question_id;
$$;

revoke all on function public.get_daily_vote_state(uuid) from public;
grant execute on function public.get_daily_vote_state(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 7) cast_daily_vote — base 20260713160000. Identical guard, identical upsert,
--    identical streak logic; only the returned tally is read from the counter
--    row that this statement's own trigger just updated (same transaction, so
--    the value already includes this vote).
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
      p_choice
    from (values (1)) as one(x)
    left join public.question_vote_counts c on c.question_id = p_question_id
    left join public.question_vote_seeds  sd on sd.question_id = p_question_id;
end;
$$;

revoke all on function public.cast_daily_vote(uuid, int, date, text) from public;
grant execute on function public.cast_daily_vote(uuid, int, date, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 8) get_vote_history — base 20260713160000. The `mine` CTE (bounded, ordered
--    index scan) stays exactly as 20260712190000 designed it; the `splits`
--    grouped pass it feeds is replaced by a PK join on the counters, so the
--    tally cost drops from "read every vote of up to 1000 questions" to "1000
--    index lookups".
-- ----------------------------------------------------------------------------
create or replace function public.get_vote_history(
  p_locale text default 'pl'
)
returns table(
  question_id uuid,
  category text,
  question_text text,
  voted_at timestamptz,
  yes_count int,
  no_count int,
  my_choice int
)
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid := auth.uid();
begin
  -- History is a PRO feature: no session or no premium → nothing to show.
  if v_uid is null or not public.is_premium(v_uid) then
    return;
  end if;

  return query
  with mine as (
    -- The caller's most recent 1000 votes — bound the work BEFORE tallying.
    select mv.question_id, mv.choice, mv.voted_at
    from public.question_votes mv
    where mv.user_id = v_uid
    order by mv.voted_at desc
    limit 1000
  )
  select
    q.id,
    q.category,
    coalesce(tr.question_text, en.question_text),
    mine.voted_at,
    coalesce(c.yes_count, 0) + coalesce(sd.seed_yes, 0),
    coalesce(c.no_count,  0) + coalesce(sd.seed_no,  0),
    mine.choice::int
  from mine
  join public.questions q on q.id = mine.question_id and q.is_active
  left join public.question_translations tr
         on tr.question_id = q.id and tr.locale = p_locale
  left join public.question_translations en
         on en.question_id = q.id and en.locale = 'en'
  left join public.question_vote_counts c on c.question_id = q.id
  left join public.question_vote_seeds sd on sd.question_id = q.id
  order by mine.voted_at desc;
end;
$function$;

revoke all on function public.get_vote_history(text) from public, anon;
grant execute on function public.get_vote_history(text) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 9) get_daily_history (legacy shipped clients) — base 20260713160000. The
--    per-row correlated `left join lateral` aggregate, the worst offender of
--    the four, becomes a PK join. Everything else (union of calendar + personal
--    days, dedup, voted-only, premium gate, limit 366) is unchanged.
-- ----------------------------------------------------------------------------
create or replace function public.get_daily_history(
  p_locale text default 'pl',
  p_date date default ((now() at time zone 'utc')::date)
)
returns table(
  question_id uuid,
  category text,
  question_text text,
  publish_date date,
  yes_count int,
  no_count int,
  my_choice int
)
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_uid   uuid := auth.uid();
  v_today date := (now() at time zone 'utc')::date;
begin
  -- History is a PRO feature: no session or no premium → nothing to show.
  if v_uid is null or not public.is_premium(v_uid) then
    return;
  end if;

  return query
    with days as (
      -- Legacy: the global calendar (votes cast while the daily was shared).
      select d.question_id as qid, d.publish_date as day
      from public.daily_questions d
      where d.publish_date < p_date and d.publish_date <= v_today
      union
      -- Personal assignments since the switch.
      select ud.question_id, ud.assigned_on
      from public.user_daily_questions ud
      where ud.user_id = v_uid
        and ud.assigned_on < p_date and ud.assigned_on <= v_today
    ),
    dedup as (
      select distinct on (days.qid) days.qid, days.day
      from days
      order by days.qid, days.day desc
    )
    select
      q.id,
      q.category,
      coalesce(tr.question_text, en.question_text),
      dedup.day,
      coalesce(vc.yes_count, 0) + coalesce(sd.seed_yes, 0),
      coalesce(vc.no_count,  0) + coalesce(sd.seed_no,  0),
      mv.choice::int
    from dedup
    join public.questions q on q.id = dedup.qid and q.is_active
    -- Voted-only: the community split stays a reward for voting.
    join public.question_votes mv
           on mv.question_id = q.id and mv.user_id = v_uid
    left join public.question_translations tr
           on tr.question_id = q.id and tr.locale = p_locale
    left join public.question_translations en
           on en.question_id = q.id and en.locale = 'en'
    left join public.question_vote_counts vc on vc.question_id = q.id
    left join public.question_vote_seeds sd on sd.question_id = q.id
    order by dedup.day desc
    limit 366;
end;
$function$;

revoke all on function public.get_daily_history(text, date) from public, anon;
grant execute on function public.get_daily_history(text, date) to authenticated, service_role;
