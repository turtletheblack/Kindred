import type { ReactNode } from 'react';
import { Alert, Platform, Pressable, StyleSheet, Switch, Text, TextInput, View, type TextInputProps } from 'react-native';

export const colors = {
  background: '#FBF8F3',
  text: '#2B2A28',
  muted: '#6B675F',
  accent: '#2F6F62',
  danger: '#A23B2A',
  border: '#D9D3C7',
};

export function Button({
  label,
  onPress,
  disabled,
  tone = 'accent',
}: {
  label: string;
  onPress: () => void;
  disabled?: boolean;
  tone?: 'accent' | 'danger' | 'plain';
}) {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityState={{ disabled }}
      onPress={onPress}
      disabled={disabled}
      style={({ pressed }) => [
        styles.button,
        tone === 'accent' && { backgroundColor: colors.accent },
        tone === 'danger' && { backgroundColor: colors.danger },
        tone === 'plain' && styles.plain,
        (pressed || disabled) && { opacity: 0.6 },
      ]}
    >
      <Text style={[styles.buttonText, tone === 'plain' && { color: colors.text }]}>{label}</Text>
    </Pressable>
  );
}

export function Field({ label, ...props }: TextInputProps & { label: string }) {
  return (
    <>
      <Text style={styles.label}>{label}</Text>
      <TextInput
        accessibilityLabel={label}
        placeholderTextColor={colors.muted}
        style={styles.input}
        {...props}
      />
    </>
  );
}

export function Note({ children }: { children: ReactNode }) {
  return <Text style={styles.note}>{children}</Text>;
}

// Supabase returns database errors as plain objects rather than Error
// instances, so read the message from either.
export function errorMessage(e: unknown, fallback: string) {
  if (e instanceof Error) return e.message;
  if (e && typeof e === 'object' && typeof (e as { message?: unknown }).message === 'string') {
    return (e as { message: string }).message;
  }
  return fallback;
}

// Asks before a serious action. Alert has no buttons on web, so the browser's
// confirm is used there.
export function confirmAction(title: string, text: string, actionLabel: string) {
  if (Platform.OS === 'web') return Promise.resolve(Boolean(globalThis.confirm?.(`${title}\n\n${text}`)));
  return new Promise<boolean>((resolve) =>
    Alert.alert(title, text, [
      { text: 'Cancel', style: 'cancel', onPress: () => resolve(false) },
      { text: actionLabel, style: 'destructive', onPress: () => resolve(true) },
    ], { cancelable: true, onDismiss: () => resolve(false) }),
  );
}

export function Card({ children, onPress }: { children: ReactNode; onPress?: () => void }) {
  if (!onPress) return <View style={styles.card}>{children}</View>;
  return (
    <Pressable
      accessibilityRole="button"
      onPress={onPress}
      style={({ pressed }) => [styles.card, pressed && { opacity: 0.7 }]}
    >
      {children}
    </Pressable>
  );
}

// One answer in a list of choices.
export function Choice({ label, selected, onPress }: { label: string; selected: boolean; onPress: () => void }) {
  return (
    <Pressable
      accessibilityRole="radio"
      accessibilityState={{ selected }}
      onPress={onPress}
      style={({ pressed }) => [
        styles.choice,
        selected && { borderColor: colors.accent, backgroundColor: '#E5F0ED' },
        pressed && { opacity: 0.7 },
      ]}
    >
      <Text style={styles.body}>{label}</Text>
    </Pressable>
  );
}

export function Toggle({
  label,
  value,
  onValueChange,
  disabled,
}: {
  label: string;
  value: boolean;
  onValueChange: (value: boolean) => void;
  disabled?: boolean;
}) {
  return (
    <View style={styles.toggle}>
      <Text style={[styles.body, { flex: 1 }]}>{label}</Text>
      <Switch
        accessibilityLabel={label}
        value={value}
        onValueChange={onValueChange}
        disabled={disabled}
        trackColor={{ true: colors.accent }}
      />
    </View>
  );
}

// A percentage bar for test results.
export function Bar({ label, percent }: { label: string; percent: number }) {
  return (
    <View accessible accessibilityLabel={`${label}: ${Math.round(percent)} percent`} style={{ gap: 4 }}>
      <View style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
        <Text style={styles.note}>{label}</Text>
        <Text style={styles.note}>{Math.round(percent)}%</Text>
      </View>
      <View style={styles.barTrack}>
        <View style={[styles.barFill, { width: `${Math.min(100, percent)}%` }]} />
      </View>
    </View>
  );
}

export const styles = StyleSheet.create({
  screen: { flexGrow: 1, padding: 24, gap: 12, backgroundColor: colors.background },
  title: { fontSize: 28, fontWeight: '600', color: colors.text },
  heading: { fontSize: 20, fontWeight: '600', color: colors.text, marginTop: 16 },
  body: { fontSize: 16, color: colors.text, lineHeight: 22 },
  note: { fontSize: 14, color: colors.muted, lineHeight: 20 },
  error: { fontSize: 15, color: colors.danger },
  label: { fontSize: 15, fontWeight: '500', color: colors.text, marginTop: 8 },
  input: {
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 10,
    padding: 12,
    fontSize: 16,
    color: colors.text,
    backgroundColor: '#fff',
  },
  button: { borderRadius: 10, paddingVertical: 14, paddingHorizontal: 16, alignItems: 'center', marginTop: 8 },
  plain: { borderWidth: 1, borderColor: colors.border },
  buttonText: { color: '#fff', fontSize: 16, fontWeight: '600' },
  card: {
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 12,
    padding: 16,
    gap: 6,
    backgroundColor: '#fff',
  },
  choice: {
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 10,
    padding: 14,
    backgroundColor: '#fff',
  },
  toggle: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 4 },
  barTrack: { height: 8, borderRadius: 4, backgroundColor: colors.border, overflow: 'hidden' },
  barFill: { height: 8, borderRadius: 4, backgroundColor: colors.accent },
  dot: { width: 10, height: 10, borderRadius: 5, backgroundColor: colors.accent },
});
