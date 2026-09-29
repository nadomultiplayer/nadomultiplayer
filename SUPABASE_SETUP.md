# Stormwatch Setup

The Supabase project URL and publishable key are already configured in `index.html`. The browser uses Realtime Presence for player locations and Broadcast for temporary chat. Tornadoes are stored in Postgres and moved by a server-side RPC.

## Enable Server Radar

For a fresh project, run these files in timestamp order in the Supabase SQL Editor: [base tornado setup](supabase/migrations/20260929000000_create_meadow_tornadoes.sql), [speed update](supabase/migrations/20260929010000_speed_up_meadow_tornadoes.sql), then [EF intensity and erratic movement](supabase/migrations/20260929020000_add_tornado_intensity.sql). If you already applied the base migration, run the EF migration now; it also upgrades existing storm speeds, so the speed-only migration is optional. Alternatively, initialize and link this repo with the Supabase CLI before running `supabase db push`.

## Play

1. Serve the workspace over HTTP and open `index.html` in a browser.
2. Enter a chaser name and choose a jacket color, then enter the field.
3. Open the field phone for global chat, weather radar, safe-distance contracts, or vehicle dispatch. Open a second tab in the same room to test multiplayer and the pickup's passenger seat.

The game clock is synchronized from the database RPC: one real hour advances one in-game day, with 45 minutes of daylight followed by 15 minutes of night. Radar dots are current server positions; the 10- and 20-minute locations are straight-line estimates and can change when a tornado steers.

EF0–EF5 probabilities favor weaker storms; the ratings use representative Enhanced Fujita wind ranges. Contracts reward 20 seconds in the safe band around a tracked storm. Tornado locations are server-stored, but damage, debris physics, vehicles, and contract progress are client-side prototype behavior.

The publishable key is intended for browser use. Never put a service-role key in this file. Chat and Presence have no account identity; add Supabase Auth, private-channel policies, and server-validated player/vehicle state before using this as a competitive or public game.