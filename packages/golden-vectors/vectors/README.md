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
offset guard throws, to it.

The plan file is at schema version 2. Version 2 (the spec's D8) closes a
Protocol's archive day and adds Skips to matching, which changed every case's
shape: each PlanDay carries `archiveDay`, each Day Status `skippedCount`, each
fill `skipId`, and each `day_statuses` input a `skips` list.

`m36-protocol-plan-validation.json` (domain `protocol-plan-validation`) pins
`validateScheduleRule`, `validateProtocolPeriod` and, for Skips,
`validateProtocolSkip` (`validateAgentProtocolSkip` in TypeScript), dispatched
on each case's `validator`, and carries a `limits` block that both runners
assert against their limits constants. Adding the Skip validator only added a
case branch, so that file stays at schema version 1. The behaviour both files
encode is specified in
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

## Trend

`m37-metric-trend.json` (domain `metric-trend`) pins the Trend core in both
languages: `metricTrend`, a time-weighted moving average of a Metric's
Readings in which one Reading a day moves the Trend 10% of the way towards it.
The app runs it in `apps/mobile/test/domain/metric_trend_golden_test.dart`
against `apps/mobile/lib/domain/metrics/metric_trend.dart`; the server runs it
in `apps/server/test/metric-trend.golden.test.mjs` against
`apps/server/src/analytics/metric-trend.ts`. The behaviour is specified in
[`docs/designs/progress-overview.md`](../../../docs/designs/progress-overview.md)
(D5).

Each case names its `function`, gives that function's arguments by parameter
name in `input`, and its full return value in `expected`. A Reading's `value`
is a number, `null`, or one of the strings `"NaN"`, `"Infinity"` and
`"-Infinity"`, which the runners decode to the IEEE value, because JSON cannot
spell a non-finite number. The file is governed by the adjacent
`m37-metric-trend.schema.json`; its `schemaVersion`, the schema's constant and
both runners' constants move together.

Unlike the other M37 files, this one has a top-level `tolerance` (`1e-9`). The
runners compare every `trend` field within it, because `pow` can differ in the
last bit between Dart and JavaScript, and compare everything else exactly.

## Meal History

`m38-meal-history.json` (domain `meal-history`) pins Meal History in both
languages: the distinct meals a user repeats, derived on each read from their
active timed Meals in the last 90 days that hold two or more distinct Foods,
and never stored. The app runs it in
`apps/mobile/test/domain/meal_history_golden_test.dart` through
`NutritionRepository.listMealHistory` against in-memory SQLite; the server
runs it in `apps/server/test/meal-history.golden.test.mjs` against
`buildMealHistory` in `apps/server/src/meal-history.ts`. The behaviour is
specified in
[`docs/designs/meal-logging.md`](../../../docs/designs/meal-logging.md) (§5).

Each case gives `now`, `limit`, the Meals (with their `timePrecision`), the
Food Entries (with their snapshot `name` and Portion) and the archived User
Food ids in `input`, and the ordered items in `expected`: the Foods in
canonical order, `count`, `lastMealId` and `lastStartedAt`. A Meal's identity
is its canonical string, the distinct `foodSource:foodId` keys in ordinal
(byte) order joined with `|`; items are ordered by count, then the latest
start, then the canonical string. Instants are ISO-8601 UTC strings in whole
seconds, as the app stores them. The file is governed by the adjacent
`m38-meal-history.schema.json`; its `schemaVersion`, the schema's constant and
both runners' constants move together.

## Meal validation

`m39-meal-validation.json` (domain `meal-validation`) pins the Meal-time tier
of the shared two-tier validator in both languages, and the rule that derives a
Meal's local date: `validateMealTime` (`validateAgentMealTime` in TypeScript)
with its three rules, `meal_ended_before_start` and `meal_type_required` (hard
reject) and `meal_time_in_future` (soft warning, more than 5 minutes after
`now`), and `localDateAtOffset`. The app runs it in
`apps/mobile/test/domain/meal_validation_golden_test.dart` against
`apps/mobile/lib/domain/nutrition/meal_validation.dart` and
`apps/mobile/lib/domain/common/local_clock.dart`; the server runs it in
`apps/server/test/agent-validation.golden.test.mjs` against
`apps/server/src/agent-validation.ts` and `apps/server/src/timezone.ts`. The
behaviour is specified in
[`docs/designs/meal-logging.md`](../../../docs/designs/meal-logging.md) (§1
and §8).

Each case gives `startedAt`, an optional `endedAt`, `mealType`,
`timezoneOffsetMinutes` and `now` in `input`, and in `expected` the ordered
error and warning rule ids, `accepted`, and the `YYYY-MM-DD` `localDate` of
`startedAt` at that offset. Instants are ISO-8601 UTC strings, and offsets stay
inside −720 to +840 minutes, including instants whose local date is a day
ahead of or behind their UTC date. The file carries a `limits` block that both
runners assert against their limits constants. It is governed by the adjacent
`m39-meal-validation.schema.json`; its `schemaVersion`, the schema's constant
and both runners' constants move together.

## Compound Purposes

`m40-compound-purposes.json` (domain `compound-purposes`) pins the Compound
Purposes core in both languages: `starterPurposes`, the six starter Purposes;
`validatePurposeName`, which trims a name and hard-rejects it with
`purpose_name_required` or `duplicate_purpose_name`; and `normalizePurposeIds`,
which collapses repeated ids keeping the first and the order. The app runs it in
`apps/mobile/test/domain/compound_purposes_golden_test.dart` against
`apps/mobile/lib/domain/protocols/compound_purposes.dart`; the server runs it in
`apps/server/test/compound-purposes.golden.test.mjs` against
`apps/server/src/compound-purposes.ts`. The behaviour is specified in
[`docs/designs/compound-purposes.md`](../../../docs/designs/compound-purposes.md)
(D3 and D8). The seed tag table is Dart only and isn't a vector.

Each case names its `function`, gives that function's arguments by parameter
name in `input`, and its full result in `expected`. A `validatePurposeName`
case expects `{"accepted": <trimmed name>}` or `{"rejected": <code>}`. The file
is governed by the adjacent `m40-compound-purposes.schema.json`; its
`schemaVersion`, the schema's constant and both runners' constants move
together.

## User Profile validation

`m41-user-profile-validation.json` (domain `user-profile-validation`) pins the
User Profile tier of the shared two-tier validator in both languages:
`validateUserProfileSection`, on both sides of every bound in the Validation
table. The app runs it in
`apps/mobile/test/domain/user_profile_validation_test.dart` against
`apps/mobile/lib/domain/profile/user_profile_validation.dart`; the server runs
it in `apps/server/test/agent-validation.golden.test.mjs` against
`apps/server/src/agent-validation.ts`. The behaviour is specified in
[`docs/designs/user-profile.md`](../../../docs/designs/user-profile.md)
(Validation).

Each case gives `referenceYear`, a `section` wire name and its snake_case
`values` in `input`, so no result depends on the clock, and in `expected` the
ordered error and warning rule ids and `accepted`. An inch height is converted
at exactly 2.54 cm per inch with no rounding, and text length is counted in
UTF-16 code units, so an astral-plane character counts as 2. The file carries a
`limits` block that both runners assert against their limits constants. It is
governed by the adjacent `m41-user-profile-validation.schema.json`; its
`schemaVersion`, the schema's constant and both runners' constants move
together.
