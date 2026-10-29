-- Kindred step 2: the core loop.
--
-- * The 18-question test, scored on the server so results can't be faked.
-- * The matching queue: one-on-one, greedy by score, with a small share of
--   exploratory matches, a boost for people who have waited, and a nudge
--   toward similar time zones.
-- * Chat safety: a message filter (blocked phrases, links for new members,
--   rate limit), crisis flags so the app can show help links, trust levels,
--   and automatic pausing when several people report the same person.

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------

alter table public.matching_settings
  add column max_active_matches int not null default 1 check (max_active_matches >= 1),
  -- Points added per day the longer-waiting person has been in the queue.
  add column wait_boost_per_day numeric(5, 2) not null default 2,
  add column wait_boost_max numeric(5, 2) not null default 10,
  -- Points taken off per hour of time zone difference.
  add column timezone_penalty_per_hour numeric(5, 2) not null default 1,
  add column timezone_penalty_max numeric(5, 2) not null default 10,
  -- Distinct people with open reports about someone before their matching
  -- and chats are paused for an admin to review.
  add column auto_pause_report_count int not null default 3,
  add column messages_per_minute int not null default 20;

-- ---------------------------------------------------------------------------
-- The 18-question test
-- ---------------------------------------------------------------------------

-- Questions 1-9 decide communication style, 10-18 friendship style. Each
-- option counts as one vote for a badge. Edit the wording in the Supabase
-- table editor; the badge column is never sent to the app.
create table public.test_questions (
  id int primary key check (id between 1 and 18),
  kind public.badge_kind not null,
  prompt text not null,
  check ((kind = 'communication') = (id <= 9))
);

create table public.test_options (
  id int generated always as identity primary key,
  question_id int not null references public.test_questions (id) on delete cascade,
  badge text not null references public.badges (code),
  label text not null,
  unique (question_id, badge)
);

insert into public.test_questions (id, kind, prompt) values
  (1, 'communication', 'A friend tells you about a problem. What do you usually do first?'),
  (2, 'communication', 'When you have a big decision to make, you tend to...'),
  (3, 'communication', 'In a group conversation, you are most often the one who...'),
  (4, 'communication', 'When a message from a friend upsets you, you...'),
  (5, 'communication', 'Your texts usually look like...'),
  (6, 'communication', 'When you explain something you care about, you...'),
  (7, 'communication', 'In a disagreement, what matters most to you?'),
  (8, 'communication', 'When someone asks "how are you?", you usually...'),
  (9, 'communication', 'A conversation leaves you feeling good when...'),
  (10, 'friendship', 'Your ideal Saturday with a friend is...'),
  (11, 'friendship', 'Friends would most likely describe you as...'),
  (12, 'friendship', 'When a friend is going through a hard time, you...'),
  (13, 'friendship', 'What makes a friendship feel solid to you?'),
  (14, 'friendship', 'What do you most want from a new friend?'),
  (15, 'friendship', 'In your friend group, you are usually the one who...'),
  (16, 'friendship', 'A friend cancels plans at the last minute. You...'),
  (17, 'friendship', 'The conversations you remember most are about...'),
  (18, 'friendship', 'You feel closest to someone after...');

insert into public.test_options (question_id, badge, label) values
  (1, 'IP', 'Listen, then take some time to think before I respond'),
  (1, 'EP', 'Start talking it through with them right away'),
  (1, 'DC', 'Ask what they need and suggest a next step'),
  (1, 'RC', 'Make sure they feel heard and cared for'),
  (1, 'AC', 'Ask questions to understand exactly what happened'),
  (1, 'EC', 'Share a story that puts it in perspective'),
  (2, 'IP', 'Think it over quietly on my own first'),
  (2, 'EP', 'Talk it out with people until it becomes clear'),
  (2, 'DC', 'Pick the most practical option and move on'),
  (2, 'RC', 'Think about how it will affect the people I care about'),
  (2, 'AC', 'Make a list of pros and cons and weigh them'),
  (2, 'EC', 'Go with the option that feels most exciting'),
  (3, 'IP', 'Listens closely and speaks up once I''ve thought it through'),
  (3, 'EP', 'Thinks out loud and gets ideas flowing'),
  (3, 'DC', 'Keeps things on track and gets to the point'),
  (3, 'RC', 'Notices how everyone is feeling and draws people in'),
  (3, 'AC', 'Fact-checks and adds the details'),
  (3, 'EC', 'Tells the stories and makes people laugh'),
  (4, 'IP', 'Wait until I''ve processed it before replying'),
  (4, 'EP', 'Call them or reply quickly to talk it through'),
  (4, 'DC', 'Tell them plainly what bothered me'),
  (4, 'RC', 'Tell them how it made me feel and ask how they''re doing'),
  (4, 'AC', 'Re-read it carefully to be sure what they meant'),
  (4, 'EC', 'Reply with a lot of feeling, then smooth it over'),
  (5, 'IP', 'A few thoughtful messages, sometimes sent hours later'),
  (5, 'EP', 'Lots of quick messages as thoughts come to me'),
  (5, 'DC', 'Short and to the point'),
  (5, 'RC', 'Warm, with plenty of check-ins and kind words'),
  (5, 'AC', 'Well organised and precise'),
  (5, 'EC', 'Full of emojis, voice notes and enthusiasm'),
  (6, 'IP', 'Choose my words carefully and take my time'),
  (6, 'EP', 'Figure out what I think while I''m saying it'),
  (6, 'DC', 'Give the key point first'),
  (6, 'RC', 'Explain why it matters to me personally'),
  (6, 'AC', 'Walk through it step by step'),
  (6, 'EC', 'Paint the big picture and get people excited'),
  (7, 'IP', 'Having time to think before we talk it through'),
  (7, 'EP', 'Talking it all out until we understand each other'),
  (7, 'DC', 'Being honest and solving it quickly'),
  (7, 'RC', 'Both of us still feeling cared for'),
  (7, 'AC', 'Getting the facts right'),
  (7, 'EC', 'Clearing the air and moving on with energy'),
  (8, 'IP', 'Give a short answer unless I know them well'),
  (8, 'EP', 'Tell them what''s going on and see where it goes'),
  (8, 'DC', 'Say "good, you?" and get to the point'),
  (8, 'RC', 'Answer honestly and ask how they really are'),
  (8, 'AC', 'Give an accurate update on what''s been happening'),
  (8, 'EC', 'Launch into the highlights of my week'),
  (9, 'IP', 'There was room for pauses and real thought'),
  (9, 'EP', 'We bounced ideas off each other'),
  (9, 'DC', 'We were honest and got somewhere'),
  (9, 'RC', 'I felt understood'),
  (9, 'AC', 'I learned something precise and new'),
  (9, 'EC', 'It was fun and full of energy'),
  (10, 'TL', 'A long walk where they can tell me what''s on their mind'),
  (10, 'DD', 'Coffee and a conversation about life'),
  (10, 'TA', 'Trying something neither of us has done before'),
  (10, 'TE', 'Getting a few people together for something lively'),
  (10, 'SH', 'A cosy day in where we can both relax'),
  (10, 'TC', 'Our usual spot, like we always do'),
  (10, 'TB', 'Working on a project or goal together'),
  (11, 'TL', 'A great listener'),
  (11, 'DD', 'Thoughtful and deep'),
  (11, 'TA', 'Up for anything'),
  (11, 'TE', 'The life of the party'),
  (11, 'SH', 'The person you can tell anything'),
  (11, 'TC', 'Reliable, always there'),
  (11, 'TB', 'Motivated and encouraging'),
  (12, 'TL', 'Let them talk for as long as they need'),
  (12, 'DD', 'Help them make sense of what it means for them'),
  (12, 'TA', 'Take them out to get their mind off it'),
  (12, 'TE', 'Lift their mood and bring some light'),
  (12, 'SH', 'Make sure they feel safe and not judged'),
  (12, 'TC', 'Check in on them regularly'),
  (12, 'TB', 'Help them make a plan to move forward'),
  (13, 'TL', 'Knowing they really listen to me'),
  (13, 'DD', 'Being able to talk about anything, even hard topics'),
  (13, 'TA', 'Having shared memories and adventures'),
  (13, 'TE', 'Always having fun together'),
  (13, 'SH', 'Feeling completely accepted'),
  (13, 'TC', 'Knowing they''ll show up'),
  (13, 'TB', 'Helping each other grow'),
  (14, 'TL', 'Someone who wants to hear my story'),
  (14, 'DD', 'Someone to have real conversations with'),
  (14, 'TA', 'Someone to explore and try new things with'),
  (14, 'TE', 'Someone who brings energy and good vibes'),
  (14, 'SH', 'Someone I can feel safe being myself around'),
  (14, 'TC', 'Someone steady I can count on'),
  (14, 'TB', 'Someone who pushes me to be better'),
  (15, 'TL', 'Everyone confides in'),
  (15, 'DD', 'Asks the big questions'),
  (15, 'TA', 'Suggests the next adventure'),
  (15, 'TE', 'Gets everyone excited'),
  (15, 'SH', 'Makes sure everyone feels included'),
  (15, 'TC', 'Remembers birthdays and keeps traditions going'),
  (15, 'TB', 'Organises and keeps people moving toward goals'),
  (16, 'TL', 'Ask what''s going on with them'),
  (16, 'DD', 'Wonder if something deeper is happening'),
  (16, 'TA', 'Find something else spontaneous to do'),
  (16, 'TE', 'Rally some other people instead'),
  (16, 'SH', 'Tell them it''s okay and that I''m there if they need me'),
  (16, 'TC', 'Feel a bit thrown, and suggest a new date'),
  (16, 'TB', 'Use the time to get something done'),
  (17, 'TL', 'Someone else opening up to me'),
  (17, 'DD', 'Meaning, values and the big questions'),
  (17, 'TA', 'Places, plans and experiences'),
  (17, 'TE', 'Wild ideas and lots of laughter'),
  (17, 'SH', 'Feelings we had never shared before'),
  (17, 'TC', 'Everyday life, little updates that add up'),
  (17, 'TB', 'Ambitions and how to reach them'),
  (18, 'TL', 'They trust me with something personal'),
  (18, 'DD', 'We talk late into the night about what matters'),
  (18, 'TA', 'We''ve been through an adventure together'),
  (18, 'TE', 'We''ve had an amazing time together'),
  (18, 'SH', 'I''ve been there for them, or they for me, in a hard moment'),
  (18, 'TC', 'We''ve kept showing up for each other over time'),
  (18, 'TB', 'We''ve helped each other reach a goal');

alter table public.test_questions enable row level security;
alter table public.test_options enable row level security;
revoke all on public.test_questions, public.test_options from anon;

create policy "questions readable" on public.test_questions
  for select to authenticated using (true);
create policy "options readable" on public.test_options
  for select to authenticated using (true);
revoke all on public.test_questions, public.test_options from authenticated;
grant select on public.test_questions to authenticated;
-- The app sees the wording but not which badge each option counts toward.
grant select (id, question_id, label) on public.test_options to authenticated;

-- Results are now written only by submit_test().
drop policy "own results insert" on public.test_results;
revoke insert on public.test_results from authenticated;

-- ---------------------------------------------------------------------------
-- Profile, match and message additions
-- ---------------------------------------------------------------------------

alter table public.profiles
  -- Decided when someone joins the queue: whether this turn is exploratory.
  add column queue_exploratory boolean not null default false,
  -- Set when matching and chat are paused for review. Only admins clear it.
  add column suspended_at timestamptz,
  add column suspended_reason text;

alter table public.matches
  add column messages_a int not null default 0,
  add column messages_b int not null default 0;

-- True when someone mentions crisis words, so the app can show help links.
alter table public.messages add column crisis boolean not null default false;
create index messages_sender_created on public.messages (sender_id, created_at);

-- When you last opened each chat, so the app can show a dot for new
-- messages. Only you can see it: there are no read receipts.
create table public.match_reads (
  match_id uuid not null references public.matches (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  last_read_at timestamptz not null default now(),
  primary key (match_id, user_id)
);

alter table public.match_reads enable row level security;
revoke all on public.match_reads from anon;
create policy "own reads" on public.match_reads
  for select to authenticated using (user_id = auth.uid());
revoke insert, update, delete on public.match_reads from authenticated;

-- Words and phrases the message filter acts on. 'block' stops the message;
-- 'crisis' lets it through but shows both people help links.
create table public.filter_terms (
  term text primary key check (term = lower(term) and char_length(term) between 2 and 100),
  action text not null check (action in ('block', 'crisis'))
);

insert into public.filter_terms (term, action) values
  ('kill yourself', 'block'),
  ('kys', 'block'),
  ('go die', 'block'),
  ('i hope you die', 'block'),
  ('kill myself', 'crisis'),
  ('killing myself', 'crisis'),
  ('suicide', 'crisis'),
  ('suicidal', 'crisis'),
  ('end my life', 'crisis'),
  ('want to die', 'crisis'),
  ('better off dead', 'crisis'),
  ('self harm', 'crisis'),
  ('self-harm', 'crisis'),
  ('hurt myself', 'crisis'),
  ('cut myself', 'crisis'),
  ('overdose', 'crisis');

alter table public.filter_terms enable row level security;
revoke all on public.filter_terms from anon, authenticated;
grant select, insert, update, delete on public.filter_terms to authenticated;
create policy "admins manage filter" on public.filter_terms
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------------
-- Trust levels
-- ---------------------------------------------------------------------------
-- 0 New: just signed in.
-- 1 Member: confirmed 18+ and took the test. Can match and chat, but can't
--   send links, emails or phone numbers in messages yet.
-- 2 Established: had a two-sided conversation (each person sent at least
--   the check-in number of messages) with no upheld report. Links unlock.
-- 3 Trusted: set by an admin.
-- Levels only go up automatically. Admins lower them or suspend.

create function public.refresh_trust_level(p_user uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  p public.profiles;
  threshold int := (select feedback_message_threshold from public.matching_settings);
  level smallint := 0;
begin
  select * into p from public.profiles where id = p_user;
  if p.id is null or p.suspended_at is not null then
    return;
  end if;
  if p.adult_confirmed_at is not null
     and exists (select 1 from public.test_results where user_id = p_user) then
    level := 1;
    if exists (
         select 1 from public.matches
         where p_user in (user_a, user_b)
           and messages_a >= threshold and messages_b >= threshold)
       and not exists (
         select 1 from public.reports where reported_id = p_user and status = 'actioned') then
      level := 2;
    end if;
  end if;
  if level > p.trust_level then
    update public.profiles set trust_level = level where id = p_user;
  end if;
end;
$$;

create or replace function public.confirm_adult(p_birth_date date) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;
  if p_birth_date > (current_date - interval '18 years') then
    raise exception 'Kindred is for adults 18 and over';
  end if;
  update public.profiles set adult_confirmed_at = now() where id = auth.uid();
  perform public.refresh_trust_level(auth.uid());
end;
$$;

-- ---------------------------------------------------------------------------
-- Test scoring
-- ---------------------------------------------------------------------------

-- p_answers maps question id to option id, e.g. {"1": 4, "2": 9, ...}.
-- Each badge's percentage is its share of the 9 answers in its half of the
-- test. Primary and secondary communication badges are the two most picked;
-- friendship is the most picked. Ties go to the badge picked earliest.
create function public.submit_test(p_answers jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  cooldown interval := (select retake_cooldown from public.matching_settings);
  last_taken timestamptz;
  chosen int;
  comm jsonb;
  friend jsonb;
  ranked_comm text[];
  ranked_friend text[];
  new_id uuid;
begin
  if me is null then
    raise exception 'not signed in';
  end if;
  select max(taken_at) into last_taken from public.test_results where user_id = me;
  if last_taken > now() - cooldown then
    raise exception 'You can retake the test from %', to_char(last_taken + cooldown, 'FMMonth FMDD, YYYY');
  end if;
  if jsonb_typeof(p_answers) <> 'object' then
    raise exception 'answers must be an object';
  end if;

  select count(*) into chosen
  from jsonb_each_text(p_answers) a
  join public.test_options o on o.question_id::text = a.key and o.id::text = a.value;
  if chosen <> 18 or (select count(*) from jsonb_object_keys(p_answers)) <> 18 then
    raise exception 'Please answer all 18 questions';
  end if;

  with picks as (
    select q.kind, o.badge, q.id as question_id
    from jsonb_each_text(p_answers) a
    join public.test_options o on o.id::text = a.value
    join public.test_questions q on q.id = o.question_id
  ),
  tallies as (
    select b.kind, b.code, count(p.badge) as votes, min(p.question_id) as first_pick,
           b.code as tiebreak
    from public.badges b
    left join picks p on p.badge = b.code
    group by b.kind, b.code
  )
  select
    jsonb_object_agg(code, round(votes * 100.0 / 9, 1)) filter (where kind = 'communication'),
    jsonb_object_agg(code, round(votes * 100.0 / 9, 1)) filter (where kind = 'friendship'),
    array_agg(code order by votes desc, first_pick nulls last, tiebreak) filter (where kind = 'communication'),
    array_agg(code order by votes desc, first_pick nulls last, tiebreak) filter (where kind = 'friendship')
  into comm, friend, ranked_comm, ranked_friend
  from tallies;

  insert into public.test_results (user_id, answers, communication_scores, friendship_scores,
    primary_communication, secondary_communication, friendship)
  values (me, p_answers, comm, friend, ranked_comm[1], ranked_comm[2], ranked_friend[1])
  returning id into new_id;

  perform public.refresh_trust_level(me);
  return new_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Compatibility scoring
-- ---------------------------------------------------------------------------

create function public.compat_adjustment(p_x text, p_y text) returns numeric
language sql stable security definer set search_path = '' as $$
  select coalesce((select adjustment from public.compatibility
                   where badge_a = least(p_x, p_y) and badge_b = greatest(p_x, p_y)), 0);
$$;

-- How well two people's badges line up, 0 to 100, before the waiting boost
-- and time zone nudge.
--
-- Three slots are compared: primary communication (60%), secondary
-- communication (20%) and friendship (20%). A slot scores 100 when both
-- people have the same badge. Otherwise it scores 50 plus half of how much
-- each person also leans toward the other's badge (from their percentages),
-- so near-misses still count.
--
-- Then every pair of badges between the two people adds its adjustment from
-- the compatibility table, weighted by importance: two primary badges count
-- 60%, a primary and another badge 40%, any other pair 20%. All adjustments
-- start at 0, so out of the box this matches people who communicate alike.
create function public.score_pair(
  pc1 text, sc1 text, f1 text, cs1 jsonb, fs1 jsonb,
  pc2 text, sc2 text, f2 text, cs2 jsonb, fs2 jsonb
) returns numeric
language sql stable security definer set search_path = '' as $$
  with slots(w, x, y, px, py) as (
    values
      (0.6, pc1, pc2, cs1, cs2),
      (0.2, sc1, sc2, cs1, cs2),
      (0.2, f1, f2, fs1, fs2)
  ),
  base as (
    select sum(w * case when x = y then 100
                        else least(100, 50 + (coalesce((px ->> y)::numeric, 0)
                                              + coalesce((py ->> x)::numeric, 0)) / 2)
                   end) as points
    from slots
  ),
  mine(w, badge) as (values (0.6, pc1), (0.2, sc1), (0.2, f1)),
  theirs(w, badge) as (values (0.6, pc2), (0.2, sc2), (0.2, f2)),
  adj as (
    select sum((a.w + b.w) / 2 * public.compat_adjustment(a.badge, b.badge)) as points
    from mine a cross join theirs b
  )
  select round(greatest(0, least(100, base.points + adj.points)), 2)
  from base, adj;
$$;

-- Convenience for admins and tests: the score between two people right now.
create function public.compatibility_score(p_a uuid, p_b uuid) returns numeric
language sql stable security definer set search_path = '' as $$
  select public.score_pair(
    a.primary_communication, a.secondary_communication, a.friendship, a.communication_scores, a.friendship_scores,
    b.primary_communication, b.secondary_communication, b.friendship, b.communication_scores, b.friendship_scores)
  from public.current_test_results a, public.current_test_results b
  where a.user_id = p_a and b.user_id = p_b;
$$;

-- Hours ahead of UTC for a time zone name, or null if unknown.
create function public.tz_offset_hours(p_tz text) returns numeric
language plpgsql stable set search_path = '' as $$
begin
  if p_tz is null then
    return null;
  end if;
  return extract(epoch from (now() at time zone p_tz) - (now() at time zone 'UTC')) / 3600;
exception when others then
  return null;
end;
$$;

-- ---------------------------------------------------------------------------
-- Matching
-- ---------------------------------------------------------------------------

create function public.active_match_count(p_user uuid) returns int
language sql stable security definer set search_path = '' as $$
  select count(*)::int from public.matches
  where p_user in (user_a, user_b) and status in ('active', 'paused');
$$;

-- Pairs up everyone waiting in the queue. Exploratory turns go first and
-- take a random partner (still respecting blocks, 18+ and never re-matching),
-- so the compatibility table can later be checked against pairs it didn't
-- choose. Everyone else is matched greedily, best score first, if the score
-- plus waiting boost minus time zone gap reaches the minimum.
create function public.run_matching() returns int
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
           t.primary_communication pc, t.secondary_communication sc, t.friendship f,
           t.communication_scores cs, t.friendship_scores fs
    from public.profiles p
    join public.current_test_results t on t.user_id = p.id
    where p.matching_status = 'queued'
      and p.adult_confirmed_at is not null
      and p.suspended_at is null
      and p.trust_level >= 1
      and public.active_match_count(p.id) < s.max_active_matches
  ),
  pairs as (
    select a.id as a, b.id as b,
           public.score_pair(a.pc, a.sc, a.f, a.cs, a.fs, b.pc, b.sc, b.f, b.cs, b.fs) as score,
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

create function public.create_match(p_a uuid, p_b uuid, p_exploratory boolean) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  new_id uuid;
begin
  insert into public.matches (user_a, user_b, score, exploratory)
  values (least(p_a, p_b), greatest(p_a, p_b), public.compatibility_score(p_a, p_b), p_exploratory)
  returning id into new_id;
  update public.profiles
    set matching_status = 'inactive', queued_at = null, queue_exploratory = false
    where id in (p_a, p_b);
  return new_id;
end;
$$;

-- Runs matching and returns your newest active match, if you have one.
create function public.find_match() returns uuid
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;
  if (select matching_status from public.profiles where id = auth.uid()) = 'queued' then
    perform public.run_matching();
  end if;
  return (select id from public.matches
          where auth.uid() in (user_a, user_b) and status = 'active'
          order by created_at desc limit 1);
end;
$$;

-- Join the queue and try to match straight away.
create function public.join_queue() returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  p public.profiles;
  s public.matching_settings;
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
  if public.active_match_count(me) >= s.max_active_matches then
    raise exception 'You already have a match. Kindred focuses on one connection at a time';
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

create function public.leave_queue() returns void
language sql security definer set search_path = '' as $$
  update public.profiles
    set matching_status = 'inactive', queued_at = null, queue_exploratory = false
    where id = auth.uid() and matching_status = 'queued';
$$;

-- ---------------------------------------------------------------------------
-- Messages: filter, counts, read dot
-- ---------------------------------------------------------------------------

create function public.filter_message() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  sender public.profiles;
  text_lower text;
  t record;
  limit_per_minute int := (select messages_per_minute from public.matching_settings);
begin
  new.body := btrim(new.body);
  if new.body = '' then
    raise exception 'Message is empty';
  end if;
  -- Only the server sets this.
  new.crisis := false;

  select * into sender from public.profiles where id = new.sender_id;
  if sender.suspended_at is not null then
    raise exception 'Chat is paused on your account while we review a report';
  end if;
  if (select count(*) from public.messages
      where sender_id = new.sender_id and created_at > now() - interval '1 minute') >= limit_per_minute then
    raise exception 'You''re sending messages very quickly. Please wait a moment';
  end if;

  text_lower := lower(new.body);
  for t in select term, action from public.filter_terms loop
    if text_lower ~ ('(^|[^[:alnum:]])'
                     || regexp_replace(t.term, '([.*+?^${}()|\[\]\\])', '\\\1', 'g')
                     || '($|[^[:alnum:]])') then
      if t.action = 'block' then
        raise exception 'This message wasn''t sent because it includes language Kindred doesn''t allow';
      end if;
      new.crisis := true;
    end if;
  end loop;

  if sender.trust_level < 2 and (
       text_lower ~ '(https?://|www\.)'
       or text_lower ~ '[[:alnum:]-]+\.(com|net|org|io|co|me|app|gg|ly|xyz|link|info|biz|tk|ru)([^[:alnum:]]|$)'
       or text_lower ~ '[[:alnum:]._%+-]+@[[:alnum:].-]+\.[a-z]{2,}'
       or regexp_replace(text_lower, '[\s().+-]', '', 'g') ~ '[0-9]{9,}') then
    raise exception 'Links, emails and phone numbers unlock after your first good conversation. To share how to reach you, use "What you share" for this match';
  end if;
  return new;
end;
$$;

create trigger messages_filter before insert on public.messages
  for each row execute function public.filter_message();

create or replace function public.touch_match_on_message() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  m public.matches;
  threshold int := (select feedback_message_threshold from public.matching_settings);
begin
  update public.matches set
      last_message_at = new.created_at,
      messages_a = messages_a + (user_a = new.sender_id)::int,
      messages_b = messages_b + (user_b = new.sender_id)::int
    where id = new.match_id
    returning * into m;
  update public.profiles set last_active_at = new.created_at where id = new.sender_id;
  -- A two-sided conversation may unlock trust level 2 for both people.
  if (m.messages_a = threshold and m.messages_b >= threshold)
     or (m.messages_b = threshold and m.messages_a >= threshold) then
    perform public.refresh_trust_level(m.user_a);
    perform public.refresh_trust_level(m.user_b);
  end if;
  return new;
end;
$$;

-- The match's newest message from the partner is newer than your last visit.
create function public.mark_match_read(p_match uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_match_member(p_match) then
    raise exception 'match not found';
  end if;
  insert into public.match_reads (match_id, user_id) values (p_match, auth.uid())
  on conflict (match_id, user_id) do update set last_read_at = now();
end;
$$;

-- Your matches, newest first, with whether there's something new to read.
-- Partner details come from match_partner().
create function public.my_matches()
returns table (
  match_id uuid,
  status public.match_status,
  created_at timestamptz,
  ended_at timestamptz,
  ended_by_me boolean,
  end_reason text,
  has_new boolean
)
language sql stable security definer set search_path = '' as $$
  select m.id, m.status, m.created_at, m.ended_at,
         m.ended_by = auth.uid(),
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
-- Safety: suspended people can't message, blocks stay private, reports pause
-- ---------------------------------------------------------------------------

create or replace function public.can_message(p_match uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.matches m
    where m.id = p_match
      and m.status = 'active'
      and auth.uid() in (m.user_a, m.user_b)
      and not exists (
        select 1 from public.profiles p
        where p.id in (m.user_a, m.user_b) and p.suspended_at is not null)
      and not exists (
        select 1 from public.blocks b
        where (b.blocker_id = m.user_a and b.blocked_id = m.user_b)
           or (b.blocker_id = m.user_b and b.blocked_id = m.user_a)
      )
  );
$$;

-- The blocked person sees only that the match ended, not why.
create or replace function public.block_user(p_user uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
begin
  if me is null or p_user = me then
    raise exception 'invalid block';
  end if;
  insert into public.blocks (blocker_id, blocked_id) values (me, p_user)
    on conflict do nothing;
  update public.matches
    set status = 'ended', ended_at = now(), ended_by = me, end_reason = null
    where user_a = least(me, p_user) and user_b = greatest(me, p_user)
      and status <> 'ended';
end;
$$;

-- Report someone you're matched with. When enough different people have
-- open reports about the same person, their matching and chats pause until
-- an admin reviews it.
create or replace function public.report_user(
  p_match uuid,
  p_reason text,
  p_details text default null,
  p_message bigint default null
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  other uuid;
  snapshot text;
  new_id uuid;
begin
  select case when user_a = me then user_b else user_a end into other
  from public.matches where id = p_match and me in (user_a, user_b);
  if other is null then
    raise exception 'match not found';
  end if;
  if p_message is not null then
    select body into snapshot from public.messages
    where id = p_message and match_id = p_match;
  end if;
  insert into public.reports (reporter_id, reported_id, match_id, message_id, reason, details, message_snapshot)
  values (me, other, p_match, p_message, left(p_reason, 100), left(p_details, 4000), snapshot)
  returning id into new_id;

  if (select count(distinct reporter_id) from public.reports
      where reported_id = other and status in ('open', 'reviewing'))
     >= (select auto_pause_report_count from public.matching_settings) then
    update public.profiles
      set suspended_at = coalesce(suspended_at, now()),
          suspended_reason = coalesce(suspended_reason, 'automatic: several open reports'),
          matching_status = 'inactive', queued_at = null
      where id = other;
  end if;
  return new_id;
end;
$$;

-- What you see about your partner: badges and trust level always, other
-- details only if they've revealed them to you.
drop function public.match_partner(uuid);
create function public.match_partner(p_match uuid)
returns table (
  partner_id uuid,
  primary_communication text,
  secondary_communication text,
  friendship text,
  trust_level smallint,
  display_name text,
  contact text,
  region text,
  timezone text
)
language sql stable security definer set search_path = '' as $$
  with m as (
    select case when user_a = auth.uid() then user_b else user_a end as partner
    from public.matches
    where id = p_match and auth.uid() in (user_a, user_b)
  )
  select
    p.id,
    t.primary_communication,
    t.secondary_communication,
    t.friendship,
    p.trust_level,
    case when r.reveal_name then p.display_name end,
    case when r.reveal_contact then p.contact end,
    case when r.reveal_region then p.region end,
    case when r.reveal_region then p.timezone end
  from m
  join public.profiles p on p.id = m.partner
  left join public.current_test_results t on t.user_id = p.id
  left join public.match_reveals r on r.match_id = p_match and r.user_id = p.id;
$$;

-- ---------------------------------------------------------------------------
-- Live updates for chats and new matches (Supabase Realtime, free tier)
-- ---------------------------------------------------------------------------

do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.messages, public.matches;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Permissions
-- ---------------------------------------------------------------------------

revoke execute on all functions in schema public from anon, public;

grant execute on function public.submit_test(jsonb) to authenticated;
grant execute on function public.join_queue() to authenticated;
grant execute on function public.leave_queue() to authenticated;
grant execute on function public.find_match() to authenticated;
grant execute on function public.mark_match_read(uuid) to authenticated;
grant execute on function public.my_matches() to authenticated;
grant execute on function public.match_partner(uuid) to authenticated;
grant execute on function public.confirm_adult(date) to authenticated;
grant execute on function public.block_user(uuid) to authenticated;
grant execute on function public.report_user(uuid, text, text, bigint) to authenticated;
grant execute on function public.can_message(uuid) to authenticated;
-- Scoring and matching internals stay server-side: run_matching,
-- create_match, score_pair, compatibility_score, refresh_trust_level.
revoke execute on function public.run_matching() from authenticated;
revoke execute on function public.create_match(uuid, uuid, boolean) from authenticated;
revoke execute on function public.score_pair(text, text, text, jsonb, jsonb, text, text, text, jsonb, jsonb) from authenticated;
revoke execute on function public.compatibility_score(uuid, uuid) from authenticated;
revoke execute on function public.refresh_trust_level(uuid) from authenticated;
revoke execute on function public.compat_adjustment(text, text) from authenticated;
revoke execute on function public.active_match_count(uuid) from authenticated;
