import { getCalendars } from 'expo-localization';

import { supabase } from './supabase';

export type Profile = {
  id: string;
  display_name: string | null;
  contact: string | null;
  region: string | null;
  timezone: string | null;
  adult_confirmed_at: string | null;
  trust_level: number;
};

export type ProfileEdits = Pick<Profile, 'display_name' | 'contact' | 'region' | 'timezone'>;

export type RevealSettings = {
  reveal_name: boolean;
  reveal_contact: boolean;
  reveal_region: boolean;
};

export function deviceTimezone() {
  return getCalendars()[0]?.timeZone ?? null;
}

export async function getMyProfile() {
  const { data, error } = await supabase
    .from('profiles')
    .select('id, display_name, contact, region, timezone, adult_confirmed_at, trust_level')
    .single();
  if (error) throw error;
  return data as Profile;
}

export async function updateMyProfile(id: string, edits: ProfileEdits) {
  const { error } = await supabase.from('profiles').update(edits).eq('id', id);
  if (error) throw error;
}

// birthDate is YYYY-MM-DD. The server checks 18+ and stores only that it passed.
export async function confirmAdult(birthDate: string) {
  const { error } = await supabase.rpc('confirm_adult', { p_birth_date: birthDate });
  if (error) throw error;
}

// Choose what one specific match can see about you.
export async function setReveal(matchId: string, userId: string, settings: RevealSettings) {
  const { error } = await supabase
    .from('match_reveals')
    .upsert({ match_id: matchId, user_id: userId, ...settings });
  if (error) throw error;
}
