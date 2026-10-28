import { Redirect } from 'expo-router';

// Google sign-in returns here. The sign-in screen finishes the session, so
// this route only sends people on to the right screen if the app opens it.
export default function AuthCallback() {
  return <Redirect href="/" />;
}
