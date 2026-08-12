-- ============================================================================
-- Bring back the teaser on the reveal paywall.
--
-- The reveal feed server-picks the next question AFTER the ad, so the paywall had
-- nothing specific to tease. peek_next_question lets the client preview the next
-- pick's teaser (first two words) WITHOUT revealing it (no text, not marked
-- seen). The id is echoed back to reveal_ad_question so the ad reveals exactly
-- the teased question; if that pick is no longer eligible (raced), reveal falls
-- back to a random one so the watched ad is never wasted.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- peek_next_question — {id, teaser} for a random eligible UNSEEN question.
-- Does not mark it seen and never returns the full text. Empty = ran out.
-- ----------------------------------------------------------------------------
create or replace function public.peek_next_question(
  p_locale text default 'pl',
  p_date   date default (now() at time zone 'utc')::date
)
returns table (id uuid, teaser text)
language sql security definer set search_path = public as $$
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
    and not q.is_premium
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

revoke all on function public.peek_next_question(text, date) from public;
grant execute on function public.peek_next_question(text, date) to authenticated;

-- ----------------------------------------------------------------------------
-- reveal_ad_question — now takes an optional p_question_id: the peeked id to
-- reveal. Validated against the same eligibility filter; falls back to a random
-- unseen pick when null or no longer eligible. (Signature changes, so drop +
-- recreate.)
-- ----------------------------------------------------------------------------
drop function if exists public.reveal_ad_question(text, date);
create or replace function public.reveal_ad_question(
  p_locale      text default 'pl',
  p_date        date default (now() at time zone 'utc')::date,
  p_question_id uuid default null
)
returns table (
  id            uuid,
  category      text,
  is_premium    boolean,
  question_text text
)
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_qid uuid;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  -- Prefer the peeked (teased) question, but only if it is still eligible.
  if p_question_id is not null then
    select q.id into v_qid
    from public.questions q
    where q.id = p_question_id
      and q.is_active
      and not q.is_premium
      and not exists (
        select 1 from public.daily_questions d
        where d.question_id = q.id and d.publish_date = p_date
      )
      and not exists (
        select 1 from public.question_seen s
        where s.user_id = v_uid and s.question_id = q.id
      );
  end if;

  -- No (valid) peek: random unseen pick so the watched ad still pays out.
  if v_qid is null then
    select q.id into v_qid
    from public.questions q
    where q.is_active
      and not q.is_premium
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
    return;  -- nothing unseen left
  end if;

  insert into public.question_seen (user_id, question_id, source)
  values (v_uid, v_qid, 'ad')
  on conflict (user_id, question_id) do nothing;

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

revoke all on function public.reveal_ad_question(text, date, uuid) from public;
grant execute on function public.reveal_ad_question(text, date, uuid) to authenticated;
