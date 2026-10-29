import { Redirect, useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';
import { ScrollView, Text } from 'react-native';

import { finishOAuthSignIn } from '../../lib/auth';
import { Button, styles, errorMessage } from '../../lib/ui';

// Google sign-in returns here when the phone opens the app through a deep
// link rather than handing the result straight back to the sign-in screen.
export default function AuthCallback() {
  const params = useLocalSearchParams();
  const [state, setState] = useState<'working' | 'done' | string>('working');

  useEffect(() => {
    finishOAuthSignIn(params)
      .then(() => setState('done'))
      .catch((e) => setState(errorMessage(e, 'Sign-in failed. Please try again.')));
  }, [params.code, params.error_description]);

  if (state === 'done') return <Redirect href="/" />;

  return (
    <ScrollView contentContainerStyle={styles.screen}>
      {state === 'working' ? (
        <Text style={styles.body}>Signing you in…</Text>
      ) : (
        <>
          <Text style={styles.error} accessibilityLiveRegion="polite">{state}</Text>
          <Button label="Back to sign in" onPress={() => setState('done')} />
        </>
      )}
    </ScrollView>
  );
}
