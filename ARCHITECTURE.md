# Architecture

How Perennia is put together, at the level that stays true as features come and
go. For the vocabulary, read [CONTEXT.md](CONTEXT.md) first — the terms used here
are defined there, and they are the same terms used in code, in the API, and in
the UI.

## The shape of it

Three things ship:

| Piece | Where | What it is |
|---|---|---|
| Mobile app | `apps/mobile` | Flutter, Android + iOS. A complete logger with no account and no network. |
| Server | `apps/server` | TypeScript on Hono over Postgres. Identity, sync, and the agent surface. |
| Agent surface | `apps/server` + `packages/contract` | An OpenAPI REST API and an in-process MCP server. Agents are first-class clients, not scrapers. |

The app is the interesting one. It is not a client that caches: it is a complete
replica that happens to sync. Everything a user does resolves locally, against
SQLite, in the same frame — logging a set on a gym floor cannot wait for a
network round trip, and nothing in the app is allowed to make it.

## The app

```
Widgets  →  Controllers  →  Repositories  →  Drift (SQLite) / HTTP
```

- **Widgets** (`lib/features/*/widgets`) render and capture input.
- **Controllers** (`lib/features/*/controllers`) are Riverpod notifiers holding
  screen state.
- **Repositories** (`lib/data`, `lib/features/*/repositories`) are **the only
  layer that touches storage or the network**. If a widget imports Drift or
  `http`, that is a bug, not a shortcut.
- **Domain** (`lib/domain`) is pure logic: analytics, validation, unit handling.
  No I/O, which is what makes it directly testable and shareable with the server
  through golden vectors.

Reads are reactive: repositories expose Drift stream queries, so a write shows up
everywhere it is displayed without anything explicitly refreshing.

Analytics — records, estimated 1RM, volume, streaks — are **computed on read,
never stored**. There is no derived state to become stale, no cache to
invalidate, and no repair path to write when it inevitably goes wrong.

## The server

Hono over Postgres, with Better Auth for identity. It owns three surfaces:

- **Sync** for devices.
- **A REST API for agents**, keyed separately from user sessions.
- **An MCP server, mounted in-process**, exposing the same operations as tools.

The agent surface is not a second-class wrapper: it is generated from the same
route definitions as everything else, so an operation cannot exist for the app
and be missing for an agent.

## The contract spine

The server is the source of truth for the API. Everything else is generated from
it:

```
apps/server/src/openapi.ts
        │
        └─ packages/contract/openapi.json          the emitted contract
             ├─ packages/contract/src/agent-client.ts        TypeScript client
             ├─ apps/mobile/lib/api/perennia_api_client.dart Dart client
             └─ agent-skills/perennia/references/…           command map
```

`pnpm --filter @perennia/contract check:drift` regenerates all of it and fails if
anything differs from what is committed. That is why the generated files are in
the repository: they are the review surface. A pull request that changes the API
shows the client and command-map consequences in its own diff, so an accidental
breaking change is visible before it merges rather than after someone's agent
stops working.

`packages/contract` is Apache-2.0 for this reason — consuming the contract must
never oblige anyone to open their own client.

## Sync

Offline-first, and deliberately boring:

- Each device holds a **full replica**. Local writes commit immediately; sync
  happens afterwards, and never blocks the UI.
- Sync is **delta-based**: a push sends what changed since the last run, a pull
  applies what the server has since then.
- Conflicts resolve **last-writer-wins, silently**. There are no conflict
  dialogs — a gym floor is the worst possible place to adjudicate a merge.
- The loser of a conflict is **not lost**: it is recorded in the Activity Log,
  which is a full history of every change, agent-made ones included, each
  reversible in one action.
- **Deleting is archiving.** User-facing deletes tombstone the row so history
  survives and sync converges. Nothing cascades.
- The most sensitive domain syncs as an **opaque payload**: the server stores and
  moves it without being able to read it.

## Validation

One two-tier module per domain, shared by every caller:

- **Hard rejects** are the impossible — a negative weight, a malformed unit.
  Nothing persists.
- **Soft warnings** are the improbable — a lift ten times your last. The write
  proceeds; the caller confirms.

The UI and the agent API run the **same** rules, so an agent cannot write
something a human could not. Because the two implementations live in different
languages, they are pinned together by **golden vectors**
(`packages/golden-vectors`): language-neutral JSON cases that both the Dart and
the TypeScript suites execute. Agreement is enforced by CI, not by discipline.

## Repository map

| Path | Contents |
|---|---|
| `apps/mobile` | The Flutter app |
| `apps/server` | The sync server and agent surface |
| `packages/contract` | Emitted OpenAPI contract, generated clients, shared agent validation |
| `packages/golden-vectors` | Cross-language test vectors |
| `agent-skills/perennia` | Generated command map and skill for driving the API |
| `sidecars/`, `examples/` | Edge-run importers, and worked examples |
| `tools/` | The local CI runner, code generators, git hooks |

## Constraints worth knowing before you design

These come up in review often enough to state plainly:

- **A workout is a session with a timestamp**, not a day bucket. Training days
  are a derived view, so two sessions in one day and imported activities do not
  collide.
- **Sets are self-describing.** Values and units are stored as entered. An
  exercise's type is an input template, not a schema constraint — changing it
  never rewrites history.
- **Derived values are never stored or synced.**
- **Import and restore are merge-only.** No destructive restore path exists.
- **The app contains no analytics or tracking, in any mode.**

Each is load-bearing: violating one produces a bug that looks like a working
feature, which is the expensive kind.
