-- Free tier gets "today" in the question history.
--
-- The daily question is always free, so its history entry should be too: the
-- redesigned history screen shows a free user today's card(s) with the older
-- record behind a locked PRO panel. But this RPC returned zero rows for any
-- non-premium caller, so the free view had nothing to render.
--
-- Free callers now get their votes from the last 48 hours; that window covers
-- "the user's local today" in every timezone (the client trims to the local
-- calendar day) without exposing meaningful history. Premium callers keep the
-- full record — the body is otherwise identical to
-- 20260815120000_question_vote_counts.sql §8.
--
-- Backwards-compatible: shipped free clients never call this RPC (the old
-- screen short-circuits to the PRO upsell client-side, so the server gate was
-- belt-and-braces), and premium output is unchanged.

create or replace function public.get_vote_history(
  p_locale text default 'pl'
)
returns table(
  question_id uuid,
  category text,
  question_text text,
  voted_at timestamptz,
  yes_count int,
  no_count int,
  my_choice int
)
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid := auth.uid();
  v_since timestamptz;
begin
  if v_uid is null then
    return;
  end if;

  -- Free tier: only the freshest votes (the always-free daily lives there).
  -- 48h ≥ any timezone's "local today"; the client trims to the local day.
  if not public.is_premium(v_uid) then
    v_since := now() - interval '48 hours';
  end if;

  return query
  with mine as (
    -- The caller's most recent 1000 votes — bound the work BEFORE tallying.
    select mv.question_id, mv.choice, mv.voted_at
    from public.question_votes mv
    where mv.user_id = v_uid
      and (v_since is null or mv.voted_at >= v_since)
    order by mv.voted_at desc
    limit 1000
  )
  select
    q.id,
    q.category,
    coalesce(tr.question_text, en.question_text),
    mine.voted_at,
    coalesce(c.yes_count, 0) + coalesce(sd.seed_yes, 0),
    coalesce(c.no_count,  0) + coalesce(sd.seed_no,  0),
    mine.choice::int
  from mine
  join public.questions q on q.id = mine.question_id and q.is_active
  left join public.question_translations tr
         on tr.question_id = q.id and tr.locale = p_locale
  left join public.question_translations en
         on en.question_id = q.id and en.locale = 'en'
  left join public.question_vote_counts c on c.question_id = q.id
  left join public.question_vote_seeds sd on sd.question_id = q.id
  order by mine.voted_at desc;
end;
$function$;

revoke all on function public.get_vote_history(text) from public, anon;
grant execute on function public.get_vote_history(text) to authenticated, service_role;
