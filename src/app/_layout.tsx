import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';

import { AuthProvider, useAuth } from '../lib/auth';

function RootStack() {
  const { session, loading } = useAuth();
  if (loading) return null;

  const signedIn = session !== null;
  return (
    <Stack screenOptions={{ headerShown: false }}>
      <Stack.Protected guard={signedIn}>
        <Stack.Screen name="index" />
        <Stack.Screen name="profile" options={{ headerShown: true, title: 'Your private profile' }} />
        <Stack.Screen name="test" options={{ headerShown: true, title: 'Communication test' }} />
        <Stack.Screen name="results" options={{ headerShown: true, title: 'Your badges' }} />
        <Stack.Screen name="match/[id]/index" options={{ headerShown: true, title: 'Chat' }} />
        <Stack.Screen name="match/[id]/about" options={{ headerShown: true, title: 'About your match' }} />
        <Stack.Screen name="match/[id]/report" options={{ headerShown: true, title: 'Report' }} />
      </Stack.Protected>
      <Stack.Protected guard={!signedIn}>
        <Stack.Screen name="sign-in" />
      </Stack.Protected>
    </Stack>
  );
}

export default function RootLayout() {
  return (
    <AuthProvider>
      <StatusBar style="dark" />
      <RootStack />
    </AuthProvider>
  );
}
