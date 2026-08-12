-- ============================================================================
-- Anti-farm: gate the free-unlock credit to REAL (non-anonymous) accounts.
--
-- The problem: anonymous identities are free and unlimited. Every signOut()
-- followed by ensureSignedIn() mints a brand-new anonymous auth.users row with a
-- clean slate, so the server-UTC anti-tamper on the credit (which defends
-- against CLOCK manipulation) is defeated by IDENTITY manipulation — log out /
-- clear app data → fresh uuid → fresh credit → repeat = unlimited free unlocks.
--
-- The fix here closes the casual logout/login farm: only a real account
-- (email / Google — auth.users.is_anonymous = false) earns the daily credit. A
-- guest re-rolling their anonymous identity gains nothing, because guests get no
-- credit at all. Guests still read today's SCHEDULED daily for free — but that
-- is the same question for everyone, so re-rolling identity yields no new
-- content. To farm now you'd have to create new REAL accounts (email
-- confirmation / Google), which is real friction.
--
-- This does NOT make abuse impossible on a phone (reinstall, factory reset, many
-- devices remain) — it stops the 99% casual case. Device-binding / attestation
-- would be the next tier if real abuse shows up.
--
-- NOTE: the random "daily free bonus question" (claim_daily_free_question +
-- daily_free_grants) was already decommissioned in streak_votes_credits_ranks
-- and replaced by this credit, so there is nothing else to gate here.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- is_real_account — true only for signed-up users, false for anonymous guests
-- (and for an unknown uid). SECURITY DEFINER so it can read auth.users without
-- exposing it to clients; mirrors the is_premium() helper's shape.
--
-- Reads auth.users.is_anonymous (authoritative) rather than the JWT claim, so it
-- stays correct the instant an anonymous user is upgraded in place to an
-- email/password account (updateUser), even before their token refreshes.
-- ----------------------------------------------------------------------------
create or replace function public.is_real_account(p_uid uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(not u.is_anonymous, false)
  from auth.users u
  where u.id = p_uid;
$$;

-- Internal helper only: it is called from inside the SECURITY DEFINER functions
-- below (which run as the owner), so it needs NO API-facing grant. Leaving it
-- unexposed avoids an anon/authenticated "is this uuid anonymous?" probe via
-- /rest/v1/rpc. (revoke from public strips the default PUBLIC execute; the owner
-- keeps it, which is all the internal callers need.)
revoke all on function public.is_real_account(uuid) from public;

-- ----------------------------------------------------------------------------
-- sync_user_state — unchanged except the credit top-up is now gated to real
-- accounts (the only edit is the `if` condition on the credit block).
-- ----------------------------------------------------------------------------
create or replace function public.sync_user_state(p_locale text default 'pl')
returns table (
  current_streak      int,
  longest_streak      int,
  free_unlock_credits int,
  rank_tier           int,
  rank_name           text,
  next_rank_streak    int,
  is_premium          boolean
)
language plpgsql security definer set search_path = public as $$
declare
  v_uid       uuid := auth.uid();
  v_today     date := (now() at time zone 'utc')::date;   -- SERVER clock only
  v_premium   boolean;
  v_streak    int;
  v_longest   int;
  v_last_vote date;
  v_credits   int;
  v_last_cred date;
  v_disp      int;                                         -- display streak
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  v_premium := public.is_premium(v_uid);

  -- Lock the profile row to serialize the credit top-up against itself.
  select p.current_streak, p.longest_streak, p.last_vote_date,
         p.free_unlock_credits, p.last_credit_date
    into v_streak, v_longest, v_last_vote, v_credits, v_last_cred
  from public.profiles p
  where p.id = v_uid
  for update;

  if not found then
    v_streak := 0; v_longest := 0; v_credits := 0;
  end if;

  -- Free-unlock credit: only REAL (non-anonymous) accounts earn it. Premium and
  -- anonymous guests are forced to 0 so the credit chip never shows for them.
  -- Gating it to real accounts is the anti-farm rule: re-rolling an anonymous
  -- identity (log out / clear data) no longer mints a fresh credit.
  if v_premium or not public.is_real_account(v_uid) then
    if coalesce(v_credits, 0) <> 0 then
      update public.profiles set free_unlock_credits = 0 where id = v_uid;
      v_credits := 0;
    end if;
  elsif v_last_cred is null or v_last_cred < v_today then
    v_credits := greatest(coalesce(v_credits, 0), 1);
    update public.profiles
       set free_unlock_credits = v_credits,
           last_credit_date     = v_today
     where id = v_uid;
  end if;

  -- Display streak: still alive if the last vote was today or yesterday;
  -- otherwise it is broken and shows 0 (the stored value resets on next vote).
  if v_last_vote is null or v_last_vote < v_today - 1 then
    v_disp := 0;
  else
    v_disp := coalesce(v_streak, 0);
  end if;

  return query
  with cur as (
    select r.tier, r.name_pl, r.name_en
    from public.ranks r
    where r.min_streak <= v_disp
    order by r.min_streak desc
    limit 1
  ),
  nxt as (
    select min(r.min_streak) as next_streak
    from public.ranks r
    where r.min_streak > v_disp
  )
  select
    v_disp,
    coalesce(v_longest, 0),
    coalesce(v_credits, 0),
    cur.tier,
    case when p_locale = 'pl' then cur.name_pl else cur.name_en end,
    nxt.next_streak,
    v_premium
  from cur cross join nxt;
end;
$$;

revoke all on function public.sync_user_state(text) from public;
grant execute on function public.sync_user_state(text) to authenticated;
