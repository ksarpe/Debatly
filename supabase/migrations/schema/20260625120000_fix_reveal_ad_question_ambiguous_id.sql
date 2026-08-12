-- ============================================================================
-- Fix: reveal_ad_question failed at runtime with
--      `column reference "id" is ambiguous`.
--
-- The function's RETURNS TABLE declares an OUT column `id`, which plpgsql also
-- exposes as a variable. The budget-spend UPDATE referenced the profiles
-- primary key UNQUALIFIED:
--
--     update public.profiles set ad_reveals_used = ... where id = v_uid;  -- BAD
--
-- so `id` collided with the OUT variable `id` and Postgres raised the ambiguity
-- error (variable_conflict defaults to `error`). Every ad-reveal threw BEFORE it
-- could record anything — which is why ad_reveals_used and ad_reward_events were
-- stuck at 0 for every user, and the client only ever saw
-- "Couldn't reveal the question — please try again."
--
-- The fix qualifies the column (`profiles.id`). Logic is otherwise byte-for-byte
-- identical to 20260622160000; CREATE OR REPLACE preserves the grants, which are
-- re-asserted at the end anyway.
-- ============================================================================

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
  c_grace    constant int := 2;   -- in-flight SSV rewards trusted on credit
  v_uid      uuid := auth.uid();
  v_qid      uuid;
  v_used     int;
  v_verified int;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  -- Lock the profile row so two concurrent taps can't both spend the same
  -- headroom (and double-reveal off one verified reward).
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

  -- Nothing unseen left: return no row and DON'T spend budget on an empty
  -- reveal (so the user keeps their headroom for when content is added).
  if v_qid is null then
    return;
  end if;

  insert into public.question_seen (user_id, question_id, source)
  values (v_uid, v_qid, 'ad')
  on conflict (user_id, question_id) do nothing;

  -- Spend one unit of the ad-reveal budget (only on a real reveal).
  -- FIX: qualify the column (`profiles.id`) so it is not ambiguous with the
  -- RETURNS TABLE OUT column `id`.
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

revoke all on function public.reveal_ad_question(text, date, uuid) from public;
grant execute on function public.reveal_ad_question(text, date, uuid) to authenticated;
