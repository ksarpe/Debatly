-- Freemium wall: the day-wall screen previews the NEXT question with the first
-- words readable and the rest blurred. Two words ("Czy osoba…") is too little
-- bait to tell what the question is about; four ("Czy osoba otyła powinna…")
-- reads as a real hook while still never leaking the full text.
--
-- Only the teaser slice changes ([1:2] → [1:4]). Pool, exclusions, security
-- posture and signature are exactly 20260804130000 / 20260713120000: active,
-- not voted, outside the caller's own ±1-day daily-assignment window, random.
-- Still a single SELECT — the function writes nothing (no question_seen row,
-- no spend); the wall may call it every day for free.

create or replace function public.peek_next_question(
  p_locale      text  default 'pl',
  p_date        date  default (now() at time zone 'utc')::date,
  p_exclude_ids uuid[] default '{}'
)
returns table (id uuid, teaser text)
language sql security definer set search_path to 'public'
as $$
  select
    q.id,
    array_to_string(
      (regexp_split_to_array(
         btrim(coalesce(tr.question_text, en.question_text)), '\s+'))[1:4],
      ' '
    ) as teaser
  from public.questions q
  left join public.question_translations tr
         on tr.question_id = q.id and tr.locale = p_locale
  left join public.question_translations en
         on en.question_id = q.id and en.locale = 'en'
  where q.is_active
    and not (q.id = any (p_exclude_ids))
    and not exists (
      select 1 from public.user_daily_questions ud
      where ud.user_id = auth.uid()
        and ud.question_id = q.id
        and ud.assigned_on between p_date - 1 and p_date + 1
    )
    and not exists (
      select 1 from public.question_votes v
      where v.user_id = auth.uid() and v.question_id = q.id
    )
  order by random()
  limit 1;
$$;

revoke all on function public.peek_next_question(text, date, uuid[]) from public;
grant execute on function public.peek_next_question(text, date, uuid[]) to authenticated;
