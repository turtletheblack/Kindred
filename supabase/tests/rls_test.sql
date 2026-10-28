-- Privacy and safety checks for the schema. Run with scripts/test-db.sh.
-- Each block raises an exception if a rule is broken.
\set ON_ERROR_STOP 1
\set QUIET 1

-- Three users: Ana and Ben get matched, Cal is a stranger to both.
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'ana@example.com'),
  ('00000000-0000-0000-0000-00000000000b', 'ben@example.com'),
  ('00000000-0000-0000-0000-00000000000c', 'cal@example.com');

update public.profiles set display_name = 'Ana', contact = 'ana@chat', region = 'Leeds', timezone = 'Europe/London'
  where id = '00000000-0000-0000-0000-00000000000a';
update public.profiles set display_name = 'Ben' where id = '00000000-0000-0000-0000-00000000000b';

insert into public.test_results (user_id, answers, communication_scores, friendship_scores,
  primary_communication, secondary_communication, friendship) values
  ('00000000-0000-0000-0000-00000000000a', '[]', '{"IP": 50}', '{"SH": 60}', 'IP', 'RC', 'SH'),
  ('00000000-0000-0000-0000-00000000000b', '[]', '{"EP": 50}', '{"TL": 60}', 'EP', 'DC', 'TL');

insert into public.matches (id, user_a, user_b, score) values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000b', 72);

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

-- Reference data
do $$ begin
  perform pg_temp.check((select count(*) from public.compatibility) = 91, 'compatibility table has every badge pair');
  perform pg_temp.check((select bool_and(adjustment = 0) from public.compatibility), 'compatibility starts neutral');
  perform pg_temp.check((select count(*) from public.profiles) = 3, 'sign-up creates a hidden profile');
end $$;

-- Signed-out visitors see nothing
set role anon;
do $$ begin
  begin
    perform 1 from public.profiles;
    raise exception 'FAILED: anon read profiles';
  exception when insufficient_privilege then
    raise notice 'ok: signed-out visitors cannot read profiles';
  end;
end $$;
reset role;

-- Ana: only her own profile, and only personal fields are editable
select pg_temp.act_as('00000000-0000-0000-0000-00000000000a') \g /dev/null
do $$ begin
  perform pg_temp.check((select count(*) from public.profiles) = 1, 'a user sees only their own profile');
  perform pg_temp.check((select count(*) from public.test_results) = 1, 'a user sees only their own test results');
  update public.profiles set display_name = 'Ana B' where id = '00000000-0000-0000-0000-00000000000b';
  perform pg_temp.check(not found, 'a user cannot edit someone else''s profile');
  begin
    update public.profiles set trust_level = 3 where id = auth.uid();
    raise exception 'FAILED: raised own trust level';
  exception when insufficient_privilege then
    raise notice 'ok: a user cannot raise their own trust level';
  end;
  begin
    perform public.confirm_adult((current_date - interval '17 years')::date);
    raise exception 'FAILED: under-18 accepted';
  exception when raise_exception then
    raise notice 'ok: under-18 birth dates are refused';
  end;
  perform public.confirm_adult(date '1990-05-01');
  perform pg_temp.check((select adult_confirmed_at is not null from public.profiles), '18+ confirmation is recorded');
  begin
    update public.compatibility set adjustment = 10 where badge_a = 'IP' and badge_b = 'SH';
    perform pg_temp.check(not found, 'non-admins cannot change the compatibility table');
  end;
end $$;

-- Ben, before Ana reveals anything, sees only her badges
select pg_temp.act_as('00000000-0000-0000-0000-00000000000b') \g /dev/null
do $$
declare p record;
begin
  select * into p from public.match_partner('11111111-1111-1111-1111-111111111111');
  perform pg_temp.check(p.primary_communication = 'IP' and p.friendship = 'SH', 'a match partner sees badges');
  perform pg_temp.check(p.display_name is null and p.contact is null and p.region is null, 'name, contact and area stay hidden by default');
end $$;

-- Ana reveals her name (only) to Ben, and messages him
select pg_temp.act_as('00000000-0000-0000-0000-00000000000a') \g /dev/null
insert into public.match_reveals (match_id, user_id, reveal_name)
  values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-00000000000a', true);
insert into public.messages (match_id, sender_id, body)
  values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-00000000000a', 'Hi Ben!');

select pg_temp.act_as('00000000-0000-0000-0000-00000000000b') \g /dev/null
do $$
declare p record;
begin
  select * into p from public.match_partner('11111111-1111-1111-1111-111111111111');
  perform pg_temp.check(p.display_name = 'Ana' and p.contact is null, 'revealing the name shares only the name');
  perform pg_temp.check((select count(*) from public.messages) = 1, 'a match member can read the chat');
  perform pg_temp.check((select count(*) from public.match_reveals) = 0, 'a partner cannot read the other person''s reveal settings');
end $$;

-- Cal, a stranger, sees nothing about the match and can't post into it
select pg_temp.act_as('00000000-0000-0000-0000-00000000000c') \g /dev/null
do $$ begin
  perform pg_temp.check((select count(*) from public.matches) = 0, 'outsiders cannot see a match');
  perform pg_temp.check((select count(*) from public.messages) = 0, 'outsiders cannot read a chat');
  perform pg_temp.check((select count(*) from public.match_partner('11111111-1111-1111-1111-111111111111')) = 0, 'outsiders get nothing from match_partner');
  begin
    insert into public.messages (match_id, sender_id, body)
      values ('11111111-1111-1111-1111-111111111111', auth.uid(), 'hello');
    raise exception 'FAILED: outsider posted';
  exception when insufficient_privilege then
    raise notice 'ok: outsiders cannot post into a chat';
  end;
  begin
    insert into public.match_reveals (match_id, user_id, reveal_name)
      values ('11111111-1111-1111-1111-111111111111', auth.uid(), true);
    raise exception 'FAILED: outsider added reveal';
  exception when insufficient_privilege then
    raise notice 'ok: outsiders cannot attach reveal settings to a match';
  end;
end $$;

-- Ben reports one of Ana's messages, then blocks her
select pg_temp.act_as('00000000-0000-0000-0000-00000000000b') \g /dev/null
do $$ begin
  perform public.report_user('11111111-1111-1111-1111-111111111111', 'harassment', null,
    (select id from public.messages limit 1));
  perform pg_temp.check((select message_snapshot = 'Hi Ben!' from public.reports), 'a report keeps a server-side copy of the message');
  begin
    insert into public.reports (reporter_id, reason) values (auth.uid(), 'fake');
    raise exception 'FAILED: direct report insert';
  exception when insufficient_privilege then
    raise notice 'ok: reports can only be filed through report_user';
  end;
  perform public.block_user('00000000-0000-0000-0000-00000000000a');
  perform pg_temp.check((select status = 'ended' from public.matches), 'blocking ends the match');
  perform pg_temp.check(not public.can_message('11111111-1111-1111-1111-111111111111'), 'nobody can message after a block');
end $$;

select pg_temp.act_as('00000000-0000-0000-0000-00000000000a') \g /dev/null
do $$ begin
  perform pg_temp.check((select count(*) from public.reports) = 0, 'the reported person cannot see the report');
  perform pg_temp.check((select count(*) from public.blocks) = 0, 'the blocked person cannot see the block');
end $$;

-- The pair can never be matched again
reset role;
do $$ begin
  begin
    insert into public.matches (user_a, user_b) values
      ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000b');
    raise exception 'FAILED: re-match';
  exception when unique_violation then
    raise notice 'ok: an ended pair can never be re-matched';
  end;
end $$;

-- Ana deletes her account
select pg_temp.act_as('00000000-0000-0000-0000-00000000000a') \g /dev/null
select public.delete_my_account() \g /dev/null
reset role;
do $$ begin
  perform pg_temp.check(not exists (select 1 from auth.users where id = '00000000-0000-0000-0000-00000000000a'), 'account deletion removes the sign-in');
  perform pg_temp.check(not exists (select 1 from public.profiles where id = '00000000-0000-0000-0000-00000000000a'), 'account deletion removes the profile');
  perform pg_temp.check(not exists (select 1 from public.messages), 'account deletion removes the chats');
  perform pg_temp.check((select reported_id is null and message_snapshot is not null from public.reports), 'reports survive deletion without the person''s id');
end $$;

\echo 'All checks passed.'
