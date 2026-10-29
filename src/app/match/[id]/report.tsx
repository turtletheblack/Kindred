import { router, useLocalSearchParams } from 'expo-router';
import { useState } from 'react';
import { ScrollView, Text } from 'react-native';

import { blockUser, getPartner, reportUser } from '../../../lib/matches';
import { Button, Choice, Field, Note, styles, Toggle } from '../../../lib/ui';

const reasons = [
  'Harassment or bullying',
  'Hateful or abusive language',
  'Sexual content or advances',
  'Scam, spam or asking for money',
  'Seems under 18',
  'Threats or worry about someone\'s safety',
  'Something else',
];

export default function Report() {
  const { id, messageId } = useLocalSearchParams<{ id: string; messageId?: string }>();
  const [reason, setReason] = useState<string | null>(null);
  const [details, setDetails] = useState('');
  const [alsoBlock, setAlsoBlock] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState(false);

  async function submit() {
    if (!reason || !id) return;
    setBusy(true);
    setError(null);
    try {
      await reportUser(id, reason, details.trim() || null, messageId ? Number(messageId) : null);
      if (alsoBlock) {
        const partner = await getPartner(id);
        if (partner) await blockUser(partner.partner_id);
      }
      setDone(true);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Something went wrong. Please try again.');
    } finally {
      setBusy(false);
    }
  }

  if (done) {
    return (
      <ScrollView contentContainerStyle={styles.screen}>
        <Text style={styles.title} accessibilityRole="header">Thank you</Text>
        <Text style={styles.body}>
          Your report was sent to the Kindred team. The other person won't know who reported them.
        </Text>
        <Note>If anyone is in immediate danger, contact your local emergency services.</Note>
        <Button label="Done" onPress={() => router.dismissTo(alsoBlock ? '/' : `/match/${id}`)} />
      </ScrollView>
    );
  }

  return (
    <ScrollView contentContainerStyle={styles.screen} keyboardShouldPersistTaps="handled">
      <Text style={styles.title} accessibilityRole="header">Report a problem</Text>
      <Note>
        {messageId
          ? 'A copy of the message you pressed is included, so it can be reviewed even if it\'s deleted.'
          : 'To include a specific message, long-press it in the chat.'}
      </Note>
      {reasons.map((r) => (
        <Choice key={r} label={r} selected={reason === r} onPress={() => setReason(r)} />
      ))}
      <Field
        label="Anything else we should know? (optional)"
        value={details}
        onChangeText={setDetails}
        multiline
        maxLength={4000}
      />
      <Toggle label="Also block them and end the match" value={alsoBlock} onValueChange={setAlsoBlock} />
      <Button label="Send report" disabled={busy || !reason} onPress={submit} />
      {error && <Text style={styles.error} accessibilityLiveRegion="polite">{error}</Text>}
    </ScrollView>
  );
}
