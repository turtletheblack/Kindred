-- Kindred initial schema.
--
-- Privacy model: every account is hidden. A user's own profile row is only
-- readable by that user. A match partner sees badges always, and name,
-- contact and area only for the fields the user has revealed to that one
-- match (see match_reveals and match_partner()).

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Badges
-- ---------------------------------------------------------------------------

create type public.badge_kind as enum ('communication', 'friendship');

create table public.badges (
  code text primary key,
  kind public.badge_kind not null,
  name text not null,
  description text not null
);

insert into public.badges (code, kind, name, description) values
  ('IP', 'communication', 'Internal Processor', 'Reflective, needs time to think'),
  ('EP', 'communication', 'External Processor', 'Thinks out loud, clarifies by talking'),
  ('DC', 'communication', 'Direct Communicator', 'Clear, efficient, solution-focused'),
  ('RC', 'communication', 'Relational Communicator', 'Emotion-first, validating, warm'),
  ('AC', 'communication', 'Analytical Communicator', 'Structured, precise, detail-oriented'),
  ('EC', 'communication', 'Expressive Communicator', 'Energetic, big-picture, story-driven'),
  ('TL', 'friendship', 'The Listener', 'Bonds through active listening'),
  ('DD', 'friendship', 'Deep Diver', 'Prefers meaning over small talk'),
  ('TA', 'friendship', 'The Adventurer', 'Bonds through shared experiences'),
  ('TE', 'friendship', 'The Energizer', 'Brings social energy'),
  ('SH', 'friendship', 'Safe Harbor', 'Provides emotional safety'),
  ('TC', 'friendship', 'The Consistent', 'Routine, reliability'),
  ('TB', 'friendship', 'The Builder', 'Growth, goals, self-improvement');

-- Editable compatibility table. One row per unordered pair of badges
-- (badge_a <= badge_b), including a badge paired with itself. Every
-- adjustment starts at 0 (neutral); admins tune it from check-in data
-- without changing code.
create table public.compatibility (
  badge_a text not null references public.badges (code),
  badge_b text not null references public.badges (code),
  adjustment numeric(5, 2) not null default 0 check (adjustment between -50 and 50),
  note text,
  updated_at timestamptz not null default now(),
  primary key (badge_a, badge_b),
  check (badge_a <= badge_b)
);

insert into public.compatibility (badge_a, badge_b)
select a.code, b.code
from public.badges a
join public.badges b on a.code <= b.code;

-- Matching settings that would otherwise be hard-coded.
create table public.matching_settings (
  id boolean primary key default true check (id),
  min_score numeric(5, 2) not null default 60,
  exploratory_share numeric(4, 3) not null default 0.10 check (exploratory_share between 0 and 1),
  feedback_message_threshold int not null default 15,
  retake_cooldown interval not null default interval '90 days'
);

insert into public.matching_settings default values;

-- ---------------------------------------------------------------------------
-- Profiles (private)
-- ---------------------------------------------------------------------------

create type public.matching_status as enum ('inactive', 'queued', 'paused');

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text check (char_length(display_name) <= 50),
  contact text check (char_length(contact) <= 200),
  region text check (char_length(region) <= 100),
  timezone text check (char_length(timezone) <= 64),
  adult_confirmed_at timestamptz,
  trust_level smallint not null default 0 check (trust_level between 0 and 3),
  matching_status public.matching_status not null default 'inactive',
  queued_at timestamptz,
  is_admin boolean not null default false,
  last_active_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create function public.set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger profiles_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();

create trigger compatibility_updated_at before update on public.compatibility
  for each row execute function public.set_updated_at();

-- Every new sign-in gets an empty, hidden profile.
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id) values (new.id);
  return new;
end;
$$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

create function public.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false);
$$;

-- ---------------------------------------------------------------------------
-- Test results
-- ---------------------------------------------------------------------------

-- Each test taken is kept, so retakes show how someone changes over time.
-- The newest row is the user's current result.
create table public.test_results (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  answers jsonb not null,
  -- Percentage per badge code, e.g. {"IP": 44.4, "EP": 22.2, ...}.
  communication_scores jsonb not null,
  friendship_scores jsonb not null,
  primary_communication text not null references public.badges (code),
  secondary_communication text not null references public.badges (code),
  friendship text not null references public.badges (code),
  taken_at timestamptz not null default now(),
  check (primary_communication <> secondary_communication)
);

create index test_results_user_taken on public.test_results (user_id, taken_at desc);

create view public.current_test_results with (security_invoker = true) as
select distinct on (user_id) *
from public.test_results
order by user_id, taken_at desc;

-- ---------------------------------------------------------------------------
-- Matches, reveal settings, messages
-- ---------------------------------------------------------------------------

create type public.match_status as enum ('active', 'paused', 'ended');

create table public.matches (
  id uuid primary key default gen_random_uuid(),
  user_a uuid references public.profiles (id) on delete cascade,
  user_b uuid references public.profiles (id) on delete cascade,
  status public.match_status not null default 'active',
  score numeric(5, 2),
  exploratory boolean not null default false,
  created_at timestamptz not null default now(),
  last_message_at timestamptz,
  ended_at timestamptz,
  ended_by uuid references public.profiles (id) on delete set null,
  end_reason text,
  check (user_a < user_b)
);

-- One row per pair, ever: an ended match blocks the pair from being matched again.
create unique index matches_pair on public.matches (user_a, user_b);
create index matches_user_b on public.matches (user_b);

create function public.is_match_member(p_match uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.matches
    where id = p_match and auth.uid() in (user_a, user_b)
  );
$$;

-- What each person has chosen to show one specific match. Nothing is shared
-- until the user turns it on.
create table public.match_reveals (
  match_id uuid not null references public.matches (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  reveal_name boolean not null default false,
  reveal_contact boolean not null default false,
  reveal_region boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (match_id, user_id)
);

create trigger match_reveals_updated_at before update on public.match_reveals
  for each row execute function public.set_updated_at();

create table public.messages (
  id bigint generated always as identity primary key,
  match_id uuid not null references public.matches (id) on delete cascade,
  sender_id uuid references public.profiles (id) on delete set null,
  body text not null check (char_length(body) between 1 and 4000),
  created_at timestamptz not null default now()
);

create index messages_match_created on public.messages (match_id, created_at);

create function public.touch_match_on_message() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update public.matches set last_message_at = new.created_at where id = new.match_id;
  update public.profiles set last_active_at = new.created_at where id = new.sender_id;
  return new;
end;
$$;

create trigger messages_touch_match after insert on public.messages
  for each row execute function public.touch_match_on_message();

-- ---------------------------------------------------------------------------
-- Feedback, blocks, reports
-- ---------------------------------------------------------------------------

-- "Did you enjoy this conversation?" Stored per person per match, so it can
-- later be compared against both people's scores to tune the compatibility table.
create table public.checkins (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  kind text not null default 'enjoyed',
  enjoyed boolean not null,
  note text check (char_length(note) <= 2000),
  created_at timestamptz not null default now(),
  unique (match_id, user_id, kind)
);

create table public.blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

-- True when the caller is in this match, it's active, and neither person
-- has blocked the other.
create function public.can_message(p_match uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.matches m
    where m.id = p_match
      and m.status = 'active'
      and auth.uid() in (m.user_a, m.user_b)
      and not exists (
        select 1 from public.blocks b
        where (b.blocker_id = m.user_a and b.blocked_id = m.user_b)
           or (b.blocker_id = m.user_b and b.blocked_id = m.user_a)
      )
  );
$$;

create type public.report_status as enum ('open', 'reviewing', 'actioned', 'dismissed');

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid references public.profiles (id) on delete set null,
  reported_id uuid references public.profiles (id) on delete set null,
  match_id uuid references public.matches (id) on delete set null,
  message_id bigint references public.messages (id) on delete set null,
  reason text not null check (char_length(reason) <= 100),
  details text check (char_length(details) <= 4000),
  -- A copy of the reported message, kept even if the chat is later deleted.
  message_snapshot text,
  status public.report_status not null default 'open',
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

alter table public.badges enable row level security;
alter table public.compatibility enable row level security;
alter table public.matching_settings enable row level security;
alter table public.profiles enable row level security;
alter table public.test_results enable row level security;
alter table public.matches enable row level security;
alter table public.match_reveals enable row level security;
alter table public.messages enable row level security;
alter table public.checkins enable row level security;
alter table public.blocks enable row level security;
alter table public.reports enable row level security;

-- Signed-out visitors get nothing.
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke execute on all functions in schema public from anon, public;

-- Reference data: readable when signed in, editable by admins.
create policy "badges readable" on public.badges
  for select to authenticated using (true);

create policy "compatibility readable" on public.compatibility
  for select to authenticated using (true);
create policy "compatibility admin update" on public.compatibility
  for update to authenticated using (public.is_admin()) with check (public.is_admin());

create policy "settings readable" on public.matching_settings
  for select to authenticated using (true);
create policy "settings admin update" on public.matching_settings
  for update to authenticated using (public.is_admin()) with check (public.is_admin());

-- Profiles: only your own row, and only the personal fields. Trust level,
-- admin flag, 18+ confirmation and queue position are set by server functions.
create policy "own profile read" on public.profiles
  for select to authenticated using (id = auth.uid());
create policy "own profile update" on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

revoke insert, update, delete on public.profiles from authenticated;
grant update (display_name, contact, region, timezone)
  on public.profiles to authenticated;

-- Test results: your own only.
create policy "own results read" on public.test_results
  for select to authenticated using (user_id = auth.uid());
create policy "own results insert" on public.test_results
  for insert to authenticated with check (user_id = auth.uid());
revoke update, delete on public.test_results from authenticated;

-- Matches: visible to the two people in them. Created and ended only
-- through server functions.
create policy "member reads match" on public.matches
  for select to authenticated using (auth.uid() in (user_a, user_b));
revoke insert, update, delete on public.matches from authenticated;

-- Reveal settings: you manage your own for matches you're in.
create policy "own reveal read" on public.match_reveals
  for select to authenticated using (user_id = auth.uid());
create policy "own reveal insert" on public.match_reveals
  for insert to authenticated
  with check (user_id = auth.uid() and public.is_match_member(match_id));
create policy "own reveal update" on public.match_reveals
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid() and public.is_match_member(match_id));
revoke delete on public.match_reveals from authenticated;

-- Messages: members read; members send only while the match is active and
-- neither person has blocked the other. No edits, so no "seen" tracking either.
create policy "member reads messages" on public.messages
  for select to authenticated using (public.is_match_member(match_id));
create policy "member sends message" on public.messages
  for insert to authenticated
  with check (sender_id = auth.uid() and public.can_message(match_id));
revoke update, delete on public.messages from authenticated;

-- Check-ins: your own answers only; the partner never sees them.
create policy "own checkins read" on public.checkins
  for select to authenticated using (user_id = auth.uid());
create policy "own checkins insert" on public.checkins
  for insert to authenticated
  with check (user_id = auth.uid() and public.is_match_member(match_id));
revoke update, delete on public.checkins from authenticated;

-- Blocks: manage your own list.
create policy "own blocks read" on public.blocks
  for select to authenticated using (blocker_id = auth.uid());
create policy "own blocks insert" on public.blocks
  for insert to authenticated with check (blocker_id = auth.uid());
create policy "own blocks delete" on public.blocks
  for delete to authenticated using (blocker_id = auth.uid());
revoke update on public.blocks from authenticated;

-- Reports: filed through report_user(), so the message copy can't be faked.
-- You see your own; admins see and handle all.
create policy "own reports read" on public.reports
  for select to authenticated using (reporter_id = auth.uid() or public.is_admin());
create policy "admin handles reports" on public.reports
  for update to authenticated using (public.is_admin()) with check (public.is_admin());
revoke insert, delete on public.reports from authenticated;

-- ---------------------------------------------------------------------------
-- Functions the app calls
-- ---------------------------------------------------------------------------

-- 18+ self-attestation. The birth date is checked but not stored.
create function public.confirm_adult(p_birth_date date) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;
  if p_birth_date > (current_date - interval '18 years') then
    raise exception 'Kindred is for adults 18 and over';
  end if;
  update public.profiles set adult_confirmed_at = now() where id = auth.uid();
end;
$$;

-- What you can see about your partner in one match: their badges always,
-- and name, contact and area only if they've revealed them to you.
create function public.match_partner(p_match uuid)
returns table (
  partner_id uuid,
  primary_communication text,
  secondary_communication text,
  friendship text,
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
    case when r.reveal_name then p.display_name end,
    case when r.reveal_contact then p.contact end,
    case when r.reveal_region then p.region end,
    case when r.reveal_region then p.timezone end
  from m
  join public.profiles p on p.id = m.partner
  left join public.current_test_results t on t.user_id = p.id
  left join public.match_reveals r on r.match_id = p_match and r.user_id = p.id;
$$;

-- Block someone: records the block and ends any match with them.
create function public.block_user(p_user uuid) returns void
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
    set status = 'ended', ended_at = now(), ended_by = me, end_reason = 'blocked'
    where user_a = least(me, p_user) and user_b = greatest(me, p_user)
      and status <> 'ended';
end;
$$;

-- End a match (soft delete). The pair is never matched again.
create function public.end_match(p_match uuid, p_reason text default null) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.matches
    set status = 'ended', ended_at = now(), ended_by = auth.uid(), end_reason = left(p_reason, 200)
    where id = p_match and auth.uid() in (user_a, user_b) and status <> 'ended';
  if not found then
    raise exception 'match not found';
  end if;
end;
$$;

-- Report someone you're matched with, optionally pointing at one message.
create function public.report_user(
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
  return new_id;
end;
$$;

-- Permanently delete your own account and everything tied to it. Reports
-- you filed or that name you are kept with the name removed, for safety review.
create function public.delete_my_account() returns void
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'not signed in';
  end if;
  delete from auth.users where id = me;
end;
$$;

grant execute on function public.is_admin() to authenticated;
grant execute on function public.is_match_member(uuid) to authenticated;
grant execute on function public.can_message(uuid) to authenticated;
grant execute on function public.report_user(uuid, text, text, bigint) to authenticated;
grant execute on function public.confirm_adult(date) to authenticated;
grant execute on function public.match_partner(uuid) to authenticated;
grant execute on function public.block_user(uuid) to authenticated;
grant execute on function public.end_match(uuid, text) to authenticated;
grant execute on function public.delete_my_account() to authenticated;
