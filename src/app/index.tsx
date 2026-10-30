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
import { answerMatters, getChatLimits, mattersDue, snoozeMatters, type MattersAnswer } from '../lib/health';
import { getMyProfile, type Profile } from '../lib/profile';
import { getMyResult, type TestResult } from '../lib/test';
import { Button, Card, Note, styles, errorMessage } from '../lib/ui';

type Chat = { match: MatchSummary; partner: Partner | null };

export default function Home() {
  const [profile, setProfile] = useState<Profile | null>(null);
  const [result, setResult] = useState<TestResult | null>(null);
  const [chats, setChats] = useState<Chat[]>([]);
  const [lastEnded, setLastEnded] = useState<MatchSummary | null>(null);
  const [chatLimit, setChatLimit] = useState(1);
  const [wave, setWave] = useState<number | null>(null);
  const [thanks, setThanks] = useState(false);
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
      const [r, matches, limits, due] = await Promise.all([
        getMyResult(),
        myMatches(),
        getChatLimits(),
        mattersDue(),
      ]);
      const open = matches.filter((m) => m.status !== 'ended');
      setProfile(p);
      setResult(r);
      setChatLimit(Math.min(limits.max_chat_limit, p.chat_limit ?? limits.default_chat_limit));
      setWave(due);
      setChats(await Promise.all(open.map(async (m) => ({ match: m, partner: await getPartner(m.match_id) }))));
      // The most recent ending, if it's newer than every open chat.
      const ended =
        matches
          .filter((m) => m.status === 'ended' && m.ended_at)
          .sort((a, b) => b.ended_at!.localeCompare(a.ended_at!))[0] ?? null;
      setLastEnded(ended && (!open[0] || ended.ended_at! > open[0].created_at) ? ended : null);
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

      {wave !== null && (
        <MattersCard
          wave={wave}
          onDone={(answered) => {
            setWave(null);
            setThanks(answered);
          }}
        />
      )}
      {thanks && <Note>Thank you. Your answer is private and helps show whether Kindred works.</Note>}

      {chats.length > 0 && (
        <Text style={styles.heading} accessibilityRole="header">
          {chats.length === 1 ? 'Your chat' : 'Your chats'}
        </Text>
      )}
      {chats.map(({ match, partner }) => (
        <Card key={match.match_id} onPress={() => router.push(`/match/${match.match_id}`)}>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
            <Text style={[styles.heading, { marginTop: 0, flex: 1 }]}>
              {partner?.display_name ??
                (partner?.communication ? comboString(partner.communication, partner.friendship) : 'Your match')}
            </Text>
            {match.has_new && <View style={styles.dot} accessibilityLabel="New messages" />}
          </View>
          <Text style={styles.body}>
            {badgeName(partner?.communication)} · {badgeName(partner?.friendship)}
          </Text>
          <Note>Open chat</Note>
        </Card>
      ))}

      {lastEnded && (
        <Note>
          {lastEnded.ended_mutually
            ? 'You and a match agreed to end your chat. That was about the fit, not either of you.'
            : lastEnded.ended_by_me
              ? 'You ended a match.'
              : 'A match has ended the connection. That was about the fit, not about you.'}
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
            <Text style={styles.heading}>Looking for {chats.length ? 'another match' : 'your match'}</Text>
            <Text style={styles.body}>
              We're looking for someone who communicates in a way that fits you. This can take
              a while when few people are waiting. You can close the app; your match will be
              here when you come back.
            </Text>
            <Button label="Stop looking" tone="plain" disabled={busy} onPress={() => run(leaveQueue)} />
          </Card>
        ) : chats.length < chatLimit ? (
          <Card>
            <Text style={styles.heading}>{chats.length ? 'Room for another chat?' : 'Ready to meet someone?'}</Text>
            <Text style={styles.body}>
              Kindred matches you one-on-one with people who communicate in a way that fits you.
              You're set to {chatLimit === 1 ? 'one chat' : `up to ${chatLimit} chats`} at a time.
            </Text>
            <Button label={chats.length ? 'Find another match' : 'Find a match'} disabled={busy} onPress={() => run(joinQueue)} />
          </Card>
        ) : (
          <Note>
            You're at your limit of {chatLimit === 1 ? 'one chat' : `${chatLimit} chats`}. You can change
            it in your profile whenever you feel like more, or less.
          </Note>
        )
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

// "Have you met someone who matters to you?", asked at 30, 90 and 365 days.
function MattersCard({ wave, onDone }: { wave: number; onDone: (answered: boolean) => void }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function act(action: () => Promise<void>, answered: boolean) {
    setBusy(true);
    setError(null);
    try {
      await action();
      onDone(answered);
    } catch (e) {
      setError(errorMessage(e, 'Something went wrong. Please try again.'));
      setBusy(false);
    }
  }

  const answer = (a: MattersAnswer) => act(() => answerMatters(wave, a), true);
  return (
    <Card>
      <Text style={styles.heading}>One question</Text>
      <Text style={styles.body}>Since joining Kindred, have you met someone here who matters to you?</Text>
      <Note>Only you see your answer. It's counted, never shared with anyone.</Note>
      <Button label="Yes" disabled={busy} onPress={() => answer('yes')} />
      <Button label="Not yet" tone="plain" disabled={busy} onPress={() => answer('not_yet')} />
      <Button label="I'm not sure" tone="plain" disabled={busy} onPress={() => answer('unsure')} />
      <Button label="I'd rather not say" tone="plain" disabled={busy} onPress={() => answer('rather_not_say')} />
      <Button label="Ask me later" tone="plain" disabled={busy} onPress={() => act(snoozeMatters, false)} />
      {error && <Text style={styles.error}>{error}</Text>}
    </Card>
  );
}
