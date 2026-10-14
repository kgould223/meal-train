# Meal Train

A tiny, account-free meal sign-up page. One static `index.html` (no build, no libraries) hosted on GitHub Pages, backed by a Supabase Postgres database.

- People pick an open day, enter their name, what they're bringing, and optionally a phone/email.
- Whoever signs up can edit or cancel later. Their browser remembers a secret edit token, and they get an edit link to use on other devices.
- Contact info and edit tokens are never sent to the public page. View them in the Supabase dashboard.

## Customizing the train

Edit the single row in the `settings` table (Supabase dashboard → Table Editor → `settings`):

| column | meaning |
| --- | --- |
| `headline` | Page title, e.g. "Meals for Sam & Alex" |
| `message` | Intro text under the title |
| `address`, `dropoff_window`, `dietary_notes` | Shown in the info box (blank = hidden) |
| `start_date`, `end_date` | Range of meal days |
| `meal_days` | Days of the week that get a meal, `0`=Sun … `6`=Sat, e.g. `{1,3,5}` |

Changes show up on the next page load. No redeploy needed.

## Organizer tasks

- **See contact info / fix a signup:** Table Editor → `signups`.
- **Help someone who lost their edit link:** find their row in `signups` and send them
  `https://<pages-url>/#edit=<id>.<edit_token>`.

## Setup from scratch

1. Create a Supabase project and run `supabase link --project-ref <ref>` then `supabase db push`.
2. Put the project URL and **publishable** key in the two constants at the bottom of `index.html`.
3. Enable GitHub Pages for the repo (Settings → Pages → deploy from `main`, root).
