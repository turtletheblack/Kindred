-- Kindred step 3: check-ins and connection health.
--
-- Everything here works by asking people, never by reading or scoring their
-- messages. Nothing is posted into a chat. Your answers stay private, except
-- that when you and your match give the same check-in answer, you both find out.
--
-- * Chat limits: each person chooses how many chats they can handle.
-- * The check-in: after 15 messages each, "Did you enjoy this conversation?"
--   Both yes strengthens the match, both no offers a mutual exit, and a mixed
--   answer changes nothing and is never shown.
-- * Connection health: every month or so, "How's this connection feeling?"
-- * Gentle prompts: a 72-hour pulse for quiet starts, a 14-day bridge after a
--   long silence, and a suggestion to deepen a strong match. Each is a card in
--   the app that can be dismissed or turned off. None of them ends a match.
-- * Conversation questions in three levels that unlock as a match grows.
-- * The "someone who matters" survey at 30, 90 and 365 days.

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------

-- The old one-match limit becomes the highest limit anyone can choose.
alter table public.matching_settings rename column max_active_matches to max_chat_limit;
alter table public.matching_settings alter column max_chat_limit set default 10;
update public.matching_settings set max_chat_limit = 10;

alter table public.matching_settings
  -- Chats someone can have at once until they choose their own number.
  add column default_chat_limit int not null default 3,
  -- A match where the conversation hasn't reached the check-in point and has
  -- been quiet this long gets the pulse.
  add column pulse_hours int not null default 72,
  -- A match that reached the check-in point and has been quiet this long gets the bridge.
  add column bridge_days int not null default 14,
  -- Connection health is first asked when a match is this old, then repeated.
  add column health_first_days int not null default 14,
  add column health_every_days int not null default 30,
  -- A match where both said yes gets the "try something new together" card at this age.
  add column deepen_after_days int not null default 21,
  -- Days after joining when the "someone who matters" question is asked.
  add column survey_days int[] not null default '{30,90,365}',
  add check (default_chat_limit between 1 and max_chat_limit);

-- ---------------------------------------------------------------------------
-- Profile additions
-- ---------------------------------------------------------------------------

alter table public.profiles
  -- Null means the default from matching_settings.
  add column chat_limit smallint check (chat_limit between 1 and 20),
  -- The pulse, bridge and deepen cards. Check-ins and questions are always
  -- optional, so they don't depend on this.
  add column gentle_prompts boolean not null default true,
  -- "Ask me later" on the someone-who-matters question.
  add column survey_snoozed_until timestamptz;

grant update (chat_limit, gentle_prompts) on public.profiles to authenticated;

create function public.chat_limit_of(p_user uuid) returns int
language sql stable security definer set search_path = '' as $$
  select least(s.max_chat_limit, coalesce(p.chat_limit, s.default_chat_limit))
  from public.profiles p, public.matching_settings s
  where p.id = p_user;
$$;

-- ---------------------------------------------------------------------------
-- Matching with per-person chat limits
-- ---------------------------------------------------------------------------

create or replace function public.run_matching() returns int
language plpgsql security definer set search_path = '' as $$
declare
  s public.matching_settings;
  paired uuid[] := '{}';
  made int := 0;
  seeker record;
  partner uuid;
  pr record;
begin
  -- One run at a time.
  perform pg_advisory_xact_lock(hashtext('kindred_run_matching'));
  select * into s from public.matching_settings;

  create temp table if not exists pg_temp.queue_pairs (
    a uuid, b uuid, score numeric, rank numeric, waited timestamptz
  ) on commit drop;
  truncate pg_temp.queue_pairs;

  insert into pg_temp.queue_pairs
  with q as (
    select p.id, p.queued_at, public.tz_offset_hours(p.timezone) as tz,
           t.communication c, t.friendship f,
           t.communication_scores cs, t.friendship_scores fs
    from public.profiles p
    join public.current_test_results t on t.user_id = p.id
    where p.matching_status = 'queued'
      and p.adult_confirmed_at is not null
      and p.suspended_at is null
      and p.trust_level >= 1
      and public.active_match_count(p.id) < public.chat_limit_of(p.id)
  ),
  pairs as (
    select a.id as a, b.id as b,
           public.score_pair(a.c, a.f, a.cs, a.fs, b.c, b.f, b.cs, b.fs) as score,
           least(a.queued_at, b.queued_at) as waited,
           abs(a.tz - b.tz) as tz_gap
    from q a join q b on a.id < b.id
    where not exists (select 1 from public.matches m where m.user_a = a.id and m.user_b = b.id)
      and not exists (
        select 1 from public.blocks bl
        where (bl.blocker_id = a.id and bl.blocked_id = b.id)
           or (bl.blocker_id = b.id and bl.blocked_id = a.id))
  )
  select a, b, score,
         score
           + least(s.wait_boost_max,
                   s.wait_boost_per_day * extract(epoch from now() - waited) / 86400)
           - least(s.timezone_penalty_max, s.timezone_penalty_per_hour * coalesce(tz_gap, 0)),
         waited
  from pairs;

  for seeker in
    select id from public.profiles
    where matching_status = 'queued' and queue_exploratory
    order by queued_at
  loop
    continue when seeker.id = any(paired);
    select case when qp.a = seeker.id then qp.b else qp.a end into partner
    from pg_temp.queue_pairs qp
    where seeker.id in (qp.a, qp.b) and not (qp.a = any(paired)) and not (qp.b = any(paired))
    order by random()
    limit 1;
    if partner is not null then
      perform public.create_match(seeker.id, partner, true);
      paired := paired || seeker.id || partner;
      made := made + 1;
    end if;
  end loop;

  for pr in
    select a, b from pg_temp.queue_pairs
    where rank >= s.min_score
    order by rank desc, waited
  loop
    continue when pr.a = any(paired) or pr.b = any(paired);
    perform public.create_match(pr.a, pr.b, false);
    paired := paired || pr.a || pr.b;
    made := made + 1;
  end loop;

  return made;
end;
$$;

create or replace function public.join_queue() returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  p public.profiles;
  s public.matching_settings;
  chat_limit int := public.chat_limit_of(auth.uid());
begin
  select * into p from public.profiles where id = me;
  select * into s from public.matching_settings;
  if p.id is null then
    raise exception 'not signed in';
  end if;
  if p.adult_confirmed_at is null then
    raise exception 'Please confirm you''re 18 or over first';
  end if;
  if not exists (select 1 from public.test_results where user_id = me) then
    raise exception 'Please take the communication test first';
  end if;
  if p.suspended_at is not null then
    raise exception 'Matching is paused on your account while we review a report';
  end if;
  if public.active_match_count(me) >= chat_limit then
    raise exception 'You''re at your limit of % chats. You can change it in your profile', chat_limit;
  end if;
  if p.matching_status <> 'queued' then
    update public.profiles
      set matching_status = 'queued', queued_at = now(),
          queue_exploratory = random() < s.exploratory_share
      where id = me;
  end if;
  return public.find_match();
end;
$$;

-- ---------------------------------------------------------------------------
-- The check-in
-- ---------------------------------------------------------------------------

-- Answers now go through answer_checkin(), which checks the conversation has
-- reached the check-in point.
drop policy "own checkins insert" on public.checkins;
revoke insert on public.checkins from authenticated;
alter table public.checkins add check (kind = 'enjoyed');

alter table public.matches add column ended_mutually boolean not null default false;

-- 'both_yes', 'both_no' or 'mixed' once both have answered. For admins and
-- tuning only: the app never sees 'mixed'.
create function public.checkin_result(p_match uuid) returns text
language sql stable security definer set search_path = '' as $$
  select case
    when count(*) < 2 then null
    when bool_and(enjoyed) then 'both_yes'
    when not bool_or(enjoyed) then 'both_no'
    else 'mixed'
  end
  from public.checkins
  where match_id = p_match and kind = 'enjoyed';
$$;

-- What you're allowed to know: 'both_yes' or 'both_no' when you gave the same
-- answer, 'answered' otherwise (whether or not your match has answered yet,
-- so a different answer is never revealed), or null if you haven't answered.
create function public.my_checkin_outcome(p_match uuid) returns text
language sql stable security definer set search_path = '' as $$
  select case
    when not exists (select 1 from public.checkins
                     where match_id = p_match and user_id = auth.uid() and kind = 'enjoyed') then null
    when public.checkin_result(p_match) in ('both_yes', 'both_no') then public.checkin_result(p_match)
    else 'answered'
  end
  where public.is_match_member(p_match);
$$;

create function public.answer_checkin(p_match uuid, p_enjoyed boolean) returns text
language plpgsql security definer set search_path = '' as $$
declare
  m public.matches;
  threshold int := (select feedback_message_threshold from public.matching_settings);
begin
  select * into m from public.matches where id = p_match and auth.uid() in (user_a, user_b);
  if m.id is null then
    raise exception 'match not found';
  end if;
  if m.messages_a < threshold or m.messages_b < threshold then
    raise exception 'The check-in opens after you''ve each sent % messages', threshold;
  end if;
  insert into public.checkins (match_id, user_id, kind, enjoyed)
    values (p_match, auth.uid(), 'enjoyed', p_enjoyed)
    on conflict (match_id, user_id, kind) do nothing;
  if not found then
    raise exception 'You''ve already answered this check-in';
  end if;
  return public.my_checkin_outcome(p_match);
end;
$$;

-- When you both said the match isn't clicking, either of you can end it for
-- both, with no blame on anyone.
create function public.mutual_exit(p_match uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if public.my_checkin_outcome(p_match) is distinct from 'both_no' then
    raise exception 'A mutual exit is only offered when you both said no at the check-in';
  end if;
  update public.matches
    set status = 'ended', ended_at = now(), ended_by = auth.uid(), end_reason = null,
        ended_mutually = true
    where id = p_match and status <> 'ended';
end;
$$;

-- ---------------------------------------------------------------------------
-- Connection health: asked, never inferred
-- ---------------------------------------------------------------------------

create table public.health_checks (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  feeling text not null check (feeling in ('growing', 'steady', 'fading', 'unsure')),
  balance text check (balance in ('balanced', 'mostly', 'one_sided', 'unsure')),
  created_at timestamptz not null default now()
);

create index health_checks_match_user on public.health_checks (match_id, user_id, created_at desc);

alter table public.health_checks enable row level security;
revoke all on public.health_checks from anon;
create policy "own health checks read" on public.health_checks
  for select to authenticated using (user_id = auth.uid());
revoke insert, update, delete on public.health_checks from authenticated;

create function public.answer_health_check(p_match uuid, p_feeling text, p_balance text default null)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_match_member(p_match) then
    raise exception 'match not found';
  end if;
  insert into public.health_checks (match_id, user_id, feeling, balance)
    values (p_match, auth.uid(), p_feeling, p_balance);
end;
$$;

-- ---------------------------------------------------------------------------
-- Prompt cards: which one to show, and "not now"
-- ---------------------------------------------------------------------------

create table public.prompt_snoozes (
  match_id uuid not null references public.matches (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  kind text not null check (kind in
    ('checkin', 'health', 'pulse', 'bridge', 'deepen', 'mutual', 'strengthened')),
  until timestamptz not null,
  primary key (match_id, user_id, kind)
);

alter table public.prompt_snoozes enable row level security;
revoke all on public.prompt_snoozes from anon;
create policy "own snoozes read" on public.prompt_snoozes
  for select to authenticated using (user_id = auth.uid());
revoke insert, update, delete on public.prompt_snoozes from authenticated;

-- Hides a card for a while. Cards that only make sense once (the deepen
-- suggestion, the both-yes and both-no notes) go away for good.
create function public.snooze_prompt(p_match uuid, p_kind text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  s public.matching_settings;
  hide_for interval;
begin
  if not public.is_match_member(p_match) then
    raise exception 'match not found';
  end if;
  select * into s from public.matching_settings;
  hide_for := case p_kind
    when 'checkin' then interval '2 days'
    when 'health' then interval '7 days'
    when 'pulse' then make_interval(hours => s.pulse_hours)
    when 'bridge' then make_interval(days => s.bridge_days)
    else null
  end;
  insert into public.prompt_snoozes (match_id, user_id, kind, until)
    values (p_match, auth.uid(), p_kind, coalesce(now() + hide_for, 'infinity'))
    on conflict (match_id, user_id, kind) do update set until = excluded.until;
end;
$$;

-- What the app may offer you in one chat right now:
--   prompt: at most one card, so the app never piles on.
--     'mutual'       you both said no at the check-in: offer to end it together
--     'strengthened' you both said yes: a one-time note
--     'checkin'      you've each sent 15 messages: did you enjoy it?
--     'pulse'        the start has gone quiet: an easy opener, no pressure
--     'bridge'       two weeks of quiet after a real conversation: a catch-up question
--     'health'       how's this connection feeling?
--     'deepen'       a strong match: try a call, a game or a harder question
--   ladder: which question levels are open (1 from the start, 2 after the
--     check-in point, 3 once you both said yes).
--   checkin: what you may know about the check-in (see my_checkin_outcome).
create function public.match_prompts(p_match uuid)
returns table (prompt text, ladder int, checkin text)
language plpgsql stable security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  m public.matches;
  s public.matching_settings;
  gentle boolean;
  outcome text;
  reached boolean;
  quiet_since timestamptz;
  last_health timestamptz;
begin
  select * into m from public.matches where id = p_match and me in (user_a, user_b);
  if m.id is null then
    return;
  end if;
  select * into s from public.matching_settings;
  select gentle_prompts into gentle from public.profiles where id = me;
  outcome := public.my_checkin_outcome(p_match);
  reached := m.messages_a >= s.feedback_message_threshold and m.messages_b >= s.feedback_message_threshold;
  quiet_since := coalesce(m.last_message_at, m.created_at);
  select max(created_at) into last_health from public.health_checks
    where match_id = p_match and user_id = me;

  ladder := case when outcome = 'both_yes' then 3 when reached then 2 else 1 end;
  checkin := outcome;

  if m.status = 'active' then
    prompt := case
      when outcome = 'both_no' and public.prompt_open(p_match, 'mutual') then 'mutual'
      when outcome = 'both_yes' and public.prompt_open(p_match, 'strengthened') then 'strengthened'
      when reached and outcome is null and public.prompt_open(p_match, 'checkin') then 'checkin'
      when gentle and not reached and quiet_since <= now() - make_interval(hours => s.pulse_hours)
           and public.prompt_open(p_match, 'pulse') then 'pulse'
      when gentle and reached and quiet_since <= now() - make_interval(days => s.bridge_days)
           and public.prompt_open(p_match, 'bridge') then 'bridge'
      when outcome is not null
           and m.created_at <= now() - make_interval(days => s.health_first_days)
           and coalesce(last_health, '-infinity') <= now() - make_interval(days => s.health_every_days)
           and public.prompt_open(p_match, 'health') then 'health'
      when gentle and outcome = 'both_yes'
           and m.created_at <= now() - make_interval(days => s.deepen_after_days)
           and public.prompt_open(p_match, 'deepen') then 'deepen'
    end;
  end if;
  return next;
end;
$$;

create function public.prompt_open(p_match uuid, p_kind text) returns boolean
language sql stable security definer set search_path = '' as $$
  select not exists (
    select 1 from public.prompt_snoozes
    where match_id = p_match and user_id = auth.uid() and kind = p_kind and until > now());
$$;

-- ---------------------------------------------------------------------------
-- Conversation questions
-- ---------------------------------------------------------------------------

-- Questions people can pick from and edit before sending, never sent for
-- them. Edit the list in the Supabase table editor. Level 1 is light, level 3
-- is for people who already trust each other.
create table public.conversation_prompts (
  id int generated always as identity primary key,
  kind text not null check (kind in ('opener', 'catch_up', 'deep')),
  level smallint not null default 1 check (level between 1 and 3),
  body text not null check (char_length(body) between 5 and 300),
  active boolean not null default true
);

insert into public.conversation_prompts (kind, level, body) values
  ('opener', 1, 'What''s something small that made your week better?'),
  ('opener', 1, 'What are you into lately that you could talk about for an hour?'),
  ('opener', 1, 'What does a good day look like for you?'),
  ('opener', 1, 'What''s the last thing you learned that surprised you?'),
  ('opener', 1, 'What''s something you''re looking forward to?'),
  ('opener', 1, 'Where are you writing from, and what''s it like there right now?'),
  ('opener', 1, 'What''s a song, show or game you keep coming back to?'),
  ('opener', 1, 'What''s something people are often surprised to learn about you?'),
  ('catch_up', 1, 'What''s happened since we last talked?'),
  ('catch_up', 1, 'What''s been taking up most of your time lately?'),
  ('catch_up', 1, 'Anything you''ve been looking forward to, or dreading?'),
  ('catch_up', 1, 'What''s one good thing and one hard thing from the last couple of weeks?'),
  ('catch_up', 1, 'Found anything new you''ve enjoyed lately?'),
  ('deep', 2, 'What''s something you''ve changed your mind about in the last few years?'),
  ('deep', 2, 'What do you wish more people asked you about?'),
  ('deep', 2, 'Who has shaped how you see the world the most?'),
  ('deep', 2, 'What''s a small thing that makes you feel at home?'),
  ('deep', 2, 'What does a good friend do that you value most?'),
  ('deep', 2, 'What''s something you''re quietly proud of?'),
  ('deep', 2, 'When do you feel most like yourself?'),
  ('deep', 3, 'What''s something you''re still figuring out about yourself?'),
  ('deep', 3, 'What''s a moment that changed the direction of your life?'),
  ('deep', 3, 'What''s a fear you''ve had to work around?'),
  ('deep', 3, 'What would you want a close friend to understand about you that''s hard to say?'),
  ('deep', 3, 'What''s something you''ve never quite been able to let go of?'),
  ('deep', 3, 'Honestly, what do you hope your life looks like in five years?'),
  ('deep', 3, 'When was the last time you felt really understood?');

alter table public.conversation_prompts enable row level security;
revoke all on public.conversation_prompts from anon, authenticated;
grant select, insert, update, delete on public.conversation_prompts to authenticated;
create policy "prompts readable" on public.conversation_prompts
  for select to authenticated using (active or public.is_admin());
create policy "admins manage prompts" on public.conversation_prompts
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- "Have you met someone who matters to you?"
-- ---------------------------------------------------------------------------

-- Kept without the person's id if they delete their account, so the
-- published numbers stay honest. The answers never say who.
create table public.matters_answers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles (id) on delete set null,
  wave int not null,
  answer text not null check (answer in ('yes', 'not_yet', 'unsure', 'rather_not_say')),
  created_at timestamptz not null default now(),
  unique (user_id, wave)
);

alter table public.matters_answers enable row level security;
revoke all on public.matters_answers from anon;
create policy "own answers read" on public.matters_answers
  for select to authenticated using (user_id = auth.uid());
revoke insert, update, delete on public.matters_answers from authenticated;

-- The survey wave (30, 90 or 365) waiting for you, or null. If you were away
-- past several waves, only the latest is asked.
create function public.matters_due() returns int
language sql stable security definer set search_path = '' as $$
  select max(w.days)
  from public.profiles p
  cross join public.matching_settings s
  cross join lateral unnest(s.survey_days) as w(days)
  where p.id = auth.uid()
    and p.created_at <= now() - make_interval(days => w.days)
    and coalesce(p.survey_snoozed_until, '-infinity') <= now()
    and not exists (select 1 from public.matters_answers a
                    where a.user_id = p.id and a.wave >= w.days);
$$;

create function public.answer_matters(p_wave int, p_answer text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if p_wave is distinct from public.matters_due() then
    raise exception 'This question isn''t open right now';
  end if;
  insert into public.matters_answers (user_id, wave, answer) values (auth.uid(), p_wave, p_answer);
end;
$$;

create function public.snooze_matters() returns void
language sql security definer set search_path = '' as $$
  update public.profiles set survey_snoozed_until = now() + interval '3 days' where id = auth.uid();
$$;

-- ---------------------------------------------------------------------------
-- Results for admins: is the theory working?
-- ---------------------------------------------------------------------------

-- How many people at each wave say they've met someone who matters.
create function public.matters_results()
returns table (wave int, answer text, people bigint)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_admin() then
    raise exception 'admins only';
  end if;
  return query
    select a.wave, a.answer, count(*) from public.matters_answers a
    group by a.wave, a.answer order by a.wave, a.answer;
end;
$$;

-- Check-in results by match score, so exploratory matches can be compared
-- with chosen ones. No ids, just numbers.
create function public.checkin_results()
returns table (score numeric, exploratory boolean, result text, matched_on date, ended boolean)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_admin() then
    raise exception 'admins only';
  end if;
  return query
    select m.score, m.exploratory, public.checkin_result(m.id), m.created_at::date, m.status = 'ended'
    from public.matches m
    where exists (select 1 from public.checkins c where c.match_id = m.id)
    order by m.created_at;
end;
$$;

-- ---------------------------------------------------------------------------
-- my_matches gains the mutual-exit flag
-- ---------------------------------------------------------------------------

drop function public.my_matches();
create function public.my_matches()
returns table (
  match_id uuid,
  status public.match_status,
  created_at timestamptz,
  ended_at timestamptz,
  ended_by_me boolean,
  ended_mutually boolean,
  end_reason text,
  has_new boolean
)
language sql stable security definer set search_path = '' as $$
  select m.id, m.status, m.created_at, m.ended_at,
         m.ended_by = auth.uid(),
         m.ended_mutually,
         m.end_reason,
         exists (
           select 1 from public.messages msg
           where msg.match_id = m.id and msg.sender_id <> auth.uid()
             and msg.created_at > coalesce(r.last_read_at, '-infinity'))
  from public.matches m
  left join public.match_reads r on r.match_id = m.id and r.user_id = auth.uid()
  where auth.uid() in (m.user_a, m.user_b)
  order by m.created_at desc;
$$;

-- ---------------------------------------------------------------------------
-- Permissions
-- ---------------------------------------------------------------------------

revoke execute on all functions in schema public from anon, public;

grant execute on function public.my_matches() to authenticated;
grant execute on function public.answer_checkin(uuid, boolean) to authenticated;
grant execute on function public.my_checkin_outcome(uuid) to authenticated;
grant execute on function public.mutual_exit(uuid) to authenticated;
grant execute on function public.answer_health_check(uuid, text, text) to authenticated;
grant execute on function public.snooze_prompt(uuid, text) to authenticated;
grant execute on function public.match_prompts(uuid) to authenticated;
grant execute on function public.matters_due() to authenticated;
grant execute on function public.answer_matters(int, text) to authenticated;
grant execute on function public.snooze_matters() to authenticated;
grant execute on function public.matters_results() to authenticated;
grant execute on function public.checkin_results() to authenticated;
-- checkin_result reveals mixed answers; the rest are internal helpers.
revoke execute on function public.checkin_result(uuid) from authenticated;
revoke execute on function public.chat_limit_of(uuid) from authenticated;
revoke execute on function public.prompt_open(uuid, text) from authenticated;
