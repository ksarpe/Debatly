-- ============================================================================
-- The vote is final in the RPC too: cast_daily_vote becomes first-write-wins.
-- ----------------------------------------------------------------------------
-- 2026-08-20, follow-up to 20260819160000_smaczek_challenge_outcome.sql and
-- 20260819190000_smaczki_prevote_meta.sql.
--
-- WHAT WAS WRONG
--   The gate stopped re-casting the vote (record_smaczek_challenge never
--   touches `choice`), but the RPC that writes the vote still ended in
--
--     on conflict (user_id, question_id) do update set choice = excluded.choice
--
--   so the vote stayed writable for the whole life of the row. Since the
--   relevance rework of 2026-08-19, `choice` is no longer just an opinion —
--   it SELECTS WHICH ARGUMENT IS READABLE: get_question_smaczki ranks by the
--   caller's own side and unlocks the top-ranked row for a free caller. That
--   quietly turned a mutable column into a content-unlock key.
--
--   1) The free tier leaked. Vote TAK, read the attacks_yes row, then call
--      cast_daily_vote again with p_choice = 2 and the attacks_no row unlocks:
--      2 of 3 arguments free on every daily, against the product rule that a
--      free device never holds more than one readable argument per question.
--      The anon key ships inside the APK, so this needed no client at all.
--
--   2) The split drifted. question_votes_sync_counts fires on UPDATE and
--      applies a ±1 delta, so every flip moved the public tally — the exact
--      "every split drifts toward 50/50" that 20260819160000 removed from the
--      gate but left reachable one layer down, on the highest-traffic question
--      in the app.
--
--   3) It also happened by accident. A vote that times out client-side at 15 s
--      but committed server-side leaves the buttons live (the panel renders
--      them whenever the vote-state provider errors — deliberately, so a
--      failed load never swallows the product's main action), and the retry
--      re-wrote the row.
--
--   Not affected, and left alone: flip_pct and the resilience axis. Their
--   writer already claims the row once (`challenge_outcome is null`), so a
--   flip could never double-count a gate.
--
-- THE FIX
--   `do nothing` + read back. The first vote on a question is the vote; every
--   later call is a no-op that reports the stored choice honestly.
--
--   * my_choice becomes the STORED choice, not the requested one. That is the
--     honest answer and it is what makes a duplicate call self-correcting: a
--     client retrying after a timeout gets back the vote that actually landed
--     and paints those bars, instead of painting a side the server never
--     recorded.
--   * The streak now advances only when a vote row was actually INSERTED.
--     Re-posting yesterday's question is no longer a vote, so it can no longer
--     keep a streak alive without engaging. Every honest path is unchanged:
--     the client has no re-vote UI, and the once-per-UTC-day guard already
--     made a same-day repeat a no-op.
--   * `do nothing` writes NOTHING on a repeat call — no dead tuple, no trigger
--     — so hammering the RPC costs a PK probe and not row churn.
--
-- WHY NOT THE NARROWER `where challenge_outcome is null`
--   Freezing the vote only once a gate has been answered would leave the
--   deliberate path wide open (never call record_smaczek_challenge and the row
--   stays flippable forever). It was worth considering only as a
--   compatibility window for a shipped client that re-casts — and there is
--   none: the re-casting gate was never released (it lived on the unreleased
--   2.0 branch for a day), and every store build back to 1.0.9 has exactly one
--   castDailyVote call site with no re-vote UI behind it. Nothing in the wild
--   needs the update path.
--
-- Signature, argument names and result shape are UNCHANGED (yes_count,
-- no_count, my_choice, flip_pct), so this is a plain create-or-replace and
-- shipped versions keep working. Grants re-asserted. Idempotent.
--
-- VERIFY (as an authenticated user, after voting once on <q>)
--   select * from public.cast_daily_vote('<q>', 1);  -- my_choice 1
--   select * from public.cast_daily_vote('<q>', 2);  -- my_choice STILL 1
--   select yes_count, no_count from public.question_vote_counts
--    where question_id = '<q>';                      -- unchanged by call 2
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
  my_choice int,
  flip_pct  int
)
language plpgsql security definer set search_path = public as $$
declare
  v_uid       uuid := auth.uid();
  v_today     date := (now() at time zone 'utc')::date;
  v_last_vote date;
  v_streak    int;
  v_longest   int;
  v_recorded  boolean;
  v_choice    int;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if p_choice not in (1, 2) then
    raise exception 'invalid choice %', p_choice;
  end if;
  -- Votable = readable now (premium / own daily) OR actually shown via a paid
  -- reveal or a daily. 'view' stays excluded: it is an unpaid browse marker and
  -- would let a free user fabricate eligibility (see 20260712160000).
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

  -- FIRST WRITE WINS. The vote is final from the moment it lands: it is what
  -- the community split counts AND what decides which argument the caller may
  -- read, so it must not stay writable behind either of them. A repeat call
  -- writes nothing at all — the counter trigger never even fires.
  insert into public.question_votes (user_id, question_id, choice)
  values (v_uid, p_question_id, p_choice::smallint)
  on conflict (user_id, question_id) do nothing;
  v_recorded := found;

  if v_recorded then
    v_choice := p_choice;
  else
    -- Already voted. Report what is ON RECORD, not what was asked for: a
    -- client retrying a timed-out cast then shows the side that actually
    -- landed. NULL only if the row vanished between the two statements
    -- (concurrent delete / admin fixup) — the client reads that as "not voted"
    -- and offers the buttons again, which is the truth in that case.
    select v.choice::int
      into v_choice
    from public.question_votes v
    where v.user_id = v_uid
      and v.question_id = p_question_id;
  end if;

  -- The streak: EVERY vote counts, at most once per UTC day. There is no
  -- daily-only branch anymore — "vote on anything today" is the streak rule in
  -- a feed where every question is votable, and it cannot be blocked by having
  -- already voted the served daily. Still keyed on the SERVER clock — and now
  -- only on a vote that was actually recorded, so a re-post of an old question
  -- is not a day of engagement.
  if v_recorded then
    select p.last_vote_date, p.current_streak, p.longest_streak
      into v_last_vote, v_streak, v_longest
    from public.profiles p
    where p.id = v_uid
    for update;

    if found and v_last_vote is distinct from v_today then
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
      coalesce(c.yes_count, 0) + coalesce(sd.seed_yes, 0),
      coalesce(c.no_count,  0) + coalesce(sd.seed_no,  0),
      v_choice,
      public.question_flip_pct(p_question_id)
    from (values (1)) as one(x)
    left join public.question_vote_counts c on c.question_id = p_question_id
    left join public.question_vote_seeds  sd on sd.question_id = p_question_id;
end;
$$;

revoke all on function public.cast_daily_vote(uuid, int, date, text) from public;
grant execute on function public.cast_daily_vote(uuid, int, date, text) to authenticated;

comment on function public.cast_daily_vote(uuid, int, date, text) is
  'Casts the caller''s vote on a readable question. FIRST WRITE WINS: a repeat '
  'call is a no-op and returns the stored choice as my_choice. The vote also '
  'decides which smaczek is readable (get_question_smaczki), so it must never '
  'be rewritable — see 20260820120000.';
