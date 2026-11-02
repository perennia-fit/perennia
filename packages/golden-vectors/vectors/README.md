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
and its return value in `expected`. A codec case that must fail, and an
`effect_bounds` case whose offset is outside −720 to +840 minutes, expect
`{"rejects": true}`: the runners map a codec error, or the `RangeError` the
offset guard throws, to it. `m36-protocol-plan-validation.json`
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

## Barcode candidates

`m36-barcode-candidates.json` (domain `barcode-candidates`) pins how a scanned
or typed code becomes the list of Open Food Facts barcodes to try. The app runs
it in `apps/mobile/test/domain/barcode_candidates_golden_test.dart` against
`barcodeCandidates` in `apps/mobile/lib/domain/nutrition/open_food_facts.dart`;
the server runs it in `apps/server/test/barcode-candidates.golden.test.mjs`
against `apps/server/src/barcode-candidates.ts`.

## Training progress

`m37-training-progress.json` (domain `training-progress`) pins the training
progress core in both languages: `trainingWeek` (a Training Day Status for
each day of the current week against the weekly Routines),
`summarizeTrainingWeek` (the counts per status) and `trainingDays` (the Logged
Workouts and the seconds per Focus of each date in a range). The app runs it in
`apps/mobile/test/domain/training_progress_golden_test.dart` against
`apps/mobile/lib/domain/training/training_progress.dart`; the server runs it in
`apps/server/test/training-progress.golden.test.mjs` against
`apps/server/src/analytics/training-progress.ts`. The behaviour is specified in
[`docs/designs/progress-overview.md`](../../../docs/designs/progress-overview.md)
(D0-D3).

Each case names its `function`, gives that function's arguments by parameter
name in `input`, and its full return value in `expected`. A case whose input
the function rejects (`today` outside the week, `from` after `to`, a range of
more than 366 dates) expects `{"error": "argument"}`: the runners map the Dart
`ArgumentError` and the TypeScript `RangeError` to it. The file is governed by
the adjacent `m37-training-progress.schema.json`; its `schemaVersion`, the
schema's constant and both runners' constants move together.

Dates are local `YYYY-MM-DD` dates and "today" is an input, so cases contain no
timezone. Instants are ISO-8601 UTC strings; a Workout's local date is given,
not derived from its start, which is how a session after midnight belongs to
the next date.

## Progress Measure

`m37-progress-measure.json` (domain `progress-measure`) pins the Progress
Measure core in both languages: `progressSeries` (one value per Logged Workout
for an exercise, taken from its Record Profile, with each New Best marked) and
`newBestsBetween` (the New Bests of several exercises dated in a period, newest
first). The app runs it in
`apps/mobile/test/domain/progress_measure_golden_test.dart` against
`apps/mobile/lib/domain/analytics/progress_measure.dart`; the server runs it in
`apps/server/test/progress-measure.golden.test.mjs` against
`apps/server/src/analytics/progress-measure.ts`. The behaviour is specified in
[`docs/designs/progress-overview.md`](../../../docs/designs/progress-overview.md)
(D0 and D4).

Each case names its `function`, gives that function's arguments by parameter
name in `input`, and its full return value in `expected`; a Record Profile with
no single best number (`minAssistancePerRepCount`, `completionStreak`) expects
`null`. The profile is `{dimensions, loadMode, recordProfile}`, as
`m4-analytics-pr-e1rm-volume.json` gives it, and Set values are the engine's
logged-values shape. The file is governed by the adjacent
`m37-progress-measure.schema.json`; its `schemaVersion`, the schema's constant
and both runners' constants move together.

Both cores call the existing exercise analytics engine once per Workout rather
than reimplementing it, so values are its normalized ones (kilograms,
kilometres, seconds, and seconds per kilometre for pace with unit `second`),
and the `m4-analytics-pr-e1rm-volume` vectors stay the engine's own. Values are
compared exactly: both languages compute them in IEEE doubles with the same
operations.
