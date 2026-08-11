# @perennia/contract

The Perennia server's OpenAPI contract, generated TypeScript
agent client, generated Dart client source, canonical import schemas, and the
shared two-tier agent validators — one package so the agent API surface, the
distributed code-mode skill, and the mobile client's generated bindings can
never quietly drift from the server that defines them.

Everything in this package is **generated from, or re-exported from, the
server's code-first OpenAPI document** (`apps/server/src/openapi.ts`). Nothing
here is hand-authored except the generator scripts themselves.

## What's in this package

| Export | Contents |
|---|---|
| `.` | Package metadata + the canonical-import schema re-exports |
| `./agent-client` | `PerenniaAgentClient` — a generated, typed client over every `/agent/*` operation in `openapi.json` |
| `./agent-validation` | The shared two-tier (hard-reject/soft-warn) agent validators, re-exported from the server so UI and agent callers run the *exact same* validation code |
| `./canonical-import` | Canonical import schemas for third-party fitness-tracker data (Garmin, etc.) |
| `./openapi` | The committed `openapi.json` OpenAPI 3.1 document itself |

## Generated artifacts

Running `pnpm run generate` (or its component scripts below) regenerates, in
order:

1. `openapi.json` — the OpenAPI document, generated from the server's
   code-first Zod route schemas.
2. `apps/mobile/lib/api/perennia_api_client.dart` — the mobile
   Dart client, generated from `openapi.json`.
3. `src/agent-client.ts` — the TypeScript `PerenniaAgentClient`,
   generated from `openapi.json`'s `/agent/*` operations.
4. `agent-skills/perennia/references/api-operations.md` — the
   code-mode skill's command-map table, generated from the same `/agent/*`
   operations (excluding the three Agent API Key management operations,
   which authenticate with a human session token rather than an agent key).

`pnpm run check:drift` regenerates everything and fails if the committed
files disagree — this is what CI's "Contract drift" job runs. **Never hand-edit
`openapi.json`, `src/agent-client.ts`, the generated Dart client, or the
generated block of `api-operations.md`** — change the server's route schemas
(or, for the skill command map, `src/agent-skill-reference.ts`'s command name
registry) and regenerate instead.

```bash
pnpm run generate                # regenerate every artifact
pnpm run generate:openapi        # openapi.json only
pnpm run generate:dart           # mobile Dart client only
pnpm run generate:agent-client   # TypeScript agent client only
pnpm run generate:agent-skill-reference  # skill command-map table only
pnpm run check:drift             # regenerate, then fail on any diff
```

## Using the generated agent client

```ts
import { PerenniaAgentClient } from "@perennia/contract/agent-client";

const client = new PerenniaAgentClient({
  baseUrl: "https://perennia.example.com",
  bearerToken: process.env.PRN_AGENT_API_KEY!
});

const workouts = await client.listAgentWorkouts({
  from: "2026-06-01T00:00:00.000Z",
  to: "2026-06-30T00:00:00.000Z"
});
```

The `agent-skills/perennia` skill's `scripts/prn-code.mjs` helper
imports this client when the package is installed, and falls back to a
portable client with identical method names otherwise — see that skill's
`SKILL.md` for the code-first agent workflow this package is built to support.

## Status

This package is versioned and structured for eventual publication to the
public npm registry (`publishConfig.access: "public"`), but has **not yet been
published** — see the note in this repository's PR history for for
why (a workspace dependency on `@perennia/server` that a real
npm install cannot resolve, plus requiring the project owner's npm account).
Until it is published, consume it from within this monorepo via the pnpm
workspace, or reference the generated client source
(`src/agent-client.ts`) and `openapi.json` directly.
