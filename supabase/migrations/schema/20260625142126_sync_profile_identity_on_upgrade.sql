-- ============================================================================
-- Keep public.profiles' identity columns (email / full_name / avatar_url /
-- provider) in sync with auth.users.
--
-- BUG this fixes: handle_new_user() only runs on AFTER INSERT of auth.users, so
-- it correctly populates profiles for a *fresh* email/Google signup. But an
-- anonymous guest who LATER links an email or Google account does so via
-- updateUser() — an UPDATE of the same auth.users row, not an insert — so the
-- insert trigger never re-runs and profiles.email/provider/full_name stay NULL
-- forever. Result: upgraded accounts are unidentifiable in the profiles table
-- (only their streak is visible), even though auth.users has the real email.
--
-- Fix: an AFTER UPDATE trigger that mirrors the identity columns whenever they
-- change, plus a one-time backfill for the accounts already in this state.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Trigger function — mirror identity from the NEW auth.users row into the
--    matching profile. coalesce() so a later partial update never wipes a value
--    that auth no longer carries (e.g. email kept when only metadata changes).
-- ----------------------------------------------------------------------------
create or replace function public.handle_user_identity_update()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.profiles p
     set email      = coalesce(new.email, p.email),
         full_name  = coalesce(new.raw_user_meta_data->>'full_name',
                               new.raw_user_meta_data->>'name',
                               p.full_name),
         avatar_url = coalesce(new.raw_user_meta_data->>'avatar_url', p.avatar_url),
         provider   = coalesce(new.raw_app_meta_data->>'provider', p.provider)
   where p.id = new.id;
  return new;
end;
$$;

-- Only fire when an identity column actually changes — auth.users is UPDATEd on
-- every sign-in (last_sign_in_at), and we don't want a profile write each time.
drop trigger if exists on_auth_user_updated on auth.users;
create trigger on_auth_user_updated
  after update on auth.users
  for each row
  when (
    old.email is distinct from new.email
    or old.raw_user_meta_data is distinct from new.raw_user_meta_data
    or old.raw_app_meta_data  is distinct from new.raw_app_meta_data
  )
  execute function public.handle_user_identity_update();

-- ----------------------------------------------------------------------------
-- 2) One-time backfill — repair the rows that already lost their identity to the
--    old insert-only trigger. Keep any value the profile already has (so a
--    manually-set name survives); pull email straight from auth.
-- ----------------------------------------------------------------------------
update public.profiles p
   set email      = u.email,
       full_name  = coalesce(p.full_name,
                             u.raw_user_meta_data->>'full_name',
                             u.raw_user_meta_data->>'name'),
       avatar_url = coalesce(p.avatar_url, u.raw_user_meta_data->>'avatar_url'),
       provider   = coalesce(p.provider, u.raw_app_meta_data->>'provider')
  from auth.users u
 where u.id = p.id
   and u.email is not null
   and (p.email    is distinct from u.email
        or p.provider is distinct from u.raw_app_meta_data->>'provider');
