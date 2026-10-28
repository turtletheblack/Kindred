import type { ReactNode } from 'react';
import { Pressable, StyleSheet, Text, TextInput, type TextInputProps } from 'react-native';

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
});
