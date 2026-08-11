# Perennia Code-Mode Patterns

Use `scripts/prn-code.mjs` when an agent can write and run JavaScript in a code
execution environment. It exports a generated-client-compatible API and small
reducers so code can fetch bounded slices, compute inside the sandbox, and return
compact results to the model.

## Client Setup

```js
import {
  createOwlAgentClient,
  metricReadingsSummary,
  nutritionPeriodSummary,
  effectWindowSummary,
  workoutsSummary
} from "./scripts/prn-code.mjs";

const client = await createOwlAgentClient();
```

Set `PRN_BASE_URL` and `PRN_AGENT_API_KEY` in the execution environment. Do not
put the agent key on argv.

When `@perennia/contract/agent-client` is importable by the current
JavaScript/TypeScript runtime, the helper uses the generated
`PerenniaAgentClient`. When the generated package is unavailable, the
helper falls back to a portable client with the same method names for the
distributed skill's agent operations.

## Reduce Before Returning

Use server-side filters and `fields`, then reduce locally:

```js
const summary = await metricReadingsSummary(client, {
  metricKey: "bodyWeight",
  from: "2026-06-01",
  to: "2026-06-30",
  limit: 200
});

console.log(JSON.stringify({ bodyWeight: summary }));
```

The output is a small summary:

```json
{
  "bodyWeight": {
    "count": 12,
    "scalarCount": 12,
    "unit": "kilogram",
    "min": 88.1,
    "max": 90.4,
    "average": 89.2,
    "latest": {
      "id": "reading-id",
      "metricId": "metric-id",
      "at": "2026-06-30T07:00:00.000Z",
      "scalarValue": 88.8,
      "unit": "kilogram"
    }
  }
}
```

Two more reducers cover the newest reads. `effectWindowSummary` wraps
`readAgentEffectWindow` and adds a `meanDelta` convenience
(`duringVsBefore`/`afterVsBefore`) on top of the before/during/after
aggregates — still `descriptiveOnly: true`, never a causal or efficacy claim
, and nothing it returns is stored:

```js
const summary = await effectWindowSummary(client, {
  compoundId: "compound-id",
  metricKey: "hrv",
  from: "2026-06-01",
  to: "2026-06-30"
});
```

`workoutsSummary` wraps `listAgentWorkouts` and reduces a bounded page to
total sets, unique exercise names touched, and the earliest/latest
`startedAt` in the page:

```js
const summary = await workoutsSummary(client, {
  from: "2026-06-01T00:00:00.000Z",
  to: "2026-06-30T00:00:00.000Z"
});
```

## Built-In Reducer CLI

For simple one-shot reductions, run the reducer CLI directly:

```bash
node scripts/prn-code.mjs metric-readings-summary \
  --query metricKey=hrv \
  --query from=2026-06-01 \
  --query to=2026-06-30 \
  --pretty
node scripts/prn-code.mjs effect-window-summary \
  --query compoundId=compound-id --query metricKey=hrv \
  --query from=2026-06-01 --query to=2026-06-30
node scripts/prn-code.mjs workouts-summary \
  --query from=2026-06-01T00:00:00.000Z --query to=2026-06-30T00:00:00.000Z
```

The CLI emits `{ ok, command, clientSource, data }`, where `clientSource` is
`generated` or `portable`.

## Method Names

The portable client reaches full method-name parity with the generated
`PerenniaAgentClient` for every agent-key-authenticated operation —
one method per row of the [command map](api-operations.md), named after the
OpenAPI `operationId` (`listAgentWorkouts`, `batchWriteAgentDoses`,
`listAgentActivity`, `undoAgentActivityBatch`, and so on). The Agent API Key
management operations (`createAgentApiKey`/`listAgentApiKeys`/
`revokeAgentApiKey`) are the one exception: they authenticate with a human
session bearer token, not an agent API key, so they are not part of this
skill's client surface. `apps/server/test/agent-skill.test.mjs` asserts this
parity against the committed `packages/contract/openapi.json` in CI.

For raw command-to-endpoint mapping and request shapes, see
`references/api-operations.md`.
