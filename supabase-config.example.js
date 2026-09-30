// LaqYan — Supabase settings (template).
// This project is plain HTML with no build step, so the browser cannot read a .env file.
// Copy this file to `supabase-config.js` (same folder as index.html) and fill in the values from
// Supabase Dashboard → Project Settings → API. Use the *publishable* (or legacy "anon") key —
// it is meant to be public. NEVER put the service_role / secret key here.
// Leave both values empty to run the app without a database (items stay on this device only).
window.LAQYAN_SUPABASE_CONFIG = {
  url: 'your_supabase_project_url',        // e.g. https://abcd1234.supabase.co
  anonKey: 'your_supabase_anon_key'        // sb_publishable_… or the legacy anon JWT
};
