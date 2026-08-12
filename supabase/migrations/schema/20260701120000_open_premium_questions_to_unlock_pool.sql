-- Opens the 218 questions.is_premium=true rows (of 482) to the ad/credit
-- unlock pool. There is no subscriber-only question tier by design — every
-- question is locked-by-default and unlockable via ad/credit or premium,
-- and free to read on the one day it's the daily. The `is_premium` column
-- was leftover from an earlier design and, combined with `and not q.is_premium`
-- in reveal_ad_question / reveal_free_question / peek_next_question, silently
-- walled those 218 off from ever being ad/credit-unlocked (only reachable as
-- a daily). Affected ids backed up to the sibling .backup.json before this run.
--
-- Fix: (1) flip the flag off catalog-wide — the column is otherwise inert
-- (text gating keys on is_premium(auth.uid()), the USER's subscription, never
-- this column); (2) drop the now-vestigial predicate from the 3 RPCs so it
-- can't silently re-wall content if the flag is ever set again by mistake.

update public.questions set is_premium = false where is_premium;

create or replace function public.peek_next_question(
  p_locale text default 'pl',
  p_date date default (now() at time zone 'utc')::date
)
returns table (id uuid, teaser text)
language sql
security definer
set search_path to 'public'
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
    and not exists (
      select 1 from public.daily_questions d
      where d.question_id = q.id and d.publish_date = p_date
    )
    and not exists (
      select 1 from public.question_seen s
      where s.user_id = auth.uid() and s.question_id = q.id
    )
  order by random()
  limit 1;
$$;

create or replace function public.reveal_ad_question(
  p_locale text default 'pl',
  p_date date default (now() at time zone 'utc')::date,
  p_question_id uuid default null
)
returns table (id uuid, category text, is_premium boolean, question_text text)
language plpgsql
security definer
set search_path to 'public'
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
        select 1 from public.question_seen s
        where s.user_id = v_uid and s.question_id = q.id
      );
  end if;

  if v_qid is null then
    select q.id into v_qid
    from public.questions q
    where q.is_active
      and not exists (
        select 1 from public.daily_questions d
        where d.question_id = q.id and d.publish_date = p_date
      )
      and not exists (
        select 1 from public.question_seen s
        where s.user_id = v_uid and s.question_id = q.id
      )
    order by random()
    limit 1;
  end if;

  if v_qid is null then
    return;
  end if;

  insert into public.question_seen (user_id, question_id, source)
  values (v_uid, v_qid, 'ad')
  on conflict (user_id, question_id) do nothing;

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

create or replace function public.reveal_free_question(
  p_locale text default 'pl',
  p_date date default (now() at time zone 'utc')::date
)
returns table (id uuid, category text, is_premium boolean, question_text text)
language plpgsql
security definer
set search_path to 'public'
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
    and not exists (
      select 1 from public.daily_questions d
      where d.question_id = q.id and d.publish_date = p_date
    )
    and not exists (
      select 1 from public.question_seen s
      where s.user_id = v_uid and s.question_id = q.id
    )
  order by random()
  limit 1;

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
