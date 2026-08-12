-- ============================================================================
-- Daily FREE bonus question for non-premium users.
--
-- A free user already gets today's scheduled daily for free. On top of that we
-- give them ONE extra question per day, picked at random BY THE SERVER from the
-- pool, and unlocked permanently (it lands in question_unlocks like an ad
-- unlock, so once revealed it stays revealed).
--
-- Anti-tampering is the whole point of doing this server-side: the "one per
-- day" reset is keyed on the SERVER clock (`now() at time zone 'utc'`), never on
-- a client-supplied date. Changing the phone's date — forward or back — cannot
-- earn extra free questions, because the client never gets to say what "today"
-- is for this grant.
--
-- Tradeoff (deliberate): the reset is at UTC midnight, not the user's local
-- midnight. Unlike the readable-daily gate (which tolerates the device timezone
-- via a ±1 clamp on a client date), a consumable once-per-day credit can't trust
-- a client date at all — a ±1 clamp would let a user oscillate the local date
-- across the boundary and claim 2–3 freebies. So this one is pure UTC.
-- ============================================================================

-- One row per (user, server-UTC day): records which question that user's free
-- bonus was spent on. The PK enforces "at most one free bonus per day". Only the
-- SECURITY DEFINER RPC below writes here (no client write policy).
create table public.daily_free_grants (
  user_id     uuid not null references auth.users(id) on delete cascade,
  grant_date  date not null,                 -- server UTC date; the per-day key
  question_id uuid not null references public.questions(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (user_id, grant_date)
);

alter table public.daily_free_grants enable row level security;

-- Read-own only; all writes go through claim_daily_free_question (DEFINER).
create policy "read own free grants" on public.daily_free_grants
  for select to authenticated
  using (user_id = auth.uid());

grant select on public.daily_free_grants to authenticated;

-- claim_daily_free_question: grant (or re-return) the caller's free bonus for
-- today. Idempotent within a server-UTC day — the first call picks and records a
-- random eligible question; later calls the same day return that SAME question.
--
-- Eligibility for the random pick: active, NOT premium-flagged, NOT today's
-- scheduled daily (already free), and NOT something the user has already
-- unlocked. If nothing is eligible (e.g. the user unlocked the whole pool), it
-- returns no row.
--
-- SECURITY DEFINER: writes question_unlocks / daily_free_grants, neither of
-- which has a client write policy. The row is always pinned to auth.uid().
create or replace function public.claim_daily_free_question(p_locale text default 'pl')
returns table (
  id            uuid,
  category      text,
  is_premium    boolean,
  question_text text,
  grant_date    date
)
language plpgsql security definer set search_path = public as $$
declare
  v_uid  uuid  := auth.uid();
  v_date date  := (now() at time zone 'utc')::date;  -- SERVER clock; phone date is irrelevant
  v_qid  uuid;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  -- Already claimed today? Reuse it, so the bonus is stable for the whole day
  -- instead of re-rolling on every app open.
  select g.question_id into v_qid
  from public.daily_free_grants g
  where g.user_id = v_uid and g.grant_date = v_date;

  if v_qid is null then
    -- First claim of this UTC day: pick a random eligible question and record it
    -- atomically. on conflict guards the race where two app instances claim at
    -- once — the loser inserts nothing and re-reads the winner's row below.
    insert into public.daily_free_grants (user_id, grant_date, question_id)
    select v_uid, v_date, q.id
    from public.questions q
    where q.is_active
      and not q.is_premium
      and not exists (
        select 1 from public.daily_questions d
        where d.question_id = q.id and d.publish_date = v_date
      )
      and not exists (
        select 1 from public.question_unlocks u
        where u.user_id = v_uid and u.question_id = q.id
      )
    order by random()
    limit 1
    on conflict (user_id, grant_date) do nothing
    returning question_id into v_qid;

    -- Lost the race (or the pick raced an unlock): read whatever was recorded.
    if v_qid is null then
      select g.question_id into v_qid
      from public.daily_free_grants g
      where g.user_id = v_uid and g.grant_date = v_date;
    end if;

    -- Make it permanently readable everywhere the gate looks (deck, daily,
    -- smaczki access check) by recording the unlock. Idempotent.
    if v_qid is not null then
      insert into public.question_unlocks (user_id, question_id, source)
      values (v_uid, v_qid, 'daily_free')
      on conflict (user_id, question_id) do nothing;
    end if;
  end if;

  -- Nothing eligible to grant (e.g. whole pool already unlocked): no row.
  if v_qid is null then
    return;
  end if;

  return query
    select q.id, q.category, q.is_premium,
           coalesce(tr.question_text, en.question_text) as question_text,
           v_date
    from public.questions q
    left join public.question_translations tr
           on tr.question_id = q.id and tr.locale = p_locale
    left join public.question_translations en
           on en.question_id = q.id and en.locale = 'en'
    where q.id = v_qid;
end;
$$;

revoke all on function public.claim_daily_free_question(text) from public;
-- 'authenticated' covers anonymous sign-in too, so guests get the bonus as well.
grant execute on function public.claim_daily_free_question(text) to authenticated;
