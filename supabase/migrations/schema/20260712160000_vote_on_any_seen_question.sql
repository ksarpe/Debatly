-- ============================================================================
-- Vote on ANY question the user has actually been shown — not just the daily.
--
-- WHY
--   The app is shifting from "one daily hero + a locked archive" to a browsable
--   feed where EVERY question the user unlocks is votable and shows the community
--   split (the "mystery" hook). The plumbing already supports it — question_votes
--   and get_daily_vote_state are keyed on an arbitrary question_id — but
--   cast_daily_vote guarded the write behind can_read_question_text(), which for
--   a FREE user is true ONLY for premium or today's daily. A revealed question's
--   text is handed back by the reveal RPCs into client session memory and is NOT
--   re-readable through the gate, so can_read_question_text() returns false for it
--   and a vote on a just-revealed question threw 'question not readable'.
--
-- FIX
--   Relax the vote's read-guard to also accept a question the user has genuinely
--   SEEN via a reveal or the daily — i.e. a question_seen row with a source that
--   means "we showed them the text":
--       'ad'          — revealed after a rewarded ad
--       'free_credit' — revealed with the daily free credit
--       'daily'       — the daily they opened to
--   We deliberately EXCLUDE source 'view' (the premium browse marker written by
--   mark_question_seen, which is granted to `authenticated` and takes no payment):
--   premium is already covered by can_read_question_text(), and excluding 'view'
--   stops a free user from calling mark_question_seen() to fabricate eligibility
--   and cast a "blind" vote on a question they never actually read.
--
-- UNCHANGED
--   * Streak still advances ONLY for the current daily (the v_is_daily branch and
--     its decayed_streak baseline are untouched), so voting on feed questions can
--     never earn or tamper with streak/rank.
--   * Same signature + return columns, so grants carry through CREATE OR REPLACE;
--     the revoke/grant at the end re-asserts them (idempotent).
--   * Based on the latest definition (20260621140000_streak_grace_decay).
-- ============================================================================

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
  -- Let the user vote on a question they may read (premium / the current daily)
  -- OR one they were actually shown via a reveal / the daily (question_seen).
  -- 'view' is excluded on purpose (see header): it's an unpaid premium-browse
  -- marker and would otherwise let a free user vote on unread questions.
  if not (
    public.can_read_question_text(p_question_id, p_date)
    or exists (
      select 1 from public.question_seen s
      where s.user_id = v_uid
        and s.question_id = p_question_id
        and s.source in ('ad', 'free_credit', 'daily')
    )
  ) then
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
    -- not bump it again. Otherwise extend from the decayed baseline (which is
    -- the unchanged streak unless a grace window has fully elapsed).
    if v_last_vote is distinct from v_today then
      v_streak := public.decayed_streak(v_streak, v_last_vote, v_today) + 1;
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
