-- ============================================================================
-- Smaczki: which answer does this argument attack?
-- ----------------------------------------------------------------------------
-- 2026-08-19. The smaczki were written on the assumption that position 1 hits
-- "the obvious answer" — but on a 40/60 split half the readers picked the OTHER
-- side and get an argument aimed at somebody else. Same sentence, and it lands
-- as trivia instead of as a sentence aimed personally at them.
--
-- WHAT THIS ADDS
--   * question_smaczki.side — 'attacks_yes' | 'attacks_no' | 'neutral', and
--     NULL for "not tagged yet". NULL is a first-class state on purpose: the
--     1676 live smaczki start untagged and the admin panel filters on it, so
--     "deliberately neutral" must be distinguishable from "nobody looked".
--   * get_question_smaczki now returns `side` and orders the rows by how
--     relevant they are to the CALLER'S OWN vote: the one attacking their
--     actual choice first, then the neutral ones, then the argument aimed at
--     the other side. Before the user has voted (and for anon) the ordering
--     collapses back to position, i.e. exactly today's behaviour.
--   * The free gate moves from "position = 1" to "the top-ranked row". A free
--     user still reads EXACTLY ONE smaczek per question — but it is the one
--     aimed at them. Edge case accepted knowingly: a free user who reads the
--     teaser before voting and then votes can end up having seen 2 of 3 (the
--     pre-vote row plus the now-relevant one). Never 3, and the day wall — not
--     the smaczki — is the conversion surface.
--   * question_snapshot carries `side`, so the admin editor round-trips it and
--     the draft diff shows it. That changes question_content_hash for EVERY
--     question, which would make all 38 open drafts fail their conflict guard
--     for a change nobody made — so the open drafts are re-based to the new
--     hash in the same transaction. Their content is untouched.
--   * _admin_write_smaczki persists `side` from the draft payload. It rewrites
--     every smaczek row on save, so without this the tags would be wiped by the
--     next unrelated edit.
--   * admin_list_questions gains `smaczki_untagged` + p_only_untagged, so the
--     tagging pass over the catalog has a worklist.
--
-- Idempotent: guarded DDL + create or replace (the two functions whose result
-- shape changes are dropped first, as Postgres requires). Safe to re-run.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) The column. Nullable = untagged; the check still constrains the values.
-- ----------------------------------------------------------------------------
alter table public.question_smaczki
  add column if not exists side text;

alter table public.question_smaczki
  drop constraint if exists question_smaczki_side_check;
alter table public.question_smaczki
  add constraint question_smaczki_side_check
  check (side is null or side in ('attacks_yes', 'attacks_no', 'neutral'));

comment on column public.question_smaczki.side is
  'Which answer this argument attacks: attacks_yes / attacks_no / neutral. '
  'NULL = not tagged yet (served as if neutral).';

-- ----------------------------------------------------------------------------
-- 2) get_question_smaczki — same gate, new ordering, one extra column.
--    Result shape changes, so the old signature has to go first.
-- ----------------------------------------------------------------------------
drop function if exists public.get_question_smaczki(uuid, text);

create function public.get_question_smaczki(
  p_question_id uuid,
  p_locale      text default 'pl'
)
returns table ("position" smallint, is_locked boolean, text text, side text)
language sql stable security definer set search_path to 'public'
as $$
  with prem as materialized (
    -- MATERIALIZED is load-bearing: without it the planner is free to inline
    -- this CTE into both reference sites and call is_premium() twice.
    select public.is_premium(auth.uid()) as full_smaczki
  ),
  mine as materialized (
    -- The caller's own vote on this question, if any. 1 = TAK, 2 = NIE.
    -- Zero rows before they vote, which is what makes the ordering fall back
    -- to plain position order below.
    select v.choice
    from public.question_votes v
    where v.user_id = auth.uid() and v.question_id = p_question_id
  ),
  access as (
    select
      p.full_smaczki,
      (
        p.full_smaczki
        or exists (
          select 1 from public.question_seen u
          where u.user_id = auth.uid() and u.question_id = p_question_id
        )
        -- Legacy calendar branch: still matches a real row every day (the
        -- table is seeded out to 2027), so it keeps the public teaser alive
        -- for pre-freemium app versions. See 20260815170000.
        or exists (
          select 1 from public.daily_questions d
          where d.question_id = p_question_id
            and d.publish_date between (now() at time zone 'utc')::date - 1
                                   and (now() at time zone 'utc')::date + 1
        )
      ) as can_access
    from prem p
  ),
  ranked as (
    select
      s.id,
      s.position,
      s.side,
      a.full_smaczki,
      row_number() over (
        order by
          case
            -- No vote yet (or anon): nothing to aim at, keep author order.
            when m.choice is null                            then 1
            when m.choice = 1 and s.side = 'attacks_yes'     then 0
            when m.choice = 2 and s.side = 'attacks_no'      then 0
            when s.side is null or s.side = 'neutral'        then 1
            else 2
          end,
          s.position
      ) as rel
    from access a
    join public.question_smaczki s
      on s.question_id = p_question_id and s.is_active
    left join mine m on true
    where a.can_access
  )
  select
    r.position,
    not (r.full_smaczki or r.rel = 1) as is_locked,
    case
      when r.full_smaczki or r.rel = 1
        then coalesce(tr.text, en.text)
      else null
    end as text,
    r.side
  from ranked r
  left join public.question_smaczki_translations tr
    on tr.smaczek_id = r.id and tr.locale = p_locale
  left join public.question_smaczki_translations en
    on en.smaczek_id = r.id and en.locale = 'en'
  order by r.rel;
$$;

-- anon is intentionally on the list (matches prod): an unauthenticated caller
-- gets auth.uid() = null, so is_premium is false, no question_seen row matches
-- and `mine` is empty — it can only ever read smaczek #1 of the calendar daily.
revoke all on function public.get_question_smaczki(uuid, text) from public;
grant execute on function public.get_question_smaczki(uuid, text) to anon, authenticated;

-- ----------------------------------------------------------------------------
-- 3) question_snapshot: carry `side` through the admin draft flow.
-- ----------------------------------------------------------------------------
create or replace function public.question_snapshot(p_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select case when q.id is null then null else jsonb_build_object(
    'id', q.id,
    'category', q.category,
    'is_premium', q.is_premium,
    'is_active', q.is_active,
    'pl', (select t.question_text from public.question_translations t
            where t.question_id = q.id and t.locale = 'pl'),
    'en', (select t.question_text from public.question_translations t
            where t.question_id = q.id and t.locale = 'en'),
    'smaczki', coalesce((
      select jsonb_agg(jsonb_build_object(
               'position', s.position, 'pl', tp.text, 'en', te.text, 'side', s.side)
                       order by s.position)
      from public.question_smaczki s
      left join public.question_smaczki_translations tp on tp.smaczek_id = s.id and tp.locale = 'pl'
      left join public.question_smaczki_translations te on te.smaczek_id = s.id and te.locale = 'en'
      where s.question_id = q.id and s.is_active), '[]'::jsonb)
  ) end
  from public.questions q where q.id = p_id;
$$;

-- The snapshot gained a key, so every question's content hash just changed
-- without its content changing. Re-base the open drafts, or each one would
-- fail admin_approve_draft's conflict guard on a phantom edit.
update public.question_drafts d
   set base_hash = public.question_content_hash(d.question_id)
 where d.status in ('draft', 'pending')
   and d.question_id is not null;

-- ----------------------------------------------------------------------------
-- 4) _admin_write_smaczki: persist `side`.
--    p_items = [{"pl":"…","en":"…","side":"attacks_yes"|"attacks_no"|"neutral"|null}, …]
--    Anything outside that set is stored as NULL (untagged) rather than
--    rejected — the writer must never be the reason a save fails.
-- ----------------------------------------------------------------------------
create or replace function public._admin_write_smaczki(p_question_id uuid, p_items jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare it jsonb; pos int := 0; sid uuid; v_side text;
begin
  delete from public.question_smaczki_translations
   where smaczek_id in (select id from public.question_smaczki where question_id = p_question_id);
  delete from public.question_smaczki where question_id = p_question_id;

  for it in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
    if coalesce(btrim(it->>'pl'), '') = '' then continue; end if;   -- skip blanks, keeps 1..N tight
    pos := pos + 1;
    v_side := nullif(btrim(coalesce(it->>'side', '')), '');
    if v_side is not null and v_side not in ('attacks_yes', 'attacks_no', 'neutral') then
      v_side := null;
    end if;
    insert into public.question_smaczki (question_id, position, is_active, side)
    values (p_question_id, pos, true, v_side) returning id into sid;
    insert into public.question_smaczki_translations (smaczek_id, locale, text)
    values (sid, 'pl', btrim(it->>'pl'));
    if coalesce(btrim(it->>'en'), '') <> '' then
      insert into public.question_smaczki_translations (smaczek_id, locale, text)
      values (sid, 'en', btrim(it->>'en'));
    end if;
  end loop;
end;
$$;

revoke all on function public._admin_write_smaczki(uuid, jsonb) from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 5) admin_list_questions: untagged-smaczki count + filter.
--    Return-type change => drop + recreate + re-grant. Replaces the
--    20260818120000_admin_question_needs_review.sql version.
-- ----------------------------------------------------------------------------
drop function if exists public.admin_list_questions(text, boolean, integer, integer, boolean, boolean, boolean, boolean);

create function public.admin_list_questions(
  p_search text default null,
  p_only_active boolean default true,
  p_limit int default 50,
  p_offset int default 0,
  p_only_en_review boolean default false,
  p_only_favorites boolean default false,
  p_only_unverified boolean default false,
  p_only_needs_review boolean default false,
  p_only_untagged boolean default false
) returns table (
  id uuid, category text, is_premium boolean, is_active boolean,
  pl text, en text, smaczki_count int, open_draft_id uuid, content_hash text,
  en_review_needed boolean, is_favorite boolean, is_verified boolean,
  needs_review boolean, smaczki_untagged int, total_count bigint
) language plpgsql stable security definer set search_path = public as $$
begin
  perform public.admin_require();
  return query
  with base as (
    select q.id, q.category, q.is_premium, q.is_active, q.en_review_needed,
           (q.verified_at is not null) as is_verified,
           (q.needs_review_at is not null) as needs_review,
           tp.question_text as pl, te.question_text as en,
           exists (select 1 from public.admin_question_favorites f
                    where f.question_id = q.id and f.user_id = auth.uid()) as is_favorite
    from public.questions q
    left join public.question_translations tp on tp.question_id = q.id and tp.locale = 'pl'
    left join public.question_translations te on te.question_id = q.id and te.locale = 'en'
    where (not p_only_active or q.is_active)
      and (not p_only_en_review or q.en_review_needed)
      and (not p_only_unverified or q.verified_at is null)
      and (not p_only_needs_review or q.needs_review_at is not null)
      and (not p_only_untagged or exists
             (select 1 from public.question_smaczki s
               where s.question_id = q.id and s.is_active and s.side is null))
      and (not p_only_favorites or exists
             (select 1 from public.admin_question_favorites f
               where f.question_id = q.id and f.user_id = auth.uid()))
      and (p_search is null or btrim(p_search) = ''
           or tp.question_text ilike '%' || p_search || '%'
           or te.question_text ilike '%' || p_search || '%')
  )
  select b.id, b.category, b.is_premium, b.is_active, b.pl, b.en,
         (select count(*)::int from public.question_smaczki s where s.question_id = b.id and s.is_active),
         (select d.id from public.question_drafts d
           where d.question_id = b.id and d.status in ('draft','pending')
           order by d.updated_at desc limit 1),
         public.question_content_hash(b.id),
         b.en_review_needed,
         b.is_favorite,
         b.is_verified,
         b.needs_review,
         (select count(*)::int from public.question_smaczki s
           where s.question_id = b.id and s.is_active and s.side is null),
         (select count(*) from base)
  from base b
  order by b.pl
  limit greatest(1, least(coalesce(p_limit, 50), 200)) offset greatest(0, coalesce(p_offset, 0));
end;
$$;

revoke all on function public.admin_list_questions(text, boolean, int, int, boolean, boolean, boolean, boolean, boolean) from public, anon;
grant execute on function public.admin_list_questions(text, boolean, int, int, boolean, boolean, boolean, boolean, boolean) to authenticated, service_role;
