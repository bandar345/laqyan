// LaqYan — the single Supabase client for the app.
// Needs, loaded before this file:
//   1. supabase-js (UMD build from jsDelivr, exposes window.supabase)
//   2. supabase-config.js (sets window.LAQYAN_SUPABASE_CONFIG)
// Exposes window.laqyanSupabase: the client, or null when not configured / library missing,
// in which case the app falls back to keeping items on this device (localStorage).
(function () {
  var cfg = window.LAQYAN_SUPABASE_CONFIG || {};
  var configured = typeof cfg.url === 'string' && /^https:\/\/.+/.test(cfg.url) &&
                   typeof cfg.anonKey === 'string' && cfg.anonKey.length > 20 &&
                   cfg.anonKey.indexOf('your_') !== 0;
  window.laqyanSupabase = null;
  if (!configured) return;
  if (!window.supabase || typeof window.supabase.createClient !== 'function') {
    console.error('LaqYan: supabase-js did not load; using on-device storage instead.');
    return;
  }
  window.laqyanSupabase = window.supabase.createClient(cfg.url, cfg.anonKey, {
    auth: { persistSession: false, autoRefreshToken: false }   // no sign-in in this demo
  });
})();
