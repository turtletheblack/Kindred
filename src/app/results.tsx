import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import { ScrollView, Text } from 'react-native';

import { badgeName, badges, comboString, communicationCodes, friendshipCodes, type BadgeCode } from '../lib/badges';
import { getMyResult, getRetakeCooldownDays, type TestResult } from '../lib/test';
import { Bar, Button, Card, Note, styles } from '../lib/ui';

export default function ResultsScreen() {
  const [result, setResult] = useState<TestResult | null | undefined>(undefined);
  const [cooldownDays, setCooldownDays] = useState(90);

  useEffect(() => {
    getMyResult().then(setResult).catch(() => setResult(null));
    getRetakeCooldownDays().then(setCooldownDays).catch(() => {});
  }, []);

  if (result === undefined) return null;
  if (result === null) {
    return (
      <ScrollView contentContainerStyle={styles.screen}>
        <Text style={styles.body}>You haven't taken the test yet.</Text>
        <Button label="Take the test" onPress={() => router.replace('/test')} />
      </ScrollView>
    );
  }

  const retakeFrom = new Date(new Date(result.taken_at).getTime() + cooldownDays * 86400000);
  const canRetake = retakeFrom <= new Date();
  const mine: [string, BadgeCode][] = [
    ['Main communication style', result.primary_communication as BadgeCode],
    ['Second communication style', result.secondary_communication as BadgeCode],
    ['Friendship style', result.friendship as BadgeCode],
  ];

  return (
    <ScrollView contentContainerStyle={styles.screen}>
      <Text style={styles.title} accessibilityRole="header">
        {comboString(result.primary_communication, result.secondary_communication, result.friendship)}
      </Text>
      <Note>
        Your badges are a short manual for how to talk with you. Matches see these three badges,
        never your percentages.
      </Note>

      {mine.map(([label, code]) => (
        <Card key={label}>
          <Text style={styles.note}>{label}</Text>
          <Text style={[styles.heading, { marginTop: 0 }]}>{badgeName(code)} ({code})</Text>
          <Text style={styles.body}>{badges[code]?.description}</Text>
        </Card>
      ))}

      <Text style={styles.heading} accessibilityRole="header">How you communicate</Text>
      {communicationCodes.map((code) => (
        <Bar key={code} label={badgeName(code)} percent={result.communication_scores[code] ?? 0} />
      ))}
      <Text style={styles.heading} accessibilityRole="header">What kind of friend you are</Text>
      {friendshipCodes.map((code) => (
        <Bar key={code} label={badgeName(code)} percent={result.friendship_scores[code] ?? 0} />
      ))}
      <Note>
        Matching uses these percentages, not just the badges, so close second choices still count.
      </Note>

      {canRetake ? (
        <Button label="Retake the test" tone="plain" onPress={() => router.replace('/test')} />
      ) : (
        <Note>You can retake the test from {retakeFrom.toLocaleDateString()}.</Note>
      )}
      <Button label="Done" onPress={() => router.replace('/')} />
    </ScrollView>
  );
}
