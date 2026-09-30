# لقيان — LaqYan

Lost & found web app for King Saud University students (Arabic RTL, with an English version).
Demo project.

## Features
- Lost / found reports, split into male and female sections, with search and filters
- Report form with photo (camera or gallery), share link, light / dark mode
- Sign-in: students with student ID + password, admins with admin name + password
- Admins: edit, delete, mark as returned, statistics dashboard, downloadable report
- **مساعد لقيان** chat assistant (Gemini): searches found items and files a lost report for the student

## Structure
| Path | What it is |
|---|---|
| `index.html` | The whole app (HTML, CSS, JS) |
| `lib/supabaseClient.js` | Creates the Supabase client |
| `supabase-config.js` | Project URL + publishable key (public by design) |
| `supabase/migrations/` | Tables `items` and `users`, security rules, admin functions |
| `supabase/seed.sql` | Sample reports |
| `supabase/functions/chat-assistant/` | Edge Function for the chat assistant |
| `assets/` | Logos and item drawings |

## Run locally
Open `index.html` through any static server, e.g.:

```bash
python -m http.server 8000
```

Then go to http://localhost:8000. Add `?backend=local` to use on-device storage instead of Supabase.

## Supabase setup
1. Run the SQL files in `supabase/migrations/` in order, then `supabase/seed.sql`.
2. Put your project URL and publishable key in `supabase-config.js` (see `supabase-config.example.js`).
3. Deploy `supabase/functions/chat-assistant` and add the secret `GEMINI_API_KEY`
   (Dashboard → Edge Functions → Secrets). Optional: `GEMINI_MODEL`.

## Demo accounts
Password `12345` for all: admin `admin`; students `443101234`, `443105678`, `444109876`.

> ⚠️ Demo only: passwords in `public.users` are stored as plain text (not readable through the API).
> Do not use real passwords.
