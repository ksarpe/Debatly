-- ============================================================================
-- EN-review flag ("angielski do weryfikacji")
-- ----------------------------------------------------------------------------
-- 2026-07-29. Editors may polish the Polish text without touching the English
-- translation; the owner verifies EN himself. This adds a per-question flag:
--
--   * questions.en_review_needed — kept OUTSIDE question_snapshot() /
--     question_content_hash() on purpose: toggling the flag never invalidates
--     open drafts (no false CONFLICTs).
--   * admin_approve_draft maintains the flag automatically on apply:
--       - payload.en_review present -> explicit value wins (panel checkbox)
--       - create                    -> flag when EN is blank
--       - update                    -> EN changed => clear; PL changed with EN
--                                      untouched => set; neither => keep as-is
--   * admin_set_en_review(q, flag) — direct toggle without a draft; any admin
--     may flag, clearing requires the approver role (clearing IS the
--     verification). Both directions are audit-logged (en_review/en_verified).
--   * admin_list_questions gains an en_review_needed column + p_only_en_review
--     filter (return-type change => drop + recreate + re-grant).
--
-- Idempotent: guarded DDL + create or replace. Safe to re-run.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Flag column
-- ----------------------------------------------------------------------------
alter table public.questions
  add column if not exists en_review_needed boolean not null default false;

create index if not exists idx_questions_en_review
  on public.questions (en_review_needed) where en_review_needed;

-- ----------------------------------------------------------------------------
-- 2) Direct toggle (no draft needed)
-- ----------------------------------------------------------------------------
create or replace function public.admin_set_en_review(p_question_id uuid, p_flag boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_flag is null then
    raise exception 'BAD_REQUEST: p_flag required' using errcode = '22023';
  end if;
  -- flagging: any admin; clearing: approver only (clearing = "I verified it")
  perform public.admin_require(not p_flag);

  update public.questions set en_review_needed = p_flag where id = p_question_id;
  if not found then raise exception 'NOT_FOUND: question' using errcode = 'P0002'; end if;

  insert into public.admin_audit_log (question_id, action, actor)
  values (p_question_id, case when p_flag then 'en_review' else 'en_verified' end, auth.uid());
end;
$$;

-- ----------------------------------------------------------------------------
-- 3) admin_get_question: expose the flag (outside the snapshot => hash-stable)
-- ----------------------------------------------------------------------------
create or replace function public.admin_get_question(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.admin_require();
  return jsonb_build_object(
    'question', public.question_snapshot(p_id),
    'content_hash', public.question_content_hash(p_id),
    'en_review_needed', (select q.en_review_needed from public.questions q where q.id = p_id),
    'open_draft', (select to_jsonb(d) from public.question_drafts d
                    where d.question_id = p_id and d.status in ('draft','pending')
                    order by d.updated_at desc limit 1)
  );
end;
$$;

-- ----------------------------------------------------------------------------
-- 4) admin_list_questions: flag column + p_only_en_review filter
-- ----------------------------------------------------------------------------
drop function if exists public.admin_list_questions(text, boolean, integer, integer);

create function public.admin_list_questions(
  p_search text default null,
  p_only_active boolean default true,
  p_limit int default 50,
  p_offset int default 0,
  p_only_en_review boolean default false
) returns table (
  id uuid, category text, is_premium boolean, is_active boolean,
  pl text, en text, smaczki_count int, open_draft_id uuid, content_hash text,
  en_review_needed boolean, total_count bigint
) language plpgsql stable security definer set search_path = public as $$
begin
  perform public.admin_require();
  return query
  with base as (
    select q.id, q.category, q.is_premium, q.is_active, q.en_review_needed,
           tp.question_text as pl, te.question_text as en
    from public.questions q
    left join public.question_translations tp on tp.question_id = q.id and tp.locale = 'pl'
    left join public.question_translations te on te.question_id = q.id and te.locale = 'en'
    where (not p_only_active or q.is_active)
      and (not p_only_en_review or q.en_review_needed)
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
         (select count(*) from base)
  from base b
  order by b.pl
  limit greatest(1, least(coalesce(p_limit, 50), 200)) offset greatest(0, coalesce(p_offset, 0));
end;
$$;

-- ----------------------------------------------------------------------------
-- 5) admin_approve_draft: maintain the flag when a draft is applied
-- ----------------------------------------------------------------------------
create or replace function public.admin_approve_draft(p_draft_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  d public.question_drafts;
  v_before jsonb; v_after jsonb; v_hash text; v_qid uuid;
  v_flag boolean; v_pl_chg boolean; v_en_chg boolean;
  v_spl_b text; v_sen_b text; v_spl_a text; v_sen_a text;
begin
  perform public.admin_require(true);

  select * into d from public.question_drafts where id = p_draft_id for update;
  if not found then raise exception 'NOT_FOUND: draft' using errcode = 'P0002'; end if;
  if d.status <> 'pending' then
    raise exception 'BAD_STATE: draft is %, expected pending', d.status using errcode = '55006';
  end if;

  -- conflict guard: the live row must be exactly what the editor started from
  if d.action <> 'create' then
    if not exists (select 1 from public.questions where id = d.question_id) then
      raise exception 'CONFLICT: question no longer exists' using errcode = '40001';
    end if;
    v_hash := public.question_content_hash(d.question_id);
    if d.base_hash is distinct from v_hash then
      raise exception 'CONFLICT: question changed since this draft was started'
        using errcode = '40001';
    end if;
    v_before := public.question_snapshot(d.question_id);
  end if;

  if d.action = 'create' then
    insert into public.questions (category, is_premium, is_active)
    values (coalesce(d.payload->>'category', 'Reflection'),
            coalesce((d.payload->>'is_premium')::boolean, false),
            coalesce((d.payload->>'is_active')::boolean, true))
    returning id into v_qid;

    insert into public.question_translations (question_id, locale, question_text)
    values (v_qid, 'pl', btrim(d.payload->>'pl')),
           (v_qid, 'en', btrim(d.payload->>'en'));

    perform public._admin_write_smaczki(v_qid, d.payload->'smaczki');
    insert into public.question_vote_seeds (question_id, seed_yes_pct, seed_total)
    values (v_qid, 50, 0) on conflict (question_id) do nothing;

  elsif d.action = 'update' then
    v_qid := d.question_id;
    update public.questions
       set category   = coalesce(d.payload->>'category', category),
           is_premium = coalesce((d.payload->>'is_premium')::boolean, is_premium),
           is_active  = coalesce((d.payload->>'is_active')::boolean, is_active)
     where id = v_qid;

    if coalesce(btrim(d.payload->>'pl'), '') <> '' then
      update public.question_translations set question_text = btrim(d.payload->>'pl')
       where question_id = v_qid and locale = 'pl';
    end if;
    if coalesce(btrim(d.payload->>'en'), '') <> '' then
      update public.question_translations set question_text = btrim(d.payload->>'en')
       where question_id = v_qid and locale = 'en';
    end if;
    if d.payload ? 'smaczki' then
      perform public._admin_write_smaczki(v_qid, d.payload->'smaczki');
    end if;

  else -- delete
    v_qid := d.question_id;
    -- daily_questions is ON DELETE RESTRICT: free this question's slots first.
    -- Only its own slots are removed; the legacy calendar may keep a gap, which
    -- is harmless (the served daily is per-user, see user_daily_questions).
    delete from public.daily_questions where question_id = v_qid;
    delete from public.questions where id = v_qid;
  end if;

  v_after := case when d.action = 'delete' then null else public.question_snapshot(v_qid) end;

  -- EN-review flag: explicit payload value wins; otherwise auto-detect a
  -- PL-only edit (question text or smaczki) with the EN side untouched.
  if d.action <> 'delete' then
    if d.payload ? 'en_review' then
      v_flag := coalesce((d.payload->>'en_review')::boolean, false);
    elsif d.action = 'create' then
      v_flag := coalesce(btrim(d.payload->>'en'), '') = '';
    else
      select string_agg(coalesce(e.x->>'pl',''), chr(1) order by e.ord),
             string_agg(coalesce(e.x->>'en',''), chr(1) order by e.ord)
        into v_spl_b, v_sen_b
        from jsonb_array_elements(coalesce(v_before->'smaczki', '[]'::jsonb))
             with ordinality e(x, ord);
      select string_agg(coalesce(e.x->>'pl',''), chr(1) order by e.ord),
             string_agg(coalesce(e.x->>'en',''), chr(1) order by e.ord)
        into v_spl_a, v_sen_a
        from jsonb_array_elements(coalesce(v_after->'smaczki', '[]'::jsonb))
             with ordinality e(x, ord);
      v_pl_chg := ((v_before->>'pl') is distinct from (v_after->>'pl'))
                  or (v_spl_b is distinct from v_spl_a);
      v_en_chg := ((v_before->>'en') is distinct from (v_after->>'en'))
                  or (v_sen_b is distinct from v_sen_a);
      if v_en_chg then v_flag := false;          -- EN was touched => verified here
      elsif v_pl_chg then v_flag := true;        -- PL-only edit => needs EN review
      else select q.en_review_needed into v_flag -- metadata-only edit => keep
             from public.questions q where q.id = v_qid;
      end if;
    end if;
    update public.questions set en_review_needed = coalesce(v_flag, false)
     where id = v_qid;
  end if;

  update public.question_drafts
     set status = 'approved', reviewed_by = auth.uid(), reviewed_at = now(),
         applied_at = now(), updated_at = now(),
         question_id = coalesce(question_id, v_qid)
   where id = p_draft_id;

  insert into public.admin_audit_log (question_id, draft_id, action, actor, before, after)
  values (v_qid, p_draft_id, d.action, auth.uid(), v_before, v_after);

  return jsonb_build_object('question_id', v_qid, 'action', d.action);
end;
$$;

-- ----------------------------------------------------------------------------
-- 6) Privileges: same posture as the foundation — nothing to anon/public,
--    authenticated may only call (the functions enforce admin_require()).
-- ----------------------------------------------------------------------------
revoke all on function public.admin_set_en_review(uuid, boolean) from public, anon;
grant execute on function public.admin_set_en_review(uuid, boolean) to authenticated, service_role;

revoke all on function public.admin_list_questions(text, boolean, int, int, boolean) from public, anon;
grant execute on function public.admin_list_questions(text, boolean, int, int, boolean) to authenticated, service_role;
