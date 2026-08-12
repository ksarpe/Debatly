-- ============================================================================
-- Streak · Daily voting · Free-unlock credit · Rank system
--
-- Adds the "engagement layer" on top of the question catalog:
--
--   * STREAK  — consecutive days the user voted on the daily. Built on top of
--               real binary voting (added here). The streak ledger lives on
--               profiles and is keyed on the SERVER UTC clock, so changing the
--               phone date can't earn streak days (same anti-tamper stance as
--               claim_daily_free_question).
--   * VOTING  — one binary vote (1 = TAK / 2 = NIE) per (user, question). Reading
--               the community split goes through a DEFINER RPC; a user never
--               reads other users' vote rows directly.
--   * CREDIT  — a daily free-unlock credit (cap 1, no stacking) the user spends
--               on a question of THEIR choice. Premium users don't have it. This
--               REPLACES the old random auto-bonus (dropped at the end).
--   * RANKS   — a data-driven ladder resolved from the CURRENT streak, so a
--               broken streak drops the user back down the ladder.
--
-- Readability of question TEXT is unchanged — it still uses the local-date ±1
-- clamp in can_read_question_text(). Only consumable/earned state (streak,
-- credit) is keyed on the pure server clock.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) PROFILES — streak + credit columns (server-managed; read-own RLS already
--    covers them, and no client write policy exists, so only the DEFINER RPCs
--    below ever change these).
-- ----------------------------------------------------------------------------
alter table public.profiles
  add column if not exists current_streak      int  not null default 0,
  add column if not exists longest_streak      int  not null default 0,
  add column if not exists last_vote_date      date,
  add column if not exists free_unlock_credits int  not null default 0,
  add column if not exists last_credit_date    date;

-- ----------------------------------------------------------------------------
-- 2) QUESTION VOTES — one binary vote per (user, question).
-- ----------------------------------------------------------------------------
create table if not exists public.question_votes (
  user_id     uuid     not null references auth.users(id)      on delete cascade,
  question_id uuid     not null references public.questions(id) on delete cascade,
  choice      smallint not null check (choice in (1, 2)),   -- 1 = TAK, 2 = NIE
  voted_at    timestamptz not null default now(),
  primary key (user_id, question_id)
);
create index if not exists question_votes_question_idx
  on public.question_votes (question_id);

alter table public.question_votes enable row level security;

-- Read-own only; all writes go through cast_daily_vote (DEFINER). Aggregate
-- counts are served by get_daily_vote_state (DEFINER), never by direct reads.
drop policy if exists "read own votes" on public.question_votes;
create policy "read own votes" on public.question_votes
  for select to authenticated
  using (user_id = auth.uid());

grant select on public.question_votes to authenticated;

-- ----------------------------------------------------------------------------
-- 3) RANKS — data-driven ladder. Small fixed list, so i18n is two columns
--    rather than a translations split. Edit/extend by changing these rows.
-- ----------------------------------------------------------------------------
create table if not exists public.ranks (
  tier       int  primary key,
  min_streak int  not null unique,    -- streak >= min_streak unlocks this tier
  name_pl    text not null,
  name_en    text not null,
  icon       text                     -- optional icon key for the client
);

alter table public.ranks enable row level security;

drop policy if exists "read ranks" on public.ranks;
create policy "read ranks" on public.ranks
  for select to anon, authenticated using (true);

grant select on public.ranks to anon, authenticated;

insert into public.ranks (tier, min_streak, name_pl, name_en, icon) values
  (0,   0, 'Amator kontrowersji', 'Controversy Amateur', 'seedling'),
  (1,   3, 'Prowokator',          'Provocateur',          'spark'),
  (2,   7, 'Podżegacz',           'Instigator',           'flame'),
  (3,  14, 'Adwokat diabła',      'Devil''s Advocate',    'mask'),
  (4,  30, 'Mąciciel',            'Troublemaker',         'storm'),
  (5,  60, 'Wichrzyciel',         'Agitator',             'bolt'),
  (6, 100, 'Legenda kontrowersji','Controversy Legend',   'crown')
on conflict (tier) do update
  set min_streak = excluded.min_streak,
      name_pl    = excluded.name_pl,
      name_en    = excluded.name_en,
      icon       = excluded.icon;

-- ----------------------------------------------------------------------------
-- 4) sync_user_state — the single stats row the top icons read, plus the
--    once-per-UTC-day free-credit top-up as a side effect (called on launch).
-- ----------------------------------------------------------------------------
create or replace function public.sync_user_state(p_locale text default 'pl')
returns table (
  current_streak      int,
  longest_streak      int,
  free_unlock_credits int,
  rank_tier           int,
  rank_name           text,
  next_rank_streak    int,
  is_premium          boolean
)
language plpgsql security definer set search_path = public as $$
declare
  v_uid       uuid := auth.uid();
  v_today     date := (now() at time zone 'utc')::date;   -- SERVER clock only
  v_premium   boolean;
  v_streak    int;
  v_longest   int;
  v_last_vote date;
  v_credits   int;
  v_last_cred date;
  v_disp      int;                                         -- display streak
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

  -- Display streak: still alive if the last vote was today or yesterday;
  -- otherwise it is broken and shows 0 (the stored value resets on next vote).
  if v_last_vote is null or v_last_vote < v_today - 1 then
    v_disp := 0;
  else
    v_disp := coalesce(v_streak, 0);
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
    v_premium
  from cur cross join nxt;
end;
$$;

revoke all on function public.sync_user_state(text) from public;
grant execute on function public.sync_user_state(text) to authenticated;

-- ----------------------------------------------------------------------------
-- 5) cast_daily_vote — record a binary vote and (when it's the daily) advance
--    the streak at most once per UTC day. Returns the community split.
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
    -- not bump it again.
    if v_last_vote is distinct from v_today then
      if v_last_vote = v_today - 1 then
        v_streak := coalesce(v_streak, 0) + 1;   -- consecutive day → extend
      else
        v_streak := 1;                           -- first day or broken → reset
      end if;
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

-- ----------------------------------------------------------------------------
-- 6) get_daily_vote_state — read-only community split + the caller's own vote
--    (null when they haven't voted), so a revisited daily renders results.
-- ----------------------------------------------------------------------------
create or replace function public.get_daily_vote_state(p_question_id uuid)
returns table (
  yes_count int,
  no_count  int,
  my_choice int
)
language sql stable security definer set search_path = public as $$
  select
    count(*) filter (where v.choice = 1)::int,
    count(*) filter (where v.choice = 2)::int,
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
-- 7) spend_free_unlock_credit — spend the daily credit on a chosen question.
--    Charges only on a FRESH unlock; returns the new credit balance.
-- ----------------------------------------------------------------------------
create or replace function public.spend_free_unlock_credit(p_question_id uuid)
returns int
language plpgsql security definer set search_path = public as $$
declare
  v_uid      uuid := auth.uid();
  v_credits  int;
  v_inserted int;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if public.is_premium(v_uid) then
    raise exception 'premium users do not use unlock credits';
  end if;
  if not exists (
    select 1 from public.questions q where q.id = p_question_id and q.is_active
  ) then
    raise exception 'question not found or inactive';
  end if;

  -- Lock the profile row so two taps can't both spend the same credit.
  select p.free_unlock_credits into v_credits
  from public.profiles p
  where p.id = v_uid
  for update;

  if coalesce(v_credits, 0) < 1 then
    raise exception 'no free unlock credits';
  end if;

  insert into public.question_unlocks (user_id, question_id, source)
  values (v_uid, p_question_id, 'free_credit')
  on conflict (user_id, question_id) do nothing;
  get diagnostics v_inserted = row_count;

  -- Already unlocked (nothing inserted) → don't charge.
  if v_inserted = 1 then
    v_credits := v_credits - 1;
    update public.profiles set free_unlock_credits = v_credits where id = v_uid;
  end if;

  return v_credits;
end;
$$;

revoke all on function public.spend_free_unlock_credit(uuid) from public;
grant execute on function public.spend_free_unlock_credit(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 8) Decommission the random auto-bonus — replaced by the credit above. Past
--    unlocks are preserved: they live in question_unlocks (source 'daily_free'),
--    not in this per-day ledger.
-- ----------------------------------------------------------------------------
drop function if exists public.claim_daily_free_question(text);
drop table if exists public.daily_free_grants;
