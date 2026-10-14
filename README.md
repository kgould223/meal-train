# Meal Train

A tiny, account-free meal sign-up page. One static `index.html` (no build, no libraries) hosted on GitHub Pages, backed by a Supabase Postgres database.

- People pick an open day and enter their name, email, phone, and optionally what they're bringing.
- Whoever signs up can edit or cancel later. Their browser remembers a secret edit token. On another device they tap Edit and enter the email they signed up with (10 wrong tries locks that signup).
- Email, phone, and edit tokens are never sent to the public page. View them in the Supabase dashboard.

## Customizing the train

The organizer taps **Organizer login** on the page and enters the organizer password to change all of this. Logged in, they also see each signup's phone and email and can copy all emails at once. You can also edit the single row in the `settings` table (Supabase dashboard → Table Editor → `settings`):

| column | meaning |
| --- | --- |
| `headline` | Page title, e.g. "Meals for Sam & Alex" |
| `message` | Intro text under the title |
| `address`, `dropoff_window`, `dietary_notes` | Shown in the info box (blank = hidden) |
| `ranges` | List of date ranges that get meals, e.g. `[{"start":"2026-10-14","end":"2026-10-25"},{"start":"2026-11-03","end":"2026-11-20"}]` |
| `meal_days` | Days of the week that get a meal, `0`=Sun … `6`=Sat, e.g. `{1,3,5}` |
| `skip_dates` | Specific dates with no meal (the organizer toggles these with the Skip / Add back buttons) |

Changes show up on the next page load. No redeploy needed.

## Organizer tasks

- **See contact info / fix a signup:** Table Editor → `signups`.
- **Someone can't get in (typo'd email or locked out):** fix their `email` / reset `failed_claims` to 0 in `signups`,
  or send them `https://<pages-url>/#edit=<id>.<edit_token>`, which opens their signup directly.

## Changing the organizer password

Run in the Supabase SQL editor (this also logs out existing organizer sessions):

```sql
update settings set organizer_password_hash = extensions.crypt('new password here', extensions.gen_salt('bf'));
delete from organizer_sessions;
```

## Setup from scratch

1. Create a Supabase project and run `supabase link --project-ref <ref>` then `supabase db push`.
2. Put the project URL and **publishable** key in the two constants at the bottom of `index.html`.
3. Enable GitHub Pages for the repo (Settings → Pages → deploy from `main`, root).
