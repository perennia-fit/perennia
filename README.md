# Perennia

**An open-source, AI-native workout logger.** Flexible enough to log strength, cardio,
mobility, HIIT, and calisthenics — and built from day one so your AI assistant can log
and read workouts on your behalf.

> **Status: early development.** The design is settled (see roadmap below); the apps are
> being built. This README describes where the project is going, not a shipped product.

---

## Why another workout logger?

Perennia takes the flexible, low-friction logging model that makes
[FitNotes](https://www.fitnotesapp.com) great and rebuilds it as something new:

- **Open source.** Your training data is yours — exportable, self-hostable, never held hostage.
- **AI-native.** A public, documented API (and an MCP server) lets authorized AI agents
  log workouts, answer questions about your history, and help you program — as
  first-class clients, not screen-scrapers.
- **Genuinely flexible logging.** Most apps hard-code a strength-or-cardio worldview.
  Here, an exercise is defined by the *dimensions* it measures — any combination of
  **load, reps, duration, distance**, or none at all — so a barbell lift, an assault-bike
  interval, a timed plank, and a "just track completion" mobility flow are all
  first-class.
- **Cross-platform.** One Flutter app for **Android and iOS** (FitNotes is Android-only).
- **Offline-first, never offline-only.** Fully functional with no account; sign in to
  sync across devices and unlock the agent API.

## Highlights of the design

- **Sessions, not day-buckets.** A workout is a session with a real timestamp, so
  multiple sessions a day and integration-imported activities don't collide — while the
  everyday one-session-a-day experience stays simple.
- **Routines & prescriptions.** Programmed training (5×5, Tabata, EMOM, circuits) is
  expressed with repeat counts, planned rest, and rounds; an interval timer walks the
  plan and logs sets as you go.
- **Honest analytics.** Personal records are computed from raw sets (never a stale
  cache), and each exercise picks the record that matters — heaviest set, most reps,
  longest hold, fastest pace, or least assistance.
- **Your data, recoverable.** Portable, versioned backups; merge-only import (no
  destructive restore); a full activity log with one-tap undo of any change — including
  changes an agent makes.
- **Privacy by default.** No behavioral analytics, ever. Crash reporting is opt-in and
  off by default.

## Architecture at a glance

| Layer | Technology |
|---|---|
| Mobile app | Flutter (Android + iOS), Drift (SQLite), Riverpod |
| Server | TypeScript on Hono, Postgres, Better Auth |
| Agent surface | OpenAPI REST + in-process MCP server |
| Sync | Offline-first replica; delta sync, last-writer-wins |
| Hosting | Containerized; managed cloud (primary) or self-hosted (supported) |

The device is a fully functional offline replica. When you sign in, the server becomes
the system of record and AI agents and (later) fitness-platform integrations write
through it; devices stay in sync.

## Roadmap

Development follows a three-rung ladder — **build offline-first, launch AI-native**:

1. **Alpha** — the complete offline logger (logging, routines, interval timer, analytics,
   backups). No account required.
2. **Beta** — accounts, cross-device sync, automatic backup, body tracker.
3. **1.0** — the public agent API and MCP server: *your AI assistant can log your workouts.*

Fitness-platform integrations (trackers), advanced visualizations, goals, and a FitNotes
importer are planned for after 1.0.

## Self-hosting

Self-hosting will be a supported, developer-grade option (a Docker image + Postgres) for
contributors and privacy-minded users — the hosted service is the primary way to use the
app, but you are never locked to it: the mobile app can point at any server.

Server auth uses Better Auth in-process. Set `PUBLIC_SERVER_URL` or
`BETTER_AUTH_URL` to the public server origin and register these OAuth redirect
URIs with the providers:

- Google: `${PUBLIC_SERVER_URL}/api/auth/callback/google`
- Apple: `${PUBLIC_SERVER_URL}/api/auth/callback/apple`

Configure Google with `GOOGLE_OAUTH_CLIENT_ID` and
`GOOGLE_OAUTH_CLIENT_SECRET`; `GOOGLE_OAUTH_HOSTED_DOMAIN` is optional for a
Google Workspace hosted-domain restriction. Configure Apple with
`APPLE_OAUTH_CLIENT_ID` and `APPLE_OAUTH_CLIENT_SECRET`; optionally set
`APPLE_OAUTH_APP_BUNDLE_IDENTIFIER` and comma-separated `APPLE_OAUTH_AUDIENCE`
when your Apple setup needs explicit bundle or service audiences.

## Contributing

The project is in early development and not yet ready for broad contribution. Issues and
discussions are welcome as the foundations land.

## License

Perennia application source code is licensed under the GNU Affero General
Public License v3.0. See [LICENSE](LICENSE).

The bundled Platform Exercise Library data asset is licensed separately under
CC-BY-SA 4.0. See
[apps/mobile/assets/seeds/platform_exercises.LICENSE.md](apps/mobile/assets/seeds/platform_exercises.LICENSE.md).
