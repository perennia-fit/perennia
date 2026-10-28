# Protocol Target Outcome Sync Shape

*   **Author:** Leonardo Pinheiro
*   **Status:** In Review
*   **Date:** 2026-10-28

--------------------------------------------------------------------------------

## Overview

A Protocol may declare **target outcomes**: the Metrics, or Workout performance
broadly, that the user wants to watch while following it. They seed the later
Effect view (an [Effect](../../CONTEXT.md#effect) is derived and never stored). A
target outcome is a plan row in the synced table `protocol_target_outcomes`.
Two writers create these rows: the app's Protocol editor and the Agent
Protocols batch write (`POST /agent/protocols/batch-write`, MCP tool
`agent_batch_write_protocols`).

The two writers store different payloads, and the app can't read the Agent's.
When one Agent-written target outcome reaches a device, every sync pull on that
device fails from then on. This spec makes the Agent write store the payload
the app stores, makes both readers use it, and says how rows already stored in
the Agent's old shape are read.

Read these first. [CONTEXT.md](../../CONTEXT.md) has the terms used here.
[ARCHITECTURE.md](../../ARCHITECTURE.md) covers the sync model: opaque
payloads, last writer wins, and the Activity Log. [AGENTS.md](../../AGENTS.md)
has the invariants every spec must keep. The Protocol plan surface this builds
on is specified in
[Protocol Schedules and Reminders](protocol-schedules-and-reminders.md). That
spec doesn't cover target outcomes beyond saying that an Agent archives one by
setting `deletedAt`.

## The Problem

### The two payloads

The server stores every synced plan row as an opaque JSON `payload`, and a pull
returns that payload unchanged. So the payload's keys are the sync contract
between writers and readers.

The app writes a target outcome image as
(`_protocolTargetOutcomeImage`, `apps/mobile/lib/data/repositories/training_repositories.dart`):

```json
{ "id": "…", "protocol_id": "…", "kind": "metric", "metric_id": "…",
  "position": 0, "updated_at": "…", "deleted_at": null }
```

The Agent write (`prepareAgentProtocolBatchWrite`,
`apps/server/src/agent-protocols.ts`) stores:

```json
{ "id": "…", "protocol_id": "…", "metric_id": "…", "outcome_kind": "metric",
  "updated_at": "…", "deleted_at": null }
```

The Agent payload has no `kind` and no `position`. Its kind is under
`outcome_kind`, a key the app never reads.

### What the app does with the Agent's payload today

A sync pull applies each change through `_protocolTargetOutcomeCompanionFromImage`.
That function reads `kind` and `position` with `_activityRequiredString` and
`_activityRequiredInt`, which throw a `StateError` when the key is missing.

The pull quarantines a change only when it fails with an error that comes from
the row itself. `_quarantineFailureKind` (`apps/mobile/lib/features/sync/repositories/sync_repository.dart`)
lists those errors: `FormatException`, `TypeError`, `InvalidDataException`,
`ArgumentError`, and a SQLite constraint failure. A `StateError` is not on that
list, so the pull treats it as a failure that isn't the row's fault. It rolls
back the whole page and leaves the cursor where it was.

We confirmed this with a sync test. Device A creates a Protocol and pushes it.
The fake server then adds one target outcome in the Agent's shape. Device B
pulls twice. Both pulls throw
`StateError: Activity image field kind must be a string.` After them, device B
has no Protocol, no target outcome, and nothing quarantined. Its sync state is
`failed`, and its pull cursor is still null. The page held the Protocol too,
and it was rolled back with the outcome. Every later pull fetches the same page
and fails the same way. So one Agent-written target outcome stops the device
from receiving anything else.

Undo fails too, in a different way. The Agent write records the stored row's
previous payload as the change's Activity Log before-image (empty for a new
row) and its own payload as the after-image, and the app stores those images
as the server sends them. Before undoing an entry, `undoBatch` checks that the
row still matches the entry's after-image, with `_activityImagesEqualForEntity`.
The device's current image has the app's seven keys and the Agent's after-image
has six, so the check always reports the entry as `stale`, and the user can't
undo an Agent's outcome change on the app. If an old-shape before-image did get
past the check, it would be reapplied through the same decoder, which throws.

The pull path also defers an outcome whose Metric isn't on the device yet
(`_applyPulledProtocolTargetOutcomeChange`), before decoding it. When the Metric
arrives, `_applyDeferredChangesNowApplicable` applies the held change. That
loop has no quarantine catch, so any error there fails the page.

### What the Agent reads

`serializeTargetOutcome` reads `outcome_kind` and defaults it to `"metric"`.
An app-written row has no `outcome_kind`, so a `performance` outcome the user
declared in the app reads as `"metric"` through the Agent API. The read
doesn't return `position`, and it orders outcomes by id rather than by the
order the user gave them.

### What else the Agent write accepts

`outcomeKind` is any non-empty string. The app's kinds are a closed set,
`ProtocolOutcomeKind` (`metric`, `performance`), and the app's Protocol read
resolves the stored kind with `protocolOutcomeKindFromName`, which throws on
anything else. A row with an unknown kind would apply and then break every
Protocol read on the device. The app also refuses a `metric` outcome without a
Metric id (`validateProtocolTargetOutcomes`), and it never stores a Metric id
on a `performance` outcome. The Agent write checks neither.

## Goals

1.  An Agent-written target outcome applies on the app the same way an
    app-written one does: through sync pull and through undo.
2.  The Agent read returns the kind and order the user sees in the app, for
    rows from either writer.
3.  The Agent write can't store a target outcome whose kind, or whose kind
    and Metric id together, the app couldn't have written. (Whether the
    Metric exists is not checked; see Non-Goals.)
4.  Rows already stored in the Agent's old shape stay readable on both sides,
    and a device whose sync is stuck on one recovers when it updates, with no
    action from the user.

## Non-Goals

*   **Quarantining `StateError`.** Any image missing a required field throws a
    `StateError` and fails the page. That affects every synced table, not just
    this one. It is a separate change to the pull's failure handling.
*   **Rejecting duplicate target outcomes from an Agent.** The app refuses the
    same Metric twice, or `performance` twice, in one Protocol. An Agent write
    that adds a duplicate stores two rows. The app reads both and shows both,
    and its next edit of that Protocol's outcomes keeps both. That is untidy but
    it doesn't fail anything, and refusing it needs a read of stored rows. A
    later change can add it.
*   **A CONTEXT.md term for target outcome.** The phrase is used as plain
    English here, as it is in the code and the Protocol Schedules spec.
*   **The Effect view.** This spec only stores and reads the rows.
*   **Checking an Agent's `metricId` against the user's Metrics.** The app
    requires an active Metric when it writes an outcome, and its table has a
    foreign key on `metric_id`. The Agent write doesn't check that the Metric
    exists. An outcome naming a Metric the device never receives stays
    deferred there. That is today's behaviour and is unchanged.

## Open Questions

None.

## Critical User Journeys (CUJs)

### CUJ 1: An Agent adds a target outcome and the app shows it

*   **Given** a signed-in user with a Protocol on their phone, and an Agent
    with their API key,
*   **When** the Agent sends a Protocol batch write with one target outcome,
    `{ "id": "<uuidv7>", "metricId": "<metric id>", "outcomeKind": "metric" }`,
    and no `position`,
*   **Then** the server stores the outcome with `kind: "metric"` and the next
    position among that Protocol's outcomes. The phone's next pull applies it,
    and the Protocol shows the outcome after the ones it already had. Sync
    keeps working.

### CUJ 2: An Agent reads outcomes the user declared in the app

*   **Given** a Protocol whose outcomes the user declared in the app, in the
    order Weight then Performance,
*   **When** an Agent reads `GET /agent/protocols`,
*   **Then** `targetOutcomes` lists Weight with `outcomeKind: "metric"` and
    `position: 0`, then Performance with `outcomeKind: "performance"` and
    `position: 1`.

### CUJ 3: A device stuck on an old Agent-written outcome recovers

*   **Given** a device whose pulls have failed since an Agent stored a target
    outcome in the old shape (`outcome_kind`, no `position`),
*   **When** the user updates to a build with this change,
*   **Then** the next pull applies the page, the outcome included, and sync
    status returns to normal. The outcome reads with the kind the Agent sent,
    at position 0.

### CUJ 4: An Agent sends an outcome the app couldn't store

*   **Given** an Agent with a valid API key,
*   **When** it sends `outcomeKind: "mood"`, or `outcomeKind: "metric"` with
    `metricId: null`, or `outcomeKind: "performance"` with a Metric id,
*   **Then** the write is refused before anything is stored: a 400 for the
    unknown kind (the schema), and a 422 with rule `target_outcome_metric_id`
    for the other two.

## Technical Plan

### D1. One stored shape: the app's

A target outcome payload has exactly the keys the app's image has: `id`,
`protocol_id`, `kind`, `metric_id`, `position`, `updated_at` and `deleted_at`.
The Agent write stores that shape and never `outcome_kind`. The Activity Log
images of an Agent write are that payload, so undo on the app reads them too.

The app's image is the reference because the app is the main writer, the app
can't change its stored shape without a schema migration on every device, and
the server stores payloads opaquely.

### D2. The write contract

`AgentProtocolBatchWriteTargetOutcomeSchema` changes as follows. The field
names stay. `outcomeKind` is the API's name for what the payload calls `kind`,
and renaming it would break Agents for no gain.

| Field | Before | After |
| :--- | :--- | :--- |
| `outcomeKind` | any non-empty string, default `"metric"` | `"metric"` or `"performance"`, default `"metric"` |
| `position` | not accepted (the schema isn't strict, so it was silently dropped) | optional integer ≥ 0 |
| `metricId`, `id`, `updatedAt`, `deletedAt` | unchanged | unchanged |

The schema stays non-strict, as the Protocol Schedules spec records for this
object, so a sent `outcome_kind` or other extra key is still ignored.

This narrows what the write accepts. Two requests that used to succeed now
fail, and the Agent skill reference says so:

*   An `outcomeKind` other than the two kinds is a 400. That includes one with
    surrounding spaces (`" metric"`), which the old `.trim()` accepted.
*   An outcome sent as just `{ "id": … }` defaults to `metric` with a null
    `metricId`, so it is now refused with `target_outcome_metric_id` (a 422).
*   So is an archive sent as `{ "id": …, "deletedAt": … }`. An outcome write
    replaces the whole payload, as a Protocol write replaces the whole row, so
    an archive re-sends the outcome as read (its `outcomeKind` and `metricId`)
    with `deletedAt` set. Before this change such an archive was accepted, and
    it overwrote a `performance` outcome's kind with `metric`. The rule has no
    exception for archives: a tombstone in a shape the app couldn't write is
    still wrong data, and the Agent skill reference tells an Agent to re-send
    the outcome.

`prepareAgentProtocolBatchWrite` refuses an outcome whose Metric id doesn't
match its kind, with one structural rule, `target_outcome_metric_id`, on field
`protocols[i].targetOutcomes`:

*   `metric` with a null `metricId`: "A metric target outcome needs a
    metricId."
*   `performance` with a non-null `metricId`: "A performance target outcome
    has no metricId; send null."

This mirrors `validateProtocolTargetOutcomes` in the app. Like the other
structural Protocol checks in `prepareAgentProtocolBatchWrite`
(`duplicate_plan_row_id`, for example), it is a hard refusal outside the shared
two-tier validator. It isn't a validation tier and it has no golden vector.

### D3. Position

A sent `position` is stored as sent. Positions don't have to be unique or
dense: the app sorts outcomes by position, as it does Protocol Members, and the
Agent member write already accepts any position the same way.

An omitted `position` is assigned by the store, inside the write's transaction,
in `finalizeProtocolPlanRows`. That is where the store already dates Schedule
Versions from stored rows. `prepareAgentProtocolBatchWrite` stores
`position: null` as a placeholder, as it stores `effective_from: null`. The
finalize step replaces each null, in batch order:

1.  If a stored row with that id exists for this user, its payload's
    `protocol_id` is this outcome's Protocol, and its payload's `position` is
    a non-negative integer, the outcome keeps that position. So archiving an
    outcome by sending `deletedAt`, or re-sending one as read, doesn't move it.
2.  Otherwise it gets one more than the largest position in the set below, or
    0 if the set is empty. The set holds, for this outcome's Protocol:
    *   every stored row whose `deleted_at` column is null and whose id isn't
        in this batch, at its payload's `position` (0 if that isn't a
        non-negative integer); and
    *   every outcome earlier in this batch whose `deletedAt` is null, at its
        final position, whether the Agent sent it, rule 1 kept it, or this
        rule assigned it.

Outcomes later in the batch don't count, even when they carry a sent
position. So the result depends on batch order: an outcome sent with
`position: 7` after one without a position doesn't push the first past 7. That
is accepted. Positions don't have to be unique, and an Agent that cares about
the order sends positions.

A replayed batch (same idempotency key) returns before finalize runs, so it
never reassigns positions.

### D4. The read contract

`AgentProtocolTargetOutcomeSchema` (the read) gains `position`, an integer ≥ 0.
Its `outcomeKind` stays `z.string().min(1)`, with a description naming the two
kinds. It doesn't become the enum. Until this change the write accepted any
non-empty string, so a stored row can hold a kind such as `"mood"`, and
`listProtocols` parses every Protocol through `AgentProtocolSchema`. An enum
there would make one such row fail the read for the whole account. The read
returns such a kind as stored. The app quarantines that row on pull (D5). The
Agent can see it, but can't re-send it with that kind: the write schema refuses
it. To archive it, the Agent sends a valid kind and Metric id with `deletedAt`
(for example `performance` and a null `metricId`), and the archived row stores
that kind. A row the app never applied loses nothing it showed.

`serializeTargetOutcome` reads:

*   `outcomeKind`: the payload's `kind` if it is a non-empty string, else its
    `outcome_kind` if that is a non-empty string (rows stored before this
    change), else `"metric"`.
*   `position`: the payload's `position` if it is a non-negative integer,
    otherwise 0.

`listProtocols` orders each Protocol's `targetOutcomes` by `position`, then by
id with `compareIds` (the comparison this file already uses to sort members by
id). That is the app's order, with a fixed tie-break. The response still
includes archived outcomes with their `deletedAt`, as it does today.

### D5. Rows already stored in the old shape

There is no data migration. Both readers accept the old shape instead:

*   The Agent read falls back to `outcome_kind` (D4).
*   The app decoder, `_protocolTargetOutcomeCompanionFromImage`, uses the
    image's `kind` if it is a string, else its `outcome_kind` if that is a
    string. If neither is, it throws a `FormatException`. This is the same rule
    as the Agent read, except that the read falls back to `"metric"` where the
    decoder throws. The decoder resolves the kind with
    `protocolOutcomeKindFromName`, so an unknown kind throws an `ArgumentError`
    and the pull quarantines that change instead of storing a row the app
    can't read. Both errors are on `_quarantineFailureKind`'s list, so a bad
    kind fails only this one row and doesn't stall the pull.
*   It reads `position` as an integer, using 0 when the key is absent or null,
    and throws a `FormatException` when it is anything else. That uses a new
    helper, not `_activityNullableInt`, whose `StateError` would stall the
    pull.
*   **Deferred changes.** `_applyDeferredChangesNowApplicable` applies each
    held change in its own savepoint and quarantines it on an error that
    `_quarantineFailureKind` recognises, as the main pull loop does. The held
    change is dropped from `deferred_sync_changes` before the savepoint, as it
    is today, so a quarantined change moves from one table to the other. Any
    other error still fails the page.
*   **Undo on the app.** `_activityImagesEqualForEntity` normalises both
    images of a `protocol_target_outcomes` entry before comparing them: a
    `kind` that isn't a string is replaced by `outcome_kind` when that is a
    string, `outcome_kind` is removed, and a missing or null `position`
    becomes 0. This is the same rule as the decoder, so an entry that an Agent
    wrote before this change compares equal to the row it produced and can be
    undone. Its before-image, if any, then applies through the decoder.

A device that is stuck (CUJ 3) never advanced its cursor past the failing page.
After the update, its next pull fetches that page again and applies it. The
server returns the stored payload (with `updated_at` and `deleted_at` set from
the row's clock, as for every entity), so this works without touching the
server's rows.

A migration that rewrote stored payloads wouldn't be enough on its own. The
Activity Log keeps the old shape in its before- and after-images, and those are
append-only history. Undo on the app reads them through the same decoder, so
the decoder needs the fallback either way. With the fallback in place, a
migration adds nothing.

An old row takes the new shape the next time the app or an Agent batch write
rewrites it, since both write the whole payload. A third writer can store the
old shape again: an Agent undo on the server (`agent-activity.ts`, through
`UNDOABLE_ENTITY_REGISTRY` and `inversePayload`) pushes a recorded image back
as it was recorded. Undoing an Agent write made before this change can
therefore restore an old-shape payload. Both readers accept it, so this is
left as it is.

### Agent surface

*   **REST:** `POST /agent/protocols/batch-write` and `GET /agent/protocols`,
    as in D2 and D4. No new operation.
*   **MCP:** `agent_batch_write_protocols` and the Protocol read tool use the
    same Zod schemas, so they change identically. No new tool.
*   **Contract diff** (`packages/contract/openapi.json` and the generated
    `agent-client.ts`): `AgentProtocolBatchWriteTargetOutcome.outcomeKind`
    becomes an enum of `metric` and `performance`, and gains an optional
    `position`. `AgentProtocolTargetOutcome` gains a required `position`; its
    `outcomeKind` stays a string, with a new description (D4). The Dart API
    client (`apps/mobile/lib/api/perennia_api_client.dart`) has no Agent
    Protocol types, so it doesn't change.
*   **Agent skill:** the Protocol write example in
    `agent-skills/perennia/references/api-operations.md` documents the two
    kinds, `position` and its default, the new refusal, and the two requests
    that no longer succeed (D2).

### Invariants

*   **Sync is silent LWW with recoverable losers.** Preserved. Nothing about
    last-writer-wins changes. The decoder fallback turns a page-stalling failure
    into an applied row, and an unreadable kind into a quarantined change,
    which stays recoverable.
*   **Validation is one shared two-tier module.** Not touched. The new refusal
    is structural, like the app's `validateProtocolTargetOutcomes`, and the
    shared validator's rules and golden vectors don't change (D2).
*   **Derived analytics are never stored.** Preserved. A target outcome is plan
    data, and no Effect is computed or stored.
*   **User-facing delete = archive; no cascading deletes.** Preserved. An Agent
    still archives an outcome by sending `deletedAt`, now with the outcome's
    kind and Metric id as read (D2). That keeps its position (D3) and touches
    nothing else.
*   **Restore/import is merge-only.** Not touched.
*   **Local writes never block on the network.** Not touched. The change is on
    the pull and Agent paths only.
*   The other invariants (Workout as session, self-describing sets, no
    behavioral analytics) are unrelated.

### Validation and analytics

The shared two-tier validator and its golden vectors don't change. The Agent
write gets one structural hard refusal, `target_outcome_metric_id` (D2). The
unknown-kind refusal comes from the schema. No analytics computation changes.

## Alternatives Considered

### Alternative A: Change the app to the Agent's shape

Make the app write and read `outcome_kind`. This was rejected because the app
is the main writer and its rows are already on devices and on the server. It
would also need a decoder fallback in the other direction, and the Agent shape
has no position, which the app needs.

### Alternative B: Default the position to 0, as the member write does

The Agent member write defaults `position` to 0. Doing the same here needs no
stored read. It was rejected because every Agent-added outcome would sort
first, ahead of the user's own, and in an order that depends on ids. Assigning
the next position appends, which is what the user expects. The store already
reads the Protocol's rows in finalize, so it costs one more query.

### Alternative C: A server data migration

Rewrite stored `outcome_kind` payloads into the new shape. This was rejected
under D5: the Activity Log images keep the old shape, so the decoder needs the
fallback anyway.

### Alternative D: Quarantine `StateError` in the pull

That would stop one bad row from stalling a device, but the row would still
never apply, and the Agent would keep writing rows the app can't read. It is
worth doing for every table (Non-Goals), but it doesn't fix this bug.

## Non-Functional Requirements

*   **Performance:** finalize adds one select per batch, of the target outcome
    rows for the batch's ids and Protocol ids, and only when the batch has a
    target outcome without a position. It is filtered by `user_id`, which is
    indexed (`(user_id, updated_at)`), and then by
    `payload->>'protocol_id'`, which isn't. The member select in finalize
    already works the same way, and one user's outcome rows are few. Batches are capped at 50 target outcomes
    per Protocol (`AGENT_PROTOCOL_BATCH_WRITE_MAX_TARGET_OUTCOMES`).
*   **Privacy:** no new logging. Quarantined changes stay in
    `quarantined_sync_changes`, as they do today, and nothing about their
    content is logged.

## Detailed Implementation Plan

### Server

*   `apps/server/src/agent-protocols.ts`
    *   `AgentProtocolBatchWriteTargetOutcomeSchema`: `outcomeKind` becomes
        `z.enum(["metric", "performance"]).default("metric")`, with a
        description of the two kinds. Add `position:
        z.number().int().min(0).optional()`, with a description of D3.
    *   `AgentProtocolTargetOutcomeSchema`: keep `outcomeKind` as
        `z.string().min(1)` and add a description naming the two kinds and
        saying an older row may hold another value (D4); add `position:
        z.number().int().min(0)`.
    *   `prepareAgentProtocolBatchWrite`, target outcome loop: refuse with
        `target_outcome_metric_id` (D2) and `continue`. Store the payload as
        `{ id, protocol_id, kind, metric_id, position: outcome.position ??
        null, updated_at, deleted_at }`.
    *   `finalizeProtocolPlanRows`: take `targetOutcomes: PreparedRow[]` as a
        new input, and pass it from `writeProtocolBatch`. When any target
        outcome has `position: null`, select the stored
        `protocol_target_outcomes` rows for this user whose id is in the batch
        or whose `payload->>'protocol_id'` is one of the batch's Protocol ids
        (with `selectStoredPlanRows`, as for members; widen its `table`
        parameter to accept `schema.protocolTargetOutcomes`). Assign positions
        as D3 says, in batch order, writing each into `row.payload.position`.
    *   `serializeTargetOutcome`: as D4, with a docstring saying why it falls
        back to `outcome_kind`.
    *   `listProtocols`: order `targetOutcomes` by position, then by id with
        `compareIds`.
*   `packages/contract/openapi.json` and `packages/contract/src/agent-client.ts`:
    regenerated with
    `corepack pnpm --filter @perennia/contract run generate`. Commit the
    result; the contract job's drift check fails otherwise.
*   `agent-skills/perennia/references/api-operations.md`: as in Agent
    surface. The Protocol write example and its prose are hand-written (only
    the command map between the `GENERATED` markers is generated).

### App

*   `apps/mobile/lib/data/repositories/training_repositories.dart`:
    *   `_protocolTargetOutcomeCompanionFromImage` (which the pull reaches
        through `_protocolTargetOutcomeSyncCompanionFromImage`): read the kind
        and position as D5 says, through two small helpers next to it. Resolve
        the kind with `protocolOutcomeKindFromName` and store its `.name`. The
        docstring says why the fallbacks exist and that only rows an Agent
        stored before this change need them.
    *   `_activityImagesEqualForEntity`: add the `protocol_target_outcomes`
        normalisation of D5, through a helper shared with the decoder's kind
        and position rules.
*   `apps/mobile/lib/features/sync/repositories/sync_repository.dart`,
    `_applyDeferredChangesNowApplicable`: wrap each held change's apply in
    `_database.transaction` and catch as the main loop does, quarantining with
    `_quarantinePulledChange` (D5).

No schema change and no migration on either side.

## Verification Plan

The gate: `pnpm ci:local --changed`, which runs `js` (server tests, against
Postgres), `contract` (codegen and drift check), `mobile` (analyze and Flutter
tests) and `sync`, as the paths require. It must be green.

### Server tests (`apps/server/test/agent-protocols.test.mjs`)

*   `prepareAgentProtocolBatchWrite` stores the app's shape: a test asserts
    the payload's keys are exactly
    `id, protocol_id, kind, metric_id, position, updated_at, deleted_at`, that
    `kind` is `"metric"`, that `outcome_kind` is absent, and that an omitted
    `position` is `null` and a sent one is kept.
*   `prepareAgentProtocolBatchWrite` refuses `metric` with a null Metric id
    and `performance` with one, with rule `target_outcome_metric_id`.
*   The batch-write route returns 400 for `outcomeKind: "mood"` and for a
    negative `position` before the store is called (in the existing
    strictness test).
*   Against Postgres: a Protocol whose stored outcomes' largest position is
    9. An Agent write that adds two outcomes without a position stores them at
    10 and 11, in batch order. Re-sending the first with `deletedAt` keeps its
    position. A sent `position: 7` is stored as 7. An old row stored with
    `outcome_kind: "mood"` is archived by re-sending it as `performance` with a
    null `metricId` and `deletedAt`.
*   Against Postgres: a row stored directly in the old shape
    (`outcome_kind: "metric"`, no position) reads through
    `GET /agent/protocols` as `outcomeKind: "metric"` at position 0, and a row
    stored in the app's shape (`kind: "performance"`, `position: 1`) reads as
    `outcomeKind: "performance"` at position 1, in that order. A row stored
    with `outcome_kind: "mood"` reads as `"mood"`, and the read still
    succeeds.

### MCP parity (`apps/server/test/agent-mcp-parity.test.mjs`)

*   The existing mapping tests still pass: no operation or tool is added. The
    MCP tool's input and output schemas are the REST ones, so the contract job
    checks them.

### App tests

*   `apps/mobile/test/features/sync/sync_agent_target_outcome_test.dart`, a
    new file, with a fake sync server like the one in
    `sync_missing_metric_reference_test.dart`:
    *   An outcome in the new Agent shape, for a Protocol pushed by device A,
        applies on device B with its kind and position. The pull's cursor
        advances, and `listProtocols` shows the outcome.
    *   An outcome in the old Agent shape (`outcome_kind`, no position)
        applies on device B with that kind at position 0. The Protocol on the
        same page applies too. This is the test that fails before the change,
        with the `StateError` described under The Problem.
    *   An outcome with an unknown kind is quarantined (`failureKind:
        "argument"`). The rest of the page applies, and the cursor advances.
    *   An outcome with neither `kind` nor `outcome_kind` is quarantined
        (`failureKind: "format"`).
    *   An outcome with an unknown kind whose Metric arrives later: it is
        deferred, then quarantined when the Metric arrives, and the page that
        brought the Metric applies.
*   An undo test, in the same file: an Agent's create of an outcome in the old
    shape, pulled with its Activity Log images, can be undone on the device
    (`undoBatch` reports no conflict and the row is tombstoned).
*   No kill-and-reopen test: the change doesn't touch the logging path.
