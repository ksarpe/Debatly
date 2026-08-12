-- ============================================================================
-- Reveal feed + seen-memory.
--
-- Shifts the free-user model from "unlock = permanent read permission" to
-- "reveal one new question at a time; remember it so it never repeats".
--
--   * question_unlocks  -> question_seen   (a CONSUMPTION log, not a grant)
--   * can_read_question_text / RLS         (drop the seen branch: free text =
--                                           premium OR the current daily only)
--   * reveal_free_question / reveal_ad_question (DEFINER) server-pick a random
--     UNSEEN, non-premium, non-daily question, record it in question_seen, and
--     RETURN its text in the same call — the only way a free user ever gets that
--     text. The client holds it in session memory; once dropped it is neither
--     re-readable (the gate no longer grants it) nor re-served (seen-memory).
--   * unlock_question / spend_free_unlock_credit are replaced by the two reveals.
--
-- Decisions (2026-06-20): back-navigation is client-session-only; a logged-in
-- free user gets 1 reveal/day on the credit (reveal_free_question), every other
-- reveal needs a rewarded ad (reveal_ad_question, guests included); premium is
-- unlimited and keeps reading the whole catalog via the gate.
--
-- Premium content (questions.is_premium = true) is NEVER handed out by a reveal —
-- it stays premium-only. Running out of unseen questions => the reveal returns no
-- row (client handles the empty state; behaviour TBD).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) question_unlocks -> question_seen. Grants, the PK and the read-own policy
--    follow the table through the rename; we just relabel the policy.
-- ----------------------------------------------------------------------------
alter table public.question_unlocks rename to question_seen;
alter policy "read own unlocks" on public.question_seen rename to "read own seen";

-- ----------------------------------------------------------------------------
-- 2) Text gate: free users may read ONLY the current daily (premium reads all).
--    The seen branch is gone, so a revealed question is not re-readable later.
-- ----------------------------------------------------------------------------
create or replace function public.can_read_question_text(
  p_question_id uuid,
  p_date        date
)
returns boolean
language sql stable security definer set search_path = public as $$
  select
    public.is_premium(auth.uid())
    or exists (
      select 1 from public.daily_questions d
      where d.question_id = p_question_id
        and d.publish_date = p_date
        and p_date between (now() at time zone 'utc')::date - 1
                       and (now() at time zone 'utc')::date + 1
    );
$$;
revoke all on function public.can_read_question_text(uuid, date) from public;

-- RLS on the translations table now frees text for premium only. The single free
-- daily reaches free users exclusively through the DEFINER RPCs (get_daily_question
-- + the reveals), never a direct table read.
drop policy if exists "read question text (gated)" on public.question_translations;
create policy "read question text (gated)" on public.question_translations
  for select to anon, authenticated
  using (
    exists (
      select 1 from public.questions q
      where q.id = question_translations.question_id and q.is_active
    )
    and public.is_premium(auth.uid())
  );

-- ----------------------------------------------------------------------------
-- 3) Retire the old per-question unlock + credit-spend RPCs.
-- ----------------------------------------------------------------------------
drop function if exists public.unlock_question(uuid);
drop function if exists public.spend_free_unlock_credit(uuid);

-- ----------------------------------------------------------------------------
-- 4) reveal_ad_question — reveal the next UNSEEN question after a rewarded ad.
--    Server-picks (random eligible), records it in question_seen, returns text.
--    Available to any signed-in user, guests included (watching ads is fine;
--    the seen-memory is just per-uuid and farming a new identity only loses
--    progress). Returns no row when the user has seen everything eligible.
-- ----------------------------------------------------------------------------
create or replace function public.reveal_ad_question(
  p_locale text default 'pl',
  p_date   date default (now() at time zone 'utc')::date
)
returns table (
  id            uuid,
  category      text,
  is_premium    boolean,
  question_text text
)
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_qid uuid;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

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

  if v_qid is null then
    return;  -- nothing unseen left
  end if;

  insert into public.question_seen (user_id, question_id, source)
  values (v_uid, v_qid, 'ad')
  on conflict (user_id, question_id) do nothing;

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

revoke all on function public.reveal_ad_question(text, date) from public;
grant execute on function public.reveal_ad_question(text, date) to authenticated;

-- ----------------------------------------------------------------------------
-- 5) reveal_free_question — same reveal, paid with the daily free credit instead
--    of an ad. Real accounts only (anti-farm); premium does not use it. Charges
--    one credit only on a successful reveal (no charge when nothing is left).
-- ----------------------------------------------------------------------------
create or replace function public.reveal_free_question(
  p_locale text default 'pl',
  p_date   date default (now() at time zone 'utc')::date
)
returns table (
  id            uuid,
  category      text,
  is_premium    boolean,
  question_text text
)
language plpgsql security definer set search_path = public as $$
declare
  v_uid     uuid := auth.uid();
  v_credits int;
  v_qid     uuid;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if public.is_premium(v_uid) then
    raise exception 'premium users do not use unlock credits';
  end if;
  if not public.is_real_account(v_uid) then
    raise exception 'free credit is for real accounts only';
  end if;

  -- Lock the profile row so two taps can't both spend the same credit.
  select p.free_unlock_credits into v_credits
  from public.profiles p
  where p.id = v_uid
  for update;

  if coalesce(v_credits, 0) < 1 then
    raise exception 'no free unlock credits';
  end if;

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

  -- Nothing left to reveal: don't charge the credit.
  if v_qid is null then
    return;
  end if;

  insert into public.question_seen (user_id, question_id, source)
  values (v_uid, v_qid, 'free_credit')
  on conflict (user_id, question_id) do nothing;

  -- Qualify profiles.id: this function RETURNS a column named `id`, so an
  -- unqualified `id` here is ambiguous with that OUT variable.
  update public.profiles set free_unlock_credits = v_credits - 1
   where profiles.id = v_uid;

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

revoke all on function public.reveal_free_question(text, date) from public;
grant execute on function public.reveal_free_question(text, date) to authenticated;
