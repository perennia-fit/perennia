---
name: perennia
description: Use Perennia's agent API from code execution when Claude, Codex, or another agent needs to query, analyze, or log Perennia workout, nutrition, Metric, or Protocols data with reusable JavaScript client/reducer scripts, bounded REST calls, or the /mcp endpoint.
---

# Perennia

## Overview

Use this skill when an agent needs to interact with a Perennia
server from a code execution environment. The intended path is code-first:
write a short script against the bundled client helper, fetch bounded slices,
reduce inside the sandbox, and return only compact results to model context.
This works the same way for Claude-family agents (Claude Code, Claude in a
code-execution tool) and for Codex or another code-executing agent — the
skill and its scripts have no host-specific behavior.

The Perennia server remains REST/OpenAPI-first. MCP tools are adapters over the same
operations (`apps/server/src/agent-mcp.ts`, thin adapters — no forked logic),
and this skill gives code-executing agents reusable scripts for the workout,
nutrition, Metric, and Protocols API surface. When the runtime is MCP-native
(no code execution sandbox available), call the same operations over `/mcp`
instead — see [MCP path](#mcp-path) below. Code-first is still preferred
whenever a sandbox is available: it lets an agent reduce a bounded read
in-process instead of returning a raw payload to model context.

When working inside the Perennia repository or another workspace that has
`@perennia/contract` installed, prefer the generated
`PerenniaAgentClient` client for typed application code. The bundled
`scripts/prn-code.mjs` helper imports that generated client when available and
falls back to a portable client with the same method names when the package is
not installed. Use `scripts/prn-agent.mjs` for raw one-command REST calls.

## MCP path

When code execution is unavailable, an agent can reach the identical set of
operations over Streamable HTTP MCP at `POST /mcp` (mounted in
`apps/server/src/app.ts`, stateless — a fresh `McpServer` + transport per
request, JSON responses enabled). Authenticate exactly like REST: an
`Authorization: Bearer <agent API key>` header, resolved through the same
`authenticateToolCall`/`authenticateAgentOperation` path (including per-key
rate limiting) — one key, one Activity Log accountability trail,
regardless of transport. Tool names follow `agent_<operation>` (for example
`agent_list_workouts`, `agent_batch_write_workout`, `agent_list_activity`,
`agent_undo_activity_batch`); every tool declares `outputSchema` and mirrors
one row of the [command map](references/api-operations.md). The `apiKey`
tool-input field some schemas still accept is deprecated — the header is
canonical; it is retained only for in-process transports (like tests) with no
HTTP request to carry a header on.

## Setup

Set these environment variables in the code execution environment:

```bash
export PRN_BASE_URL="https://perennia.example.com"
export PRN_AGENT_API_KEY="prn_agent_..."
```

For local development, `PRN_BASE_URL` is commonly `http://localhost:3000`.

Run the script help before the first call:

```bash
node scripts/prn-code.mjs --help
node scripts/prn-agent.mjs --help
```

## Workflow

1. Prefer `scripts/prn-code.mjs` or a short script importing it. Fetch with
   `limit`, `from`, `to`, `metricKey`, `metricId`, `exerciseId`, or `fields`,
   then reduce in code before returning anything to the model.
2. For writes, create a JSON request file in the execution workspace and run the
   matching command with `--dry-run` first.
3. Execute the write only after the JSON is complete and idempotent. Every write
   request must include a stable `idempotencyKey`.
4. Parse stdout as JSON. Treat nonzero exits as failed API calls; diagnostics go
   to stderr, while stdout remains structured JSON.
5. For raw CLI reads, use server-side `fields` projections and `--select` to
   copy only the subtrees needed by the next computation.

## Commands

Use `references/code-mode.md` for importable JavaScript patterns and built-in
reducers. The raw REST command script is `scripts/prn-agent.mjs`.

Common reads:

```bash
node scripts/prn-code.mjs metric-readings-summary --query metricKey=hrv --query from=2026-06-01 --query to=2026-06-30
node scripts/prn-code.mjs effect-window-summary --query compoundId=compound-id --query metricKey=hrv --query from=2026-06-01 --query to=2026-06-30
node scripts/prn-code.mjs workouts-summary --query from=2026-06-01T00:00:00.000Z --query to=2026-06-30T00:00:00.000Z
node scripts/prn-agent.mjs probe
node scripts/prn-agent.mjs list-exercises --query search=squat --query limit=10
node scripts/prn-agent.mjs list-history-sets --query exerciseId=exercise-id --query limit=25
node scripts/prn-agent.mjs list-workouts --query from=2026-06-01T00:00:00.000Z --query to=2026-06-30T00:00:00.000Z
node scripts/prn-agent.mjs list-workout-templates --query search=push --query limit=10
node scripts/prn-agent.mjs get-workout-template --workout-template-id template-id --query componentLimit=100
node scripts/prn-agent.mjs list-routines --query limit=10
node scripts/prn-agent.mjs get-routine --routine-id routine-id --query selectedDate=2026-07-06
node scripts/prn-agent.mjs list-meals --query from=2026-06-01T00:00:00.000Z --query to=2026-06-30T00:00:00.000Z --query fields=id,mealType,startedAt,entries
node scripts/prn-agent.mjs list-foods --query search=banana --query limit=10
node scripts/prn-agent.mjs search-platform-foods --query search=chicken
node scripts/prn-agent.mjs nutrition-totals --query from=2026-06-01 --query to=2026-06-30
node scripts/prn-agent.mjs list-nutrition-goals
node scripts/prn-agent.mjs resolve-exercise --query name="Back Squat"
node scripts/prn-agent.mjs list-metrics --query metricKey=bodyWeight --query enabledOnly=true --query fields=id,name,canonicalKey,unit
node scripts/prn-agent.mjs list-metric-readings --query metricKey=sleepScore --query limit=25 --select readings[].scalarValue
node scripts/prn-agent.mjs list-compounds --query search=creatine --query limit=10 --query fields=id,name,defaultUnit
node scripts/prn-agent.mjs list-protocols --query limit=10
node scripts/prn-agent.mjs list-doses --query from=2026-06-01 --query to=2026-06-30 --query compoundId=compound-id --query limit=50
node scripts/prn-agent.mjs effect-window --query compoundId=compound-id --query metricKey=hrv --query from=2026-06-01 --query to=2026-06-30
node scripts/prn-agent.mjs read-settings
node scripts/prn-agent.mjs list-activity --query actor=agent --query limit=20
```

Common writes:

```bash
node scripts/prn-agent.mjs log-workout --file workout.json --dry-run
node scripts/prn-agent.mjs log-workout --file workout.json
node scripts/prn-agent.mjs log-meal --file meal.json
node scripts/prn-agent.mjs manage-foods --file foods.json
node scripts/prn-agent.mjs log-metrics --file metrics.json
node scripts/prn-agent.mjs log-nutrition-goals --file nutrition-goals.json
node scripts/prn-agent.mjs manage-exercise-catalog --file exercise-catalog.json
node scripts/prn-agent.mjs manage-plan-tree --file plan-tree.json --dry-run
node scripts/prn-agent.mjs manage-plan-tree --file plan-tree.json
node scripts/prn-agent.mjs materialize-workout-template --file materialize.json
node scripts/prn-agent.mjs capture-workout-template --file capture.json
node scripts/prn-agent.mjs update-workout-template-from-workout --file update.json
node scripts/prn-agent.mjs log-doses --file doses.json --dry-run
node scripts/prn-agent.mjs log-doses --file doses.json
node scripts/prn-agent.mjs manage-compounds --file compounds.json
node scripts/prn-agent.mjs manage-protocols --file protocols.json
node scripts/prn-agent.mjs update-settings --file settings.json
node scripts/prn-agent.mjs undo-activity-batch --json '{"batchId":"batch-id","idempotencyKey":"undo-key"}'
```

For `log-doses`, `manage-compounds`, and `manage-protocols`, generate UUIDv7 ids
for every newly authored row and reuse both those ids and the same
`idempotencyKey` on retry. Existing legacy ids remain valid only when editing or
archiving rows that already belong to the account. Results report `applied`,
`superseded`, `duplicate`, or `refused` per item; Dose results also carry the shared
validator's per-item `warnings[]`. A `duplicate` retry must not be resubmitted with
a new key. A `422` error with rule `idempotency_key_conflict` means the key was
reused for different work, so keep the original key with the original payload and
use a new key only for the new request.

Use `list-workout-templates`/`get-workout-template` and
`list-routines`/`get-routine` for the redesigned plan layer. Lists are
cursor-bounded with minimal default projections; detail reads carry explicit
component caps and truncation flags. Routine detail returns the Cadence slot
layout (including empty rest slots) and derives Up next from Template Links on
demand. Pass `selectedDate=YYYY-MM-DD` when asking about a weekly Routine;
rotating Routines ignore the date and advance from the latest materialized
Template Link. No rotation cursor is stored.

Use `manage-plan-tree` to create, edit, restore, or archive Workout Templates,
Template Exercises, Prescriptions, Template Groups and members, Routines,
Cadences, and Routine Entries atomically. The request is capped at 500 total
rows and must carry one stable `idempotencyKey`; retries converge on the same
client-supplied ids. Hard validation rejects the entire batch, while soft
validation warnings are returned on each affected item. Archive uses
`deletedAt`, never cascades into child rows or history, and the resulting
single Activity Log batch can be reverted with `undo-activity-batch`.

Use `materialize-workout-template` to start a new Workout from one active
Workout Template. Supply a stable `idempotencyKey`, the IANA `timezone`, and
optionally `startedAt`; add `routineId` plus its `slot` when fulfilling a
Cadence entry. The server resolves `copyPrevious` from the latest completed
Set for each Exercise (or deterministic zero-values when there is no history),
unrolls `repeat`, enforces the 100-Set cap, records one Template Link, and
nudges sync. Retrying the same key returns the same Workout and advances a
rotating Routine only once.

Use `capture-workout-template` to explicitly project one Workout into a new
Workout Template. The capture strips Set annotations, preserves entered values
and units, collapses only adjacent identical Sets into fixed Prescription
repeats, and can optionally append the new Template to a cadence-less Routine
or place it at a Cadence slot. Server-materialized Workouts carry the structure
envelope needed to preserve exact Workout Exercise order and groups. When the
response warning has rule `capture_workout_structure_unavailable`, tell the
caller that the source was recovered from Sets only and exact order, groups,
and archive state were unavailable. Use
`update-workout-template-from-workout` only when the Workout has an active
Template Link and the caller explicitly wants write-back: it replaces the
linked Template's child content while preserving Template identity, Routine
memberships, Template Links, and matching `copyPrevious` modes. Update returns
the divergence it applied and writes no plan rows when that divergence is
empty. Both commands require a stable `idempotencyKey`, reject empty Workouts,
validate atomically, and nudge sync after an applied write; logging or
materializing a Workout never writes back implicitly.

`list-activity` and `undo-activity-batch` close's accountability loop:
list the caller's own Activity Log batches (filterable by `actor`,
`entityTable`, `batchId`, `from`/`to`), then undo one by `batchId` — the
server applies the inverse images as a new ordinary write batch, never a hard
delete. Undo is atomic: if any entry in the batch no longer matches its
recorded after-image, nothing is applied and the conflicting entries are
returned instead.

When `resolve-exercise` returns `not_found` or `ambiguous`, follow its
`guidance` field back to `manage-exercise-catalog` to create the Exercise (or
disambiguate by id), then retry the original write — a User Library create-then-log
loop, no human in the loop required.

`references/api-operations.md` lists the command-to-endpoint mapping and minimal
request shapes for workout, nutrition, and metric writes.

## Data Rules

Use Perennia domain terms exactly: Workout, Logged Set, Exercise, Meal, Food Entry,
Metric, Metric Reading, Compound, Dose, Protocol, Schedule. Do not create derived
analytics or repair/recalculate state through this skill. Analytics are read from
computed endpoints only.

Never hard-delete user data. Agent writes use idempotent batch endpoints that
record Activity Log entries and sync nudges on the server.

Protocols (Compound/Dose/Protocol) is a neutral logbook: track a Compound, log a
Dose, and describe an outcome. Never categorize a Compound by substance type or
legality, and never surface Protocols values in workout/nutrition analytics. The
`effect-window` read is strictly descriptive — a before/during/after summary of an
outcome Metric around the logged Dose timeline — never a causal, efficacy, or
medical claim, and nothing it returns is stored.
