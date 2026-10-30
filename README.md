# Perennia

**An open-source, AI-native workout logger.** Flexible enough to log strength, cardio,
mobility, HIIT, and calisthenics — and built from day one so your AI assistant can log
and read workouts on your behalf.

> **Status: pre-1.0 and unreleased.** The app, server, and agent surface are built and
> tested, but nothing has shipped to an app store and the API is not yet stable. Expect
> breaking changes.

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

## What is built

- **Training**: workouts, sets across any combination of dimensions, exercise groups and
  rounds, an interval timer, records and analytics computed from raw sets.
- **Plan layer**: workout templates, routines with optional cadences, capture from a
  finished workout, an up-next suggestion.
- **Nutrition**: foods, meals, nutrient targets, and file import from several trackers.
- **Protocols**: plans for what you take (supplements, peptides, hormones, medications)
  with reminders, a neutral dose log, and its observed effect on metrics.
- **Sync**: offline-first replica, delta sync, last-writer-wins with a recoverable
  activity log.
- **Agent surface**: the OpenAPI REST API, an in-process MCP server, and agent keys.

## Hosted or self-hosted

The app from the app stores signs in to the **Official Service**,
`https://api.perennia.fit`, operated by the maintainers. A build from this
repository carries no default server: you enter your own on the sign-in screen,
or bake one in at build time, so a self-built app never contacts the maintainers'
infrastructure unless you point it there.

Self-hosting is a Docker image plus Postgres, and a self-hosted deployment gets the
same agent API and MCP surface as the Official Service.

See **[docs/self-hosting.md](docs/self-hosting.md)** for the runbook: configuration,
sign-in providers, migrations, and connecting the app.

## Connecting an AI agent

An agent needs a server URL and an agent key.

- **Server URL**: the server your app signs in to — `https://api.perennia.fit` if
  you use the app from the stores, or your own server's address if you self-host.
- **Agent key**: create one in the app's account settings (you must be signed
  in). It is shown once; give it to the agent as a bearer token.

MCP clients connect to `<server URL>/mcp` with an `Authorization: Bearer <agent
key>` header. Agents that run code can use the skill in
[agent-skills/perennia](agent-skills/perennia/SKILL.md) instead.

## Documentation

| Document | What it covers |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | How the pieces fit, and the constraints that shape them |
| [CONTEXT.md](CONTEXT.md) | The vocabulary — the same words in code, API, and UI |
| [DESIGN.md](DESIGN.md) | The visual design system |
| [docs/development.md](docs/development.md) | Build and run from source; the CI gate |
| [docs/self-hosting.md](docs/self-hosting.md) | Running your own server |
| [docs/releasing.md](docs/releasing.md) | Cutting a release, and the rules that keep installs updatable |
| [CONTRIBUTING.md](CONTRIBUTING.md) | The CLA, the gate, and what a good pull request looks like |

## Contributing

Early days: the foundations are in place, but there is no stable API yet and
conventions are still settling. Issues and discussions are welcome, and small,
focused pull requests are easier to accept than large ones while things move.

Start with [CONTRIBUTING.md](CONTRIBUTING.md) — particularly the section on why
the CLA's grant is broader than the project's own licence. It is worth reading
before you sign rather than after.

## License

Copyright (C) 2026 Leonardo Pinheiro.

The licence depends on where a file lives:

| Path | Licence |
|---|---|
| `apps/mobile`, `apps/server`, `sidecars/` | [AGPL-3.0](LICENSE) |
| `packages/contract` | [Apache-2.0](packages/contract/LICENSE) |
| `packages/golden-vectors` | [Apache-2.0](packages/golden-vectors/LICENSE) |
| `examples/` | [Apache-2.0](examples/LICENSE) |
| `agent-skills/perennia` | [Apache-2.0](agent-skills/perennia/LICENSE) |

The product is copyleft; the interface artifacts a third-party agent or client has
to consume — the contract, the golden vectors, the examples, and the generated
command map — are permissive on purpose, so building against Perennia never
obliges you to open your own client.

The bundled Platform Exercise Library data asset is licensed separately under
CC-BY-SA 4.0. See
[apps/mobile/assets/seeds/platform_exercises.LICENSE.md](apps/mobile/assets/seeds/platform_exercises.LICENSE.md).
