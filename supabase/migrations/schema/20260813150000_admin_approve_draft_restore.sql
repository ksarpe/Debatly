-- ============================================================================
-- Restore admin_approve_draft + fix the delete path
-- ============================================================================
-- Two separate problems, both invisible from the panel:
--
-- 1) On prod the function had been replaced, by hand in the SQL editor, with a
--    no-op stub that returned {"disabled": true}. It never went through a
--    migration, so nothing in the repo recorded it. Every "Zatwierdź" click
--    succeeded, published nothing, and left the draft sitting in "Oczekujące".
--    The stub was an emergency killswitch after a request flood; the flood was
--    a client-side retry storm (98% of all transactions on this project are
--    rollbacks that never executed any SQL), not something this function can
--    cause — its body is a single transaction with no loop.
--
-- 2) The delete branch quietly ate its own draft. question_drafts.question_id
--    is ON DELETE CASCADE, so `delete from questions` removed the draft row
--    mid-transaction, and the trailing `set status = 'approved'` then updated
--    zero rows. The question went away, the approval was never recorded.
--    Fixed by settling the draft and the audit row *before* the delete, and
--    detaching it from the question so the cascade cannot reach it.
--
-- The check constraint has to allow that detached state, hence the relaxation:
-- an applied draft (applied_at is not null) may have a null question_id.
-- ----------------------------------------------------------------------------

alter table public.question_drafts drop constraint if exists draft_needs_question;
alter table public.question_drafts add constraint draft_needs_question
  check (action = 'create' or question_id is not null or applied_at is not null);

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

  -- Delete first, and separately: settle the draft and write the audit row
  -- BEFORE the question disappears, or the FK cascade takes the draft with it.
  if d.action = 'delete' then
    v_qid := d.question_id;

    update public.question_drafts
       set status = 'approved', reviewed_by = auth.uid(), reviewed_at = now(),
           applied_at = now(), updated_at = now(), question_id = null
     where id = p_draft_id;

    insert into public.admin_audit_log (question_id, draft_id, action, actor, before, after)
    values (v_qid, p_draft_id, 'delete', auth.uid(), v_before, null);

    -- daily_questions is ON DELETE RESTRICT: free this question's slots first.
    -- Only its own slots are removed; the legacy calendar may keep a gap, which
    -- is harmless (the served daily is per-user, see user_daily_questions).
    delete from public.daily_questions where question_id = v_qid;
    delete from public.questions where id = v_qid;

    return jsonb_build_object('question_id', v_qid, 'action', 'delete');
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

  else -- update
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
  end if;

  v_after := public.question_snapshot(v_qid);

  -- EN-review flag: explicit payload value wins; otherwise auto-detect a
  -- PL-only edit (question text or smaczki) with the EN side untouched.
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

grant execute on function public.admin_approve_draft(uuid) to authenticated;
