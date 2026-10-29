import { router, useFocusEffect } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { RefreshControl, ScrollView, Text, View } from 'react-native';

import { signOut } from '../lib/auth';
import { badgeName, comboString } from '../lib/badges';
import {
  findMatch,
  getPartner,
  joinQueue,
  leaveQueue,
  myMatches,
  onMatchChange,
  type MatchSummary,
  type Partner,
} from '../lib/matches';
import { getMyProfile, type Profile } from '../lib/profile';
import { getMyResult, type TestResult } from '../lib/test';
import { Button, Card, Note, styles, errorMessage } from '../lib/ui';

type Current = { match: MatchSummary; partner: Partner | null };

export default function Home() {
  const [profile, setProfile] = useState<Profile | null>(null);
  const [result, setResult] = useState<TestResult | null>(null);
  const [current, setCurrent] = useState<Current | null>(null);
  const [lastEnded, setLastEnded] = useState<MatchSummary | null>(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      let p = await getMyProfile();
      // While waiting, check again for a match each time Home opens.
      if (p.matching_status === 'queued') {
        await findMatch();
        p = await getMyProfile();
      }
      const [r, matches] = await Promise.all([getMyResult(), myMatches()]);
      const active = matches.find((m) => m.status !== 'ended') ?? null;
      setProfile(p);
      setResult(r);
      setCurrent(active ? { match: active, partner: await getPartner(active.match_id) } : null);
      setLastEnded(!active && matches[0]?.status === 'ended' ? matches[0] : null);
    } catch (e) {
      setError(errorMessage(e, 'Could not load. Pull down to try again.'));
    } finally {
      setLoading(false);
    }
  }, []);

  useFocusEffect(
    useCallback(() => {
      void load();
    }, [load]),
  );

  // A match can be made while you're on this screen, when someone else joins.
  useEffect(() => onMatchChange(() => void load()), [load]);

  async function run(action: () => Promise<unknown>) {
    setBusy(true);
    setError(null);
    try {
      await action();
      await load();
    } catch (e) {
      setError(errorMessage(e, 'Something went wrong. Please try again.'));
    } finally {
      setBusy(false);
    }
  }

  if (!profile) {
    return (
      <ScrollView contentContainerStyle={styles.screen}>
        {error ? <Text style={styles.error}>{error}</Text> : null}
        {!loading && <Button label="Try again" onPress={() => void load()} />}
      </ScrollView>
    );
  }

  const adult = profile.adult_confirmed_at !== null;
  const queued = profile.matching_status === 'queued';

  return (
    <ScrollView
      contentContainerStyle={styles.screen}
      refreshControl={<RefreshControl refreshing={loading} onRefresh={() => void load()} />}
    >
      <Text style={styles.title} accessibilityRole="header">Kindred</Text>

      {profile.suspended_at && (
        <Note>
          Matching and chat are paused on your account while we review a report. We'll be in touch.
        </Note>
      )}

      {current ? (
        <>
          <Text style={styles.heading} accessibilityRole="header">Your match</Text>
          <Card onPress={() => router.push(`/match/${current.match.match_id}`)}>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
              <Text style={[styles.heading, { marginTop: 0, flex: 1 }]}>
                {current.partner?.display_name ??
                  (current.partner?.communication
                    ? comboString(current.partner.communication, current.partner.friendship)
                    : 'Your match')}
              </Text>
              {current.match.has_new && (
                <View style={styles.dot} accessibilityLabel="New messages" />
              )}
            </View>
            <Text style={styles.body}>
              {badgeName(current.partner?.communication)} · {badgeName(current.partner?.friendship)}
            </Text>
            <Note>Open chat</Note>
          </Card>
        </>
      ) : (
        <>
          {lastEnded && (
            <Note>
              {lastEnded.ended_by_me
                ? 'You ended your last match.'
                : 'Your last match has ended the connection.'}
              {!lastEnded.ended_by_me && lastEnded.end_reason ? ` They said: "${lastEnded.end_reason}"` : ''}
            </Note>
          )}

          {!adult && (
            <Card>
              <Text style={styles.body}>First, confirm you're 18 or over.</Text>
              <Button label="Confirm in your profile" onPress={() => router.push('/profile')} />
            </Card>
          )}

          {adult && !result && (
            <Card>
              <Text style={styles.heading}>Take the communication test</Text>
              <Text style={styles.body}>
                18 quick questions about how you talk and what kind of friend you are. You'll get
                two badges that help your matches know how to talk with you.
              </Text>
              <Button label="Start the test" onPress={() => router.push('/test')} />
            </Card>
          )}

          {adult && result && !profile.suspended_at && (
            queued ? (
              <Card>
                <Text style={styles.heading}>Looking for your match</Text>
                <Text style={styles.body}>
                  We're looking for someone who communicates in a way that fits you. This can take
                  a while when few people are waiting. You can close the app; your match will be
                  here when you come back.
                </Text>
                <Button label="Stop looking" tone="plain" disabled={busy} onPress={() => run(leaveQueue)} />
              </Card>
            ) : (
              <Card>
                <Text style={styles.heading}>Ready to meet someone?</Text>
                <Text style={styles.body}>
                  Kindred matches you with one person at a time, based on how you both communicate.
                </Text>
                <Button label="Find a match" disabled={busy} onPress={() => run(joinQueue)} />
              </Card>
            )
          )}
        </>
      )}

      {error && <Text style={styles.error} accessibilityLiveRegion="polite">{error}</Text>}

      {result && (
        <Button
          label={`Your badges: ${comboString(result.communication, result.friendship)}`}
          tone="plain"
          onPress={() => router.push('/results')}
        />
      )}
      <Button label="Your private profile" tone="plain" onPress={() => router.push('/profile')} />
      <Button label="Sign out" tone="plain" onPress={signOut} />
    </ScrollView>
  );
}
