-- "Not now" on the pulse and bridge cards hid them for pulse_hours and
-- bridge_days. With those set low for testing, the card came straight back.
-- They now hide for a fixed 3 days (pulse) and 7 days (bridge).
create or replace function public.snooze_prompt(p_match uuid, p_kind text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  hide_for interval;
begin
  if not public.is_match_member(p_match) then
    raise exception 'match not found';
  end if;
  hide_for := case p_kind
    when 'checkin' then interval '2 days'
    when 'health' then interval '7 days'
    when 'pulse' then interval '3 days'
    when 'bridge' then interval '7 days'
    else null
  end;
  insert into public.prompt_snoozes (match_id, user_id, kind, until)
    values (p_match, auth.uid(), p_kind, coalesce(now() + hide_for, 'infinity'))
    on conflict (match_id, user_id, kind) do update set until = excluded.until;
end;
$$;
