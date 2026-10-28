# Kindred

A friendship app that matches adults one-on-one by how they communicate, not
what they like. Built with Expo (React Native) and the Supabase free tier, so
it costs nothing to run while it's small.

## What's here

- `src/app/`: the app screens (Expo Router). Sign-in, home, and your private profile.
- `src/lib/`: the Supabase client, sign-in, and profile helpers.
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
| Your test results and scores | You (partners see only your three badges) |
| A match and its messages | The two people in it |
| What you've revealed | You choose, per match |
| Your check-in answers | You |
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
- `match_reveals`, `messages`, `checkins`, `blocks`, `reports`.

Server functions the app calls: `confirm_adult`, `match_partner`, `block_user`,
`end_match`, `report_user`, `delete_my_account`.

## Set up Supabase (free)

1. Create a free account at [supabase.com](https://supabase.com) and a new
   project. Pick the region closest to your users. Save the database password somewhere safe.
2. Open **SQL Editor**, paste the contents of
   `supabase/migrations/20261028000000_init.sql`, and run it.
3. Under **Authentication > Sign In / Providers**, make sure **Email** is on.
   Phone sign-in needs a paid SMS provider, so it's left off for now.
4. Under **Authentication > Emails > Magic Link**, add `{{ .Token }}` to the
   template so the email contains the 6-digit code the app asks for.
5. Supabase's built-in email sender only delivers to members of your Supabase
   organization (Organization settings > Team), at about 2 emails an hour. That's
   enough for you to test sign-in yourself. Testers can use Google sign-in
   (next section), or see "Sending sign-in emails" below.
6. Under **Authentication > URL Configuration > Redirect URLs**, add
   `kindred://**`, `exp://**` and `http://localhost:8081`, so sign-in can
   return to the app, Expo Go, and the web version.
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

## Run the app

```bash
npm install
npx expo start
```

Scan the QR code with the Expo Go app on your phone.

## Checks

```bash
npm run typecheck
PGHOST=/tmp PGUSER=postgres npm run test:db   # needs a local Postgres
```

`test:db` builds a throwaway database, applies the migrations on top of a
small stand-in for Supabase's auth, and checks the privacy rules: strangers
can't see matches or chats, hidden fields stay hidden until revealed, blocks
end matches, ended pairs are never re-matched, and deleting an account
removes everything except anonymised safety reports.

## Not built yet

These come in later steps: the 18-question test and scoring, the matching
queue, chat screens and the reveal toggles, the message filter and crisis
links, check-ins, Kind Exit, nudges, the admin page, and scheduled backups.
