-- Conformity stats — powers the top-bar "oś zgodności" panel: how often the
-- caller votes with the community majority vs the minority.
--
-- One aggregate row over the caller's own `question_votes`, joined to the
-- maintained per-question counters (20260815120000_question_vote_counts) plus
-- the seed baseline (20260713160000_vote_seed_baseline). The majority is
-- decided on the SAME seed-inclusive totals every read RPC returns as the
-- community split, so the axis can never disagree with the result bars the
-- user actually saw. A vote on a tied split has no majority to agree with:
-- it counts into total_votes but into neither side.
--
-- Deliberately NOT premium-gated: free users vote the daily too, and the axis
-- is a retention row like the streak — it exposes only aggregates of the
-- caller's own votes, never gated question content.

create or replace function public.get_conformity_stats()
returns table (
  total_votes    int,
  majority_votes int,
  minority_votes int
)
language sql stable security definer set search_path = public as $$
  select
    count(*)::int,
    count(*) filter (where t.yes_total <> t.no_total
                       and ((t.choice = 1 and t.yes_total > t.no_total)
                         or (t.choice = 2 and t.no_total > t.yes_total)))::int,
    count(*) filter (where t.yes_total <> t.no_total
                       and ((t.choice = 1 and t.yes_total < t.no_total)
                         or (t.choice = 2 and t.no_total < t.yes_total)))::int
  from (
    select
      v.choice,
      coalesce(c.yes_count, 0) + coalesce(sd.seed_yes, 0) as yes_total,
      coalesce(c.no_count,  0) + coalesce(sd.seed_no,  0) as no_total
    from public.question_votes v
    left join public.question_vote_counts c  on c.question_id  = v.question_id
    left join public.question_vote_seeds  sd on sd.question_id = v.question_id
    where v.user_id = auth.uid()
  ) t;
$$;

comment on function public.get_conformity_stats() is
  'One aggregate row (total / with-majority / with-minority) over the caller''s '
  'own votes, majority decided on the seed-inclusive totals. Ties count into '
  'total only. Backs the client''s conformity-axis panel; not premium-gated.';

revoke all on function public.get_conformity_stats() from public, anon;
grant execute on function public.get_conformity_stats() to authenticated, service_role;
