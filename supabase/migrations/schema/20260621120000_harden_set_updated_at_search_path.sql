-- Pin the search_path of the set_updated_at trigger function so it can't be
-- hijacked by a caller-controlled search_path (Supabase advisor
-- function_search_path_mutable). The function body only touches NEW, so this is
-- a pure hardening with no behavioural change.
alter function public.set_updated_at() set search_path = public, pg_temp;
