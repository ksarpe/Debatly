-- ============================================================================
-- Reveal pool = questions the user has NOT VOTED on (was: not SEEN).
--
-- WHY
--   A revealed question the user never voted on should come back around, so
--   forgetting to vote / closing the app doesn't permanently burn it. Today the
--   reveal/peek pool excludes `question_seen` (anything ever SHOWN), so a
--   question revealed-but-unvoted is gone forever. We repoint the pool at
--   `question_votes` instead: eligibility = "active, not today's daily, and NOT
--   YET VOTED". A shown-but-unvoted question stays eligible and resurfaces; a
--   voted one is retired for good. "Nothing left" now means "voted on everything".
--
-- WHY NOT "write question_seen on vote"
--   `question_seen` means "the user was SHOWN this text" and TWO gates depend on
--   that meaning: get_question_smaczki (a free user may open "go deeper" only for
--   a seen question) and cast_daily_vote (may vote only on a seen question, see
--   20260712160000). Moving the write to vote-time would deny smaczki on a
--   just-revealed question and make voting chicken-and-egg. So we KEEP writing
--   question_seen on reveal (the "shown" signal) and only change what the pool
--   excludes. "Shown" and "voted" are two different signals; question_votes is
--   the one we already have for "voted".
--
-- WITHIN-SESSION DEDUP
--   Because the pool is now "unvoted", a question revealed-but-unvoted this
--   session is still eligible and a random draw could re-serve it (a wasted ad on
--   a question already on screen). Each function takes p_exclude_ids — the
--   client passes this session's already-revealed ids (revealedFeedProvider) — so
--   the current session never re-draws what it already showed. The targeted ad
--   reveal (p_question_id, the peeked question) is intentionally NOT excluded:
--   that IS the question we want to reveal.
--
-- Signatures gain p_exclude_ids, so these are DROP + CREATE; grants re-applied.
-- Based on the latest definitions (20260701120000).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- peek_next_question — teaser bait for the paywall (no text, no spend).
-- ----------------------------------------------------------------------------
drop function if exists public.peek_next_question(text, date);
create function public.peek_next_question(
  p_locale      text  default 'pl',
  p_date        date  default (now() at time zone 'utc')::date,
  p_exclude_ids uuid[] default '{}'
)
returns table (id uuid, teaser text)
language sql security definer set search_path to 'public'
as $$
  select
    q.id,
    array_to_string(
      (regexp_split_to_array(
         btrim(coalesce(tr.question_text, en.question_text)), '\s+'))[1:2],
      ' '
    ) as teaser
  from public.questions q
  left join public.question_translations tr
         on tr.question_id = q.id and tr.locale = p_locale
  left join public.question_translations en
         on en.question_id = q.id and en.locale = 'en'
  where q.is_active
    and not (q.id = any (p_exclude_ids))
    and not exists (
      select 1 from public.daily_questions d
      where d.question_id = q.id and d.publish_date = p_date
    )
    and not exists (
      select 1 from public.question_votes v
      where v.user_id = auth.uid() and v.question_id = q.id
    )
  order by random()
  limit 1;
$$;

revoke all on function public.peek_next_question(text, date, uuid[]) from public;
grant execute on function public.peek_next_question(text, date, uuid[]) to authenticated;

-- ----------------------------------------------------------------------------
-- reveal_ad_question — reveal after a (verified) rewarded ad. Budget gate and
-- targeted-peek logic unchanged; only the eligibility pool moves to "unvoted".
-- ----------------------------------------------------------------------------
drop function if exists public.reveal_ad_question(text, date, uuid);
create function public.reveal_ad_question(
  p_locale      text  default 'pl',
  p_date        date  default (now() at time zone 'utc')::date,
  p_question_id uuid  default null,
  p_exclude_ids uuid[] default '{}'
)
returns table (id uuid, category text, is_premium boolean, question_text text)
language plpgsql security definer set search_path to 'public'
as $$
declare
  c_grace    constant int := 2;
  v_uid      uuid := auth.uid();
  v_qid      uuid;
  v_used     int;
  v_verified int;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  -- Budget gate: the reveal must be backed by a verified ad reward (+ grace).
  select p.ad_reveals_used into v_used
  from public.profiles p
  where p.id = v_uid
  for update;

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

  -- Spend one unit of the ad-reveal budget (only on a real reveal).
  update public.profiles
     set ad_reveals_used = coalesce(v_used, 0) + 1
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
-- reveal_free_question — same pool, paid with the daily free credit.
-- ----------------------------------------------------------------------------
drop function if exists public.reveal_free_question(text, date);
create function public.reveal_free_question(
  p_locale      text  default 'pl',
  p_date        date  default (now() at time zone 'utc')::date,
  p_exclude_ids uuid[] default '{}'
)
returns table (id uuid, category text, is_premium boolean, question_text text)
language plpgsql security definer set search_path to 'public'
as $$
declare
  v_uid     uuid := auth.uid();
  v_credits int;
  v_qid     uuid;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if public.is_premium(v_uid) then
    raise exception 'premium users do not use unlock credits';
  end if;
  if not public.is_real_account(v_uid) then
    raise exception 'free credit is for real accounts only';
  end if;

  select p.free_unlock_credits into v_credits
  from public.profiles p
  where p.id = v_uid
  for update;

  if coalesce(v_credits, 0) < 1 then
    raise exception 'no free unlock credits';
  end if;

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

  -- Nothing votable left: don't charge the credit.
  if v_qid is null then
    return;
  end if;

  insert into public.question_seen (user_id, question_id, source)
  values (v_uid, v_qid, 'free_credit')
  on conflict (user_id, question_id) do nothing;

  update public.profiles set free_unlock_credits = v_credits - 1
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

revoke all on function public.reveal_free_question(text, date, uuid[]) from public;
grant execute on function public.reveal_free_question(text, date, uuid[]) to authenticated;
