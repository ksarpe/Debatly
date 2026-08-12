-- ============================================================================
-- Harden reveal_ad_question: a reveal must be BACKED BY a verified ad reward.
--
-- THE HOLE THIS CLOSES
--   reveal_ad_question is granted to `authenticated` and was gated only on
--   auth.uid() — it never checked that an ad was actually watched. The AdMob SSV
--   callback (admob-ssv) is the ONLY unspoofable proof a rewarded ad played
--   (Google signs it with ECDSA P-256), but it is a pure audit log that grants
--   nothing. So anyone could POST /rest/v1/rpc/reveal_ad_question in a loop and
--   drain the entire non-premium catalog without a single ad — and re-roll a
--   fresh anonymous identity (signOut -> signInAnonymously) for unlimited draws.
--   That is lost ad revenue + free content extraction. (Premium-flagged
--   questions were never at risk: the reveal filter excludes them.)
--
-- THE FIX (no change to the client flow: peek -> watch ad -> reveal)
--   Tie each reveal to a verified ad reward, with a tiny grace buffer:
--
--       ad_reveals_used  <=  verified_ad_rewards  +  GRACE
--
--   * verified_ad_rewards = COUNT of this user's ad_reward_events rows the SSV
--     callback marked `verified`. Unspoofable: only Google's signed callback,
--     written by the service-role edge function, ever creates them — no client
--     (anon or authenticated) can insert a row (no INSERT policy + no grant).
--   * GRACE absorbs the SSV race. The on-device reward callback fires the instant
--     the ad ends and the client reveals immediately, while Google's
--     server-to-server SSV lands a beat later. GRACE lets that one in-flight
--     reward pay out NOW; the next reveal needs its SSV to have landed. A legit
--     user (one ad at a time, ~20-30s each) never notices — by the time they
--     finish the next ad, the previous SSV has arrived. A script with no real ad
--     gets at most GRACE reveals per identity, then is blocked.
--
-- RESULT
--   * Legit watch-an-ad flow: unchanged.
--   * Looping the RPC with no ad: capped at GRACE, then 'ad reward not verified'.
--   * Re-rolling anonymous identities: GRACE per identity — heavy friction for
--     mass extraction instead of an instant, unlimited drain.
--
-- ⚠ PREREQUISITE BEFORE RELEASE
--   The AdMob rewarded unit's SSV callback URL MUST point at the admob-ssv
--   function (see supabase/functions/README.md). Test ad units fire SSV too, so
--   the full loop is testable pre-launch. If SSV is NOT wired up, no verified
--   rewards ever land and every user is capped at GRACE lifetime reveals. To
--   relax enforcement temporarily, raise c_grace below and re-run this file.
-- ============================================================================

-- Lifetime count of ad-reveals this user has spent. Compared against their
-- verified ad rewards to enforce the budget. Server-managed (no client write
-- policy); only the DEFINER RPC below ever changes it.
alter table public.profiles
  add column if not exists ad_reveals_used int not null default 0;

-- Signature is unchanged, so CREATE OR REPLACE preserves the existing grants;
-- the revoke/grant at the end re-asserts them anyway (idempotent).
create or replace function public.reveal_ad_question(
  p_locale      text default 'pl',
  p_date        date default (now() at time zone 'utc')::date,
  p_question_id uuid default null
)
returns table (
  id            uuid,
  category      text,
  is_premium    boolean,
  question_text text
)
language plpgsql security definer set search_path = public as $$
declare
  c_grace    constant int := 2;   -- in-flight SSV rewards trusted on credit
  v_uid      uuid := auth.uid();
  v_qid      uuid;
  v_used     int;
  v_verified int;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  -- ---- Budget gate: the reveal must be backed by a verified ad reward -------
  -- Lock the profile row so two concurrent taps can't both spend the same
  -- headroom (and double-reveal off one verified reward).
  select p.ad_reveals_used into v_used
  from public.profiles p
  where p.id = v_uid
  for update;

  select count(*) into v_verified
  from public.ad_reward_events e
  where e.user_id = v_uid and e.verified;

  if coalesce(v_used, 0) >= coalesce(v_verified, 0) + c_grace then
    -- No proof of a watched ad (beyond the grace buffer). The client surfaces
    -- this like any reveal failure: a toast + the paywall again, so a genuine
    -- user whose SSV is merely lagging can simply watch another ad.
    raise exception 'ad reward not verified';
  end if;

  -- ---- Pick the question to reveal (unchanged logic) ------------------------
  -- Prefer the peeked (teased) question, but only if it is still eligible.
  if p_question_id is not null then
    select q.id into v_qid
    from public.questions q
    where q.id = p_question_id
      and q.is_active
      and not q.is_premium
      and not exists (
        select 1 from public.daily_questions d
        where d.question_id = q.id and d.publish_date = p_date
      )
      and not exists (
        select 1 from public.question_seen s
        where s.user_id = v_uid and s.question_id = q.id
      );
  end if;

  -- No (valid) peek: random unseen pick so the watched ad still pays out.
  if v_qid is null then
    select q.id into v_qid
    from public.questions q
    where q.is_active
      and not q.is_premium
      and not exists (
        select 1 from public.daily_questions d
        where d.question_id = q.id and d.publish_date = p_date
      )
      and not exists (
        select 1 from public.question_seen s
        where s.user_id = v_uid and s.question_id = q.id
      )
    order by random()
    limit 1;
  end if;

  -- Nothing unseen left: return no row and DON'T spend budget on an empty
  -- reveal (so the user keeps their headroom for when content is added).
  if v_qid is null then
    return;
  end if;

  insert into public.question_seen (user_id, question_id, source)
  values (v_uid, v_qid, 'ad')
  on conflict (user_id, question_id) do nothing;

  -- Spend one unit of the ad-reveal budget (only on a real reveal).
  update public.profiles
     set ad_reveals_used = coalesce(v_used, 0) + 1
   where id = v_uid;

  return query
    select q.id, q.category, q.is_premium,
           coalesce(tr.question_text, en.question_text)
    from public.questions q
    left join public.question_translations tr
           on tr.question_id = q.id and tr.locale = p_locale
    left join public.question_translations en
           on en.question_id = q.id and en.locale = 'en'
    where q.id = v_qid;
end;
$$;

revoke all on function public.reveal_ad_question(text, date, uuid) from public;
grant execute on function public.reveal_ad_question(text, date, uuid) to authenticated;
