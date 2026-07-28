-- ============================================================================
-- Admin panel foundation
-- ----------------------------------------------------------------------------
-- 2026-07-24. Backend for the content admin panel (admin.debatly.app).
--
-- SECURITY MODEL
--   * The panel gets NO table grants and NEVER holds a service_role key.
--     Every mutation goes through a `security definer` admin_* RPC that first
--     checks public.is_admin(auth.uid()). Stealing a panel session therefore
--     buys exactly these operations and nothing else — there is no
--     "arbitrary write" path to the database at all.
--   * New tables (admin_users, question_drafts, admin_audit_log) have RLS on,
--     no policies and no client grants: only the definer functions reach them.
--   * Roles: 'editor' may create/submit drafts; 'approver' may also apply them.
--
-- CONFLICT SAFETY (the "no conflicts" requirement)
--   A draft stores base_hash = question_content_hash(question_id) captured when
--   editing started. Approving re-computes the hash; if the live row changed in
--   the meantime the apply is refused with CONFLICT instead of silently
--   overwriting a colleague's edit. Same md5-of-content trick used to verify the
--   bulk catalog batches.
--
-- INVARIANTS ENFORCED IN THE DB (not in the UI, so they cannot be bypassed)
--   * smaczki are always stored renumbered 1..N (position 1 = the free teaser)
--   * a question always has PL + EN rows and a question_vote_seeds row
--   * deleting frees the legacy daily_questions slots first (ON DELETE RESTRICT)
--
-- Idempotent: guarded DDL + CREATE OR REPLACE. Safe to re-run.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Admin roster
-- ----------------------------------------------------------------------------
create table if not exists public.admin_users (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  role       text not null default 'editor' check (role in ('editor','approver')),
  note       text,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id)
);
alter table public.admin_users enable row level security;
revoke all on public.admin_users from public, anon, authenticated;
grant all on public.admin_users to service_role;

create or replace function public.is_admin(p_uid uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select p_uid is not null and exists (select 1 from public.admin_users a where a.user_id = p_uid);
$$;

create or replace function public.admin_role(p_uid uuid default auth.uid())
returns text language sql stable security definer set search_path = public as $$
  select a.role from public.admin_users a where a.user_id = p_uid;
$$;

create or replace function public.admin_require(p_need_approver boolean default false)
returns void language plpgsql stable security definer set search_path = public as $$
declare r text;
begin
  r := public.admin_role();
  if r is null then
    raise exception 'FORBIDDEN: not an admin' using errcode = '42501';
  end if;
  if p_need_approver and r <> 'approver' then
    raise exception 'FORBIDDEN: approver role required' using errcode = '42501';
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 2) Content hash + snapshot (conflict detection & audit payloads)
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
      select jsonb_agg(jsonb_build_object('position', s.position, 'pl', tp.text, 'en', te.text)
                       order by s.position)
      from public.question_smaczki s
      left join public.question_smaczki_translations tp on tp.smaczek_id = s.id and tp.locale = 'pl'
      left join public.question_smaczki_translations te on te.smaczek_id = s.id and te.locale = 'en'
      where s.question_id = q.id and s.is_active), '[]'::jsonb)
  ) end
  from public.questions q where q.id = p_id;
$$;

create or replace function public.question_content_hash(p_id uuid)
returns text language sql stable security definer set search_path = public as $$
  select md5(coalesce(public.question_snapshot(p_id)::text, ''));
$$;

-- ----------------------------------------------------------------------------
-- 3) Drafts (proposal + approval) and audit log
-- ----------------------------------------------------------------------------
create table if not exists public.question_drafts (
  id          uuid primary key default gen_random_uuid(),
  question_id uuid references public.questions(id) on delete cascade,
  action      text not null check (action in ('create','update','delete')),
  payload     jsonb,
  base_hash   text,
  status      text not null default 'draft' check (status in ('draft','pending','approved','rejected')),
  title       text,
  created_by  uuid not null references auth.users(id),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  review_note text,
  applied_at  timestamptz,
  constraint draft_needs_question check (action = 'create' or question_id is not null)
);
create index if not exists idx_drafts_status on public.question_drafts (status, updated_at desc);
create index if not exists idx_drafts_open on public.question_drafts (question_id)
  where status in ('draft','pending');
alter table public.question_drafts enable row level security;
revoke all on public.question_drafts from public, anon, authenticated;
grant all on public.question_drafts to service_role;

create table if not exists public.admin_audit_log (
  id          bigserial primary key,
  question_id uuid,
  draft_id    uuid,
  action      text not null,
  actor       uuid,
  at          timestamptz not null default now(),
  before      jsonb,
  after       jsonb
);
create index if not exists idx_audit_question on public.admin_audit_log (question_id, at desc);
create index if not exists idx_audit_at on public.admin_audit_log (at desc);
alter table public.admin_audit_log enable row level security;
revoke all on public.admin_audit_log from public, anon, authenticated;
grant all on public.admin_audit_log to service_role;

-- ----------------------------------------------------------------------------
-- 4) Internal writer: replace a question's smaczki, renumbered 1..N
--    p_items = [{"pl":"...","en":"..."}, ...] in display order.
-- ----------------------------------------------------------------------------
create or replace function public._admin_write_smaczki(p_question_id uuid, p_items jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare it jsonb; pos int := 0; sid uuid;
begin
  delete from public.question_smaczki_translations
   where smaczek_id in (select id from public.question_smaczki where question_id = p_question_id);
  delete from public.question_smaczki where question_id = p_question_id;

  for it in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
    if coalesce(btrim(it->>'pl'), '') = '' then continue; end if;   -- skip blanks, keeps 1..N tight
    pos := pos + 1;
    insert into public.question_smaczki (question_id, position, is_active)
    values (p_question_id, pos, true) returning id into sid;
    insert into public.question_smaczki_translations (smaczek_id, locale, text)
    values (sid, 'pl', btrim(it->>'pl'));
    if coalesce(btrim(it->>'en'), '') <> '' then
      insert into public.question_smaczki_translations (smaczek_id, locale, text)
      values (sid, 'en', btrim(it->>'en'));
    end if;
  end loop;
end;
$$;

-- ----------------------------------------------------------------------------
-- 5) Read RPCs for the panel
-- ----------------------------------------------------------------------------
create or replace function public.admin_list_questions(
  p_search text default null,
  p_only_active boolean default true,
  p_limit int default 50,
  p_offset int default 0
) returns table (
  id uuid, category text, is_premium boolean, is_active boolean,
  pl text, en text, smaczki_count int, open_draft_id uuid, content_hash text, total_count bigint
) language plpgsql stable security definer set search_path = public as $$
begin
  perform public.admin_require();
  return query
  with base as (
    select q.id, q.category, q.is_premium, q.is_active,
           tp.question_text as pl, te.question_text as en
    from public.questions q
    left join public.question_translations tp on tp.question_id = q.id and tp.locale = 'pl'
    left join public.question_translations te on te.question_id = q.id and te.locale = 'en'
    where (not p_only_active or q.is_active)
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
         (select count(*) from base)
  from base b
  order by b.pl
  limit greatest(1, least(coalesce(p_limit, 50), 200)) offset greatest(0, coalesce(p_offset, 0));
end;
$$;

create or replace function public.admin_get_question(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.admin_require();
  return jsonb_build_object(
    'question', public.question_snapshot(p_id),
    'content_hash', public.question_content_hash(p_id),
    'open_draft', (select to_jsonb(d) from public.question_drafts d
                    where d.question_id = p_id and d.status in ('draft','pending')
                    order by d.updated_at desc limit 1)
  );
end;
$$;

create or replace function public.admin_list_drafts(p_status text default null)
returns setof public.question_drafts
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.admin_require();
  return query
  select d.* from public.question_drafts d
  where p_status is null or d.status = p_status
  order by d.updated_at desc
  limit 200;
end;
$$;

create or replace function public.admin_question_history(p_question_id uuid)
returns setof public.admin_audit_log
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.admin_require();
  return query
  select l.* from public.admin_audit_log l
  where l.question_id = p_question_id
  order by l.at desc
  limit 200;
end;
$$;

-- ----------------------------------------------------------------------------
-- 6) Draft lifecycle
-- ----------------------------------------------------------------------------
create or replace function public.admin_save_draft(
  p_action text,
  p_payload jsonb,
  p_question_id uuid default null,
  p_draft_id uuid default null,
  p_title text default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_owner uuid; v_status text;
begin
  perform public.admin_require();
  if p_action not in ('create','update','delete') then
    raise exception 'BAD_ACTION: %', p_action using errcode = '22023';
  end if;
  if p_action <> 'create' and p_question_id is null then
    raise exception 'BAD_REQUEST: question_id required for %', p_action using errcode = '22023';
  end if;

  if p_draft_id is null then
    insert into public.question_drafts (question_id, action, payload, base_hash, created_by, title)
    values (p_question_id, p_action, p_payload,
            case when p_question_id is null then null else public.question_content_hash(p_question_id) end,
            auth.uid(), p_title)
    returning id into v_id;
  else
    select created_by, status into v_owner, v_status
      from public.question_drafts where id = p_draft_id for update;
    if not found then raise exception 'NOT_FOUND: draft' using errcode = 'P0002'; end if;
    if v_status not in ('draft','rejected') then
      raise exception 'LOCKED: draft is % and cannot be edited', v_status using errcode = '55006';
    end if;
    if v_owner <> auth.uid() and public.admin_role() <> 'approver' then
      raise exception 'FORBIDDEN: not your draft' using errcode = '42501';
    end if;
    update public.question_drafts
       set payload = p_payload, action = p_action, title = coalesce(p_title, title),
           status = 'draft', updated_at = now()
     where id = p_draft_id
    returning id into v_id;
  end if;
  return v_id;
end;
$$;

create or replace function public.admin_submit_draft(p_draft_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.admin_require();
  update public.question_drafts
     set status = 'pending', updated_at = now()
   where id = p_draft_id and status in ('draft','rejected')
     and (created_by = auth.uid() or public.admin_role() = 'approver');
  if not found then
    raise exception 'NOT_FOUND: draft not editable by you' using errcode = 'P0002';
  end if;
end;
$$;

create or replace function public.admin_reject_draft(p_draft_id uuid, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.admin_require(true);
  update public.question_drafts
     set status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now(),
         review_note = p_note, updated_at = now()
   where id = p_draft_id and status = 'pending';
  if not found then raise exception 'NOT_FOUND: no pending draft' using errcode = 'P0002'; end if;
end;
$$;

-- Approve + apply, atomically, with conflict check.
create or replace function public.admin_approve_draft(p_draft_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  d public.question_drafts;
  v_before jsonb; v_after jsonb; v_hash text; v_qid uuid;
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
-- 7) Privileges: nothing to anon; authenticated may only call admin_* (which
--    themselves enforce admin_require()).
-- ----------------------------------------------------------------------------
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and (p.proname like 'admin\_%' or p.proname in
           ('is_admin','admin_role','question_snapshot','question_content_hash','_admin_write_smaczki'))
  loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated, service_role', f.sig);
  end loop;
end $$;

-- internals must not be callable by clients at all
revoke all on function public._admin_write_smaczki(uuid, jsonb) from authenticated;
revoke all on function public.admin_require(boolean) from authenticated;
