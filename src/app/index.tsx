import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { ScrollView, Text } from 'react-native';

import { signOut } from '../lib/auth';
import { getMyProfile, type Profile } from '../lib/profile';
import { Button, Note, styles } from '../lib/ui';

export default function Home() {
  const [profile, setProfile] = useState<Profile | null>(null);

  useFocusEffect(
    useCallback(() => {
      getMyProfile().then(setProfile).catch(() => setProfile(null));
    }, []),
  );

  return (
    <ScrollView contentContainerStyle={styles.screen}>
      <Text style={styles.title} accessibilityRole="header">Welcome to Kindred</Text>
      <Text style={styles.body}>
        Your account is hidden. Matches see your badges, and only what you choose to reveal to
        each of them.
      </Text>
      {profile && !profile.adult_confirmed_at && (
        <Note>Confirm you're 18 or over in your profile before matching.</Note>
      )}
      <Note>The communication test and matching are coming next.</Note>

      <Button label="Your private profile" onPress={() => router.push('/profile')} />
      <Button label="Sign out" tone="plain" onPress={signOut} />
    </ScrollView>
  );
}
