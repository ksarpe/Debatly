-- ============================================================================
-- The daily calendar heals itself: compact_daily_picks() + nightly cron.
-- ----------------------------------------------------------------------------
-- 2026-08-20, follow-up to 20260820150000/20260820170000.
--
-- WHY
--   The owner curates the catalog by DEACTIVATING questions (and occasionally
--   deleting them — the daily_picks FK cascades). Every RPC join filters on
--   q.is_active, so a dead pick never breaks anything — but its date silently
--   degrades into "personal draw for everyone": the shared moment is lost and
--   nobody is told. At the time of writing 5 future picks already pointed at
--   deactivated questions.
--
-- WHAT
--   compact_daily_picks():
--     * touches ONLY dates AFTER today (UTC) — past picks are history (they
--       feed get_daily_history via assignments), today's pick is already on
--       screens and its per-user fallback covers a mid-day deactivation;
--     * deletes future picks whose question is inactive;
--     * re-dates the survivors onto consecutive days starting TOMORROW, order
--       preserved — this also closes holes left by cascade deletes;
--     * two-phase re-date (park at +20000 days, then assign final dates), so
--       the publish_date PK never sees a transient duplicate mid-update.
--   Scheduled nightly at 02:47 UTC (cron.schedule upserts by job name, same
--   pattern as recompute-profile-boundaries) and run once at apply time.
--
-- EFFECTS ON USERS
--   Compaction only ever pulls picks EARLIER, never reorders. Tomorrow's pick
--   can change overnight; the day wall's teaser is fetched live, and a device
--   ahead of UTC that already assigned "tomorrow" keeps its stored assignment
--   (stored wins in get_daily_question) — a bounded, self-resolving skew.
-- ============================================================================

create or replace function public.compact_daily_picks()
returns text
language plpgsql security definer set search_path = public as $$
declare
  v_today    date := (now() at time zone 'utc')::date;
  v_start    date := (now() at time zone 'utc')::date + 1;
  v_removed  int  := 0;
  v_moved    int  := 0;
  v_end      date;
begin
  -- 1) Drop future picks whose question was deactivated.
  with dead as (
    delete from public.daily_picks dp
    using public.questions q
    where q.id = dp.question_id
      and not q.is_active
      and dp.publish_date > v_today
    returning 1
  )
  select count(*) into v_removed from dead;

  -- 2) Park the surviving future picks far out of the way, so step 3 can
  --    never collide with a not-yet-moved row on the date PK.
  update public.daily_picks
     set publish_date = publish_date + 20000
   where publish_date > v_today;

  -- 3) Re-date them consecutively from tomorrow, original order preserved.
  with renumbered as (
    select dp.question_id,
           v_start + (row_number() over (order by dp.publish_date))::int - 1
             as new_date
    from public.daily_picks dp
    where dp.publish_date > v_today + 10000
  )
  update public.daily_picks dp
     set publish_date = r.new_date
    from renumbered r
   where dp.question_id = r.question_id;
  get diagnostics v_moved = row_count;

  select max(publish_date) into v_end from public.daily_picks;

  return format('removed %s dead pick(s), calendar: %s future pick(s), ends %s',
                v_removed, v_moved, v_end);
end;
$$;

revoke all on function public.compact_daily_picks()
  from public, anon, authenticated;
grant execute on function public.compact_daily_picks() to service_role;

comment on function public.compact_daily_picks() is
  'Removes FUTURE daily_picks whose question is deactivated and re-dates the '
  'survivors onto consecutive days from tomorrow (also closing cascade-delete '
  'holes). Past and today are never touched. Nightly via pg_cron; safe to run '
  'by hand any time. See 20260820190000.';

-- Nightly, 02:47 UTC. cron.schedule upserts by job name, so re-running this
-- migration just refreshes the same job.
create extension if not exists pg_cron;
select cron.schedule(
  'compact-daily-picks',
  '47 2 * * *',
  'select public.compact_daily_picks()'
);

-- Run once now: 5 dead future picks are in the calendar at apply time.
select public.compact_daily_picks();
