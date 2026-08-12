-- ============================================================================
-- Close the seen-memory over BOTH the daily and the premium catalog.
--
-- Two gaps in the "never re-serve a question the user has already seen" model
-- (see the reveal-feed migration 20260620120000):
--
--   1) FREE users — viewing the daily was a pure read; it never recorded a
--      question_seen row. But each question is the daily on exactly one date
--      (Strategy A: unique(question_id) in daily_questions), so a returning free
--      user reads every non-premium question for free as a past daily, and the
--      reveal RPCs — which only exclude TODAY's daily — would later serve those
--      same questions again as a paid (ad/credit) reveal. get_daily_question now
--      records the view, so a question read as a daily is never re-served.
--
--   2) PREMIUM users — premium reads the whole catalog via the gate and was
--      never tracked at all, so the deck just looped the same questions forever
--      with no notion of "new". We now (a) let the client mark a question seen as
--      premium browses (mark_question_seen) and (b) return a `seen` flag from
--      get_questions so the client can surface UNSEEN questions first. Premium is
--      never walled — seen questions stay readable (archive), just sorted last.
--
-- The seen-memory is per-uuid and idempotent on (user_id, question_id).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) get_daily_question — record the daily view in the seen-memory.
--
--    Becomes plpgsql/VOLATILE (it now writes). Same signature + return columns,
--    so CREATE OR REPLACE keeps the existing grants. Records the view only when
--    the caller is signed in AND could actually read this daily (the readable
--    daily for their local date, which is also always-true for premium) — so a
--    locked future daily a client might prefetch is never marked seen.
-- ----------------------------------------------------------------------------
create or replace function public.get_daily_question(
  p_locale text default 'pl',
  p_date   date default (now() at time zone 'utc')::date
)
returns table (
  id            uuid,
  category      text,
  is_premium    boolean,
  question_text text,
  publish_date  date
)
language plpgsql volatile security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_qid uuid;
begin
  -- The question scheduled as the daily for this date (active only).
  select d.question_id into v_qid
  from public.daily_questions d
  join public.questions q on q.id = d.question_id and q.is_active
  where d.publish_date = p_date
  limit 1;

  if v_qid is null then
    return;  -- no daily scheduled for this date
  end if;

  -- Remember that this user saw the daily, so a reveal never re-serves it later
  -- (free) and it is never surfaced as "new" (premium). Idempotent.
  if v_uid is not null and public.can_read_question_text(v_qid, p_date) then
    insert into public.question_seen (user_id, question_id, source)
    values (v_uid, v_qid, 'daily')
    on conflict (user_id, question_id) do nothing;
  end if;

  return query
    select q.id, q.category, q.is_premium,
           case when public.can_read_question_text(q.id, p_date)
                then coalesce(tr.question_text, en.question_text)
                else null end,
           d.publish_date
    from public.daily_questions d
    join public.questions q on q.id = d.question_id and q.is_active
    left join public.question_translations tr
           on tr.question_id = q.id and tr.locale = p_locale
    left join public.question_translations en
           on en.question_id = q.id and en.locale = 'en'
    where d.publish_date = p_date
    limit 1;
end;
$$;

-- ----------------------------------------------------------------------------
-- 2) get_questions — add a per-caller `seen` flag so the premium deck can put
--    unseen questions first. Adding an OUT column changes the return type, so
--    this is a DROP + CREATE; grants must be re-applied (PUBLIC execute is
--    restored automatically on CREATE, anon/authenticated are explicit).
-- ----------------------------------------------------------------------------
drop function if exists public.get_questions(text, date);
create function public.get_questions(
  p_locale text default 'pl',
  p_date   date default (now() at time zone 'utc')::date
)
returns table (
  id            uuid,
  category      text,
  is_premium    boolean,
  question_text text,
  locked        boolean,
  teaser        text,
  seen          boolean
)
language sql stable security definer set search_path = public as $$
  select
    q.id,
    q.category,
    q.is_premium,
    case when public.can_read_question_text(q.id, p_date)
         then coalesce(tr.question_text, en.question_text)
         else null end                              as question_text,
    not public.can_read_question_text(q.id, p_date) as locked,
    array_to_string(
      (regexp_split_to_array(
         btrim(coalesce(tr.question_text, en.question_text)), '\s+'))[1:2],
      ' '
    )                                               as teaser,
    exists (
      select 1 from public.question_seen s
      where s.user_id = auth.uid() and s.question_id = q.id
    )                                               as seen
  from public.questions q
  left join public.question_translations tr
         on tr.question_id = q.id and tr.locale = p_locale
  left join public.question_translations en
         on en.question_id = q.id and en.locale = 'en'
  where q.is_active
  order by q.created_at, q.id;
$$;
grant execute on function public.get_questions(text, date) to anon, authenticated;

-- ----------------------------------------------------------------------------
-- 3) mark_question_seen — record that the caller has viewed a question.
--
--    The client calls this for a PREMIUM user as they browse the catalog (free
--    users only ever reach the daily + their reveals, both recorded elsewhere).
--    Best-effort + idempotent; only records active questions for a signed-in
--    caller. Never hands back any text — it is a write-only consumption marker.
-- ----------------------------------------------------------------------------
create or replace function public.mark_question_seen(p_question_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    return;  -- not signed in: nothing to record (no raw error to the caller)
  end if;

  insert into public.question_seen (user_id, question_id, source)
  select v_uid, q.id, 'view'
  from public.questions q
  where q.id = p_question_id and q.is_active
  on conflict (user_id, question_id) do nothing;
end;
$$;

revoke all on function public.mark_question_seen(uuid) from public;
grant execute on function public.mark_question_seen(uuid) to authenticated;
