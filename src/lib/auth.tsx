import type { Session } from '@supabase/supabase-js';
import * as Linking from 'expo-linking';
import * as WebBrowser from 'expo-web-browser';
import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';
import { Platform } from 'react-native';

import { supabase } from './supabase';

type AuthState = { session: Session | null; loading: boolean };

const AuthContext = createContext<AuthState>({ session: null, loading: true });

export function AuthProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<AuthState>({ session: null, loading: true });

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setState({ session: data.session, loading: false });
    });
    const { data } = supabase.auth.onAuthStateChange((_event, session) => {
      setState({ session, loading: false });
    });
    return () => data.subscription.unsubscribe();
  }, []);

  return <AuthContext.Provider value={state}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  return useContext(AuthContext);
}

// Email sign-in with a one-time code. No password, and the email address is
// never shown to other users.
export async function sendCode(email: string) {
  const { error } = await supabase.auth.signInWithOtp({
    email,
    options: { shouldCreateUser: true },
  });
  if (error) throw error;
}

export async function verifyCode(email: string, token: string) {
  const { error } = await supabase.auth.verifyOtp({ email, token, type: 'email' });
  if (error) throw error;
}

// Google sign-in, handled by Supabase. Kindred only uses it to identify the
// account; nothing from the Google profile is shown to other users.
export async function signInWithGoogle() {
  if (Platform.OS === 'web') {
    const { error } = await supabase.auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo: window.location.origin },
    });
    if (error) throw error;
    return;
  }

  const redirectTo = Linking.createURL('auth/callback');
  const { data, error } = await supabase.auth.signInWithOAuth({
    provider: 'google',
    options: { redirectTo, skipBrowserRedirect: true },
  });
  if (error) throw error;

  const result = await WebBrowser.openAuthSessionAsync(data.url, redirectTo);
  // On some phones the browser hands back through a deep link to
  // /auth/callback instead, and that screen finishes the sign-in.
  if (result.type !== 'success') return;
  await finishOAuthSignIn(Linking.parse(result.url).queryParams ?? {});
}

const usedCodes = new Set<string>();

// Turns the one-time code Google sign-in returns into a session. Both the
// sign-in screen and /auth/callback may see the same code, so only the
// first call uses it.
export async function finishOAuthSignIn(params: Record<string, unknown>) {
  if (typeof params.error_description === 'string') {
    throw new Error(params.error_description);
  }
  const code = params.code;
  if (typeof code !== 'string') {
    throw new Error('Google sign-in did not finish. Please try again.');
  }
  if (usedCodes.has(code)) return;
  usedCodes.add(code);
  const { error } = await supabase.auth.exchangeCodeForSession(code);
  if (error) throw error;
}

export async function signOut() {
  await supabase.auth.signOut();
}

export async function deleteAccount() {
  const { error } = await supabase.rpc('delete_my_account');
  if (error) throw error;
  await supabase.auth.signOut({ scope: 'local' });
}
