-- ============================================================================
-- The global pick always wins the daily slot — and an OLD vote on it melts.
-- ----------------------------------------------------------------------------
-- 2026-08-20, follow-up to 20260820150000_global_daily_picks.sql (same day).
--
-- WHY
--   20260820150000 skipped the pick for ANY caller who had ever voted it and
--   served a personal draw instead. Owner decision (2026-08-20): the shared
--   moment beats the fresh question.
--     * A PRO caller should always land on the pick — voted just means the
--       daily shows its result bars; their feed still holds the catalog.
--     * A FREE caller whose vote on the pick is genuinely OLD (cast back when
--       the question was a random feed/daily draw — before it ever became the
--       pick of the day) gets the pick back WITH the buttons: one honest
--       re-vote, so their one question of the day is the same one the world
--       is debating.
--   Also: the personal fallback draw used to sample the WHOLE unvoted catalog
--   — including future picks, which it kept "burning" one user-day at a time.
--   It now leaves the future calendar alone.
--
-- THE RE-VOTE WINDOW (deliberately narrow — the vote stays final everywhere
-- else; see 20260820120000 for why choice must not be generally rewritable:
-- it is a smaczek-unlock key and the tally trigger fires on update)
--   _daily_pick_revote_ok(uid, question) is true only when ALL hold:
--     1. the question is the daily_picks pick for a date within UTC ±1 of
--        today (i.e. it is "today's pick" in some plausible timezone);
--     2. the caller is NOT premium (PRO sees result bars instead — their
--        catalog access makes the re-vote pointless and would only reopen
--        the argument-flip surface for the tier that can read everything);
--     3. the caller's existing vote predates the EARLIEST possible start of
--        the pick's local day anywhere on Earth: voted_at < publish_date
--        00:00 UTC+14, i.e. publish_date (as UTC) minus 14 hours. A vote cast
--        ON the pick's day is the daily vote itself and stays final.
--   The allowed update refreshes voted_at, which closes the window by (3) —
--   one re-vote per pick, ever, enforced by the data itself. Each question is
--   a pick at most once (UNIQUE), so the lifetime exposure per question is a
--   single side-flip on its pick day; the counter trigger handles the delta
--   (and a same-side re-vote as a no-op) correctly.
--
-- WHAT CHANGES
--   1) _daily_pick_revote_ok — the shared predicate (internal, no grants).
--   2) get_daily_question — the pick is served to premium unconditionally,
--      and to free when unvoted OR re-votable; the personal fallback (now
--      only for gap dates / free callers with a fresh vote on the pick)
--      excludes future picks.
--   3) get_daily_vote_state — my_choice is NULL inside the re-vote window,
--      so every shipped client shows the vote buttons instead of dead bars.
--      No client code needs to change.
--   4) cast_daily_vote — on conflict, an allowed re-vote UPDATEs choice +
--      voted_at (and advances the streak: voting today's pick is today's
--      engagement); everything else keeps the 20260820120000 behaviour
--      (write nothing, return the stored choice).
--
-- KNOWN, ACCEPTED CORNERS
--   * During the window a crafted call could read get_question_smaczki with
--     the OLD vote standing and re-vote informed; the shipped client never
--     does (it treats my_choice null as unvoted and only prefetches meta).
--   * After the re-vote the free row of the sheet re-ranks against the new
--     side — one extra readable argument per pick day at most, bounded by
--     the one-shot window. The unlimited-flip exploit stays dead.
--   * A vote row whose smaczek gate was already answered keeps its
--     challenge_outcome — the re-vote never re-arms a gate, so resilience
--     counters cannot double-count.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) The predicate. Internal only: SECURITY DEFINER RPCs call it with an
--    explicit uid; clients get no execute.
-- ----------------------------------------------------------------------------
create or replace function public._daily_pick_revote_ok(
  p_uid         uuid,
  p_question_id uuid
)
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select true
    from public.daily_picks dp
    join public.question_votes v
      on v.user_id = p_uid and v.question_id = dp.question_id
    where dp.question_id = p_question_id
      and dp.publish_date between (now() at time zone 'utc')::date - 1
                              and (now() at time zone 'utc')::date + 1
      and v.voted_at < (dp.publish_date::timestamp at time zone 'utc')
                         - interval '14 hours'
  ), false)
  and not public.is_premium(p_uid);
$$;

revoke all on function public._daily_pick_revote_ok(uuid, uuid)
  from public, anon, authenticated;

comment on function public._daily_pick_revote_ok(uuid, uuid) is
  'True when the free caller''s OLD vote on today''s (UTC±1) daily pick may be '
  're-cast once: the vote predates the pick''s day everywhere on Earth '
  '(publish_date UTC - 14h). Self-closing — the re-vote refreshes voted_at. '
  'See 20260820170000.';

-- ----------------------------------------------------------------------------
-- 2) get_daily_question — pick priority. Base 20260820150000; the pick branch
--    and the fallback pool change, everything else is identical.
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
  v_uid   uuid := auth.uid();
  v_today date := (now() at time zone 'utc')::date;
  v_date  date := p_date;
  v_qid   uuid;
begin
  -- The daily needs an identity; the app always signs in (anonymous included)
  -- before fetching. An unauthenticated call gets no row.
  if v_uid is null then
    return;
  end if;

  -- Honour the device's local "today" but clamp to UTC ±1 (the widest a real
  -- timezone can be off), so a client can't harvest assignments for arbitrary
  -- dates. Out-of-window claims just get the server's today.
  if v_date is null or v_date < v_today - 1 or v_date > v_today + 1 then
    v_date := v_today;
  end if;

  -- Today's assignment, if it exists and its question is still active. Stored
  -- wins even over the global pick: a user who resolved their daily this
  -- morning must not watch it swap mid-day because the calendar changed.
  select ud.question_id into v_qid
  from public.user_daily_questions ud
  join public.questions q on q.id = ud.question_id and q.is_active
  where ud.user_id = v_uid and ud.assigned_on = v_date;

  if v_qid is null then
    -- Clear a stale assignment whose question was deactivated mid-day, so the
    -- redraw below can replace it instead of serving nothing.
    delete from public.user_daily_questions
     where user_id = v_uid and assigned_on = v_date;

    -- THE GLOBAL PICK — the shared debate, and it now outranks the caller's
    -- vote history: premium always lands here (voted = result bars), free
    -- lands here when unvoted or when the old vote melts (_daily_pick_
    -- revote_ok). Only a free caller whose vote on the pick is FRESH (cast on
    -- the pick's own day) falls through to the personal draw.
    select dp.question_id into v_qid
    from public.daily_picks dp
    join public.questions q on q.id = dp.question_id and q.is_active
    where dp.publish_date = v_date
      and (
        public.is_premium(v_uid)
        or not exists (
          select 1 from public.question_votes v
          where v.user_id = v_uid and v.question_id = dp.question_id
        )
        or public._daily_pick_revote_ok(v_uid, dp.question_id)
      );

    -- Personal fallback: any active question the user has NOT voted on,
    -- never-seen ones first (fresh over "shown but skipped"), random within
    -- each group. FUTURE picks are off limits — the fallback used to sample
    -- them like any unvoted question and quietly burned the shared calendar
    -- one user-day at a time.
    if v_qid is null then
      select q.id into v_qid
      from public.questions q
      where q.is_active
        and not exists (
          select 1 from public.question_votes v
          where v.user_id = v_uid and v.question_id = q.id
        )
        and not exists (
          select 1 from public.daily_picks dp
          where dp.question_id = q.id and dp.publish_date > v_date
        )
      order by
        exists (
          select 1 from public.question_seen s
          where s.user_id = v_uid and s.question_id = q.id
        ) asc,
        random()
      limit 1;
    end if;

    -- Voted on everything reachable: fall back to the legacy calendar question
    -- for the date (deterministic, always exists while the calendar lasts) so
    -- the screen never comes up empty.
    if v_qid is null then
      select d.question_id into v_qid
      from public.daily_questions d
      join public.questions q on q.id = d.question_id and q.is_active
      where d.publish_date = v_date;
    end if;

    if v_qid is null then
      return;
    end if;

    insert into public.user_daily_questions (user_id, assigned_on, question_id)
    values (v_uid, v_date, v_qid)
    on conflict (user_id, assigned_on) do nothing;

    -- A concurrent call (second device) may have won the insert; serve the
    -- STORED assignment either way so both devices show the same question.
    select ud.question_id into v_qid
    from public.user_daily_questions ud
    where ud.user_id = v_uid and ud.assigned_on = v_date;
  end if;

  -- Seen-memory: the daily was shown to this user (idempotent). The smaczki
  -- gate and the vote guard read this.
  insert into public.question_seen (user_id, question_id, source)
  values (v_uid, v_qid, 'daily')
  on conflict (user_id, question_id) do nothing;

  -- The caller's own assignment within the clamp is readable by construction
  -- (see can_read_question_text), so the text is returned un-gated.
  return query
    select q.id, q.category, q.is_premium,
           coalesce(tr.question_text, en.question_text),
           v_date
    from public.questions q
    left join public.question_translations tr
           on tr.question_id = q.id and tr.locale = p_locale
    left join public.question_translations en
           on en.question_id = q.id and en.locale = 'en'
    where q.id = v_qid;
end;
$$;

grant execute on function public.get_daily_question(text, date) to anon, authenticated;

comment on function public.get_daily_question(text, date) is
  'Serves (and on first call of the day assigns) the caller''s daily. The '
  'daily_picks pick for the date outranks the caller''s vote history: premium '
  'always gets it, free gets it when unvoted or inside the one-shot re-vote '
  'window (_daily_pick_revote_ok). Personal unvoted draw (future picks '
  'excluded) only for gap dates and fresh-voted free callers. '
  'See 20260820170000.';

-- ----------------------------------------------------------------------------
-- 3) get_daily_vote_state — my_choice melts inside the re-vote window, so the
--    shipped client (which reads null my_choice as "not voted") renders the
--    vote buttons on its own. Counts stay honest; the client hides them until
--    the vote anyway.
-- ----------------------------------------------------------------------------
create or replace function public.get_daily_vote_state(p_question_id uuid)
returns table (
  yes_count int,
  no_count  int,
  my_choice int,
  flip_pct  int
)
language sql stable security definer set search_path = public as $$
  select
    coalesce(c.yes_count, 0) + coalesce(sd.seed_yes, 0),
    coalesce(c.no_count,  0) + coalesce(sd.seed_no,  0),
    (select v2.choice::int
       from public.question_votes v2
      where v2.question_id = p_question_id
        and v2.user_id = auth.uid()
        and not public._daily_pick_revote_ok(auth.uid(), p_question_id)),
    public.question_flip_pct(p_question_id)
  from (values (1)) as one(x)
  left join public.question_vote_counts c on c.question_id = p_question_id
  left join public.question_vote_seeds  sd on sd.question_id = p_question_id;
$$;

revoke all on function public.get_daily_vote_state(uuid) from public;
grant execute on function public.get_daily_vote_state(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 4) cast_daily_vote — base 20260820120000 (first-write-wins), plus the ONE
--    sanctioned update path: the re-vote window. Signature, guard and result
--    shape unchanged.
-- ----------------------------------------------------------------------------
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

  -- FIRST WRITE WINS — with exactly one sanctioned exception. The vote is
  -- final from the moment it lands (it selects the readable argument and
  -- feeds the public tally), so a repeat call writes nothing... UNLESS the
  -- stored vote is an OLD one on TODAY'S pick by a free caller
  -- (_daily_pick_revote_ok): that vote predates the shared debate, so the
  -- caller gets it back once. The update refreshes voted_at, which closes
  -- the window — the re-cast vote is final again. The tally trigger applies
  -- the side delta (same-side re-vote = no-op) — see 20260815120000.
  insert into public.question_votes (user_id, question_id, choice)
  values (v_uid, p_question_id, p_choice::smallint)
  on conflict (user_id, question_id) do nothing;
  v_recorded := found;

  if not v_recorded
     and public._daily_pick_revote_ok(v_uid, p_question_id) then
    update public.question_votes
       set choice = p_choice::smallint, voted_at = now()
     where user_id = v_uid and question_id = p_question_id;
    v_recorded := found;
  end if;

  if v_recorded then
    v_choice := p_choice;
  else
    -- Already voted and no window. Report what is ON RECORD, not what was
    -- asked for: a client retrying a timed-out cast then shows the side that
    -- actually landed. NULL only if the row vanished between the statements
    -- (concurrent delete / admin fixup) — the client reads that as "not
    -- voted" and offers the buttons again, which is the truth in that case.
    select v.choice::int
      into v_choice
    from public.question_votes v
    where v.user_id = v_uid
      and v.question_id = p_question_id;
  end if;

  -- The streak: EVERY vote counts, at most once per UTC day, keyed on the
  -- SERVER clock — and only on a write that actually landed (insert OR the
  -- sanctioned re-vote: re-casting today's pick IS today's engagement). A
  -- re-post of an old question is still not a day of engagement.
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
  'call is a no-op and returns the stored choice — with one sanctioned '
  'exception: a free caller''s OLD vote on today''s daily pick may be re-cast '
  'once (_daily_pick_revote_ok; the update closes the window). See '
  '20260820120000 and 20260820170000.';
