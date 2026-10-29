import { useState } from 'react';
import { ScrollView, Text } from 'react-native';

import { sendCode, signInWithGoogle, verifyCode } from '../lib/auth';
import { Button, Field, Note, styles, errorMessage } from '../lib/ui';

export default function SignIn() {
  const [email, setEmail] = useState('');
  const [code, setCode] = useState('');
  const [codeSent, setCodeSent] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function run(action: () => Promise<void>) {
    setBusy(true);
    setError(null);
    try {
      await action();
    } catch (e) {
      setError(errorMessage(e, 'Something went wrong. Please try again.'));
    } finally {
      setBusy(false);
    }
  }

  return (
    <ScrollView contentContainerStyle={styles.screen} keyboardShouldPersistTaps="handled">
      <Text style={styles.title} accessibilityRole="header">Kindred</Text>
      <Text style={styles.body}>Find people who speak your language.</Text>
      <Note>
        Your Google account or email is only used to sign you in. Nobody you match with sees it,
        or anything else about you, unless you choose to share it with them.
      </Note>

      <Button
        label="Sign in with Google"
        disabled={busy}
        onPress={() => run(signInWithGoogle)}
      />
      <Note>Or sign in with a code sent to your email:</Note>

      <Field
        label="Email"
        value={email}
        onChangeText={setEmail}
        autoCapitalize="none"
        autoComplete="email"
        keyboardType="email-address"
        editable={!codeSent}
      />
      {codeSent ? (
        <>
          <Field
            label="Code from your email"
            value={code}
            onChangeText={setCode}
            keyboardType="number-pad"
            autoComplete="one-time-code"
          />
          <Button
            label="Sign in"
            disabled={busy || code.trim().length < 6}
            onPress={() => run(() => verifyCode(email.trim(), code.trim()))}
          />
          <Button label="Use a different email" tone="plain" onPress={() => setCodeSent(false)} />
        </>
      ) : (
        <Button
          label="Send me a code"
          disabled={busy || !email.includes('@')}
          onPress={() => run(async () => {
            await sendCode(email.trim());
            setCodeSent(true);
          })}
        />
      )}
      {error && <Text style={styles.error} accessibilityLiveRegion="polite">{error}</Text>}
    </ScrollView>
  );
}
