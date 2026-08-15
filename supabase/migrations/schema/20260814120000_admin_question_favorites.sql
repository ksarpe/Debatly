-- Admin panel: per-admin "ulubione" stars on questions.
--
-- * New table admin_question_favorites — RLS on, no client grants; all access
--   goes through the security-definer admin_* RPCs, same as the rest of the
--   admin panel (20260724130000_admin_panel_foundation.sql).
-- * admin_toggle_favorite(question_id) flips the star for the calling admin
--   and returns the new state.
-- * admin_list_questions gains an is_favorite column + p_only_favorites filter.
--   List order stays by PL text — the star does not reorder the list.

-- ----------------------------------------------------------------------------
-- 1) Table
-- ----------------------------------------------------------------------------
create table if not exists public.admin_question_favorites (
  user_id     uuid not null references auth.users (id) on delete cascade,
  question_id uuid not null references public.questions (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (user_id, question_id)
);

alter table public.admin_question_favorites enable row level security;
revoke all on public.admin_question_favorites from public, anon, authenticated;
grant all on public.admin_question_favorites to service_role;

-- ----------------------------------------------------------------------------
-- 2) Toggle RPC
-- ----------------------------------------------------------------------------
create or replace function public.admin_toggle_favorite(p_question_id uuid)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  perform public.admin_require();

  delete from public.admin_question_favorites
   where user_id = auth.uid() and question_id = p_question_id;
  if found then
    return false;
  end if;

  insert into public.admin_question_favorites (user_id, question_id)
  values (auth.uid(), p_question_id);
  return true;
end;
$$;

revoke all on function public.admin_toggle_favorite(uuid) from public, anon;
grant execute on function public.admin_toggle_favorite(uuid) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 3) admin_list_questions: is_favorite column + p_only_favorites filter
--    (replaces the 20260729130000_admin_en_review_flag.sql version)
-- ----------------------------------------------------------------------------
drop function if exists public.admin_list_questions(text, boolean, integer, integer, boolean);

create function public.admin_list_questions(
  p_search text default null,
  p_only_active boolean default true,
  p_limit int default 50,
  p_offset int default 0,
  p_only_en_review boolean default false,
  p_only_favorites boolean default false
) returns table (
  id uuid, category text, is_premium boolean, is_active boolean,
  pl text, en text, smaczki_count int, open_draft_id uuid, content_hash text,
  en_review_needed boolean, is_favorite boolean, total_count bigint
) language plpgsql stable security definer set search_path = public as $$
begin
  perform public.admin_require();
  return query
  with base as (
    select q.id, q.category, q.is_premium, q.is_active, q.en_review_needed,
           tp.question_text as pl, te.question_text as en,
           exists (select 1 from public.admin_question_favorites f
                    where f.question_id = q.id and f.user_id = auth.uid()) as is_favorite
    from public.questions q
    left join public.question_translations tp on tp.question_id = q.id and tp.locale = 'pl'
    left join public.question_translations te on te.question_id = q.id and te.locale = 'en'
    where (not p_only_active or q.is_active)
      and (not p_only_en_review or q.en_review_needed)
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
         (select count(*) from base)
  from base b
  order by b.pl
  limit greatest(1, least(coalesce(p_limit, 50), 200)) offset greatest(0, coalesce(p_offset, 0));
end;
$$;

revoke all on function public.admin_list_questions(text, boolean, int, int, boolean, boolean) from public, anon;
grant execute on function public.admin_list_questions(text, boolean, int, int, boolean, boolean) to authenticated, service_role;
