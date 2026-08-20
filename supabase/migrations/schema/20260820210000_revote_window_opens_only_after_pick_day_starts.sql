-- ============================================================================
-- The one-shot re-vote window really is one-shot.
-- ----------------------------------------------------------------------------
-- 2026-08-20, fix to 20260820170000_daily_revote_and_pick_priority.sql
-- (same day — nothing shipped in between).
--
-- THE BUG
--   _daily_pick_revote_ok derived its threshold purely from publish_date:
--     v.voted_at < publish_date::timestamp at time zone 'utc' - interval '14h'
--   The window is meant to close itself, because the sanctioned UPDATE sets
--   voted_at = now() and now() was assumed to be past the threshold. It is
--   not, for the UPPER end of the UTC±1 clamp. A pick dated utc_today + 1 has
--   its threshold at utc_today 10:00 UTC, so any re-vote cast before 10:00
--   writes a voted_at that is STILL below its own threshold:
--
--     re-vote at (UTC)   voted_at after write   threshold   window open?
--     00:00              2026-08-20 00:00       10:00       yes
--     09:00              2026-08-20 09:00       10:00       yes
--     10:00              2026-08-20 10:00       10:00       no
--
--   Ten hours a day, `choice` on that question was freely flippable — and
--   choice is the key that selects the free readable argument, so this
--   reopened exactly the hole 20260820120000_vote_is_final_in_the_rpc closed,
--   reachable with the anon key that ships inside the APK.
--
--   Not exploitable today, by accident: all 150 votes that currently satisfy
--   the age test belong to premium accounts (is_premium short-circuits the
--   predicate) and the picks they sit on start 2027-06-13. One of those
--   entitlements expires 2026-09-17 while holding 34 such votes, so the
--   accident does not hold.
--
-- THE FIX
--   One clause: the window may not OPEN before the pick's day has started
--   somewhere on Earth. Then now() >= threshold whenever the window is open,
--   the UPDATE writes voted_at = now() >= threshold, and the window is shut
--   for good — one flip per pick, ever, still enforced by the data itself.
--
--   The legal path loses nothing: the window opens at publish_date 00:00
--   UTC+14, i.e. 10:00 UTC the day before, while a Polish user's local
--   midnight for that pick falls at 22:00 UTC — twelve hours later. Every
--   real timezone gets its whole local pick-day.
-- ============================================================================

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
      -- The pick's day has begun somewhere (UTC+14). Without this the window
      -- could open BEFORE its own threshold, and the closing UPDATE would
      -- write a voted_at that still passes the test below — see the header.
      and now() >= (dp.publish_date::timestamp at time zone 'utc')
                     - interval '14 hours'
      and v.voted_at < (dp.publish_date::timestamp at time zone 'utc')
                         - interval '14 hours'
  ), false)
  and not public.is_premium(p_uid);
$$;

revoke all on function public._daily_pick_revote_ok(uuid, uuid)
  from public, anon, authenticated;

comment on function public._daily_pick_revote_ok(uuid, uuid) is
  'True when the free caller''s OLD vote on today''s (UTC±1) daily pick may be '
  're-cast once: the pick''s day has started somewhere on Earth '
  '(publish_date UTC - 14h) and the vote predates that same instant. '
  'Self-closing — the re-vote writes voted_at = now(), which is at or past '
  'the threshold by the first condition. See 20260820170000, fixed by '
  '20260820210000.';
