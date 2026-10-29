import { useEffect, useState } from 'react';
import { Alert, Platform, ScrollView, Text } from 'react-native';

import { deleteAccount } from '../lib/auth';
import {
  confirmAdult,
  deviceTimezone,
  getMyProfile,
  updateMyProfile,
  type Profile,
} from '../lib/profile';
import { trustLevels } from '../lib/badges';
import { Button, Field, Note, styles } from '../lib/ui';

export default function ProfileScreen() {
  const [profile, setProfile] = useState<Profile | null>(null);
  const [name, setName] = useState('');
  const [contact, setContact] = useState('');
  const [region, setRegion] = useState('');
  const [birthDate, setBirthDate] = useState('');
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    getMyProfile().then((p) => {
      setProfile(p);
      setName(p.display_name ?? '');
      setContact(p.contact ?? '');
      setRegion(p.region ?? '');
    });
  }, []);

  async function run(action: () => Promise<void>, done: string) {
    setBusy(true);
    setMessage(null);
    try {
      await action();
      setMessage(done);
    } catch (e) {
      setMessage(e instanceof Error ? e.message : 'Something went wrong. Please try again.');
    } finally {
      setBusy(false);
    }
  }

  function askToDelete() {
    const text = 'This permanently deletes your account, profile, test results and chats. It cannot be undone.';
    // Alert has no buttons on web, so fall back to the browser's confirm.
    if (Platform.OS === 'web') {
      if (globalThis.confirm?.(text)) void deleteAccount();
      return;
    }
    Alert.alert('Delete your account?', text, [
      { text: 'Cancel', style: 'cancel' },
      { text: 'Delete', style: 'destructive', onPress: () => void deleteAccount() },
    ]);
  }

  if (!profile) return null;

  return (
    <ScrollView contentContainerStyle={styles.screen} keyboardShouldPersistTaps="handled">
      <Note>
        Nobody can see these details. In each match you choose separately whether to share your
        name, contact, or area with that one person.
      </Note>

      <Field label="Name or nickname" value={name} onChangeText={setName} maxLength={50} />
      <Field
        label="How a match can reach you outside Kindred"
        value={contact}
        onChangeText={setContact}
        placeholder="e.g. a phone number or social handle"
        maxLength={200}
      />
      <Field
        label="Rough area"
        value={region}
        onChangeText={setRegion}
        placeholder="City or region, not your address"
        maxLength={100}
      />
      <Note>Time zone: {deviceTimezone() ?? 'unknown'} (from your device)</Note>
      <Button
        label="Save"
        disabled={busy}
        onPress={() =>
          run(async () => {
            await updateMyProfile(profile.id, {
              display_name: name.trim() || null,
              contact: contact.trim() || null,
              region: region.trim() || null,
              timezone: deviceTimezone(),
            });
          }, 'Saved.')
        }
      />

      {!profile.adult_confirmed_at && (
        <>
          <Text style={styles.heading} accessibilityRole="header">Confirm you're 18 or over</Text>
          <Note>Kindred is for adults. Your birth date is checked and then discarded.</Note>
          <Field
            label="Birth date (YYYY-MM-DD)"
            value={birthDate}
            onChangeText={setBirthDate}
            placeholder="1990-05-01"
            keyboardType="numbers-and-punctuation"
            maxLength={10}
          />
          <Button
            label="Confirm"
            disabled={busy || !/^\d{4}-\d{2}-\d{2}$/.test(birthDate)}
            onPress={() =>
              run(async () => {
                await confirmAdult(birthDate);
                setProfile(await getMyProfile());
              }, 'Thanks, confirmed.')
            }
          />
        </>
      )}

      {message && <Text style={styles.body} accessibilityLiveRegion="polite">{message}</Text>}

      <Text style={styles.heading} accessibilityRole="header">
        Trust level: {trustLevels[profile.trust_level]?.name}
      </Text>
      <Note>{trustLevels[profile.trust_level]?.about}</Note>

      <Text style={styles.heading} accessibilityRole="header">Delete account</Text>
      <Button label="Delete my account" tone="danger" onPress={askToDelete} />
    </ScrollView>
  );
}
