-- ============================================================================
-- Tighten the free window to EXACTLY one question: the daily for the user's
-- own local date. Only the current daily is free; everything else is locked.
--
-- The previous ±1 UTC-day band lived in RLS (which can't see the device's
-- timezone), so it freed 3 days of dailies to everyone at once -- a free user
-- saw today's AND tomorrow's daily. The free-daily decision now lives in
-- SECURITY DEFINER RPCs that take the caller's LOCAL date and clamp it to UTC
-- ±1, so a real device's "today" is honoured but a client can't claim an
-- arbitrary archive date to harvest old dailies.
-- ============================================================================

-- Centralized text-access gate. p_date is the CALLER's local date ("today" on
-- their device). Free only if this question is the daily for that date AND the
-- date is within one day of UTC (the widest a real timezone can legitimately be
-- off from UTC). Premium / per-question unlocks always pass.
create or replace function public.can_read_question_text(
  p_question_id uuid,
  p_date        date
)
returns boolean
language sql stable security definer set search_path = public as $$
  select
    public.is_premium(auth.uid())
    or exists (
      select 1 from public.question_unlocks u
      where u.user_id = auth.uid()
        and u.question_id = p_question_id
    )
    or exists (
      select 1 from public.daily_questions d
      where d.question_id = p_question_id
        and d.publish_date = p_date
        and p_date between (now() at time zone 'utc')::date - 1
                       and (now() at time zone 'utc')::date + 1
    );
$$;
revoke all on function public.can_read_question_text(uuid, date) from public;

-- RLS no longer frees text by date at all: a direct table read exposes only
-- premium / unlocked rows. The single free daily is served exclusively by the
-- DEFINER RPCs below, which know (and clamp) the caller's local date.
drop policy if exists "read question text (gated)" on public.question_translations;
create policy "read question text (gated)" on public.question_translations
  for select to anon, authenticated
  using (
    exists (
      select 1 from public.questions q
      where q.id = question_translations.question_id and q.is_active
    )
    and (
      public.is_premium(auth.uid())
      or exists (
        select 1 from public.question_unlocks u
        where u.user_id = auth.uid()
          and u.question_id = question_translations.question_id
      )
    )
  );

-- get_questions: catalog source for the swipe deck. Takes the caller's local
-- date and gates each question's text through can_read_question_text, so a free
-- user gets exactly their local daily unlocked and everything else as a locked
-- card (text NULL).
drop function if exists public.get_questions(text);
create or replace function public.get_questions(
  p_locale text default 'pl',
  p_date   date default (now() at time zone 'utc')::date
)
returns table (
  id            uuid,
  category      text,
  is_premium    boolean,
  question_text text,
  locked        boolean
)
language sql stable security definer set search_path = public as $$
  select
    q.id,
    q.category,
    q.is_premium,
    case when public.can_read_question_text(q.id, p_date)
         then coalesce(tr.question_text, en.question_text)
         else null end                             as question_text,
    not public.can_read_question_text(q.id, p_date) as locked
  from public.questions q
  left join public.question_translations tr
         on tr.question_id = q.id and tr.locale = p_locale
  left join public.question_translations en
         on en.question_id = q.id and en.locale = 'en'
  where q.is_active
  order by q.created_at, q.id;
$$;
grant execute on function public.get_questions(text, date) to anon, authenticated;

-- get_daily_question: same gate. DEFINER now (RLS no longer frees the daily),
-- so the free daily's text is delivered here for a local date within the ±1
-- clamp; older dates (the premium archive) come back with NULL text.
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
language sql stable security definer set search_path = public as $$
  select q.id, q.category, q.is_premium,
         case when public.can_read_question_text(q.id, p_date)
              then coalesce(tr.question_text, en.question_text)
              else null end as question_text,
         d.publish_date
  from public.daily_questions d
  join public.questions q on q.id = d.question_id and q.is_active
  left join public.question_translations tr
         on tr.question_id = q.id and tr.locale = p_locale
  left join public.question_translations en
         on en.question_id = q.id and en.locale = 'en'
  where d.publish_date = p_date
  limit 1;
$$;
grant execute on function public.get_daily_question(text, date) to anon, authenticated;
