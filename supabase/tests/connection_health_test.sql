-- Checks for chat limits, the check-in, connection health, prompt cards and
-- the someone-who-matters survey. Run with scripts/test-db.sh.
\set ON_ERROR_STOP 1
\set QUIET 1

-- Ana and Dee, Ben and Cal, Eve and Fay: three pairs who communicate alike.
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'ana@example.com'),
  ('00000000-0000-0000-0000-00000000000b', 'ben@example.com'),
  ('00000000-0000-0000-0000-00000000000c', 'cal@example.com'),
  ('00000000-0000-0000-0000-00000000000d', 'dee@example.com'),
  ('00000000-0000-0000-0000-00000000000e', 'eve@example.com'),
  ('00000000-0000-0000-0000-00000000000f', 'fay@example.com');

update public.matching_settings set exploratory_share = 0, feedback_message_threshold = 2;

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

create function pg_temp.answers(picks text[]) returns jsonb language sql as $$
  select jsonb_object_agg(o.question_id::text, o.id)
  from unnest(picks) with ordinality as p(badge, n)
  join public.test_options o on o.question_id = p.n and o.badge = p.badge;
$$;

create function pg_temp.onboard(p_user text, picks text[]) returns void language plpgsql as $$
declare a jsonb := pg_temp.answers(picks);
begin
  perform pg_temp.act_as(p_user);
  perform public.confirm_adult(date '1990-01-01');
  perform public.submit_test(a);
  perform public.join_queue();
  execute 'reset role';
end;
$$;

create function pg_temp.match_of(p_a text, p_b text) returns uuid language sql as $$
  select id from public.matches where user_a = least(p_a, p_b)::uuid and user_b = greatest(p_a, p_b)::uuid;
$$;

-- Sends n messages from one person in a match.
create function pg_temp.say(p_user text, p_match uuid, n int) returns void language plpgsql as $$
begin
  perform pg_temp.act_as(p_user);
  for i in 1..n loop
    insert into public.messages (match_id, sender_id, body) values (p_match, auth.uid(), 'message ' || i);
  end loop;
  execute 'reset role';
end;
$$;

create function pg_temp.prompt(p_user text, p_match uuid) returns text language plpgsql as $$
declare r text;
begin
  perform pg_temp.act_as(p_user);
  select prompt into r from public.match_prompts(p_match);
  execute 'reset role';
  return r;
end;
$$;

select pg_temp.onboard('00000000-0000-0000-0000-00000000000a',
  array['IP','IP','IP','IP','IP','IP','IP','IP','IP', 'SH','SH','SH','SH','SH','SH','SH','SH','SH']) \g /dev/null
select pg_temp.onboard('00000000-0000-0000-0000-00000000000d',
  array['IP','IP','IP','IP','IP','IP','IP','IP','IP', 'SH','SH','SH','SH','SH','SH','SH','SH','SH']) \g /dev/null
select pg_temp.onboard('00000000-0000-0000-0000-00000000000b',
  array['DC','DC','DC','DC','DC','DC','DC','DC','DC', 'TA','TA','TA','TA','TA','TA','TA','TA','TA']) \g /dev/null
select pg_temp.onboard('00000000-0000-0000-0000-00000000000c',
  array['DC','DC','DC','DC','DC','DC','DC','DC','DC', 'TA','TA','TA','TA','TA','TA','TA','TA','TA']) \g /dev/null
select pg_temp.onboard('00000000-0000-0000-0000-00000000000e',
  array['EC','EC','EC','EC','EC','EC','EC','EC','EC', 'TE','TE','TE','TE','TE','TE','TE','TE','TE']) \g /dev/null
select pg_temp.onboard('00000000-0000-0000-0000-00000000000f',
  array['EC','EC','EC','EC','EC','EC','EC','EC','EC', 'TE','TE','TE','TE','TE','TE','TE','TE','TE']) \g /dev/null

do $$ begin
  perform pg_temp.check((select count(*) from public.matches) = 3, 'three pairs are matched');
end $$;

-- Chat limits --------------------------------------------------------------------

select pg_temp.act_as('00000000-0000-0000-0000-00000000000a') \g /dev/null
do $$ begin
  perform public.join_queue();
  perform pg_temp.check((select matching_status = 'queued' from public.profiles),
    'with the default limit of 3 you can look for another match while chatting');
  perform public.leave_queue();
  update public.profiles set chat_limit = 1;
  begin
    perform public.join_queue();
    raise exception 'FAILED: went over own limit';
  exception when raise_exception then
    perform pg_temp.check(sqlerrm like '%limit of 1 chats%', 'your own chat limit is respected');
  end;
  update public.profiles set chat_limit = null;
  begin
    update public.profiles set trust_level = 3;
    raise exception 'FAILED: changed trust level';
  exception when insufficient_privilege then
    raise notice 'ok: you can set your chat limit but still not your trust level';
  end;
end $$;
reset role;

-- The pulse ---------------------------------------------------------------------

do $$
declare m uuid := pg_temp.match_of('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000d');
begin
  perform pg_temp.check(pg_temp.prompt('00000000-0000-0000-0000-00000000000a', m) is null,
    'a brand new match shows no card');
  update public.matches set created_at = now() - interval '73 hours' where id = m;
  perform pg_temp.check(pg_temp.prompt('00000000-0000-0000-0000-00000000000a', m) = 'pulse'
    and pg_temp.prompt('00000000-0000-0000-0000-00000000000d', m) = 'pulse',
    'after 72 quiet hours both people get the pulse');
  perform pg_temp.check((select status = 'active' from public.matches where id = m), 'the pulse never ends a match');

  perform pg_temp.act_as('00000000-0000-0000-0000-00000000000a');
  perform public.snooze_prompt(m, 'pulse');
  update public.profiles set gentle_prompts = false where id = '00000000-0000-0000-0000-00000000000d';
  execute 'reset role';
  perform pg_temp.check(pg_temp.prompt('00000000-0000-0000-0000-00000000000a', m) is null, '"Not now" hides the pulse');
  perform pg_temp.check(pg_temp.prompt('00000000-0000-0000-0000-00000000000d', m) = 'pulse',
    'you can''t turn off someone else''s prompts');
  update public.profiles set gentle_prompts = false where id = '00000000-0000-0000-0000-00000000000d';
  perform pg_temp.check(pg_temp.prompt('00000000-0000-0000-0000-00000000000d', m) is null,
    'turning gentle prompts off hides the pulse');
  update public.profiles set gentle_prompts = true where id = '00000000-0000-0000-0000-00000000000d';
end $$;

-- The check-in -------------------------------------------------------------------

do $$
declare
  ad uuid := pg_temp.match_of('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000d');
  bc uuid := pg_temp.match_of('00000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-00000000000c');
  ef uuid := pg_temp.match_of('00000000-0000-0000-0000-00000000000e', '00000000-0000-0000-0000-00000000000f');
  r text;
begin
  perform pg_temp.say('00000000-0000-0000-0000-00000000000a', ad, 2);
  perform pg_temp.act_as('00000000-0000-0000-0000-00000000000a');
  begin
    perform public.answer_checkin(ad, true);
    raise exception 'FAILED: early check-in';
  exception when raise_exception then
    perform pg_temp.check(sqlerrm like '%each sent 2 messages%', 'the check-in waits until you''ve both talked');
  end;
  begin
    insert into public.checkins (match_id, user_id, enjoyed) values (ad, auth.uid(), true);
    raise exception 'FAILED: direct check-in insert';
  exception when insufficient_privilege then
    raise notice 'ok: check-ins go through answer_checkin';
  end;
  execute 'reset role';

  perform pg_temp.say('00000000-0000-0000-0000-00000000000d', ad, 2);
  perform pg_temp.check(pg_temp.prompt('00000000-0000-0000-0000-00000000000a', ad) = 'checkin',
    'after 2 messages each, the check-in is asked');

  -- Ana and Dee both say yes.
  perform pg_temp.act_as('00000000-0000-0000-0000-00000000000a');
  perform pg_temp.check((select ladder from public.match_prompts(ad)) = 2, 'deeper questions open at the check-in point');
  r := public.answer_checkin(ad, true);
  perform pg_temp.check(r = 'answered', 'the first answer reveals nothing');
  begin
    perform public.answer_checkin(ad, false);
    raise exception 'FAILED: answered twice';
  exception when raise_exception then
    raise notice 'ok: you answer the check-in once';
  end;
  perform pg_temp.act_as('00000000-0000-0000-0000-00000000000d');
  perform pg_temp.check((select count(*) from public.checkins) = 0, 'you can''t see your match''s check-in answer');
  r := public.answer_checkin(ad, true);
  perform pg_temp.check(r = 'both_yes', 'when you both say yes, you both find out');
  perform pg_temp.check((select ladder = 3 and prompt = 'strengthened' from public.match_prompts(ad)),
    'both yes strengthens the match and opens the deepest questions');
  perform public.snooze_prompt(ad, 'strengthened');
  perform pg_temp.check((select prompt from public.match_prompts(ad)) is null, 'the both-yes note shows once');
  execute 'reset role';

  -- Ben says yes, Cal says no.
  perform pg_temp.say('00000000-0000-0000-0000-00000000000b', bc, 2);
  perform pg_temp.say('00000000-0000-0000-0000-00000000000c', bc, 2);
  perform pg_temp.act_as('00000000-0000-0000-0000-00000000000b');
  perform public.answer_checkin(bc, true);
  perform pg_temp.act_as('00000000-0000-0000-0000-00000000000c');
  r := public.answer_checkin(bc, false);
  perform pg_temp.check(r = 'answered', 'a mixed answer is never revealed to the second person');
  begin
    perform public.checkin_result(bc);
    raise exception 'FAILED: read mixed result';
  exception when insufficient_privilege then
    raise notice 'ok: the app can''t ask for the raw result';
  end;
  begin
    perform public.mutual_exit(bc);
    raise exception 'FAILED: mutual exit on mixed answers';
  exception when raise_exception then
    raise notice 'ok: a mixed answer offers no mutual exit';
  end;
  perform pg_temp.act_as('00000000-0000-0000-0000-00000000000b');
  perform pg_temp.check((select checkin = 'answered' and ladder = 2 and prompt is null from public.match_prompts(bc)),
    'a mixed answer changes nothing for the first person either');
  execute 'reset role';
  perform pg_temp.check(public.checkin_result(bc) = 'mixed', 'the mixed result is kept for tuning');

  -- Eve and Fay both say no; Eve ends it for both.
  perform pg_temp.say('00000000-0000-0000-0000-00000000000e', ef, 2);
  perform pg_temp.say('00000000-0000-0000-0000-00000000000f', ef, 2);
  perform pg_temp.act_as('00000000-0000-0000-0000-00000000000e');
  perform public.answer_checkin(ef, false);
  perform pg_temp.act_as('00000000-0000-0000-0000-00000000000f');
  perform pg_temp.check(public.answer_checkin(ef, false) = 'both_no', 'when you both say no, you both find out');
  perform pg_temp.act_as('00000000-0000-0000-0000-00000000000e');
  perform pg_temp.check((select prompt from public.match_prompts(ef)) = 'mutual', 'both no offers a mutual exit');
  perform public.mutual_exit(ef);
  perform pg_temp.act_as('00000000-0000-0000-0000-00000000000f');
  perform pg_temp.check((select status = 'ended' and ended_mutually and end_reason is null from public.my_matches()),
    'a mutual exit ends the match for both, with no blame');
  execute 'reset role';
end $$;

-- Bridge, health, deepen ----------------------------------------------------------

do $$
declare ad uuid := pg_temp.match_of('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000d');
begin
  perform pg_temp.act_as('00000000-0000-0000-0000-00000000000a');
  perform public.snooze_prompt(ad, 'strengthened');
  execute 'reset role';

  update public.matches set last_message_at = now() - interval '15 days' where id = ad;
  perform pg_temp.check(pg_temp.prompt('00000000-0000-0000-0000-00000000000a', ad) = 'bridge',
    'two quiet weeks after a real conversation brings the bridge');

  update public.matches set last_message_at = now(), created_at = now() - interval '15 days' where id = ad;
  perform pg_temp.check(pg_temp.prompt('00000000-0000-0000-0000-00000000000a', ad) = 'health',
    'after two weeks you''re asked how the connection feels');

  perform pg_temp.act_as('00000000-0000-0000-0000-00000000000a');
  begin
    perform public.answer_health_check(ad, 'amazing');
    raise exception 'FAILED: odd answer';
  exception when check_violation then
    raise notice 'ok: health answers are one of the offered choices';
  end;
  perform public.answer_health_check(ad, 'growing', 'balanced');
  perform pg_temp.check((select prompt from public.match_prompts(ad)) is null, 'health is asked again only after a month');
  perform pg_temp.act_as('00000000-0000-0000-0000-00000000000d');
  perform pg_temp.check((select count(*) from public.health_checks) = 0, 'your match never sees your health answers');
  execute 'reset role';

  update public.matches set created_at = now() - interval '22 days' where id = ad;
  perform pg_temp.check(pg_temp.prompt('00000000-0000-0000-0000-00000000000a', ad) = 'deepen',
    'a strong match gets the suggestion to try something new together');
  perform pg_temp.act_as('00000000-0000-0000-0000-00000000000a');
  perform public.snooze_prompt(ad, 'deepen');
  perform pg_temp.check((select prompt from public.match_prompts(ad)) is null, 'the deepen card goes away for good');
  perform pg_temp.check((select count(*) from public.conversation_prompts) > 20, 'conversation questions are readable');
  execute 'reset role';
end $$;

-- Someone who matters -------------------------------------------------------------

select pg_temp.act_as('00000000-0000-0000-0000-00000000000a') \g /dev/null
do $$ begin
  perform pg_temp.check(public.matters_due() is null, 'new members aren''t asked yet');
end $$;
reset role;
update public.profiles set created_at = now() - interval '31 days' where id = '00000000-0000-0000-0000-00000000000a';
select pg_temp.act_as('00000000-0000-0000-0000-00000000000a') \g /dev/null
do $$ begin
  perform pg_temp.check(public.matters_due() = 30, 'at 30 days you''re asked');
  perform public.snooze_matters();
  perform pg_temp.check(public.matters_due() is null, '"Ask me later" waits a few days');
end $$;
reset role;
update public.profiles set survey_snoozed_until = null where id = '00000000-0000-0000-0000-00000000000a';
select pg_temp.act_as('00000000-0000-0000-0000-00000000000a') \g /dev/null
do $$ begin
  begin
    perform public.answer_matters(90, 'yes');
    raise exception 'FAILED: answered a future wave';
  exception when raise_exception then
    raise notice 'ok: only the open wave can be answered';
  end;
  perform public.answer_matters(30, 'not_yet');
  perform pg_temp.check(public.matters_due() is null, 'each wave is asked once');
  begin
    perform public.matters_results();
    raise exception 'FAILED: non-admin read results';
  exception when raise_exception then
    raise notice 'ok: only admins see the totals';
  end;
end $$;
reset role;
update public.profiles set created_at = now() - interval '400 days' where id = '00000000-0000-0000-0000-00000000000a';
select pg_temp.act_as('00000000-0000-0000-0000-00000000000a') \g /dev/null
do $$ begin
  perform pg_temp.check(public.matters_due() = 365, 'after a long absence only the latest wave is asked');
  perform public.answer_matters(365, 'yes');
end $$;
reset role;

update public.profiles set is_admin = true where id = '00000000-0000-0000-0000-00000000000b';
select pg_temp.act_as('00000000-0000-0000-0000-00000000000b') \g /dev/null
do $$ begin
  perform pg_temp.check((select people from public.matters_results() where wave = 365 and answer = 'yes') = 1,
    'admins see how many people met someone who matters');
  perform pg_temp.check((select count(*) from public.checkin_results()) = 3, 'admins see check-in results by score');
end $$;
reset role;

select pg_temp.act_as('00000000-0000-0000-0000-00000000000a') \g /dev/null
select public.delete_my_account() \g /dev/null
reset role;
do $$ begin
  perform pg_temp.check((select count(*) from public.matters_answers where user_id is null) = 2,
    'survey answers are kept without the person''s id after account deletion');
  perform pg_temp.check((select count(*) from public.health_checks) = 0, 'health answers are deleted with the account');
end $$;

\echo 'All checks passed.'
