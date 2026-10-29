// Badge names and the short "manual" a partner sees: how to talk with
// someone who has this badge.
export type BadgeCode =
  | 'IP' | 'EP' | 'DC' | 'RC' | 'AC' | 'EC'
  | 'TL' | 'DD' | 'TA' | 'TE' | 'SH' | 'TC' | 'TB';

export const badges: Record<BadgeCode, { name: string; description: string; tip: string }> = {
  IP: {
    name: 'Internal Processor',
    description: 'Reflective, needs time to think',
    tip: 'Give them time to reply. Slow answers usually mean careful thought, not lack of interest.',
  },
  EP: {
    name: 'External Processor',
    description: 'Thinks out loud, clarifies by talking',
    tip: 'They figure things out by talking. Bounce ideas back and don\'t treat every thought as final.',
  },
  DC: {
    name: 'Direct Communicator',
    description: 'Clear, efficient, solution-focused',
    tip: 'Say what you mean. They appreciate honesty and getting to the point.',
  },
  RC: {
    name: 'Relational Communicator',
    description: 'Emotion-first, validating, warm',
    tip: 'Acknowledge feelings before solutions. Warmth goes a long way.',
  },
  AC: {
    name: 'Analytical Communicator',
    description: 'Structured, precise, detail-oriented',
    tip: 'Be specific. They enjoy details and clear reasoning.',
  },
  EC: {
    name: 'Expressive Communicator',
    description: 'Energetic, big-picture, story-driven',
    tip: 'Match their energy and share stories. They love the big picture.',
  },
  TL: {
    name: 'The Listener',
    description: 'Bonds through active listening',
    tip: 'They\'ll make space for you. Share something real, and ask about them too.',
  },
  DD: {
    name: 'Deep Diver',
    description: 'Prefers meaning over small talk',
    tip: 'Skip the small talk when you can. Ask what matters to them.',
  },
  TA: {
    name: 'The Adventurer',
    description: 'Bonds through shared experiences',
    tip: 'Suggest doing something together, even something small.',
  },
  TE: {
    name: 'The Energizer',
    description: 'Brings social energy',
    tip: 'Enjoy the energy, and say so if you need a slower pace.',
  },
  SH: {
    name: 'Safe Harbor',
    description: 'Provides emotional safety',
    tip: 'They make it safe to be yourself. Return the kindness.',
  },
  TC: {
    name: 'The Consistent',
    description: 'Routine, reliability',
    tip: 'Reliability matters to them. Follow through on what you say.',
  },
  TB: {
    name: 'The Builder',
    description: 'Growth, goals, self-improvement',
    tip: 'Ask about their goals and cheer them on.',
  },
};

export const communicationCodes: BadgeCode[] = ['IP', 'EP', 'DC', 'RC', 'AC', 'EC'];
export const friendshipCodes: BadgeCode[] = ['TL', 'DD', 'TA', 'TE', 'SH', 'TC', 'TB'];

export function badgeName(code: string | null | undefined) {
  return code && code in badges ? badges[code as BadgeCode].name : 'Unknown';
}

// e.g. "IP/RC · SH"
export function comboString(primary: string, secondary: string, friendship: string) {
  return `${primary}/${secondary} · ${friendship}`;
}

export const trustLevels = [
  { name: 'New', about: 'Confirm you\'re 18 or over and take the test to start matching.' },
  { name: 'Member', about: 'Links, emails and phone numbers in chat unlock after your first good two-way conversation.' },
  { name: 'Established', about: 'You\'ve had a good two-way conversation. Links are unlocked.' },
  { name: 'Trusted', about: 'Recognised by the Kindred team.' },
];

// Shown when someone mentions crisis words in a chat.
export const crisisHelp = {
  text: 'If you or someone you\'re talking to is struggling, you don\'t have to handle it alone.',
  links: [
    { label: 'Call or text 988 (US)', url: 'tel:988' },
    { label: 'Find a helpline in your country', url: 'https://findahelpline.com' },
  ],
};
