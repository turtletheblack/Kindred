-- Gentle prompts are opt-in: off for new accounts. Home offers them once,
-- after the test, and remembers the answer either way.
alter table public.profiles alter column gentle_prompts set default false;
alter table public.profiles add column gentle_prompts_asked boolean not null default false;
grant update (gentle_prompts_asked) on public.profiles to authenticated;
