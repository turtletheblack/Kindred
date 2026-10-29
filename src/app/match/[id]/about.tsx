import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';
import { ScrollView, Text } from 'react-native';

import { useAuth } from '../../../lib/auth';
import { badgeName, badges, trustLevels, type BadgeCode } from '../../../lib/badges';
import {
  blockUser,
  endMatch,
  getMatchStatus,
  getMyReveal,
  getPartner,
  type MatchSummary,
  type Partner,
} from '../../../lib/matches';
import { getMyProfile, setReveal, type Profile, type RevealSettings } from '../../../lib/profile';
import { Button, Card, confirmAction, Field, Note, styles, Toggle } from '../../../lib/ui';

// About your match: their badges as a manual, what they've shared, what you
// share with them, and the safety tools.
export default function AboutMatch() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { session } = useAuth();
  const me = session?.user.id ?? '';
  const [partner, setPartner] = useState<Partner | null>(null);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [reveal, setRevealState] = useState<RevealSettings | null>(null);
  const [status, setStatus] = useState<MatchSummary['status']>('active');
  const [exitNote, setExitNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!id) return;
    getPartner(id).then(setPartner).catch(() => {});
    getMyProfile().then(setProfile).catch(() => {});
    getMyReveal(id).then(setRevealState).catch(() => {});
    getMatchStatus(id).then(setStatus).catch(() => {});
  }, [id]);

  async function run(action: () => Promise<void>) {
    setBusy(true);
    setError(null);
    try {
      await action();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Something went wrong. Please try again.');
    } finally {
      setBusy(false);
    }
  }

  function toggle(key: keyof RevealSettings, value: boolean) {
    if (!reveal || !id) return;
    const next = { ...reveal, [key]: value };
    setRevealState(next);
    void run(() => setReveal(id, me, next));
  }

  async function kindExit() {
    const ok = await confirmAction(
      'End this match?',
      'Your match will see that you ended it, along with your note if you wrote one. You won\'t be matched with each other again.',
      'End match',
    );
    if (ok && id) await run(async () => {
      await endMatch(id, exitNote.trim() || null);
      router.dismissTo('/');
    });
  }

  async function block() {
    if (!partner) return;
    const ok = await confirmAction(
      'Block this person?',
      'The match ends straight away and you will never be matched again. They won\'t be told you blocked them.',
      'Block',
    );
    if (ok) await run(async () => {
      await blockUser(partner.partner_id);
      router.dismissTo('/');
    });
  }

  if (!partner) return null;
  const partnerBadges = [partner.primary_communication, partner.secondary_communication, partner.friendship]
    .filter((c): c is BadgeCode => !!c && c in badges);
  const active = status === 'active';

  return (
    <ScrollView contentContainerStyle={styles.screen} keyboardShouldPersistTaps="handled">
      <Text style={styles.title} accessibilityRole="header">
        {partner.display_name ?? 'Your match'}
      </Text>
      <Note>{trustLevels[partner.trust_level]?.name ?? 'Member'} on Kindred</Note>

      <Text style={styles.heading} accessibilityRole="header">How to talk with them</Text>
      {partnerBadges.map((code) => (
        <Card key={code}>
          <Text style={styles.body}>
            <Text style={{ fontWeight: '600' }}>{badgeName(code)}</Text> · {badges[code].description}
          </Text>
          <Text style={styles.note}>{badges[code].tip}</Text>
        </Card>
      ))}

      {(partner.contact || partner.region) && (
        <>
          <Text style={styles.heading} accessibilityRole="header">They've shared with you</Text>
          {partner.contact && <Text style={styles.body}>Contact: {partner.contact}</Text>}
          {partner.region && (
            <Text style={styles.body}>
              Area: {partner.region}{partner.timezone ? ` (${partner.timezone})` : ''}
            </Text>
          )}
        </>
      )}

      <Text style={styles.heading} accessibilityRole="header">What you share</Text>
      <Note>
        Nothing is shared unless you turn it on, and only with this match. Your badges are always
        visible to them.
      </Note>
      {reveal && profile && (
        <>
          <Toggle
            label={`Your name${profile.display_name ? ` (${profile.display_name})` : ' (not set)'}`}
            value={reveal.reveal_name}
            disabled={busy || !profile.display_name}
            onValueChange={(v) => toggle('reveal_name', v)}
          />
          <Toggle
            label={`How to reach you${profile.contact ? ` (${profile.contact})` : ' (not set)'}`}
            value={reveal.reveal_contact}
            disabled={busy || !profile.contact}
            onValueChange={(v) => toggle('reveal_contact', v)}
          />
          <Toggle
            label={`Your area${profile.region ? ` (${profile.region})` : ' (not set)'}`}
            value={reveal.reveal_region}
            disabled={busy || !profile.region}
            onValueChange={(v) => toggle('reveal_region', v)}
          />
          {(!profile.display_name || !profile.contact || !profile.region) && (
            <Button label="Fill in your private profile" tone="plain" onPress={() => router.push('/profile')} />
          )}
        </>
      )}

      {active && (
        <>
          <Text style={styles.heading} accessibilityRole="header">Kind Exit</Text>
          <Note>
            Not clicking? That's okay. Ending kindly is better than going quiet. You can leave a
            short note.
          </Note>
          <Field
            label="Note to your match (optional)"
            value={exitNote}
            onChangeText={setExitNote}
            placeholder="e.g. Thanks for the chats, I don't think we're a fit."
            maxLength={200}
          />
          <Button label="End this match" tone="plain" disabled={busy} onPress={kindExit} />
        </>
      )}

      <Text style={styles.heading} accessibilityRole="header">Safety</Text>
      <Button label="Report a problem" tone="plain" onPress={() => router.push(`/match/${id}/report`)} />
      <Button label="Block" tone="danger" disabled={busy} onPress={block} />

      {error && <Text style={styles.error} accessibilityLiveRegion="polite">{error}</Text>}
    </ScrollView>
  );
}
