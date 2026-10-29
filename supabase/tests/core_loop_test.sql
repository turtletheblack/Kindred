-- Checks for the test, matching, chat filter and trust levels. Run with
-- scripts/test-db.sh. Each block raises an exception if a rule is broken.
\set ON_ERROR_STOP 1
\set QUIET 1

-- Ana and Dee communicate alike, so do Ben and Cal. Eve and Fay are alike
-- too, but Fay has blocked Eve.
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'ana@example.com'),
  ('00000000-0000-0000-0000-00000000000b', 'ben@example.com'),
  ('00000000-0000-0000-0000-00000000000c', 'cal@example.com'),
  ('00000000-0000-0000-0000-00000000000d', 'dee@example.com'),
  ('00000000-0000-0000-0000-00000000000e', 'eve@example.com'),
  ('00000000-0000-0000-0000-00000000000f', 'fay@example.com');

-- Exploratory matches are tested separately, so switch them off for now.
update public.matching_settings set exploratory_share = 0;

create function pg_temp.act_as(p_user text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_user, false);
  execute 'set role authenticated';
end;
$$;

create function pg_temp.check(ok boolean, what text) returns void language plpgsql as $$
begin
  if not coalesce(ok, false) then
    raise exception 'FAILED: %', what;
  end if;
  raise notice 'ok: %', what;
end;
$$;

-- Builds answers that pick the given badge for each question, in order.
create function pg_temp.answers(picks text[]) returns jsonb language sql as $$
  select jsonb_object_agg(o.question_id::text, o.id)
  from unnest(picks) with ordinality as p(badge, n)
  join public.test_options o on o.question_id = p.n and o.badge = p.badge;
$$;

-- Confirms 18+ and submits a test as the given user.
create function pg_temp.onboard(p_user text, picks text[]) returns void language plpgsql as $$
declare a jsonb := pg_temp.answers(picks);
begin
  perform pg_temp.act_as(p_user);
  perform public.confirm_adult(date '1990-01-01');
  perform public.submit_test(a);
  execute 'reset role';
end;
$$;

create function pg_temp.match_of(p_a text, p_b text) returns public.matches language sql as $$
  select * from public.matches where user_a = least(p_a, p_b)::uuid and user_b = greatest(p_a, p_b)::uuid;
$$;

-- The test itself ------------------------------------------------------------

do $$ begin
  perform pg_temp.check((select count(*) from public.test_questions) = 18, 'the test has 18 questions');
  perform pg_temp.check((select count(*) from public.test_options where question_id <= 9) = 54, 'each communication question offers all 6 styles');
  perform pg_temp.check((select count(*) from public.test_options where question_id > 9) = 63, 'each friendship question offers all 7 styles');
end $$;

select pg_temp.act_as('00000000-0000-0000-0000-00000000000a') \g /dev/null
do $$ begin
  perform pg_temp.check((select count(*) from public.test_options) = 117, 'the app can read the options');
  begin
    perform badge from public.test_options limit 1;
    raise exception 'FAILED: badge column readable';
  exception when insufficient_privilege then
    raise notice 'ok: the app cannot see which badge an option counts toward';
  end;
  begin
    insert into public.test_results (user_id, answers, communication_scores, friendship_scores,
      communication, friendship)
      values (auth.uid(), '{}', '{}', '{}', 'IP', 'SH');
    raise exception 'FAILED: wrote own test result';
  exception when insufficient_privilege then
    raise notice 'ok: test results can only come from server-side scoring';
  end;
  begin
    perform public.submit_test('{"1": 1}');
    raise exception 'FAILED: partial test accepted';
  exception when raise_exception then
    raise notice 'ok: all 18 questions must be answered';
  end;
  begin
    perform public.join_queue();
    raise exception 'FAILED: queued before 18+';
  exception when raise_exception then
    raise notice 'ok: you must confirm 18+ before matching';
  end;
  begin
    perform public.run_matching();
    raise exception 'FAILED: ran matching directly';
  exception when insufficient_privilege then
    raise notice 'ok: the app cannot run matching internals directly';
  end;
end $$;
reset role;

select pg_temp.onboard('00000000-0000-0000-0000-00000000000a',
  array['IP','IP','IP','IP','IP','RC','RC','RC','EP', 'SH','SH','SH','SH','SH','SH','TL','TL','TL']) \g /dev/null
select pg_temp.onboard('00000000-0000-0000-0000-00000000000d',
  array['IP','IP','IP','IP','IP','RC','RC','RC','EP', 'SH','SH','SH','SH','SH','SH','TL','TL','TL']) \g /dev/null
-- Ben ties DC and EP four each; DC was picked first, so it's his badge.
select pg_temp.onboard('00000000-0000-0000-0000-00000000000b',
  array['DC','EP','EP','DC','EP','DC','EP','DC','AC', 'TL','TL','TL','TL','TL','TL','TA','TA','TA']) \g /dev/null
select pg_temp.onboard('00000000-0000-0000-0000-00000000000c',
  array['DC','EP','EP','DC','EP','DC','EP','DC','AC', 'TL','TL','TL','TL','TL','TL','TA','TA','TA']) \g /dev/null
select pg_temp.onboard('00000000-0000-0000-0000-00000000000e',
  array['EC','EC','EC','EC','EC','AC','AC','AC','AC', 'TE','TE','TE','TE','TE','TB','TB','TB','TB']) \g /dev/null
select pg_temp.onboard('00000000-0000-0000-0000-00000000000f',
  array['EC','EC','EC','EC','EC','AC','AC','AC','AC', 'TE','TE','TE','TE','TE','TB','TB','TB','TB']) \g /dev/null

do $$
declare r public.test_results;
begin
  select * into r from public.test_results where user_id = '00000000-0000-0000-0000-00000000000a';
  perform pg_temp.check(r.communication = 'IP' and r.friendship = 'SH',
    'the most-picked style in each half becomes the badge');
  perform pg_temp.check((r.communication_scores ->> 'IP')::numeric = 55.6 and (r.communication_scores ->> 'DC')::numeric = 0
    and (r.friendship_scores ->> 'SH')::numeric = 66.7, 'each badge gets a percentage score');
  select * into r from public.test_results where user_id = '00000000-0000-0000-0000-00000000000b';
  perform pg_temp.check(r.communication = 'DC', 'ties go to the style picked first');
  perform pg_temp.check((select trust_level from public.profiles where id = '00000000-0000-0000-0000-00000000000a') = 1,
    'confirming 18+ and taking the test makes you a member (trust level 1)');
end $$;

select pg_temp.act_as('00000000-0000-0000-0000-00000000000a') \g /dev/null
do $$ begin
  perform public.submit_test('{}');
  raise exception 'FAILED: retake allowed';
exception when raise_exception then
  perform pg_temp.check(sqlerrm like 'You can retake the test from%', 'retakes wait for the cooldown');
end $$;
reset role;

-- Scores ----------------------------------------------------------------------

do $$ begin
  perform pg_temp.check(public.compatibility_score('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000d') = 100,
    'identical styles score 100');
  -- 70% x (IP vs DC: 50 + (0 + 0)/2) + 30% x (SH vs TL: 50 + (33.3 + 0)/2)
  perform pg_temp.check(public.compatibility_score('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000b') = 55.00,
    'different styles score lower, with credit for overlap');
  update public.compatibility set adjustment = 20 where badge_a = 'DC' and badge_b = 'IP';
  perform pg_temp.check(public.compatibility_score('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000b') = 69.00,
    'a compatibility table adjustment raises the score (two communication badges count 70%)');
  update public.compatibility set adjustment = 0;
end $$;

-- Matching ----------------------------------------------------------------------

-- Fay blocks Eve before either is matched.
insert into public.blocks (blocker_id, blocked_id)
  values ('00000000-0000-0000-0000-00000000000f', '00000000-0000-0000-0000-00000000000e');

select pg_temp.act_as('00000000-0000-0000-0000-00000000000a') \g /dev/null
do $$ begin
  perform pg_temp.check(public.join_queue() is null, 'with nobody else waiting, you stay in the queue');
end $$;
select pg_temp.act_as('00000000-0000-0000-0000-00000000000b') \g /dev/null
do $$ begin
  perform pg_temp.check(public.join_queue() is null, 'a pair below the minimum score is not matched');
end $$;
select pg_temp.act_as('00000000-0000-0000-0000-00000000000d') \g /dev/null
do $$ begin
  perform pg_temp.check(public.join_queue() is not null, 'joining the queue matches you straight away when someone fits');
end $$;
select pg_temp.act_as('00000000-0000-0000-0000-00000000000c') \g /dev/null
select public.join_queue() \g /dev/null
select pg_temp.act_as('00000000-0000-0000-0000-00000000000e') \g /dev/null
select public.join_queue() \g /dev/null
select pg_temp.act_as('00000000-0000-0000-0000-00000000000f') \g /dev/null
select public.join_queue() \g /dev/null
reset role;

do $$ begin
  perform pg_temp.check((pg_temp.match_of('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000d')).score = 100,
    'Ana and Dee are matched');
  perform pg_temp.check((pg_temp.match_of('00000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-00000000000c')).id is not null,
    'Ben and Cal are matched');
  perform pg_temp.check((pg_temp.match_of('00000000-0000-0000-0000-00000000000e', '00000000-0000-0000-0000-00000000000f')).id is null,
    'people who blocked each other are never matched');
  perform pg_temp.check((select matching_status from public.profiles where id = '00000000-0000-0000-0000-00000000000a') = 'inactive',
    'matched people leave the queue');
  perform pg_temp.check((select count(*) from public.matches) = 2, 'nobody else was matched');
end $$;

select pg_temp.act_as('00000000-0000-0000-0000-00000000000a') \g /dev/null
do $$ begin
  begin
    perform public.join_queue();
    raise exception 'FAILED: second match';
  exception when raise_exception then
    raise notice 'ok: one connection at a time';
  end;
end $$;

-- Chat ----------------------------------------------------------------------------

do $$
declare m uuid := (pg_temp.match_of('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000d')).id;
begin
  begin
    insert into public.messages (match_id, sender_id, body) values (m, auth.uid(), 'add me at https://example.com');
    raise exception 'FAILED: link sent';
  exception when raise_exception then
    raise notice 'ok: new members cannot send links';
  end;
  begin
    insert into public.messages (match_id, sender_id, body) values (m, auth.uid(), 'call me on 07700 900 123');
    raise exception 'FAILED: phone number sent';
  exception when raise_exception then
    raise notice 'ok: new members cannot send phone numbers';
  end;
  begin
    insert into public.messages (match_id, sender_id, body) values (m, auth.uid(), 'ok KYS');
    raise exception 'FAILED: blocked phrase sent';
  exception when raise_exception then
    raise notice 'ok: blocked phrases are refused';
  end;
  insert into public.messages (match_id, sender_id, body) values (m, auth.uid(), 'Honestly some days I want to die');
  insert into public.messages (match_id, sender_id, body, crisis) values (m, auth.uid(), 'Hi Dee, I''m around 2 today', true);
  perform pg_temp.check((select crisis from public.messages where body like 'Honestly%'), 'crisis words flag the message for help links');
  perform pg_temp.check(not (select crisis from public.messages where body like 'Hi Dee%'), 'only the server sets the crisis flag');
  perform pg_temp.check((select messages_a + messages_b from public.matches where id = m) = 2, 'messages are counted per person');
end $$;

select pg_temp.act_as('00000000-0000-0000-0000-00000000000d') \g /dev/null
do $$
declare m uuid := (select match_id from public.my_matches() limit 1);
begin
  perform pg_temp.check((select has_new from public.my_matches() where match_id = m), 'a new message shows a dot');
  perform public.mark_match_read(m);
  perform pg_temp.check(not (select has_new from public.my_matches() where match_id = m), 'opening the chat clears the dot');
  perform pg_temp.check((select trust_level from public.match_partner(m)) = 1, 'partners see each other''s trust level');
end $$;
select pg_temp.act_as('00000000-0000-0000-0000-00000000000a') \g /dev/null
do $$ begin
  perform pg_temp.check((select count(*) from public.match_reads) = 0, 'you cannot see when your partner last read the chat');
end $$;
reset role;

-- A two-sided conversation unlocks trust level 2 and links.
update public.matching_settings set feedback_message_threshold = 2;
select pg_temp.act_as('00000000-0000-0000-0000-00000000000d') \g /dev/null
insert into public.messages (match_id, sender_id, body)
  select id, auth.uid(), 'Hello!' from public.matches;
insert into public.messages (match_id, sender_id, body)
  select id, auth.uid(), 'How was your week?' from public.matches;
do $$ begin
  perform pg_temp.check((select trust_level from public.profiles) = 2, 'a two-sided conversation raises trust to level 2');
  insert into public.messages (match_id, sender_id, body)
    select id, auth.uid(), 'This is the hike: https://example.com/trail' from public.matches;
  raise notice 'ok: established members can share links';
end $$;
reset role;

-- Rate limit.
update public.matching_settings set messages_per_minute = 3;
select pg_temp.act_as('00000000-0000-0000-0000-00000000000a') \g /dev/null
do $$ begin
  insert into public.messages (match_id, sender_id, body) select id, auth.uid(), 'one' from public.matches;
  insert into public.messages (match_id, sender_id, body) select id, auth.uid(), 'two' from public.matches;
  insert into public.messages (match_id, sender_id, body) select id, auth.uid(), 'three' from public.matches;
  raise exception 'FAILED: rate limit';
exception when raise_exception then
  perform pg_temp.check(sqlerrm like '%very quickly%', 'sending too fast is slowed down');
end $$;
reset role;

-- Ending, re-matching, waiting boost, exploratory --------------------------------

-- Dee ends the match kindly; Ben blocks Cal.
select pg_temp.act_as('00000000-0000-0000-0000-00000000000d') \g /dev/null
select public.end_match((select id from public.matches where status = 'active' limit 1), 'Thanks for the chats!') \g /dev/null
select pg_temp.act_as('00000000-0000-0000-0000-00000000000b') \g /dev/null
select public.block_user('00000000-0000-0000-0000-00000000000c') \g /dev/null
select pg_temp.act_as('00000000-0000-0000-0000-00000000000c') \g /dev/null
do $$ begin
  perform pg_temp.check((select end_reason is null and status = 'ended' from public.matches), 'a blocked person sees the match ended, not why');
end $$;
select pg_temp.act_as('00000000-0000-0000-0000-00000000000a') \g /dev/null
do $$ begin
  perform pg_temp.check((select end_reason = 'Thanks for the chats!' and not ended_by_me from public.my_matches()), 'a Kind Exit note reaches the partner');
  perform pg_temp.check(public.join_queue() is null, 'Ana waits: Dee was already matched and Ben scores too low');
end $$;
select pg_temp.act_as('00000000-0000-0000-0000-00000000000d') \g /dev/null
select public.join_queue() \g /dev/null
select pg_temp.act_as('00000000-0000-0000-0000-00000000000b') \g /dev/null
select public.join_queue() \g /dev/null
reset role;
do $$ begin
  perform pg_temp.check((select count(*) from public.matches) = 2, 'an ended pair is never matched again');
end $$;

-- After 5 days in the queue Ana gets a 10-point boost, and pairs with Ben
-- ahead of Dee, who joined later.
update public.profiles set queued_at = now() - interval '5 days' where id = '00000000-0000-0000-0000-00000000000a';
select pg_temp.act_as('00000000-0000-0000-0000-00000000000a') \g /dev/null
do $$ begin
  perform pg_temp.check(public.find_match() is not null, 'waiting in the queue boosts your chances');
end $$;
reset role;
do $$ begin
  perform pg_temp.check((pg_temp.match_of('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000b')).exploratory = false,
    'the longest-waiting person is matched first');
end $$;

-- Exploratory: Cal and Dee score low, but an exploratory turn pairs them anyway.
update public.matching_settings set exploratory_share = 1;
select pg_temp.act_as('00000000-0000-0000-0000-00000000000c') \g /dev/null
select public.join_queue() \g /dev/null
reset role;
do $$ begin
  perform pg_temp.check((pg_temp.match_of('00000000-0000-0000-0000-00000000000c', '00000000-0000-0000-0000-00000000000d')).exploratory,
    'exploratory turns match regardless of score, and are marked');
end $$;

-- Reports -------------------------------------------------------------------------

update public.matching_settings set auto_pause_report_count = 1;
select pg_temp.act_as('00000000-0000-0000-0000-00000000000b') \g /dev/null
select public.report_user(
  (pg_temp.match_of('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000b')).id, 'harassment') \g /dev/null
do $$ begin
  perform pg_temp.check(not public.can_message((pg_temp.match_of('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000b')).id),
    'chat pauses once enough people report someone');
end $$;
select pg_temp.act_as('00000000-0000-0000-0000-00000000000a') \g /dev/null
do $$ begin
  perform pg_temp.check((select suspended_at is not null from public.profiles), 'the reported person is paused for review');
  begin
    update public.profiles set suspended_at = null;
    raise exception 'FAILED: lifted own suspension';
  exception when insufficient_privilege then
    raise notice 'ok: only admins can lift a pause';
  end;
end $$;
reset role;

\echo 'All checks passed.'
