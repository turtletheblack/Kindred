import { supabase } from './supabase';

// Check-ins, connection health, prompt cards and the someone-who-matters
// question. All of it asks people; nothing reads their messages.

export type PromptKind = 'mutual' | 'strengthened' | 'checkin' | 'pulse' | 'bridge' | 'health' | 'deepen';

// 'answered' means you answered and nothing is shared, whether or not your
// match has answered yet.
export type CheckinOutcome = 'answered' | 'both_yes' | 'both_no' | null;

export type MatchPrompts = {
  prompt: PromptKind | null;
  ladder: 1 | 2 | 3;
  checkin: CheckinOutcome;
};

export type Feeling = 'growing' | 'steady' | 'fading' | 'unsure';
export type Balance = 'balanced' | 'mostly' | 'one_sided' | 'unsure';
export type MattersAnswer = 'yes' | 'not_yet' | 'unsure' | 'rather_not_say';

export type ConversationPrompt = { id: number; kind: 'opener' | 'catch_up' | 'deep'; level: number; body: string };

export async function getMatchPrompts(matchId: string) {
  const { data, error } = await supabase.rpc('match_prompts', { p_match: matchId }).maybeSingle();
  if (error) throw error;
  return (data as MatchPrompts | null) ?? { prompt: null, ladder: 1, checkin: null };
}

export async function answerCheckin(matchId: string, enjoyed: boolean) {
  const { data, error } = await supabase.rpc('answer_checkin', { p_match: matchId, p_enjoyed: enjoyed });
  if (error) throw error;
  return data as CheckinOutcome;
}

export async function mutualExit(matchId: string) {
  const { error } = await supabase.rpc('mutual_exit', { p_match: matchId });
  if (error) throw error;
}

export async function answerHealthCheck(matchId: string, feeling: Feeling, balance: Balance | null) {
  const { error } = await supabase.rpc('answer_health_check', {
    p_match: matchId,
    p_feeling: feeling,
    p_balance: balance,
  });
  if (error) throw error;
}

// "Not now": hides a card for a while, or for good if it only makes sense once.
export async function snoozePrompt(matchId: string, kind: PromptKind) {
  const { error } = await supabase.rpc('snooze_prompt', { p_match: matchId, p_kind: kind });
  if (error) throw error;
}

// Questions up to the level this match has reached.
export async function getConversationPrompts(kind: ConversationPrompt['kind'] | 'any', maxLevel: number) {
  let query = supabase.from('conversation_prompts').select('id, kind, level, body').lte('level', maxLevel);
  if (kind !== 'any') query = query.eq('kind', kind);
  const { data, error } = await query;
  if (error) throw error;
  return data as ConversationPrompt[];
}

export async function mattersDue() {
  const { data, error } = await supabase.rpc('matters_due');
  if (error) throw error;
  return data as number | null;
}

export async function answerMatters(wave: number, answer: MattersAnswer) {
  const { error } = await supabase.rpc('answer_matters', { p_wave: wave, p_answer: answer });
  if (error) throw error;
}

export async function snoozeMatters() {
  const { error } = await supabase.rpc('snooze_matters');
  if (error) throw error;
}

export async function getChatLimits() {
  const { data, error } = await supabase
    .from('matching_settings')
    .select('default_chat_limit, max_chat_limit')
    .single();
  if (error) throw error;
  return data as { default_chat_limit: number; max_chat_limit: number };
}
