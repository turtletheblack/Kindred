import { useEffect, useState } from 'react';
import { Alert, Platform, ScrollView, Text, View } from 'react-native';

import { deleteAccount } from '../lib/auth';
import {
  confirmAdult,
  deviceTimezone,
  getMyProfile,
  updateMyPreferences,
  updateMyProfile,
  type Profile,
} from '../lib/profile';
import { getChatLimits } from '../lib/health';
import { trustLevels } from '../lib/badges';
import { Button, Field, Note, styles, Toggle, errorMessage } from '../lib/ui';

export default function ProfileScreen() {
  const [profile, setProfile] = useState<Profile | null>(null);
  const [name, setName] = useState('');
  const [contact, setContact] = useState('');
  const [region, setRegion] = useState('');
  const [birthDate, setBirthDate] = useState('');
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [limits, setLimits] = useState({ default_chat_limit: 3, max_chat_limit: 10 });

  useEffect(() => {
    getChatLimits().then(setLimits).catch(() => {});
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
      setMessage(errorMessage(e, 'Something went wrong. Please try again.'));
    } finally {
      setBusy(false);
    }
  }

  function askToDelete() {
    const text =
      'This permanently deletes your account, profile, test results and chats. It cannot be undone. ' +
      'Survey answers are kept as anonymous totals.';
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

      <Text style={styles.heading} accessibilityRole="header">How many chats can you handle right now?</Text>
      <Note>
        Kindred won't look for new matches once you have this many open chats. Change it whenever
        you like; your current chats stay as they are.
      </Note>
      <ChatLimit
        value={Math.min(limits.max_chat_limit, profile.chat_limit ?? limits.default_chat_limit)}
        max={limits.max_chat_limit}
        disabled={busy}
        onChange={(n) =>
          run(async () => {
            await updateMyPreferences(profile.id, { chat_limit: n });
            setProfile({ ...profile, chat_limit: n });
          }, `Saved: up to ${n} ${n === 1 ? 'chat' : 'chats'}.`)
        }
      />

      <Text style={styles.heading} accessibilityRole="header">Gentle prompts</Text>
      <Note>
        Small cards in a chat when it's gone quiet, or when a match could go deeper, with a
        question you can use if you like. They're only shown to you, and nothing is ever sent for
        you. Check-ins are separate and always optional.
      </Note>
      <Toggle
        label="Show gentle prompts"
        value={profile.gentle_prompts}
        disabled={busy}
        onValueChange={(v) =>
          run(async () => {
            await updateMyPreferences(profile.id, { gentle_prompts: v });
            setProfile({ ...profile, gentle_prompts: v });
          }, v ? 'Gentle prompts on.' : 'Gentle prompts off.')
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

function ChatLimit({ value, max, disabled, onChange }: {
  value: number;
  max: number;
  disabled: boolean;
  onChange: (n: number) => void;
}) {
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 16 }}>
      <View style={{ width: 64 }}>
        <Button label="−" tone="plain" disabled={disabled || value <= 1} onPress={() => onChange(value - 1)} />
      </View>
      <Text style={[styles.title, { minWidth: 32, textAlign: 'center' }]} accessibilityLiveRegion="polite">
        {value}
      </Text>
      <View style={{ width: 64 }}>
        <Button label="+" tone="plain" disabled={disabled || value >= max} onPress={() => onChange(value + 1)} />
      </View>
    </View>
  );
}
