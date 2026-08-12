-- ============================================================================
-- Fix: reveal_ad_question lost the personal-daily exclusion.
--
-- WHY
--   20260729130000 (daily ad-reveal cap) rebuilt reveal_ad_question from the
--   20260712170000 definition instead of the newest one from 20260713120000
--   (personal daily). The cap version therefore excludes the RETIRED global
--   calendar (daily_questions, p_date) instead of the caller's own assignment
--   (user_daily_questions, assigned_on between p_date-1 and p_date+1). On prod
--   that means a watched ad can reveal the very question the user gets for
--   free as their daily, and reveal eligibility can disagree with
--   peek_next_question (which does use the ±1-day personal window) — a peeked
--   teaser may be rejected, or a non-peeked pick may collide with the daily.
--
-- HOW
--   Re-create the function keeping EVERYTHING from 20260729130000 (daily-cap
--   gate, per-day counter bump, SSV budget gate) and swapping only the two
--   `not exists (... daily_questions ...)` predicates for the
--   user_daily_questions ±1-day ones from 20260713120000, matching
--   peek_next_question. Signature unchanged; grants re-asserted.
-- ============================================================================

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

  -- Prefer the peeked (teased) question, but only if still eligible: not the
  -- caller's current daily assignment and NOT YET VOTED.
  if p_question_id is not null then
    select q.id into v_qid
    from public.questions q
    where q.id = p_question_id
      and q.is_active
      and not exists (
        select 1 from public.user_daily_questions ud
        where ud.user_id = v_uid
          and ud.question_id = q.id
          and ud.assigned_on between p_date - 1 and p_date + 1
      )
      and not exists (
        select 1 from public.question_votes v
        where v.user_id = v_uid and v.question_id = q.id
      );
  end if;

  -- No (valid) peek: random UNVOTED pick, skipping this session's shown ids so
  -- a watched ad never re-serves a question already on screen this session.
  if v_qid is null then
    select q.id into v_qid
    from public.questions q
    where q.is_active
      and not (q.id = any (p_exclude_ids))
      and not exists (
        select 1 from public.user_daily_questions ud
        where ud.user_id = v_uid
          and ud.question_id = q.id
          and ud.assigned_on between p_date - 1 and p_date + 1
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
