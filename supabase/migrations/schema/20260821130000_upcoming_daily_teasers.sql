-- ============================================================================
-- The notification loop's content, read ahead: teasers for the coming dailies.
-- ----------------------------------------------------------------------------
-- 2026-08-21.
--
-- WHY
--   Reminders are LOCAL (flutter_local_notifications). The body is baked at
--   SCHEDULE time and nothing whatsoever runs when a notification actually
--   fires — so the only way a reminder can name the question it is calling the
--   user back to is for the device to already hold that question's teaser, days
--   in advance. Until now it could not, and every nudge talked about mechanics
--   ("day 7 of your streak") because mechanics were all the device knew.
--
--   daily_picks is a curated calendar seeded far past any reminder horizon, so
--   the text IS knowable ahead of time. It simply had no read path.
--
--   peek_next_question cannot serve this: by design it clamps to TOMORROW
--   (UTC±1, then +1), filters against the CALLER's own vote history, and returns
--   a single random row. This is the calendar read instead.
--
-- WHAT
--   get_upcoming_daily_teasers(p_locale, p_from, p_days)
--     -> (publish_date, teaser)
--   The same first-4-words cut the day wall already shows, for every date in
--   the window that has a pick whose question is still active. A pure read:
--   nothing is consumed, recorded or assigned (no user_daily_questions row, no
--   question_seen), exactly like the wall's peek.
--
-- WHAT IT DELIBERATELY DOES NOT DO
--   * Never the full question text — 4 words, the same cut as
--     peek_next_question. The wall's blurred tease is what the free tier's
--     countdown is selling; a notification must not undercut it by shipping the
--     whole question to the notification shade.
--   * No per-caller filtering, and no auth.uid() anywhere. The pick outranks
--     vote history for every tier (20260820170000), so the global calendar IS
--     what the reminder is calling the user back to. Being caller-independent
--     is also what makes the result identical on every device and therefore
--     cacheable — which the local-notification model needs.
--   * p_days is capped at 31: one reminder cadence (max offset 30), not the
--     400-day content roadmap. p_from is clamped to UTC±1 like every other
--     client-supplied date, so nobody can walk the calendar by lying about it.
--
-- A gap date (no pick, or a pick whose question was deactivated before
-- compact_daily_picks ran) simply yields no row: the client falls back to its
-- evergreen copy for that day, the same way the feed falls back to a personal
-- draw. Nothing bricks.
-- ============================================================================

create or replace function public.get_upcoming_daily_teasers(
  p_locale text default 'pl',
  p_from   date default (now() at time zone 'utc')::date,
  p_days   int  default 31
)
returns table (publish_date date, teaser text)
language sql
stable
security definer
set search_path to 'public'
as $$
  with bounds as (
    select
      least(
        greatest(
          coalesce(p_from, (now() at time zone 'utc')::date),
          (now() at time zone 'utc')::date - 1
        ),
        (now() at time zone 'utc')::date + 1
      ) as from_date,
      least(greatest(coalesce(p_days, 31), 1), 31) as days
  )
  select dp.publish_date,
         array_to_string(
           (regexp_split_to_array(
              btrim(coalesce(tr.question_text, en.question_text)), '\s+'))[1:4],
           ' '
         ) as teaser
  from bounds b
  join public.daily_picks dp
    on dp.publish_date between b.from_date and b.from_date + b.days
  join public.questions q
    on q.id = dp.question_id and q.is_active
  left join public.question_translations tr
         on tr.question_id = q.id and tr.locale = p_locale
  left join public.question_translations en
         on en.question_id = q.id and en.locale = 'en'
  where btrim(coalesce(tr.question_text, en.question_text, '')) <> ''
  order by dp.publish_date;
$$;

revoke all on function public.get_upcoming_daily_teasers(text, date, int)
  from public;
grant execute on function public.get_upcoming_daily_teasers(text, date, int)
  to anon, authenticated;
