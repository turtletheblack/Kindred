import { router, Stack, useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';
import {
  FlatList,
  KeyboardAvoidingView,
  Linking,
  Platform,
  Pressable,
  Text,
  TextInput,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { useAuth } from '../../../lib/auth';
import { comboString, crisisHelp } from '../../../lib/badges';
import {
  getMatchStatus,
  getMessages,
  getPartner,
  markRead,
  onNewMessage,
  sendMessage,
  type MatchSummary,
  type Message,
  type Partner,
} from '../../../lib/matches';
import { colors, Note, styles } from '../../../lib/ui';

// One-on-one chat. No typing indicators, read receipts or unread counts.
export default function Chat() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { session } = useAuth();
  const me = session?.user.id ?? '';
  const [messages, setMessages] = useState<Message[]>([]);
  const [partner, setPartner] = useState<Partner | null>(null);
  const [status, setStatus] = useState<MatchSummary['status']>('active');
  const [draft, setDraft] = useState('');
  const [sending, setSending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!id) return;
    getMessages(id).then(setMessages).catch(() => setError('Could not load messages.'));
    getPartner(id).then(setPartner).catch(() => {});
    getMatchStatus(id).then(setStatus).catch(() => {});
    void markRead(id).catch(() => {});
    return onNewMessage(id, (m) => {
      setMessages((list) => (list.some((x) => x.id === m.id) ? list : [m, ...list]));
      void markRead(id).catch(() => {});
    });
  }, [id]);

  async function send() {
    const body = draft.trim();
    if (!body || !id) return;
    setSending(true);
    setError(null);
    try {
      const m = await sendMessage(id, me, body);
      setMessages((list) => (list.some((x) => x.id === m.id) ? list : [m, ...list]));
      setDraft('');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Message not sent. Please try again.');
    } finally {
      setSending(false);
    }
  }

  const title =
    partner?.display_name ??
    (partner?.primary_communication
      ? comboString(partner.primary_communication, partner.secondary_communication ?? '', partner.friendship ?? '')
      : 'Chat');
  const active = status === 'active';

  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: colors.background }} edges={['bottom']}>
      <Stack.Screen
        options={{
          title,
          headerRight: () => (
            <Pressable accessibilityRole="button" onPress={() => router.push(`/match/${id}/about`)} hitSlop={12}>
              <Text style={{ color: colors.accent, fontSize: 16, fontWeight: '600' }}>About</Text>
            </Pressable>
          ),
        }}
      />
      <KeyboardAvoidingView
        style={{ flex: 1 }}
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
        keyboardVerticalOffset={Platform.OS === 'ios' ? 100 : 0}
      >
        <FlatList
          inverted
          data={messages}
          keyExtractor={(m) => String(m.id)}
          contentContainerStyle={{ padding: 16, gap: 8 }}
          ListFooterComponent={
            <Note>
              Tap About to see how your match likes to talk, choose what you share, or get help.
              Long-press a message to report it.
            </Note>
          }
          renderItem={({ item }) => (
            <MessageBubble
              message={item}
              mine={item.sender_id === me}
              onReport={() => router.push(`/match/${id}/report?messageId=${item.id}`)}
            />
          )}
        />
        {error && <Text style={[styles.error, { paddingHorizontal: 16 }]} accessibilityLiveRegion="polite">{error}</Text>}
        {active ? (
          <View style={{ flexDirection: 'row', gap: 8, padding: 12, borderTopWidth: 1, borderColor: colors.border }}>
            <TextInput
              accessibilityLabel="Message"
              placeholder="Write a message"
              placeholderTextColor={colors.muted}
              value={draft}
              onChangeText={setDraft}
              multiline
              maxLength={4000}
              style={[styles.input, { flex: 1, maxHeight: 120 }]}
            />
            <Pressable
              accessibilityRole="button"
              accessibilityState={{ disabled: sending || !draft.trim() }}
              disabled={sending || !draft.trim()}
              onPress={send}
              style={({ pressed }) => [
                styles.button,
                { backgroundColor: colors.accent, marginTop: 0, justifyContent: 'center' },
                (pressed || sending || !draft.trim()) && { opacity: 0.6 },
              ]}
            >
              <Text style={styles.buttonText}>Send</Text>
            </Pressable>
          </View>
        ) : (
          <View style={{ padding: 16 }}>
            <Note>This match has ended. You can still read your conversation.</Note>
          </View>
        )}
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

function MessageBubble({ message, mine, onReport }: { message: Message; mine: boolean; onReport: () => void }) {
  return (
    <View style={{ alignItems: mine ? 'flex-end' : 'flex-start', gap: 6 }}>
      <Pressable
        onLongPress={mine ? undefined : onReport}
        accessibilityHint={mine ? undefined : 'Long-press to report this message'}
        style={{
          maxWidth: '85%',
          padding: 12,
          borderRadius: 14,
          backgroundColor: mine ? colors.accent : '#fff',
          borderWidth: mine ? 0 : 1,
          borderColor: colors.border,
        }}
      >
        <Text style={{ fontSize: 16, lineHeight: 22, color: mine ? '#fff' : colors.text }}>{message.body}</Text>
      </Pressable>
      {message.crisis && <CrisisHelp />}
    </View>
  );
}

function CrisisHelp() {
  return (
    <View style={[{ maxWidth: '90%', padding: 12, borderRadius: 12, backgroundColor: '#FFF4E5', gap: 6 }]}>
      <Text style={styles.note}>{crisisHelp.text}</Text>
      {crisisHelp.links.map((l) => (
        <Text
          key={l.url}
          accessibilityRole="link"
          onPress={() => void Linking.openURL(l.url)}
          style={{ color: colors.accent, fontWeight: '600', fontSize: 15 }}
        >
          {l.label}
        </Text>
      ))}
    </View>
  );
}
