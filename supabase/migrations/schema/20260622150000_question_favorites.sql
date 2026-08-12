-- ============================================================================
-- question_favorites: a premium user's saved questions.
--
-- Premium walks the whole catalog (see get_questions); this lets them bookmark
-- the questions worth keeping. Two product rules shape the gate:
--
--   * ADDING a favorite is premium-only — a free user's star is a paywall hook,
--     never a write. toggle_question_favorite enforces this server-side, so the
--     client gate is convenience, not the trust boundary.
--   * VIEWING a favorite is readable FOREVER — once saved, get_favorite_questions
--     returns the full text even after premium lapses. The favorite row itself
--     acts as the grant (like question_unlocks), so a lapsed user keeps the list
--     they curated. This deliberately trades a small "favorite the catalog while
--     premium, read forever" loophole for a kinder downgrade; accepted by design.
--
-- Per the project convention nothing here is client-writable: reads go through
-- RLS read-own, the single write path is the SECURITY DEFINER toggle RPC.
-- The table is per-uuid and idempotent on (user_id, question_id).
-- ============================================================================

create table public.question_favorites (
  user_id      uuid not null references auth.users(id) on delete cascade,
  question_id  uuid not null references public.questions(id) on delete cascade,
  favorited_at timestamptz not null default now(),
  primary key (user_id, question_id)
);

alter table public.question_favorites enable row level security;

-- Read-own only; the list is private to its owner.
create policy "read own favorites" on public.question_favorites
  for select to authenticated using (user_id = auth.uid());

-- No client INSERT/DELETE policy — every write is mediated by the toggle RPC.
grant select on public.question_favorites to authenticated;

-- ----------------------------------------------------------------------------
-- toggle_question_favorite — add or remove the caller's favorite, returning the
-- NEW state (true = now favorited, false = now removed).
--
-- SECURITY DEFINER because the table has no client write policy. The row is
-- always pinned to auth.uid(), so a caller can only ever toggle their own.
-- Removing is allowed regardless of premium (a lapsed user can still curate);
-- ADDING raises 'premium required' for a non-premium caller, and the INSERT ...
-- SELECT guards the target is a real, active question.
-- ----------------------------------------------------------------------------
create or replace function public.toggle_question_favorite(p_question_id uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  -- Already a favorite? Toggle it off. Allowed for anyone (curating a list you
  -- already own isn't gated), so a lapsed-premium user can still prune theirs.
  delete from public.question_favorites
  where user_id = v_uid and question_id = p_question_id;
  if found then
    return false;
  end if;

  -- Adding is premium-only — the free-tier star is a paywall hook, not a write.
  if not public.is_premium(v_uid) then
    raise exception 'premium required';
  end if;

  insert into public.question_favorites (user_id, question_id)
  select v_uid, q.id
  from public.questions q
  where q.id = p_question_id and q.is_active
  on conflict (user_id, question_id) do nothing;

  return true;
end;
$$;

revoke all on function public.toggle_question_favorite(uuid) from public;
grant execute on function public.toggle_question_favorite(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- get_favorite_ids — the caller's favorited question ids.
--
-- Drives the star's filled/outline state on the question screen without the
-- client having to know each question's status up front. Cheap (a small set per
-- user); the client loads it once per session and updates it optimistically on
-- toggle. SECURITY DEFINER + auth.uid() filter so it only ever returns own rows.
-- ----------------------------------------------------------------------------
create or replace function public.get_favorite_ids()
returns setof uuid
language sql stable security definer set search_path = public as $$
  select question_id from public.question_favorites where user_id = auth.uid();
$$;

revoke all on function public.get_favorite_ids() from public;
grant execute on function public.get_favorite_ids() to authenticated;

-- ----------------------------------------------------------------------------
-- get_favorite_questions — the caller's favorites WITH text, newest first.
--
-- Deliberately returns the full question_text unconditionally for favorited
-- rows: the favorite is the grant ("readable forever", see the table comment),
-- so this is NOT gated by can_read_question_text / is_premium. SECURITY DEFINER
-- lets it read question_translations past RLS; the auth.uid() filter keeps it to
-- the caller's own favorites. Falls back to the EN text when the requested
-- locale is missing, mirroring get_questions.
-- ----------------------------------------------------------------------------
create or replace function public.get_favorite_questions(p_locale text default 'pl')
returns table (
  id            uuid,
  category      text,
  is_premium    boolean,
  question_text text,
  favorited_at  timestamptz
)
language sql stable security definer set search_path = public as $$
  select
    q.id,
    q.category,
    q.is_premium,
    coalesce(tr.question_text, en.question_text) as question_text,
    f.favorited_at
  from public.question_favorites f
  join public.questions q on q.id = f.question_id and q.is_active
  left join public.question_translations tr
         on tr.question_id = q.id and tr.locale = p_locale
  left join public.question_translations en
         on en.question_id = q.id and en.locale = 'en'
  where f.user_id = auth.uid()
  order by f.favorited_at desc;
$$;

revoke all on function public.get_favorite_questions(text) from public;
grant execute on function public.get_favorite_questions(text) to authenticated;
