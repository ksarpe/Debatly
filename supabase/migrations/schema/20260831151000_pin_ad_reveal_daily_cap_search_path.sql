-- ============================================================================
-- ad_reveal_daily_cap(): pin search_path.
-- ----------------------------------------------------------------------------
-- 2026-08-31. The last function in the schema with a role-mutable search_path
-- (Supabase advisor 0011). Not SECURITY DEFINER, so the exposure is
-- theoretical — but every other function pins it, and the advisor noise hides
-- real findings. No body change.
-- ============================================================================

alter function public.ad_reveal_daily_cap() set search_path = public;
