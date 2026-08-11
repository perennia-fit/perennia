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
