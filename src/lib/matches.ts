import { supabase } from './supabase';
import type { RevealSettings } from './profile';

export type MatchSummary = {
  match_id: string;
  status: 'active' | 'paused' | 'ended';
  created_at: string;
  ended_at: string | null;
  ended_by_me: boolean;
  ended_mutually: boolean;
  end_reason: string | null;
  has_new: boolean;
};

export type Partner = {
  partner_id: string;
  communication: string | null;
  friendship: string | null;
  trust_level: number;
  display_name: string | null;
  contact: string | null;
  region: string | null;
  timezone: string | null;
};

export type Message = {
  id: number;
  match_id: string;
  sender_id: string | null;
  body: string;
  crisis: boolean;
  created_at: string;
};

// Joins the queue and tries to match straight away. Returns the new match id, if any.
export async function joinQueue() {
  const { data, error } = await supabase.rpc('join_queue');
  if (error) throw error;
  return data as string | null;
}

export async function leaveQueue() {
  const { error } = await supabase.rpc('leave_queue');
  if (error) throw error;
}

// While you're waiting, checks again for a match.
export async function findMatch() {
  const { data, error } = await supabase.rpc('find_match');
  if (error) throw error;
  return data as string | null;
}

export async function myMatches() {
  const { data, error } = await supabase.rpc('my_matches');
  if (error) throw error;
  return data as MatchSummary[];
}

export async function getPartner(matchId: string) {
  const { data, error } = await supabase.rpc('match_partner', { p_match: matchId }).maybeSingle();
  if (error) throw error;
  return data as Partner | null;
}

export async function getMatchStatus(matchId: string) {
  const { data, error } = await supabase.from('matches').select('status').eq('id', matchId).single();
  if (error) throw error;
  return data.status as MatchSummary['status'];
}

export async function getMessages(matchId: string) {
  const { data, error } = await supabase
    .from('messages')
    .select('id, match_id, sender_id, body, crisis, created_at')
    .eq('match_id', matchId)
    .order('created_at', { ascending: false })
    .limit(200);
  if (error) throw error;
  return data as Message[];
}

export async function sendMessage(matchId: string, senderId: string, body: string) {
  const { data, error } = await supabase
    .from('messages')
    .insert({ match_id: matchId, sender_id: senderId, body })
    .select('id, match_id, sender_id, body, crisis, created_at')
    .single();
  if (error) throw error;
  return data as Message;
}

// Live updates for one chat. Returns a function that stops listening.
export function onNewMessage(matchId: string, handler: (message: Message) => void) {
  const channel = supabase
    // A fresh name each time: re-using a name returns the already-subscribed
    // channel, which can't take new listeners.
    .channel(`match-${matchId}-${Math.random().toString(36).slice(2)}`)
    .on(
      'postgres_changes',
      { event: 'INSERT', schema: 'public', table: 'messages', filter: `match_id=eq.${matchId}` },
      (payload) => handler(payload.new as Message),
    )
    .subscribe();
  return () => {
    void supabase.removeChannel(channel);
  };
}

// Live updates when a match is created or ends.
export function onMatchChange(handler: () => void) {
  const channel = supabase
    .channel(`my-matches-${Math.random().toString(36).slice(2)}`)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'matches' }, handler)
    .subscribe();
  return () => {
    void supabase.removeChannel(channel);
  };
}

export async function markRead(matchId: string) {
  const { error } = await supabase.rpc('mark_match_read', { p_match: matchId });
  if (error) throw error;
}

// Kind Exit: ends the match, with an optional note to the other person.
export async function endMatch(matchId: string, note: string | null) {
  const { error } = await supabase.rpc('end_match', { p_match: matchId, p_reason: note });
  if (error) throw error;
}

export async function blockUser(userId: string) {
  const { error } = await supabase.rpc('block_user', { p_user: userId });
  if (error) throw error;
}

export async function reportUser(matchId: string, reason: string, details: string | null, messageId: number | null) {
  const { error } = await supabase.rpc('report_user', {
    p_match: matchId,
    p_reason: reason,
    p_details: details,
    p_message: messageId,
  });
  if (error) throw error;
}

export async function getMyReveal(matchId: string) {
  const { data, error } = await supabase
    .from('match_reveals')
    .select('reveal_name, reveal_contact, reveal_region')
    .eq('match_id', matchId)
    .maybeSingle();
  if (error) throw error;
  return (data as RevealSettings | null) ?? { reveal_name: false, reveal_contact: false, reveal_region: false };
}
