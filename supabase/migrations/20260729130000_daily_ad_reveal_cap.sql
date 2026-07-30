-- ============================================================================
-- Daily cap on ad reveals: at most 3 per UTC day (free tier).
--
-- WHY
--   The rewarded-ad path had no quantity limit: as long as each reveal was
--   backed by a verified SSV reward (see 20260622160000), a user could watch
--   ads back-to-back indefinitely and drain the catalog for free. That quietly
--   destroys the PRO value proposition — content consumed for free cannot be
--   re-sold — and contradicts the scarcity story the free tier tells (the
--   daily + one credit "meter"). A DAILY cap (industry-standard 3-5) beats a
--   lifetime cap: the wall re-appears every day at the moment of highest
--   intent (the user wants MORE now), which is exactly when the PRO paywall
--   converts, while "come back tomorrow" keeps non-payers returning, voting
--   and watching a few ads instead of uninstalling.
--
-- HOW
--   * profiles gains a per-day counter (ad_reveals_today + last_ad_reveal_date)
--     mirroring the free-credit pattern (free_unlock_credits/last_credit_date):
--     O(1), exact, reset lazily on first use of a new UTC day.
--   * The cap lives in ONE place — ad_reveal_daily_cap() — read by both
--     reveal_ad_question (enforcement) and sync_user_state (reporting), so the
--     two can never drift. Tuning the cap = replacing that one-liner.
--   * reveal_ad_question raises 'daily ad reveal limit reached' BEFORE the SSV
--     budget gate and before anything is spent. The cap counts the SERVER's
--     UTC day (never client-supplied p_date, which would let a tampered client
--     roll the day over at will).
--   * sync_user_state returns ad_reveals_left_today (null for premium, who
--     never see the ad wall) so the client can hide the "watch an ad" button
--     BEFORE an ad plays — the RPC error is defense-in-depth for tampered or
--     stale clients, not the primary UX. Extra return column only: name +
--     args unchanged, old store clients simply ignore the new key.
-- ============================================================================

alter table public.profiles
  add column if not exists ad_reveals_today    int  not null default 0,
  add column if not exists last_ad_reveal_date date;

-- Single source of truth for the cap (enforcement + reporting read this).
create or replace function public.ad_reveal_daily_cap()
returns int
language sql immutable
as $$ select 3 $$;

revoke all on function public.ad_reveal_daily_cap() from public;
grant execute on function public.ad_reveal_daily_cap() to authenticated;

-- ----------------------------------------------------------------------------
-- reveal_ad_question — unchanged except the new daily-cap gate (first) and the
-- per-day counter bump on spend. Signature identical (grants preserved,
-- re-asserted anyway). Based on the latest definition (20260712170000).
-- ----------------------------------------------------------------------------
create or replace function public.reveal_ad_question(
  p_locale      text  default 'pl',
  p_date        date  default (now() at time zone 'utc')::date,
  p_question_id uuid  default null,
  p_exclude_ids uuid[] default '{}'
)
returns table (id uuid, category text, is_premium boolean, question_text text)
language plpgsql security definer set search_path to 'public'
as $$
declare
  c_grace     constant int := 2;
  v_uid       uuid := auth.uid();
  v_today     date := (now() at time zone 'utc')::date; -- server clock, not p_date
  v_qid       uuid;
  v_used      int;
  v_verified  int;
  v_ads_today int;
  v_last_ad   date;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  -- Lock the profile row so two concurrent taps can't both pass the gates.
  select p.ad_reveals_used, p.ad_reveals_today, p.last_ad_reveal_date
    into v_used, v_ads_today, v_last_ad
  from public.profiles p
  where p.id = v_uid
  for update;

  -- Daily cap gate: lazy reset when the last ad reveal was on an earlier day.
  if v_last_ad is distinct from v_today then
    v_ads_today := 0;
  end if;
  if coalesce(v_ads_today, 0) >= public.ad_reveal_daily_cap() then
    -- The client hides the ad button when the synced count hits the cap, so
    -- landing here means a stale or tampered client; it surfaces as a toast +
    -- the PRO-only paywall (no ad has played for this attempt's reveal).
    raise exception 'daily ad reveal limit reached';
  end if;

  -- Budget gate: the reveal must be backed by a verified ad reward (+ grace).
  select count(*) into v_verified
  from public.ad_reward_events e
  where e.user_id = v_uid and e.verified;

  if coalesce(v_used, 0) >= coalesce(v_verified, 0) + c_grace then
    raise exception 'ad reward not verified';
  end if;

  -- Prefer the peeked (teased) question, but only if it is still eligible: not
  -- today's daily and NOT YET VOTED (a shown-but-unvoted peek is fine to reveal).
  if p_question_id is not null then
    select q.id into v_qid
    from public.questions q
    where q.id = p_question_id
      and q.is_active
      and not exists (
        select 1 from public.daily_questions d
        where d.question_id = q.id and d.publish_date = p_date
      )
      and not exists (
        select 1 from public.question_votes v
        where v.user_id = v_uid and v.question_id = q.id
      );
  end if;

  -- No (valid) peek: random UNVOTED pick, skipping this session's shown ids so a
  -- watched ad never re-serves a question already on screen this session.
  if v_qid is null then
    select q.id into v_qid
    from public.questions q
    where q.is_active
      and not (q.id = any (p_exclude_ids))
      and not exists (
        select 1 from public.daily_questions d
        where d.question_id = q.id and d.publish_date = p_date
      )
      and not exists (
        select 1 from public.question_votes v
        where v.user_id = v_uid and v.question_id = q.id
      )
    order by random()
    limit 1;
  end if;

  -- Nothing votable left: return no row and DON'T spend budget on an empty reveal.
  if v_qid is null then
    return;
  end if;

  -- Record that the user was SHOWN this text (the smaczki + vote gates read this).
  insert into public.question_seen (user_id, question_id, source)
  values (v_uid, v_qid, 'ad')
  on conflict (user_id, question_id) do nothing;

  -- Spend one unit of the ad-reveal budget and one slot of today's cap
  -- (only on a real reveal).
  update public.profiles
     set ad_reveals_used     = coalesce(v_used, 0) + 1,
         ad_reveals_today    = coalesce(v_ads_today, 0) + 1,
         last_ad_reveal_date = v_today
   where profiles.id = v_uid;

  return query
    select q.id, q.category, q.is_premium,
           coalesce(tr.question_text, en.question_text)
    from public.questions q
    left join public.question_translations tr
           on tr.question_id = q.id and tr.locale = p_locale
    left join public.question_translations en
           on en.question_id = q.id and en.locale = 'en'
    where q.id = v_qid;
end;
$$;

revoke all on function public.reveal_ad_question(text, date, uuid, uuid[]) from public;
grant execute on function public.reveal_ad_question(text, date, uuid, uuid[]) to authenticated;

-- ----------------------------------------------------------------------------
-- sync_user_state — gains ad_reveals_left_today in the returned row (null for
-- premium). Return-table change => DROP + CREATE; args unchanged, grants
-- re-asserted. Based on the live prod definition (streak decay + credit top-up
-- logic untouched).
-- ----------------------------------------------------------------------------
drop function if exists public.sync_user_state(text);
create function public.sync_user_state(p_locale text default 'pl')
returns table (
  current_streak       integer,
  longest_streak       integer,
  free_unlock_credits  integer,
  rank_tier            integer,
  rank_name            text,
  next_rank_streak     integer,
  grace_days_left      integer,
  is_premium           boolean,
  ad_reveals_left_today integer
)
language plpgsql security definer set search_path to 'public'
as $$
declare
  v_uid        uuid := auth.uid();
  v_today      date := (now() at time zone 'utc')::date;
  v_premium    boolean;
  v_streak     int;
  v_longest    int;
  v_last_vote  date;
  v_credits    int;
  v_last_cred  date;
  v_ads_today  int;
  v_last_ad    date;
  v_ads_left   int;
  v_disp       int;
  v_disp_tier  int;
  v_missed     int;
  v_grace_left int;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  v_premium := public.is_premium(v_uid);

  select p.current_streak, p.longest_streak, p.last_vote_date,
         p.free_unlock_credits, p.last_credit_date,
         p.ad_reveals_today, p.last_ad_reveal_date
    into v_streak, v_longest, v_last_vote, v_credits, v_last_cred,
         v_ads_today, v_last_ad
  from public.profiles p
  where p.id = v_uid
  for update;

  if not found then
    v_streak := 0; v_longest := 0; v_credits := 0;
  end if;

  -- Free-unlock credit: only REAL (non-anonymous) accounts earn it; premium and
  -- anonymous guests are forced to 0.
  if v_premium or not public.is_real_account(v_uid) then
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

  -- Ad reveals left today: the counter only means anything on the day it was
  -- written (lazy reset, mirroring reveal_ad_question). Null for premium — they
  -- never see the ad wall, so "remaining ads" is meaningless for them.
  if v_premium then
    v_ads_left := null;
  else
    if v_last_ad is distinct from v_today then
      v_ads_today := 0;
    end if;
    v_ads_left := greatest(0, public.ad_reveal_daily_cap() - coalesce(v_ads_today, 0));
  end if;

  v_disp := public.decayed_streak(v_streak, v_last_vote, v_today);

  select r.tier into v_disp_tier
  from public.ranks r
  where r.min_streak <= v_disp
  order by r.min_streak desc
  limit 1;
  v_disp_tier := coalesce(v_disp_tier, 0);

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
    v_premium,
    v_ads_left
  from cur cross join nxt;
end;
$$;

revoke all on function public.sync_user_state(text) from public;
grant execute on function public.sync_user_state(text) to authenticated;
