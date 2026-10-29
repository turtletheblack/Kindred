import { supabase } from './supabase';

export type TestOption = { id: number; label: string };
export type TestQuestion = { id: number; kind: 'communication' | 'friendship'; prompt: string; options: TestOption[] };

export type TestResult = {
  id: string;
  communication_scores: Record<string, number>;
  friendship_scores: Record<string, number>;
  primary_communication: string;
  secondary_communication: string;
  friendship: string;
  taken_at: string;
};

function shuffle<T>(items: T[]) {
  const out = [...items];
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

// Options are shuffled so their order doesn't nudge anyone toward a badge.
export async function getQuestions() {
  const [questions, options] = await Promise.all([
    supabase.from('test_questions').select('id, kind, prompt').order('id'),
    supabase.from('test_options').select('id, question_id, label'),
  ]);
  if (questions.error) throw questions.error;
  if (options.error) throw options.error;
  return (questions.data as Omit<TestQuestion, 'options'>[]).map((q) => ({
    ...q,
    options: shuffle(
      (options.data as (TestOption & { question_id: number })[])
        .filter((o) => o.question_id === q.id)
        .map(({ id, label }) => ({ id, label })),
    ),
  }));
}

// answers maps question id to option id. Scoring happens on the server.
export async function submitTest(answers: Record<number, number>) {
  const { error } = await supabase.rpc('submit_test', { p_answers: answers });
  if (error) throw error;
}

export async function getMyResult() {
  const { data, error } = await supabase
    .from('current_test_results')
    .select('id, communication_scores, friendship_scores, primary_communication, secondary_communication, friendship, taken_at')
    .maybeSingle();
  if (error) throw error;
  return data as TestResult | null;
}

export async function getRetakeCooldownDays() {
  const { data, error } = await supabase.from('matching_settings').select('retake_cooldown').single();
  if (error) throw error;
  // Postgres sends intervals like "90 days".
  return parseInt(String(data.retake_cooldown), 10) || 90;
}
