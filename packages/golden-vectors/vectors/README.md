# Golden Vectors

Language-neutral fixtures shared by Dart and TypeScript tests live here. A
fixture may include a `domain` field so domain-specific parity tests can select
only the cases they implement today.

## Workout capture

`m33-workout-capture.json` is governed by the adjacent
`m33-workout-capture.schema.json` JSON Schema. Its top-level `schemaVersion`
must match the schema's constant and the Dart runner's
`workoutCaptureGoldenSchemaVersion`; a future incompatible fixture change must
increment all three together. Input intentionally contains fact-only comments,
RPE, side, completion, and timing so runners prove those fields disappear.
Expected output contains only reusable fixed Prescription content. Captured
Workout groups always declare `rounds: 1` because Workout facts do not retain a
round count and any larger inferred value would multiply the logged Sets.

## Protocol plan

`m36-protocol-plan.json` (domain `protocol-plan`) pins the Protocol Plan core
in both languages: the Schedule Rule and Protocol Period codecs, `planDays`,
`dayStatuses`, `dueUnfilled` and `effectBoundsFromLocalDates`. Each case names
its `function`, gives that function's arguments by parameter name in `input`,
and its return value in `expected`. `m36-protocol-plan-validation.json`
(domain `protocol-plan-validation`) pins `validateScheduleRule` and
`validateProtocolPeriod`, dispatched on each case's `validator`, and carries a
`limits` block that both runners assert against their limits constants. The
behaviour both files encode is specified in
[`docs/designs/protocol-schedules-and-reminders.md`](../../../docs/designs/protocol-schedules-and-reminders.md).

Each file is governed by the adjacent `.schema.json` of the same name. A
file's top-level `schemaVersion`, its schema's `schemaVersion` constant and
its runners' schema-version constants move together: an incompatible change
to a case shape increments all of them in the same change.

Cases contain no IANA timezone names. The core works only in local dates and
`HH:MM` wall-clock times, and receives "today" and "now" as inputs; a UTC
offset appears only as an input of `effect_bounds` cases.
