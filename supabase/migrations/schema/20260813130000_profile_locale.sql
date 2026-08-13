-- ============================================================================
-- profiles.locale — the language the auth emails (confirm signup, password
-- reset, email change) are written in.
--
-- WHY A COLUMN AND NOT JUST USER METADATA
--   GoTrue's Send Email Hook receives the auth user, so `raw_user_meta_data`
--   is already in the payload for free and the app writes `locale` there at
--   registration (signUp/updateUser `data`). That covers the signup and
--   email-change mails, which are sent in the same breath as the write.
--
--   It does NOT cover someone who registers in Polish, switches the app to
--   English months later, and then asks for a password reset. Keeping that
--   fresh via `updateUser(data:)` would work, but every such write emits a
--   `userUpdated` auth event — which SessionNotifier treats as an identity
--   change and answers with a full session reload + entitlement reconcile
--   (see isIdentityChangingAuthEvent in session_providers.dart). Changing the
--   UI language must not cost a premium re-check, so the live value lives in
--   a plain table the app updates through the RPC below.
--
--   The edge function reads profiles.locale first and falls back to the
--   metadata copy, so a brand-new signup is covered even if the trigger and
--   the hook race.
--
-- WHY AN RPC AND NOT AN RLS UPDATE POLICY
--   `profiles` deliberately has no UPDATE policy for `authenticated` — the
--   table also holds `is_premium` / `premium_until`, so a broad "update own
--   profile" policy would let any client grant itself premium. The SECURITY
--   DEFINER function below writes exactly one column for exactly auth.uid(),
--   which is the same shape as apply_store_entitlement / set_promotional_premium.
-- ============================================================================

alter table public.profiles add column if not exists locale text;

-- Backfill from the metadata copy for accounts created before this migration.
-- Unrecognised values are left null so the check constraint below can be added
-- without a validation error; the app rewrites them on next launch anyway.
update public.profiles p
set locale = u.raw_user_meta_data ->> 'locale'
from auth.users u
where u.id = p.id
  and p.locale is null
  and u.raw_user_meta_data ->> 'locale' in ('pl', 'en');

alter table public.profiles
  drop constraint if exists profiles_locale_supported;
alter table public.profiles
  add constraint profiles_locale_supported
  check (locale is null or locale in ('pl', 'en'));

-- ----------------------------------------------------------------------------
-- Seed the column at account creation from the `locale` the app passes in
-- signUp/updateUser `data`. Everything else in this trigger is unchanged from
-- schema.sql — it is restated in full because create-or-replace has no way to
-- patch a single line.
-- ----------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, full_name, avatar_url, provider, locale)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name'),
    new.raw_user_meta_data->>'avatar_url',
    new.raw_app_meta_data->>'provider',
    nullif(new.raw_user_meta_data->>'locale', '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- ----------------------------------------------------------------------------
-- The only way a client may write the column. Guests (anonymous sessions carry
-- the `authenticated` role too) can set it as well, so the value is already in
-- place by the time they upgrade to a real account and the first email goes out.
-- ----------------------------------------------------------------------------
create or replace function public.set_profile_locale(p_locale text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if p_locale is null or p_locale not in ('pl', 'en') then
    raise exception 'unsupported locale: %', p_locale using errcode = '22023';
  end if;

  update public.profiles
     set locale = p_locale,
         updated_at = now()
   where id = auth.uid();
end;
$$;

revoke execute on function public.set_profile_locale(text) from public, anon;
grant  execute on function public.set_profile_locale(text) to authenticated;

-- The send-auth-email edge function reads profiles.locale with the service key.
-- service_role is server-only (its key never ships to the client), so this does
-- not widen client access; anon/authenticated keep the "read own profile" RLS
-- policy as their only way in.
grant select on public.profiles to service_role;
