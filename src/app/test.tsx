import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import { ScrollView, Text } from 'react-native';

import { getQuestions, submitTest, type TestQuestion } from '../lib/test';
import { Button, Card, Choice, Note, styles } from '../lib/ui';

// The 18-question test: one question at a time, then a review page where
// any answer can be changed before submitting.
export default function TestScreen() {
  const [questions, setQuestions] = useState<TestQuestion[] | null>(null);
  const [answers, setAnswers] = useState<Record<number, number>>({});
  // Index of the question shown, or null for the review page.
  const [index, setIndex] = useState<number | null>(0);
  const [reviewing, setReviewing] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    getQuestions()
      .then(setQuestions)
      .catch((e) => setError(e instanceof Error ? e.message : 'Could not load the test.'));
  }, []);

  if (!questions) {
    return (
      <ScrollView contentContainerStyle={styles.screen}>
        {error ? <Text style={styles.error}>{error}</Text> : <Text style={styles.body}>Loading…</Text>}
      </ScrollView>
    );
  }

  async function submit() {
    setBusy(true);
    setError(null);
    try {
      await submitTest(answers);
      router.replace('/results');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Something went wrong. Please try again.');
    } finally {
      setBusy(false);
    }
  }

  if (index === null) {
    const unanswered = questions.filter((q) => answers[q.id] === undefined).length;
    return (
      <ScrollView contentContainerStyle={styles.screen}>
        <Text style={styles.title} accessibilityRole="header">Review your answers</Text>
        <Note>Tap any answer to change it.</Note>
        {questions.map((q, i) => (
          <Card key={q.id} onPress={() => setIndex(i)}>
            <Text style={styles.note}>{i + 1}. {q.prompt}</Text>
            <Text style={styles.body}>
              {q.options.find((o) => o.id === answers[q.id])?.label ?? 'Not answered yet'}
            </Text>
          </Card>
        ))}
        <Button
          label={unanswered ? `${unanswered} still to answer` : 'Submit'}
          disabled={busy || unanswered > 0}
          onPress={submit}
        />
        {error && <Text style={styles.error} accessibilityLiveRegion="polite">{error}</Text>}
      </ScrollView>
    );
  }

  const q = questions[index];
  const isLast = index === questions.length - 1;
  const next = () => {
    if (reviewing || isLast) {
      setReviewing(true);
      setIndex(null);
    } else {
      setIndex(index + 1);
    }
  };

  return (
    <ScrollView contentContainerStyle={styles.screen}>
      <Note>
        Question {index + 1} of {questions.length} ·{' '}
        {q.kind === 'communication' ? 'How you communicate' : 'What kind of friend you are'}
      </Note>
      <Text style={styles.heading} accessibilityRole="header">{q.prompt}</Text>
      <Note>Pick the answer that sounds most like you. There are no wrong answers.</Note>
      {q.options.map((o) => (
        <Choice
          key={o.id}
          label={o.label}
          selected={answers[q.id] === o.id}
          onPress={() => setAnswers({ ...answers, [q.id]: o.id })}
        />
      ))}
      <Button
        label={reviewing ? 'Back to review' : isLast ? 'Review answers' : 'Next'}
        disabled={answers[q.id] === undefined}
        onPress={next}
      />
      {index > 0 && !reviewing && (
        <Button label="Back" tone="plain" onPress={() => setIndex(index - 1)} />
      )}
    </ScrollView>
  );
}
