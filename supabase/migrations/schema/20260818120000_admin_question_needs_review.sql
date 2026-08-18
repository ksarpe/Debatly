-- ============================================================================
-- Admin panel: global "do weryfikacji" flag on questions
-- ----------------------------------------------------------------------------
-- 2026-08-18. A third row marker next to ★ favorite and ✓ verified: the owner
-- flags a question as "needs another look" while browsing, then filters the
-- list down to the flagged ones. Same shape as verified_at:
--
--   * questions.needs_review_at — NULL = not flagged. Kept OUTSIDE
--     question_snapshot() / question_content_hash() on purpose (same as
--     en_review_needed / verified_at): toggling never invalidates open drafts.
--   * admin_toggle_needs_review(question_id) — flips the flag, returns the new
--     state (true = flagged). Global, not per-admin: like "verified", it is a
--     property of the content. Both directions audit-logged
--     (needs_review / needs_review_cleared).
--   * admin_list_questions gains needs_review + p_only_needs_review filter
--     (return-type change => drop + recreate + re-grant).
--   * admin_get_question exposes needs_review_at.
--
-- Idempotent: guarded DDL + create or replace. Safe to re-run.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Flag column
-- ----------------------------------------------------------------------------
alter table public.questions
  add column if not exists needs_review_at timestamptz;

-- ----------------------------------------------------------------------------
-- 2) Toggle RPC
-- ----------------------------------------------------------------------------
create or replace function public.admin_toggle_needs_review(p_question_id uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  v_new timestamptz;
begin
  perform public.admin_require();

  update public.questions
     set needs_review_at = case when needs_review_at is null then now() else null end
   where id = p_question_id
  returning needs_review_at into v_new;
  if not found then raise exception 'NOT_FOUND: question' using errcode = 'P0002'; end if;

  insert into public.admin_audit_log (question_id, action, actor)
  values (p_question_id, case when v_new is not null then 'needs_review' else 'needs_review_cleared' end, auth.uid());

  return v_new is not null;
end;
$$;

revoke all on function public.admin_toggle_needs_review(uuid) from public, anon;
grant execute on function public.admin_toggle_needs_review(uuid) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 3) admin_get_question: expose needs_review_at (outside the snapshot => hash-stable)
-- ----------------------------------------------------------------------------
create or replace function public.admin_get_question(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.admin_require();
  return jsonb_build_object(
    'question', public.question_snapshot(p_id),
    'content_hash', public.question_content_hash(p_id),
    'en_review_needed', (select q.en_review_needed from public.questions q where q.id = p_id),
    'verified_at', (select q.verified_at from public.questions q where q.id = p_id),
    'needs_review_at', (select q.needs_review_at from public.questions q where q.id = p_id),
    'open_draft', (select to_jsonb(d) from public.question_drafts d
                    where d.question_id = p_id and d.status in ('draft','pending')
                    order by d.updated_at desc limit 1)
  );
end;
$$;

-- ----------------------------------------------------------------------------
-- 4) admin_list_questions: needs_review column + p_only_needs_review filter
--    (replaces the 20260817130000_admin_question_verified.sql version)
-- ----------------------------------------------------------------------------
drop function if exists public.admin_list_questions(text, boolean, integer, integer, boolean, boolean, boolean);

create function public.admin_list_questions(
  p_search text default null,
  p_only_active boolean default true,
  p_limit int default 50,
  p_offset int default 0,
  p_only_en_review boolean default false,
  p_only_favorites boolean default false,
  p_only_unverified boolean default false,
  p_only_needs_review boolean default false
) returns table (
  id uuid, category text, is_premium boolean, is_active boolean,
  pl text, en text, smaczki_count int, open_draft_id uuid, content_hash text,
  en_review_needed boolean, is_favorite boolean, is_verified boolean,
  needs_review boolean, total_count bigint
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
         (select count(*) from base)
  from base b
  order by b.pl
  limit greatest(1, least(coalesce(p_limit, 50), 200)) offset greatest(0, coalesce(p_offset, 0));
end;
$$;

revoke all on function public.admin_list_questions(text, boolean, int, int, boolean, boolean, boolean, boolean) from public, anon;
grant execute on function public.admin_list_questions(text, boolean, int, int, boolean, boolean, boolean, boolean) to authenticated, service_role;
