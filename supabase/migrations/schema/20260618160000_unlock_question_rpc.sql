-- ============================================================================
-- unlock_question: grant the caller a per-question unlock immediately.
--
-- The swipe deck lets a free user reveal one locked question by watching a
-- rewarded ad. AdMob's Server-Side Verification (SSV) is the authoritative,
-- unspoofable grant -- but it arrives server-to-server with some latency, so
-- refetching the deck the instant the ad ends would still show the question
-- locked (a race the user reads as "I watched the ad and got nothing").
--
-- This RPC lets the signed-in client record the unlock the moment the reward
-- fires, so the text reveals in place with no wait. The SSV callback
-- (admob-ssv) upserts the SAME (user, question) row idempotently as the
-- verified backstop / audit trail.
--
-- SECURITY DEFINER because question_unlocks has no client write policy (all
-- writes are server-mediated). The function pins the row to auth.uid(), so a
-- caller can only ever unlock for THEMSELVES, and the INSERT ... SELECT guards
-- that the target is a real, active question -- a caller cannot conjure rows
-- for arbitrary ids.
-- ============================================================================
create or replace function public.unlock_question(p_question_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  insert into public.question_unlocks (user_id, question_id, source)
  select auth.uid(), q.id, 'ad'
  from public.questions q
  where q.id = p_question_id and q.is_active
  on conflict (user_id, question_id) do nothing;
end;
$$;

revoke all on function public.unlock_question(uuid) from public;
grant execute on function public.unlock_question(uuid) to authenticated;
