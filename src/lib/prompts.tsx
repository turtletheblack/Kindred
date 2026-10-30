import { useEffect, useState, type ReactNode } from 'react';
import { Text, View } from 'react-native';

import {
  answerCheckin,
  answerHealthCheck,
  getConversationPrompts,
  mutualExit,
  snoozePrompt,
  type Balance,
  type ConversationPrompt,
  type Feeling,
  type MatchPrompts,
} from './health';
import { Button, Card, Choice, confirmAction, errorMessage, Note, styles } from './ui';

// The cards shown above the message box in a chat. At most one at a time,
// always dismissable, never posted into the conversation.

export type QuestionKind = ConversationPrompt['kind'] | 'any';

function Buttons({ children }: { children: ReactNode }) {
  return <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8 }}>{children}</View>;
}

function Small({ label, onPress, tone = 'plain', disabled }: {
  label: string;
  onPress: () => void;
  tone?: 'accent' | 'plain';
  disabled?: boolean;
}) {
  return (
    <View style={{ flexGrow: 1 }}>
      <Button label={label} tone={tone} onPress={onPress} disabled={disabled} />
    </View>
  );
}

export function MatchPromptCard({
  matchId,
  prompts,
  onChanged,
  onAskQuestion,
  onWriteToThem,
  onEnded,
}: {
  matchId: string;
  prompts: MatchPrompts;
  onChanged: () => void;
  onAskQuestion: (kind: QuestionKind) => void;
  onWriteToThem: () => void;
  onEnded: () => void;
}) {
  // A follow-up shown right after answering, before the next card loads.
  const [after, setAfter] = useState<'appreciation' | 'thanks' | 'fading' | null>(null);
  const [feeling, setFeeling] = useState<Feeling | null>(null);
  const [balance, setBalance] = useState<Balance | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function run(action: () => Promise<unknown>, then?: () => void) {
    setBusy(true);
    setError(null);
    try {
      await action();
      if (then) then();
      else onChanged();
    } catch (e) {
      setError(errorMessage(e, 'Something went wrong. Please try again.'));
    } finally {
      setBusy(false);
    }
  }

  const later = () => run(() => snoozePrompt(matchId, prompts.prompt!));
  const done = () => {
    setAfter(null);
    onChanged();
  };

  let body: ReactNode = null;

  if (after === 'appreciation') {
    body = (
      <>
        <Text style={styles.body}>
          Has your match done something that meant something to you? Want to tell them?
        </Text>
        <Buttons>
          <Small label="Tell them" tone="accent" onPress={() => { done(); onWriteToThem(); }} />
          <Small label="Not now" onPress={done} />
        </Buttons>
      </>
    );
  } else if (after === 'thanks') {
    body = (
      <>
        <Text style={styles.body}>
          Thanks for being honest. Nothing changes unless you both feel the same way.
        </Text>
        <Buttons><Small label="OK" onPress={done} /></Buttons>
      </>
    );
  } else if (after === 'fading') {
    body = (
      <>
        <Text style={styles.body}>
          That happens. A new question or a change of pace can help. And if it's run its course,
          ending kindly from About is always okay.
        </Text>
        <Buttons>
          <Small label="Give me a question" tone="accent" onPress={() => { done(); onAskQuestion('any'); }} />
          <Small label="OK" onPress={done} />
        </Buttons>
      </>
    );
  } else {
    switch (prompts.prompt) {
      case 'checkin':
        body = (
          <>
            <Text style={styles.heading}>A quick check-in</Text>
            <Text style={styles.body}>You've been talking for a while. Are you enjoying this conversation?</Text>
            <Note>
              Only you see your answer. If you both say yes, or both say no, we'll tell you both.
              Otherwise nothing changes.
            </Note>
            <Buttons>
              <Small label="Yes" tone="accent" disabled={busy}
                onPress={() => run(() => answerCheckin(matchId, true), () => setAfter('appreciation'))} />
              <Small label="Not really" disabled={busy}
                onPress={() => run(() => answerCheckin(matchId, false), () => setAfter('thanks'))} />
              <Small label="Ask me later" disabled={busy} onPress={later} />
            </Buttons>
          </>
        );
        break;
      case 'strengthened':
        body = (
          <>
            <Text style={styles.body}>
              You both said you're enjoying this. Deeper questions are open whenever you'd like one.
            </Text>
            <Buttons>
              <Small label="Show me one" tone="accent" disabled={busy}
                onPress={() => run(() => snoozePrompt(matchId, 'strengthened'), () => { onChanged(); onAskQuestion('deep'); })} />
              <Small label="OK" disabled={busy} onPress={later} />
            </Buttons>
          </>
        );
        break;
      case 'mutual':
        body = (
          <>
            <Text style={styles.body}>
              You both felt this one isn't quite clicking. That's about the fit, not about either of
              you.
            </Text>
            <Buttons>
              <Small label="End it together" tone="accent" disabled={busy} onPress={async () => {
                const ok = await confirmAction(
                  'End this match for both of you?',
                  'You\'ll both see that you ended it together. You won\'t be matched with each other again.',
                  'End match',
                );
                if (ok) await run(() => mutualExit(matchId), onEnded);
              }} />
              <Small label="Keep talking" disabled={busy} onPress={later} />
            </Buttons>
          </>
        );
        break;
      case 'pulse':
        body = (
          <>
            <Text style={styles.body}>
              Quiet start? That's normal, and it's often the same on both sides. The first message
              is the hardest one.
            </Text>
            <Buttons>
              <Small label="Give me an opener" tone="accent" onPress={() => onAskQuestion('opener')} />
              <Small label="Not now" disabled={busy} onPress={later} />
            </Buttons>
          </>
        );
        break;
      case 'bridge':
        body = (
          <>
            <Text style={styles.body}>
              It's been a couple of weeks. Quiet stretches are part of most friendships. Want to pick
              things back up?
            </Text>
            <Buttons>
              <Small label="Give me a catch-up question" tone="accent" onPress={() => onAskQuestion('catch_up')} />
              <Small label="Not now" disabled={busy} onPress={later} />
            </Buttons>
          </>
        );
        break;
      case 'health':
        body = (
          <>
            <Text style={styles.heading}>How's this connection feeling?</Text>
            <Note>Only you see this. It helps Kindred learn which matches work.</Note>
            <Buttons>{(
              [['growing', 'It\'s growing'], ['steady', 'It\'s steady'], ['fading', 'It\'s fading'], ['unsure', 'Not sure']] as const
            ).map(([value, label]) => (
              <Choice key={value} label={label} selected={feeling === value} onPress={() => setFeeling(value)} />
            ))}</Buttons>
            <Text style={styles.label}>Does it feel balanced?</Text>
            <Buttons>{(
              [['balanced', 'We both put in'], ['mostly', 'Mostly'], ['one_sided', 'It feels one-sided'], ['unsure', 'Not sure']] as const
            ).map(([value, label]) => (
              <Choice key={value} label={label} selected={balance === value} onPress={() => setBalance(value)} />
            ))}</Buttons>
            <Buttons>
              <Small label="Save" tone="accent" disabled={busy || !feeling} onPress={() =>
                run(() => answerHealthCheck(matchId, feeling!, balance), () => {
                  if (feeling === 'fading' || balance === 'one_sided') setAfter('fading');
                  else onChanged();
                })} />
              <Small label="Not now" disabled={busy} onPress={later} />
            </Buttons>
          </>
        );
        break;
      case 'deepen':
        body = (
          <>
            <Text style={styles.body}>
              You two have been talking for a while. If it feels right, try something new together:
              a voice call, a game online, or watching something at the same time. Or try a deeper
              question.
            </Text>
            <Buttons>
              <Small label="Give me a deeper question" tone="accent" disabled={busy}
                onPress={() => run(() => snoozePrompt(matchId, 'deepen'), () => { onChanged(); onAskQuestion('deep'); })} />
              <Small label="Got it" disabled={busy} onPress={later} />
            </Buttons>
          </>
        );
        break;
    }
  }

  if (!body) return null;
  return (
    <View style={{ paddingHorizontal: 12, paddingTop: 8 }}>
      <Card>
        {body}
        {error && <Text style={styles.error} accessibilityLiveRegion="polite">{error}</Text>}
      </Card>
    </View>
  );
}

// A question to start from. "Use it" puts it in the message box to edit or
// send; nothing is ever sent for you.
export function QuestionPicker({
  kind,
  ladder,
  onUse,
  onClose,
}: {
  kind: QuestionKind;
  ladder: number;
  onUse: (text: string) => void;
  onClose: () => void;
}) {
  const [questions, setQuestions] = useState<ConversationPrompt[]>([]);
  const [index, setIndex] = useState(0);
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    setLoaded(false);
    getConversationPrompts(kind, ladder)
      .then((list) => {
        // Deeper questions first when they're open, shuffled.
        const shuffled = [...list].sort(() => Math.random() - 0.5);
        setQuestions(kind === 'deep' ? shuffled.sort((a, b) => b.level - a.level) : shuffled);
        setIndex(0);
      })
      .catch(() => setQuestions([]))
      .finally(() => setLoaded(true));
  }, [kind, ladder]);

  const question = questions[index];
  return (
    <View style={{ paddingHorizontal: 12, paddingTop: 8 }}>
      <Card>
        <Note>A question you could ask</Note>
        <Text style={styles.body}>{question?.body ?? (loaded ? 'No questions here yet.' : 'Loading…')}</Text>
        <Buttons>
          <Small label="Use it" tone="accent" disabled={!question} onPress={() => question && onUse(question.body)} />
          <Small label="Another" disabled={questions.length < 2}
            onPress={() => setIndex((i) => (i + 1) % questions.length)} />
          <Small label="Close" onPress={onClose} />
        </Buttons>
        {ladder < 3 && (
          <Note>
            {ladder === 1
              ? 'Deeper questions open as you get to know each other.'
              : 'The deepest questions open once you both say you\'re enjoying this.'}
          </Note>
        )}
      </Card>
    </View>
  );
}
