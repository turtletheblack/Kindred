# Kindred

A friendship app that matches adults one-on-one by how they communicate, not
what they like. Built with Expo (React Native) and the Supabase free tier, so
it costs nothing to run while it's small.

## What's here

- `src/app/`: the app screens (Expo Router). Sign-in, home, your private profile,
  the 18-question test and results, and each match's chat, About page and report form.
- `src/lib/`: the Supabase client, sign-in, profile, test, match and badge helpers.
- `supabase/migrations/`: the database schema, privacy rules and server functions.
- `supabase/tests/`: privacy and safety checks that run against plain Postgres.

### How privacy works

Every account is hidden. You sign in with Google or with a one-time code sent
to your email, and nobody else ever sees your email or Google account. Your profile (name, how to reach you, rough
area, time zone) is visible only to you. In each match you choose separately
whether to reveal your name, your contact, or your area to that one person.
Your partner always sees your badges, nothing more unless you reveal it.

The database enforces this with row-level security, so it holds even if
someone bypasses the app:

| Data | Who can see it |
| --- | --- |
| Your profile | You |
| Your test results and scores | You (partners see only your two badges) |
| A match and its messages | The two people in it |
| What you've revealed | You choose, per match |
| Your check-in answers | You |
| When you last opened a chat | You (no read receipts) |
| Your blocks and reports | You (admins see reports) |
| Compatibility table | Everyone signed in reads it, admins edit it |

Trust level, the admin flag, the 18+ confirmation and matches themselves can
only be changed by server functions, never directly from the app.

### Database tables

- `badges`: the 6 communication and 7 friendship badges.
- `compatibility`: one row per pair of badges with an `adjustment` that starts
  at 0. Edit it in the Supabase table editor to try out a theory; no code change needed.
- `matching_settings`: the 60-point threshold, 10% exploratory share,
  15-message check-in point and 90-day retake wait.
- `profiles`: private details, rough area and time zone, 18+ confirmation, trust level.
- `test_results`: every test taken, with answers and per-badge percentages.
  The newest one counts (`current_test_results`), so retakes are kept as history.
- `matches`: one row per pair, ever. Ending a match is a soft delete, and the
  pair can never be matched again.
- `match_reveals`, `messages`, `checkins`, `blocks`, `reports`, `match_reads`.
- `test_questions` and `test_options`: the wording of the 18 questions. Edit it
  in the table editor. Each option counts as a vote for one badge; the app never
  sees which.
- `filter_terms`: phrases the chat filter blocks, or flags so both people see
  crisis help links. Add your own in the table editor.

Server functions the app calls: `confirm_adult`, `submit_test`, `join_queue`,
`leave_queue`, `find_match`, `my_matches`, `match_partner`, `mark_match_read`,
`block_user`, `end_match`, `report_user`, `delete_my_account`.

## How the core loop works

**The test.** Questions 1 to 9 decide communication style, 10 to 18 friendship
style. Each answer is one vote for one style (communication questions have 6
answers, friendship questions 7, so every style can be told apart); a
style's percentage is its share of the 9 votes. The most-voted style in each
half becomes that badge, so everyone has two, written like `IP/SH`. Ties go
to the style picked first. Scoring happens on the server (`submit_test`), and
retakes wait 90 days.

**Matching.** Pressing *Find a match* joins the queue and matches straight away
if someone fits; otherwise the app checks again each time you open it, and
whenever anyone else joins. Each pair gets a score out of 100:

- Two slots are compared: communication (70%) and friendship (30%). Same
  badge scores 100. A different badge scores 50 plus
  half of how much each person also leans toward the other's badge, using the
  percentages, so close second choices count.
- Every pair of badges between the two people then adds its `adjustment` from
  the `compatibility` table: two communication badges count 70%, a
  communication and a friendship badge 50%, two friendship badges 30%. All
  adjustments start at 0.
- For ranking, people who have waited get +2 a day (up to +10), and each hour
  of time zone difference costs 1 point (up to 10).
- The best pairs are matched first, if they reach 60.
- About 10% of queue turns are *exploratory*: that person is paired with a
  random eligible partner whatever the score, and the match is marked
  `exploratory`, so check-in answers can later show whether the table is right.

Pairs are never matched if either has blocked the other, or if they were
matched before. Everyone must be 18+ and have taken the test. Kindred keeps to
one match at a time (`max_active_matches`). Every number above is a column in
`matching_settings`, so you can change it without touching code.

To try a theory, for example that Safe Harbor and Internal Processor get on
well, run this in the SQL Editor:

```sql
update public.compatibility set adjustment = 15, note = 'alpha data: SH + IP did well'
where badge_a = 'IP' and badge_b = 'SH';   -- badge codes in alphabetical order
```

and check any two people's score with `select public.compatibility_score('<id>', '<id>');`.

**Chat.** One-on-one, live (Supabase Realtime), with no typing indicators, read
receipts or unread counts, only a dot on Home when there's something new. Each
message goes through a filter on the server:

- phrases in `filter_terms` marked `block` are refused;
- phrases marked `crisis` go through, and both people see help links under the message;
- members below trust level 2 can't send links, emails or phone numbers (they
  can still share contact details on purpose with *What you share*);
- more than 20 messages a minute is slowed down.

**What you share.** In each match's About page you choose whether to show
your name, contact and area to that person. Nothing is shared by default.

**Safety.** Long-press a message to report it (a copy is kept), or report from
the About page. Reporting can also block. Blocking ends the match straight
away and the other person isn't told why. *Kind Exit* ends a match with an
optional note. When 3 different people have open reports about someone, their
matching and chat pause until an admin looks.

**Trust levels.** 0 New, 1 Member (18+ confirmed and test taken), 2
Established (had a two-way conversation of 15+ messages each, with no upheld
report: unlocks links), 3 Trusted (set by an admin). Levels only rise on their
own. Partners see each other's level.

### Handling reports and pauses (admins)

In the table editor, `reports` lists every report with a copy of the message.
Set `status` to `actioned` (upheld) or `dismissed`. To lift a pause or change a
level:

```sql
update public.profiles set suspended_at = null, suspended_reason = null where id = '<id>';
update public.profiles set trust_level = 3 where id = '<id>';
```

## Set up Supabase (free)

1. Create a free account at [supabase.com](https://supabase.com) and a new
   project. Pick the region closest to your users. Save the database password somewhere safe.
2. Open **SQL Editor**, and paste and run each file in `supabase/migrations/`
   in order (oldest first). If you set up an earlier version, run only the
   files you haven't run yet.
3. Under **Authentication > Sign In / Providers**, make sure **Email** is on.
   Phone sign-in needs a paid SMS provider, so it's left off for now.
4. Under **Authentication > Emails > Magic Link**, add `{{ .Token }}` to the
   template so the email contains the 6-digit code the app asks for.
5. Supabase's built-in email sender only delivers to members of your Supabase
   organization (Organization settings > Team), at about 2 emails an hour. That's
   enough for you to test sign-in yourself. Testers can use Google sign-in
   (next section), or see "Sending sign-in emails" below.
6. Under **Authentication > URL Configuration**, set **Site URL** to
   `http://localhost:8081`, and under **Redirect URLs** add `kindred://**`,
   `exp://**` and `http://localhost:8081/**`, so sign-in can return to the
   app, Expo Go, and the web version. Without these, Supabase sends people
   to `localhost:3000` after signing in.
7. Copy `.env.example` to `.env` and fill in the project URL and publishable
   key from **Project Settings > API**. Never put the secret (service role) key in the app.

To make yourself an admin, run this in the SQL Editor after you've signed in once:

```sql
update public.profiles set is_admin = true
where id = (select id from auth.users where email = 'you@example.com');
```

Note: free Supabase projects pause after a week with no activity. Opening the
dashboard and clicking **Restore** brings them back.

## Set up Google sign-in (free)

1. In Supabase, open **Authentication > Sign In / Providers > Google** and copy
   the **Callback URL** it shows (it ends in `/auth/v1/callback`).
2. Go to [console.cloud.google.com](https://console.cloud.google.com), create a
   project called Kindred, and open **Google Auth Platform** (also listed as
   "APIs & Services > OAuth consent screen").
3. Fill in the app name and your support email. For audience choose **External**.
   The only scopes needed are the basic ones (email, profile, openid), so Google
   doesn't require a review.
4. Under **Clients**, create a client of type **Web application**. Under
   **Authorized redirect URIs**, paste the callback URL from step 1. Copy the
   client ID and client secret it gives you.
5. Back in Supabase, turn Google on, paste the client ID and secret, and save.
6. While the Google app is in **Testing** mode, only people you add under
   **Audience > Test users** (up to 100) can sign in. That works well for a
   community test. Click **Publish app** when you want anyone to be able to sign in.

## Sending sign-in emails

Free email services such as Brevo (300 emails a day free) work with Supabase,
but they need a domain you own so emails don't land in spam or get dropped by
Gmail. A domain costs about $10 a year. Once you have one:

1. In Brevo, open **Senders, Domains & Dedicated IPs**, add your domain, and
   add the DNS records Brevo shows you at your domain registrar. Then create
   a sender such as `no-reply@yourdomain.com`.
2. In Brevo, open **Settings > SMTP & API > SMTP** and generate an SMTP key.
3. In Supabase, open **Authentication > Emails > SMTP Settings**, turn on
   **Enable custom SMTP**, and fill in: sender email `no-reply@yourdomain.com`,
   sender name `Kindred`, host `smtp-relay.brevo.com`, port `587`, username
   your Brevo login email, password the SMTP key.
4. Supabase then allows 30 emails an hour; raise it under
   **Authentication > Rate Limits** if needed.

## Run the app on your phone

Google sign-in needs Kindred installed as its own app, because Expo Go
can't reliably return to itself after signing in. Building the Android app
in Expo's cloud is free.

One-time setup:

1. Create a free account at [expo.dev](https://expo.dev).
2. In the project folder, run:
   ```bash
   npm install
   npx eas-cli@latest login
   npx eas-cli@latest build --profile development --platform android
   ```
   Answer **yes** when it asks to create the project or generate a keystore.
   The build takes 10 to 20 minutes, then gives you a link and QR code.
3. Open that link on your Android phone, download the APK and install it.
   Android will ask you to allow installs from your browser.

Each time you work on the app:

```bash
npx expo start
```

Open the **Kindred** app on your phone (not Expo Go) and pick your computer
from the list, or scan the QR code. Code changes show up straight away. You
only need a new build when a native package is added.

iPhones need a paid Apple developer account ($99 a year) to install
anything outside the App Store, so iPhone testing waits until that's worth it.
On a computer, press `w` after `npx expo start` to use the web version.

## Checks

```bash
npm run typecheck
PGHOST=/tmp PGUSER=postgres npm run test:db   # needs a local Postgres
```

`test:db` builds a throwaway database, applies the migrations on top of a
small stand-in for Supabase's auth, and checks the privacy rules (strangers
can't see matches or chats, hidden fields stay hidden until revealed, blocks
end matches, ended pairs are never re-matched, deleting an account removes
everything except anonymised safety reports) and the core loop (scoring,
matching order, waiting boost, exploratory matches, the message filter, trust
levels and automatic pauses).

## Not built yet

These come in later steps: the "Did you enjoy this conversation?" check-in,
connection health (5:1 ratio, reciprocity), the 72-hour pulse, inactivity
bridges and deep-question prompts, suggesting a call or meetup, push
notifications, the admin page, and scheduled backups.
