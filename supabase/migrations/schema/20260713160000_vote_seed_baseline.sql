-- ============================================================================
-- Vote seed baseline — hand-curated phantom votes per question.
--
-- WHY
--   Cold start: with few users every split reads 100%–0% after one vote, which
--   kills the "how did others vote?" aha. Industry-standard fix (Reddit-style
--   seeding): give every question a curated baseline the real votes are added
--   on top of. The UI shows percentages only (vote_visuals.dart), so the
--   baseline surfaces as a plausible split, never as a fake absolute count.
--
-- DESIGN
--   * A SEPARATE table, not columns on `questions` — `questions` is client-
--     readable (grant select to anon/authenticated since init.sql), and the
--     seed values must not be visible to clients. This table has NO client
--     grants and RLS enabled with no policies; only the security-definer RPCs
--     (owner: postgres) and the SQL editor / service_role read it.
--   * You curate TWO numbers per question, by hand:
--       seed_yes_pct — percent of TAK in the baseline (0..100)
--       seed_total   — how many phantom votes the baseline is worth;
--                      0 = seeding disabled for that question (the default,
--                      so applying this migration changes nothing until the
--                      values are filled in)
--     seed_yes / seed_no are derived (generated columns) and are what the
--     RPCs add to the real counts. As real votes accumulate they naturally
--     drown the baseline out; no decay mechanism needed.
--   * Every question gets a prefilled row (50 / 0) so the Excel round-trip is
--     a pure UPDATE — no missing rows to worry about.
--
-- MANUAL CURATION WORKFLOW
--   Export for Excel (SQL editor → download CSV):
--     select s.question_id, t.question_text, s.seed_yes_pct, s.seed_total
--     from public.question_vote_seeds s
--     left join public.question_translations t
--            on t.question_id = s.question_id and t.locale = 'pl'
--     order by t.question_text;
--   Import back: generate one guarded UPDATE per edited row, e.g.
--     update public.question_vote_seeds
--        set seed_yes_pct = 63, seed_total = 180
--      where question_id = '<uuid>';
--
-- TOUCHES (all four tally-returning RPCs, latest prod versions as base):
--   cast_daily_vote      (base: 20260713120000)
--   get_daily_vote_state (base: 20260619140000)
--   get_vote_history     (base: 20260712190000)
--   get_daily_history    (base: 20260713120000, legacy shipped clients)
--
-- Idempotent: guarded DDL, ON CONFLICT DO NOTHING prefill, CREATE OR REPLACE.
-- Safe to apply immediately: with seed_total = 0 every RPC returns exactly
-- what it returns today.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) The seeds table.
-- ----------------------------------------------------------------------------
create table if not exists public.question_vote_seeds (
  question_id  uuid primary key references public.questions(id) on delete cascade,
  seed_yes_pct smallint not null default 50 check (seed_yes_pct between 0 and 100),
  seed_total   integer  not null default 0  check (seed_total >= 0),
  -- Derived counts the RPCs add to the real tallies.
  seed_yes integer generated always as
    (round((seed_total * seed_yes_pct)::numeric / 100)::integer) stored,
  seed_no integer generated always as
    (seed_total - round((seed_total * seed_yes_pct)::numeric / 100)::integer) stored
);

comment on table public.question_vote_seeds is
  'Hand-curated baseline ("phantom") votes added to real tallies by the RPCs. '
  'seed_total = 0 disables seeding for the question. Never client-readable.';

-- Deny-all for clients: RLS on with no policies, and no grants either.
alter table public.question_vote_seeds enable row level security;
revoke all on public.question_vote_seeds from public, anon, authenticated;
-- service_role bypasses RLS but still needs GRANTs (see 2026-07-05 lesson).
grant all on public.question_vote_seeds to service_role;

-- Prefill one row per question (baseline disabled) so the export always has
-- all 1000 rows and the import is a pure UPDATE.
insert into public.question_vote_seeds (question_id, seed_yes_pct, seed_total)
select q.id, 50, 0
from public.questions q
on conflict (question_id) do nothing;

-- ----------------------------------------------------------------------------
-- 2) cast_daily_vote — identical to 20260713120000 except the returned tally
--    adds the seed baseline.
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

  -- Record / update the vote (changing your mind is allowed).
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
      (count(*) filter (where v.choice = 1))::int
        + coalesce((select sd.seed_yes from public.question_vote_seeds sd
                    where sd.question_id = p_question_id), 0),
      (count(*) filter (where v.choice = 2))::int
        + coalesce((select sd.seed_no from public.question_vote_seeds sd
                    where sd.question_id = p_question_id), 0),
      p_choice
    from public.question_votes v
    where v.question_id = p_question_id;
end;
$$;

revoke all on function public.cast_daily_vote(uuid, int, date, text) from public;
grant execute on function public.cast_daily_vote(uuid, int, date, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 3) get_daily_vote_state — identical to 20260619140000 plus the baseline.
-- ----------------------------------------------------------------------------
create or replace function public.get_daily_vote_state(p_question_id uuid)
returns table (
  yes_count int,
  no_count  int,
  my_choice int
)
language sql stable security definer set search_path = public as $$
  select
    (count(*) filter (where v.choice = 1))::int
      + coalesce((select sd.seed_yes from public.question_vote_seeds sd
                  where sd.question_id = p_question_id), 0),
    (count(*) filter (where v.choice = 2))::int
      + coalesce((select sd.seed_no from public.question_vote_seeds sd
                  where sd.question_id = p_question_id), 0),
    (select v2.choice::int
       from public.question_votes v2
      where v2.question_id = p_question_id
        and v2.user_id = auth.uid())
  from public.question_votes v
  where v.question_id = p_question_id;
$$;

revoke all on function public.get_daily_vote_state(uuid) from public;
grant execute on function public.get_daily_vote_state(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 4) get_vote_history — identical to 20260712190000 plus the baseline
--    (left join; missing seed row counts as 0).
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
  ),
  splits as (
    -- One grouped pass for the community split of just those questions.
    select v.question_id,
           count(*) filter (where v.choice = 1)::int as yes_count,
           count(*) filter (where v.choice = 2)::int as no_count
    from public.question_votes v
    where v.question_id in (select m.question_id from mine m)
    group by v.question_id
  )
  select
    q.id,
    q.category,
    coalesce(tr.question_text, en.question_text),
    mine.voted_at,
    coalesce(s.yes_count, 0) + coalesce(sd.seed_yes, 0),
    coalesce(s.no_count, 0) + coalesce(sd.seed_no, 0),
    mine.choice::int
  from mine
  join public.questions q on q.id = mine.question_id and q.is_active
  left join public.question_translations tr
         on tr.question_id = q.id and tr.locale = p_locale
  left join public.question_translations en
         on en.question_id = q.id and en.locale = 'en'
  left join splits s on s.question_id = mine.question_id
  left join public.question_vote_seeds sd on sd.question_id = q.id
  order by mine.voted_at desc;
end;
$function$;

revoke all on function public.get_vote_history(text) from public, anon;
grant execute on function public.get_vote_history(text) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 5) get_daily_history (legacy shipped clients) — identical to 20260713120000
--    plus the baseline, so old and new clients show the same split.
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
      coalesce(vc.no_count, 0) + coalesce(sd.seed_no, 0),
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
    left join lateral (
      select
        count(*) filter (where v.choice = 1)::int as yes_count,
        count(*) filter (where v.choice = 2)::int as no_count
      from public.question_votes v
      where v.question_id = q.id
    ) vc on true
    left join public.question_vote_seeds sd on sd.question_id = q.id
    order by dedup.day desc
    limit 366;
end;
$function$;

revoke all on function public.get_daily_history(text, date) from public, anon;
grant execute on function public.get_daily_history(text, date) to authenticated, service_role;
