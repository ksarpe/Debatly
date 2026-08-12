-- ============================================================================
-- QuestionApp — initial schema
-- Auth/profiles · Billing (RevenueCat) · Ads (AdMob) · Questions (i18n) ·
-- Daily schedule · Monetization gate (Block A)
--
-- Everything runs in ONE transaction: any error rolls the whole thing back.
-- ============================================================================

begin;

create extension if not exists pgcrypto;

-- ----------------------------------------------------------------------------
-- Shared helper: keep updated_at fresh on UPDATE
-- ----------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ============================================================================
-- 1) PROFILES  (mirror of auth.users — Supabase manages auth.users itself)
-- ============================================================================
create table public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  email         text,
  full_name     text,
  avatar_url    text,
  provider      text,                       -- 'google' | 'email' ...
  is_premium    boolean not null default false,
  premium_until timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- Auto-create a profile row whenever a user signs up (incl. via Google)
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, full_name, avatar_url, provider)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name'),
    new.raw_user_meta_data->>'avatar_url',
    new.raw_app_meta_data->>'provider'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============================================================================
-- 2) BILLING  (RevenueCat is the source of truth; webhook writes here)
-- ============================================================================
create table public.subscriptions (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references auth.users(id) on delete cascade,
  rc_app_user_id     text,                   -- RevenueCat app_user_id == auth.uid()
  entitlement        text,                   -- e.g. 'premium'
  product_id         text,
  store              text,                   -- 'app_store' | 'play_store' | 'stripe'
  status             text not null default 'inactive',
  is_active          boolean not null default false,
  current_period_end timestamptz,
  will_renew         boolean,
  updated_at         timestamptz not null default now(),
  unique (user_id, entitlement)
);
create index subscriptions_user_id_idx on public.subscriptions (user_id);

create trigger subscriptions_set_updated_at
  before update on public.subscriptions
  for each row execute function public.set_updated_at();

-- Append-only audit log + webhook idempotency (unique event_id)
create table public.billing_events (
  id          uuid primary key default gen_random_uuid(),
  event_id    text unique,                   -- RevenueCat event id -> dedupe
  user_id     uuid references auth.users(id) on delete set null,
  type        text,                          -- INITIAL_PURCHASE, RENEWAL, ...
  payload     jsonb not null,
  received_at timestamptz not null default now()
);

-- ============================================================================
-- 3) ADS  (AdMob rewarded SSV; the admob-ssv function writes here)
-- ============================================================================
create table public.ad_reward_events (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid references auth.users(id) on delete set null,
  ad_unit_id     text,
  reward_item    text,
  reward_amount  int,
  transaction_id text unique,                -- AdMob transaction_id -> dedupe
  verified       boolean not null default false,
  created_at     timestamptz not null default now()
);
create index ad_reward_events_user_id_idx on public.ad_reward_events (user_id);

-- ============================================================================
-- 4) QUESTIONS (language-neutral metadata) + TRANSLATIONS (text per locale)
-- ============================================================================
create table public.questions (
  id         uuid primary key default gen_random_uuid(),
  category   text not null default 'general',
  is_premium boolean not null default false,
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.question_translations (
  id            uuid primary key default gen_random_uuid(),
  question_id   uuid not null references public.questions(id) on delete cascade,
  locale        text not null,
  question_text text not null,
  created_at    timestamptz not null default now(),
  unique (question_id, locale)
);
create index question_translations_locale_idx on public.question_translations (locale);

-- One question per day for everyone; unique(question_id) => never repeats (Strategy A)
create table public.daily_questions (
  id           uuid primary key default gen_random_uuid(),
  publish_date date not null unique,
  question_id  uuid not null references public.questions(id) on delete restrict,
  created_at   timestamptz not null default now(),
  unique (question_id)
);

-- ============================================================================
-- 5) MONETIZATION GATE (Block A)
-- ============================================================================
-- Per-user unlocks (rewarded ad / promo). Only the server (service_role) writes.
create table public.question_unlocks (
  user_id     uuid not null references auth.users(id) on delete cascade,
  question_id uuid not null references public.questions(id) on delete cascade,
  source      text not null default 'ad',    -- 'ad' | 'promo'
  unlocked_at timestamptz not null default now(),
  primary key (user_id, question_id)
);

-- Fast premium check used by RLS. SECURITY DEFINER so it can read profiles
-- without tripping profiles' own RLS (and without recursion).
create or replace function public.is_premium(uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles p
    where p.id = uid and p.is_premium
      and (p.premium_until is null or p.premium_until > now())
  );
$$;

-- ============================================================================
-- 6) ROW LEVEL SECURITY
-- ============================================================================
alter table public.profiles             enable row level security;
alter table public.subscriptions        enable row level security;
alter table public.billing_events       enable row level security;
alter table public.ad_reward_events     enable row level security;
alter table public.questions            enable row level security;
alter table public.question_translations enable row level security;
alter table public.daily_questions      enable row level security;
alter table public.question_unlocks     enable row level security;

-- Users read only their own rows. No write policies anywhere below =>
-- all writes go through the service_role (Edge Functions / dashboard).
create policy "read own profile" on public.profiles
  for select to authenticated using (id = auth.uid());

create policy "read own subscription" on public.subscriptions
  for select to authenticated using (user_id = auth.uid());

create policy "read own ad rewards" on public.ad_reward_events
  for select to authenticated using (user_id = auth.uid());

create policy "read own unlocks" on public.question_unlocks
  for select to authenticated using (user_id = auth.uid());

-- billing_events: intentionally NO policy => clients cannot read it at all.

-- Catalog metadata is public (lets the UI show the list with lock icons).
create policy "read active questions" on public.questions
  for select to anon, authenticated using (is_active = true);

-- Question TEXT is gated: the current daily is free; everything else needs
-- premium OR a per-question unlock.
--   * Free window is a ±1 day band around UTC today so every timezone gets
--     its local "today" for free; older dailies re-lock (premium archive).
create policy "read question text (gated)" on public.question_translations
  for select to anon, authenticated
  using (
    exists (
      select 1 from public.questions q
      where q.id = question_translations.question_id and q.is_active
    )
    and (
      exists (
        select 1 from public.daily_questions d
        where d.question_id = question_translations.question_id
          and d.publish_date between (now() at time zone 'utc')::date - 1
                                 and (now() at time zone 'utc')::date + 1
      )
      or public.is_premium(auth.uid())
      or exists (
        select 1 from public.question_unlocks u
        where u.user_id = auth.uid()
          and u.question_id = question_translations.question_id
      )
    )
  );

-- Daily schedule is readable, but clamped so a pre-filled calendar does not
-- leak future questions (+1 day covers timezones up to UTC+14).
create policy "read daily schedule" on public.daily_questions
  for select to anon, authenticated
  using (
    publish_date <= (now() at time zone 'utc')::date + 1
    and exists (
      select 1 from public.questions q
      where q.id = daily_questions.question_id and q.is_active
    )
  );

-- ============================================================================
-- 7) APP HELPER RPC  (optional — returns the flat shape Question.fromJson wants)
-- SECURITY INVOKER (default): RLS above still applies, so a client cannot use
-- it to read a locked/future question.
-- ============================================================================
create or replace function public.get_daily_question(
  p_locale text default 'pl',
  p_date   date default (now() at time zone 'utc')::date
)
returns table (
  id            uuid,
  category      text,
  is_premium    boolean,
  question_text text,
  publish_date  date
)
language sql stable set search_path = public as $$
  select q.id, q.category, q.is_premium,
         coalesce(tr.question_text, en.question_text) as question_text,
         d.publish_date
  from public.daily_questions d
  join public.questions q on q.id = d.question_id
  left join public.question_translations tr
         on tr.question_id = q.id and tr.locale = p_locale
  left join public.question_translations en
         on en.question_id = q.id and en.locale = 'en'
  where d.publish_date = p_date
  limit 1;
$$;

-- ============================================================================
-- 7b) PRIVILEGES
-- RLS controls WHICH ROWS a role may see; it does NOT grant access to the table
-- itself. Postgres needs an explicit GRANT *on top of* RLS, otherwise the role
-- gets "permission denied" (42501) before any policy is even evaluated.
-- ============================================================================
grant select on public.questions             to anon, authenticated;
grant select on public.question_translations to anon, authenticated;
grant select on public.daily_questions       to anon, authenticated;

grant select on public.profiles          to authenticated;
grant select on public.subscriptions     to authenticated;
grant select on public.ad_reward_events  to authenticated;
grant select on public.question_unlocks  to anon, authenticated;

grant execute on function public.get_daily_question(text, date) to anon, authenticated;
grant execute on function public.is_premium(uuid)               to anon, authenticated;

-- billing_events: intentionally NOT granted (service_role bypasses RLS/grants).

-- ============================================================================
-- 8) SEED DATA + PRE-FILL CALENDAR
--    (runs as the migration owner, so RLS does not block these inserts)
-- ============================================================================
with seed(category, en, pl) as (
  values
    ('Connection',
     'What is a belief you held strongly five years ago that you no longer hold?',
     'W co mocno wierzyłeś pięć lat temu, a w co już nie wierzysz?'),
    ('Dreams',
     'If money were no object, how would you spend the next ten years?',
     'Gdyby pieniądze nie grały roli, jak spędziłbyś najbliższe dziesięć lat?'),
    ('Reflection',
     'When did you last change your mind about something important?',
     'Kiedy ostatnio zmieniłeś zdanie w ważnej sprawie?')
),
ins as (
  insert into public.questions (category)
  select category from seed
  returning id, category
)
insert into public.question_translations (question_id, locale, question_text)
select ins.id, t.locale, t.text
from ins
join seed using (category)
cross join lateral (values ('en', seed.en), ('pl', seed.pl)) as t(locale, text);

-- Assign a random, never-repeated question to each upcoming date
-- (fills as many days as there are active questions).
insert into public.daily_questions (publish_date, question_id)
select dates.d::date, q.id
from (
  select d, row_number() over (order by d) rn
  from generate_series(current_date, current_date + 364, '1 day'::interval) d
) dates
join (
  select id, row_number() over (order by random()) rn
  from public.questions where is_active
) q on q.rn = dates.rn
on conflict (publish_date) do nothing;

commit;
