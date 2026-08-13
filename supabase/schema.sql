create extension if not exists pgcrypto;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  full_name text,
  avatar_url text,
  provider text,                         -- 'google' | 'email' ...
  is_premium boolean not null default false,
  premium_until timestamptz,
  locale text,                             -- 'pl' | 'en' — language of the auth emails
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_locale_supported check (locale is null or locale in ('pl', 'en'))
);

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

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- The only client-writable path into profiles: `profiles` has no UPDATE policy
-- (it also holds is_premium), so the language preference goes through a
-- definer function that touches exactly one column for exactly auth.uid().
create or replace function public.set_profile_locale(p_locale text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if p_locale is null or p_locale not in ('pl', 'en') then
    raise exception 'unsupported locale: %', p_locale using errcode = '22023';
  end if;

  update public.profiles
     set locale = p_locale, updated_at = now()
   where id = auth.uid();
end;
$$;

revoke execute on function public.set_profile_locale(text) from public, anon;
grant  execute on function public.set_profile_locale(text) to authenticated;
grant  select on public.profiles to service_role;   -- send-auth-email reads locale

create table public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  rc_app_user_id text,                   -- = auth.uid()
  entitlement text,                      -- np. 'premium'
  product_id text,
  store text,                            -- 'app_store' | 'play_store' | 'stripe'
  status text not null default 'inactive',
  is_active boolean not null default false,
  current_period_end timestamptz,
  will_renew boolean,
  updated_at timestamptz not null default now(),
  unique (user_id, entitlement)
);
create index subscriptions_user_id_idx on public.subscriptions (user_id);

-- append-only log zdarzeń (audyt + idempotencja webhooków)
create table public.billing_events (
  id uuid primary key default gen_random_uuid(),
  event_id text unique,                  -- id zdarzenia RC → blokuje podwójne przetworzenie
  user_id uuid references auth.users(id) on delete set null,
  type text,                             -- INITIAL_PURCHASE, RENEWAL, CANCELLATION...
  payload jsonb not null,
  received_at timestamptz not null default now()
);

create table public.ad_reward_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  ad_unit_id text,
  reward_item text,
  reward_amount int,
  transaction_id text unique,            -- AdMob transaction_id → idempotencja
  verified boolean not null default false,
  created_at timestamptz not null default now()
);
create index ad_reward_events_user_id_idx on public.ad_reward_events (user_id);

alter table public.profiles          enable row level security;
alter table public.subscriptions     enable row level security;
alter table public.billing_events    enable row level security;
alter table public.ad_reward_events  enable row level security;

-- profil: czyta tylko swój (zmiany premium robi serwer)
create policy "read own profile" on public.profiles
  for select to authenticated using (id = auth.uid());

-- subskrypcje: czyta tylko swoje
create policy "read own subscription" on public.subscriptions
  for select to authenticated using (user_id = auth.uid());

-- nagrody za reklamy: czyta tylko swoje
create policy "read own ad rewards" on public.ad_reward_events
  for select to authenticated using (user_id = auth.uid());

-- billing_events: BRAK polityk => klient nie ma dostępu wcale (tylko service_role)

-- Pytanie niezależne od języka (metadane)
create table if not exists public.questions (
  id uuid primary key default gen_random_uuid(),
  category text not null default 'general',
  is_premium boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- Tekst pytania w danym języku
create table if not exists public.question_translations (
  id uuid primary key default gen_random_uuid(),
  question_id uuid not null references public.questions(id) on delete cascade,
  locale text not null,
  question_text text not null,
  created_at timestamptz not null default now(),
  unique (question_id, locale)
);

create table public.question_unlocks (
  user_id uuid not null references auth.users(id) on delete cascade,
  question_id uuid not null references public.questions(id) on delete cascade,
  source text not null default 'ad',      -- 'ad' | 'promo'
  unlocked_at timestamptz not null default now(),
  primary key (user_id, question_id)
);
alter table public.question_unlocks enable row level security;

create policy "read own unlocks" on public.question_unlocks
  for select to authenticated using (user_id = auth.uid());
-- brak INSERT => pisze tylko service_role (Edge Function po weryfikacji reklamy)

-- 2) pomocnik: ważne premium
create or replace function public.is_premium(uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles p
    where p.id = uid and p.is_premium
      and (p.premium_until is null or p.premium_until > now())
  );
$$;

-- Jedno pytanie na dzień dla wszystkich (pokazywane w języku usera)
create table if not exists public.daily_questions (
  id uuid primary key default gen_random_uuid(),
  publish_date date not null unique,
  question_id uuid not null references public.questions(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (question_id)
);

-- RLS
alter table public.questions enable row level security;
alter table public.question_translations enable row level security;
alter table public.daily_questions enable row level security;

drop policy if exists "read active questions" on public.questions;
create policy "read active questions"
  on public.questions for select to anon, authenticated
  using (is_active = true);

drop policy if exists "read translations of active questions" on public.question_translations;
create policy "read question text (gated)"
  on public.question_translations for select to anon, authenticated
  using (
    exists (select 1 from public.questions q
            where q.id = question_translations.question_id and q.is_active)
    and (
      -- aktualne daily (pas ±1 dzień pokrywa wszystkie strefy czasowe)
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

drop policy if exists "read daily schedule" on public.daily_questions;
create policy "read daily schedule"
  on public.daily_questions for select to anon, authenticated
  using (
    publish_date <= (now() at time zone 'utc')::date + 1
    and exists (select 1 from public.questions q
                where q.id = daily_questions.question_id and q.is_active)
  );

-- Indeksy (unique już tworzą indeksy na (question_id, locale) i (publish_date))
create index if not exists question_translations_locale_idx
  on public.question_translations (locale);

-- Dane startowe: pytanie + tłumaczenia EN i PL
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