# Lab Results

*   **Author:** Leonardo Pinheiro
*   **Status:** Draft
*   **Date:** 2026-11-24

Read with: [AGENTS.md](../../AGENTS.md) (invariants and conventions),
[CONTEXT.md](../../CONTEXT.md) (terms), [ARCHITECTURE.md](../../ARCHITECTURE.md) (layering,
contract, sync), [DESIGN.md](../../DESIGN.md) (UI tokens and components),
[user-profile.md](user-profile.md) (the sex and birth year this spec reads), and
[progress-overview.md](progress-overview.md) (the Progress root and how the Protocols lock is
shown there).

--------------------------------------------------------------------------------

## Overview

This spec lets a user keep their blood test results in Perennia and see each one change over
time, across labs and years. It is built in two phases:

1.  **Phase 1: Lab Results.** Results are entered by hand, one collection at a time, or written
    by an Agent. It adds:
    *   a **Lab Test catalogue**: one shared data file that both the app and the server read;
    *   results stored as **Metric Readings** on **Lab Metrics**, read as one series per Lab Test
        per user;
    *   for each result: the value as the lab printed it (including limits such as `< 1`), the
        range and flag the lab printed, whether the result is interim or final, and when the
        sample was collected;
    *   duplicate handling that gives the same answer on every device, the server and the Agent
        surface;
    *   **Default Ranges** from the catalogue, chosen by the User Profile's sex and birth year,
        shown only where the lab printed no range;
    *   a Lab Results screen with a dated list of results per Lab Test.
2.  **Phase 2: Lab Report import.** The phone reads the text layer of a lab report PDF and writes
    results in the shape phase 1 defines. This spec states phase 2's constraints only. Its design
    is added to this spec after phase 1 has merged, and is reviewed before its pull request
    starts (see [Phase 2](#phase-2-lab-report-import)).

Lab results sit behind the Protocols lock, are left out of CSV export, and are kept in the
portable archive. Charts, range bands and changes to the Protocol Effect view belong to a later
visualization spec.

## The Problem

Perennia is a longevity and training logger. A user who runs a Protocol, or changes how they
train, wants to see what that did to their blood work: cholesterol, testosterone, haemoglobin,
and so on. Blood tests come a few times a year, often from different labs, for example when a
general practitioner refers the user somewhere new.

Today the only way to store a lab value is to create a custom Metric by hand and log one Reading
at a time. That path has five gaps:

*   **No place for what the lab printed.** A Reading holds a number and a unit. The lab's range,
    its flag (such as `+` or `--`) and whether the result is interim have nowhere to go.
*   **Limit values are rejected.** A value reported as `< 1` cannot be entered at all. Storing
    `1` instead would bias every average and chart.
*   **No shared identity.** Each device creates its own custom Metric with a random id. Two
    phones, or a phone and an Agent, writing "Testosterone" make separate Metrics and split the
    series. Sync and restore never join them.
*   **No duplicate handling.** Lab reports repeat earlier results (a cumulative table of past
    collections), and a final report revises an interim one. Nothing recognises the same result
    arriving twice.
*   **Entry is slow.** One form per Reading means a 40-result report needs the date picked 40
    times.

The Agent path partly works today: a user can hand a report to their own Agent, which can write
Readings through `batchWriteAgentMetrics`. It has the same five gaps, and it sends the report to
the user's model provider. Phase 1 closes the gaps for both paths at once.

Typing results is the slowest part of using the feature. A lab report PDF already holds the
values as text, so phase 2 reads them on the phone. Doing it on the phone, rather than through
an Agent, is what lets it work offline with no account, and means no third party's AI sees the
report. It comes second because it is only safe once phase 1 has defined how a result is
identified, validated and de-duplicated: a parser that writes before those rules exist would
save duplicates and wrongly read values that sync cannot undo.

## Goals

1.  **One Lab Test catalogue.** A single data file holds every Lab Test: its key, display name,
    name variants, unit and its spellings, bounds, panel, the kind of range its labs print, and
    any Default Ranges with their source. The Dart app and the TypeScript server are generated
    from it, and CI fails if the generated copies are stale.
2.  **One series per Lab Test per user.** Results for the same Lab Test from any device, the
    server, an Agent or a restore read as one series, matched by a synced `lab_test_key` on the
    Metric. No Metric id is ever shared between users.
3.  **Results keep what the lab printed.** Each result stores the value and unit as entered, an
    optional limit comparator, the Printed Range as text, the Printed Flag, the Report Status
    (interim or final), the collection date and time as printed, whether it was fasting, and the
    lab's name.
4.  **Limit Results are never treated as numbers.** A `< 1` result shows its comparator
    everywhere and is left out of every mean, Trend and chart value.
5.  **Duplicates collapse the same way everywhere.** Every row is kept. When results are read,
    rows with the same identity collapse to one: final beats interim, then the most recently
    updated row wins, compared to the second. The value is never part of the identity. The rule
    is golden-vectored in Dart and TypeScript. A save that would replace a shown result with a
    different value warns first.
6.  **Listed spellings of a unit are equal.** `U/L` and `IU/L`, `umol/L` and `µmol/L`, `x10^9/L`
    and `10^9/L` join one series, because the catalogue lists each spelling explicitly. A result
    in any other unit is rejected, never converted.
7.  **Validation is shared.** Lab values follow the two-tier rule (hard reject outside the hard
    bounds, soft warning outside the plausible bounds) in the shared validation module, the same
    for manual entry and the Agent write.
8.  **Default Ranges, labelled as general.** Where the lab printed no range, a result shows the
    catalogue's general range for the user's sex and age band, labelled "General range" with its
    source. Without the profile fields it needs, no range shows. The result's position against a
    range (below, within or above) is computed on read and shown in words.
9.  **Collection-based manual entry.** The user sets the collection date, time and lab once and
    adds many results, saved as one Activity Log Batch with one undo.
10. **The Agent gets the same operation.** `batchWriteAgentMetrics` accepts lab results keyed by
    Lab Test, with the same validation, and a new read lists the catalogue. The Agent's readings
    and Effect reads apply the same collapse and give no Trend.
11. **A Lab Results screen.** Lab Tests grouped by panel, each with a dated list of results. Lab
    Metrics stay out of the Health Metrics explorer, Trend, Body Tracker and the Body card.
12. **Plain privacy wording.** The Lab Results screen and the entry sheet carry the User Profile's
    disclosure pattern: results are on this phone and its backups, and in Synced Mode the
    server's operator and every connected Agent can read them. No report header data (patient
    name, date of birth, address, accession number) is ever kept.

## Non-Goals

*   **Unit conversion that needs a factor.** mmol/L to mg/dL depends on the molar mass of each Lab
    Test. A wrong factor saves a wrong value silently, and the Australian community pathology
    labs the seed catalogue targets all report in SI units. A factor can be added per Lab Test
    later.
*   **Flags or verdicts computed by Perennia.** Perennia never stores a flag it worked out, and
    never says "normal" or "abnormal". Only the lab's Printed Flag is stored.
*   **Default Ranges for conditional ranges.** Ranges that depend on the time of day (cortisol)
    and risk targets (lipids) get no default.
*   **Changes to the User Profile.** This spec reads `about_you.sex` and `about_you.birth_year`.
    It adds no ask for a missing field (User Profile Goal 7 permits one; this spec does not use
    it).
*   **Editing a Lab Result.** Phase 1 has archive and re-enter.
*   **Visualization.** Range bands, Limit Result markers on charts, a by-collection view, a "last
    reading before the Protocol started" baseline, and any change to the Effect view go to a
    later visualization spec.
*   **OCR, in-app AI parsing, and one parser per lab.** See
    [Parser alternatives](#parser-alternatives).
*   **Parse telemetry of any kind.**
*   **Real or realistic report PDFs in the repository.**
*   **Per-domain Agent key scopes.** Every Agent key reads lab results, as it reads every Metric
    today.
*   **A new sync entity, a new `MetricGroup` value, or a new provenance value.** Lab data rides on
    existing Metric and Reading rows.
*   **Linking existing hand-made custom Metrics** (a "Testosterone" a user created before this
    feature) to a Lab Test. They stay custom Metrics.

## Open Questions

None.

## Critical User Journeys (CUJs)

### CUJ 1: Enter one collection by hand

*   **Given** the user has no lab results, has set no Protocols lock, and has a paper report.
*   **When** they open Progress → Lab results → **Add results**, set the collection date (and
    time, if printed) once, then add Testosterone `20.0 nmol/L` with printed range `(10.0-30.0)`,
    hs-CRP `< 1 mg/L`, and Haemoglobin `150 g/L` with printed flag `+`, and tap **Save**.
*   **Then** three Lab Metrics exist, each with one Lab Result. The save is one Activity Log
    Batch, and one undo in Recent activity removes all three results. hs-CRP shows `< 1 mg/L`
    and is excluded from every mean.

### CUJ 2: The same Lab Test from a second lab

*   **Given** the user has Testosterone results from one lab.
*   **When** they enter a Testosterone result from a second lab, whose report prints the unit as
    `nmol/l` and a different range.
*   **Then** the unit field already shows the canonical `nmol/L`, the result joins the same
    Testosterone series, and the second lab's Printed Range and name are kept with that result.
    An Agent that sends `nmol/l` is accepted; one that sends `ng/dL` is rejected with the
    accepted spellings listed.

### CUJ 3: An interim result, then the final

*   **Given** an interim Haemoglobin result for a collection.
*   **When** the final result for the same collection is entered, by hand, by an Agent, or on
    another device.
*   **Then** both rows are kept. Every screen and the Agent read show only the final. Two phones,
    the server and the Agent show the same result once they have synced. Archiving the shown
    result archives both rows in one Batch.

### CUJ 4: No printed range

*   **Given** a Creatinine result with no Printed Range, collected when the user was 40. The
    catalogue has sex-specific Default Ranges for Creatinine for ages 18 to 59. The user's
    profile has no sex or birth year.
*   **When** they open Creatinine.
*   **Then** the result shows no range. The Lab Results screen's line "General ranges use your sex
    and birth year from Profile." links to Profile. After the user sets both fields, the result
    shows `General range {low}–{high} umol/L · {source title}` and a position sentence such as
    "Within the general range".

### CUJ 5: An Agent writes a report

*   **Given** a Synced Mode account and an Agent holding a report.
*   **When** the Agent calls `agent_list_lab_tests`, then `agent_batch_write_metrics` with
    readings keyed by `labTestKey` and carrying `lab` fields, and later replays the same request.
*   **Then** results join the user's Lab Metrics, or new ones are created for Lab Tests the user
    has none of. The replay writes nothing. An unknown `labTestKey` rejects the batch with
    `lab_test_unknown`, whose message names `agent_list_lab_tests`. An unaccepted unit rejects it
    with `lab_unit_not_accepted`, which lists the accepted spellings. An Agent cannot overwrite,
    archive or backdate a stored Lab Result.

### CUJ 6: Locked

*   **Given** the user has a Protocols lock and the app is locked.
*   **When** they open Progress.
*   **Then** the Lab results row shows a lock icon and no Lab Test names, counts or values.
    Opening it shows the lock screen. An open entry sheet closes when the app locks, and its
    unsaved rows are discarded.

## Technical Plan (Architecture)

### Background: how Metrics work today

No spec covers Metrics; they predate the design record. This is the contract this spec builds
on, as of `main` at the time of writing:

*   A **Metric** row (`Metrics` in `apps/mobile/lib/data/local/app_database.dart`, `metrics` in
    `apps/server/src/db/schema.ts`) has one `unit`, a `valueShape` (`scalar`, `structured` or
    `series`) and a `metricGroup` (`bodyComposition`, `monitoring` or `custom`).
*   A **Metric Reading** row stores `valueJson` (the full value, including what was entered and in
    which unit), `scalarValue` (the value in the Metric's unit, for scalar Readings only),
    `scalarEntered`, a time anchor (`atTime` or a window), `provenance` (`manual`, `integration`
    or `agent`), `source`, `externalId` and `comment`.
*   **Conversion happens on write.** `normalizeMetricReading`
    (`apps/mobile/lib/domain/metrics/reading_normalization.dart`, twin
    `apps/server/src/metric-reading-normalization.ts`) parses the entered number, converts it into
    the Metric's unit and rebuilds `valueJson` from a fixed list of keys. Every reader uses
    `scalarValue` without converting. The converter knows only the unit identifiers `pound` and
    `kilogram`, and `inch` and `centimeter`. Golden vectors: `m12-reading-normalization.json`. A
    time anchor is `atTime`, a window, or `localDateTime` plus `timezoneOffsetMinutes`; the
    normaliser derives the stored `atTime` from the last form on both sides.
*   **Types that a Limit Result relies on.** `entered` and `scalarEntered` are text.
    `scalarValue` is nullable in Drift (`MetricReadings.scalarValue`), in Postgres
    (`metric_readings.scalar_value`) and in the contract's `AgentMetricReading`. Only the app's
    in-memory `_NormalizedMetricReadingValues.scalarValue` is non-null today.
*   **Identity across devices** exists only for the two seeded defaults, Body Weight and Body Fat,
    which the server folds into one row through `metric_aliases` when a device pushes a Metric
    the server has no row for (`metricAliasTarget` in `apps/server/src/sync.ts`).
*   **Ids are global on the server.** A pushed row whose id belongs to another user is skipped
    ("TENANT ISOLATION" in `sync.ts`). Ids must therefore never be derived from shared data alone.
*   **Keys already exist on the Agent surface.** The server has a catalogue of tracker Metrics
    (`PRN_METRIC_SCHEMAS` in `apps/server/src/metric-catalog.ts`), each with a camelCase
    `canonicalKey`. `listAgentMetrics` returns `canonicalKey`, and the `metricKey` read filter
    resolves a key to the set of the user's Metric ids that match it
    (`resolveMetricIdsForMetricKey` in `apps/server/src/agent-metrics.ts`).
*   The sync payload parser for Metrics is a non-strict zod object: a server that does not know a
    payload key drops it.
*   CSV export holds no Metrics. The portable archive holds every Metric and Reading, written as
    the generated Drift row JSON, so a new column is included without code. Body Tracker and the
    Body card list only `bodyComposition` Metrics with a goal.
*   **The Protocols lock** is an optional PIN or biometric lock on Protocols content, set in
    Settings; it locks when the app goes to the background. Two widgets in
    `apps/mobile/lib/features/protocols/widgets/protocols_lock_screen.dart` apply it:
    `ProtocolsLockGate` wraps a screen and shows the lock screen instead of its content while
    locked; `ProtocolsLockSheetGuard` wraps a sheet or dialog and removes its route when the app
    locks, so anything typed into it and not saved is discarded. The lock hides content on this
    device only; sync and Agents are not affected.

In this spec a **collection** is one blood draw: the results a lab reports for one
`lab.collected` date and time.

### Shape of the change

```text
                packages/lab-catalogue/lab-tests.json   (one source of truth)
                           │  tools/generate-lab-test-catalogue.mjs [--check]
          ┌────────────────┴────────────────┐
lab_test_catalogue.generated.dart   lab-test-catalogue.generated.ts
          │                                  │
 Lab Results screen ─► LabResultsRepository  batchWriteAgentMetrics (labTestKey + lab)
 Entry sheet          (one Batch per save)   listAgentLabTests
          │                                  │
          └─────► normalizeMetricReading (+ lab, limits, unit spellings, bounds) ◄─┘
                           │                                │
                Metrics.lab_test_key  ──── sync ────  metrics.lab_test_key
                MetricReadings.valueJson.lab  ─────  metric_readings.value_json.lab
                           │                                │
         read by key + collapseLabResults       read by key + collapseLabResults
         defaultRangeFor, rangePosition (Dart)  (Agent readings, Agent Effect)
```

Nothing new is stored except one nullable column on Metrics and the `lab` object inside
`valueJson`. The collapse, Default Ranges, the parsed Printed Range and range positions are
computed on read.

### The Lab Test catalogue

**Location and generation.** The source is `packages/lab-catalogue/lab-tests.json`.
`tools/generate-lab-test-catalogue.mjs` checks it in plain code (no new dependency) and emits a
Dart file into the app's domain layer and a TypeScript file into the server, as
`tools/generate-server-usda-food-seed.mjs` does for the food seed. Both outputs are committed;
`--check` fails CI when either is stale. The catalogue is generated code rather than a Flutter
asset because validation and the normaliser are synchronous domain code that cannot await an
asset load, and the server image copies only `apps/server`. It is not a golden-vector `limits`
block because it is data contributors edit, with about 60 entries, not a handful of constants.

**File shape.** `{ "labTests": [ <entry>, ... ] }`, in display order. Each entry:

| Field | Type | Meaning |
|---|---|---|
| `key` | string, required | Stable id, lower snake case (`testosterone_total`). Never renamed, reused or removed. |
| `name` | string, required | Display name ("Testosterone"). |
| `panel` | string, required | Display grouping ("Sex hormones"). Never stored on a result. |
| `variants` | string[], required | Other names for the Lab Test, lower case, single spaces (`alk phos`). Used by the entry picker's search. |
| `unit` | string, required, non-empty | The canonical unit, used as the Metric's `unit`. A fraction uses `L/L`; a ratio uses `ratio`. |
| `unitAliases` | string[] | Other spellings of the same unit (`µmol/L`). |
| `hardBounds` | `{min, max}`, required | In `unit`, inclusive. Outside is a hard reject. |
| `plausibleBounds` | `{min, max}`, optional | In `unit`, inclusive. Outside is a soft warning. Never shown to the user as a range. |
| `printedRangeKind` | `"reference"` (default) or `"riskTarget"` | What the ranges its labs print are. Lipid Lab Tests are `riskTarget`. |
| `defaultRanges` | list, optional | See [Default Ranges](#default-ranges). |

**Unit spellings.** A Lab Test has exactly one unit and the spellings listed for it. Where labs
report the same quantity in different units, each form is its own Lab Test
(`neutrophils_percent` and `neutrophils_count`). Every unit comparison, in the generator, the
normaliser and the entry sheet, uses one fold: remove every space and keep case. So `x10^9 /L`
matches `x10^9/L`, but `nmol/l` matches `nmol/L` only because the catalogue lists `nmol/l` as an
alias. The seed lists the lower-case `l` form of every unit that ends in `/L`.

**Generator rules.** `validateCatalogue` rejects the file when any of these fails:

*   The top level is an object with only `labTests`, an array.
*   Every entry has `key`, `name`, `panel`, `variants`, `unit` and `hardBounds`, each of the type
    in the table; strings are non-empty after trimming.
*   No object at any depth has a key not listed in this spec (so no conversion factor can be added
    by accident).
*   `key` matches `^[a-z][a-z0-9_]*$` and is unique.
*   No two spellings of one Lab Test (its `unit` and `unitAliases`) are equal after the fold.
*   No `variant` is shared by two Lab Tests, and every variant is lower case with single spaces.
*   `hardBounds` and `plausibleBounds` have numeric `min <= max`, and `plausibleBounds` lies
    within `hardBounds`.
*   `printedRangeKind`, when present, is `reference` or `riskTarget`; a `riskTarget` Lab Test has
    no `defaultRanges`.
*   Each `defaultRanges` entry has `sex` in `female`, `male` or `any`; at least one of `low` and
    `high`; `low <= high` when both are set; integer `ageMin <= ageMax` when both are set;
    non-empty `source.title`, `source.url` and `source.version`. No two entries of one Lab Test can
    match the same sex and age.

One more rule needs the server's tracker catalogue, which the generator (plain JavaScript)
cannot import: no Lab Test `key` or `name`, after `normalizeMetricLookupKey`, may equal any
`PRN_METRIC_SCHEMAS` entry's `canonicalKey`, `displayName` or alias after the same normalisation.
`apps/server/test/lab-test-catalogue.test.mjs` checks it, because the server test runner reads
TypeScript.

**Contributing.** `packages/lab-catalogue/README.md` holds the checklist and the rules: keys,
names and units never change once released; aliases and variants are only added; bounds are
only widened; every Default Range cites its source. A new Lab Test needs no spec.

### Storage

**Lab Metrics.** A Lab Metric is an ordinary scalar Metric with a non-null `lab_test_key`:

*   Drift: `Metrics.labTestKey` (nullable text) with an index, schema version 68. Postgres:
    `metrics.lab_test_key` (nullable text) with index `(user_id, lab_test_key)`, migration `0038`.
    No unique index: two devices that create the same Lab Metric offline produce two rows
    legitimately, and a refused push would stall every later Sync Run (ARCHITECTURE.md, Sync).
*   `metricGroup` is `custom` and `valueShape` is `scalar`. No new enum value is added (see
    [Alternative D](#alternative-d-a-new-metricgroup-value-such-as-labresults)).
*   `unit` is the Lab Test's `unit`; `name` is its `name`.
*   The Metric sync payload gains `lab_test_key`. The app sends it from `_metricImage`, which also
    feeds the Activity Log; the server sends it from `metricSyncPayload`. An older server drops the
    field, because its parser is not strict; see [Risks](#risks--mitigations). No pull cursor is
    reset: Lab Metrics first exist in the release that adds the column.
*   **`lab_test_key` is write-once.** Every receiver (server push, app pull, archive restore) keeps
    a stored non-null key: a payload that omits the field, sends null or sends a different key
    leaves it unchanged. A null stored key takes the payload's key. So a stray null cannot turn a
    Lab Metric back into a custom Metric, and a key is never moved to another Lab Test.
*   A Lab Metric is a container. The user archives results, never a Lab Metric directly (only the
    undo of the save that created one archives it), and the Agent cannot upsert one. Whether a Lab
    Metric row is archived has no effect on its readings.

**Lab Results.** A Lab Result is a scalar Metric Reading on a Lab Metric, with provenance
`manual` and source `labEntry` (manual entry), or provenance `agent` and source `agent` (the
server sets both for an Agent write, whatever the request says). Its `valueJson` gains a `lab`
object, with keys in this order:

```text
valueJson = {
  shape: "scalar", unit, value, entered, enteredUnit,   // as today
  lab: {
    collected:    "2026-03-04T08:15" | "2026-03-04",    // as printed, local, no offset
    limit:        { comparator: "<" | "<=" | ">" | ">=", bound: number } | null,
    printedRange: string | null,                        // the text, as printed
    printedFlag:  string | null,                        // as printed: "+", "--", "H"
    reportStatus: "final" | "interim",
    fasting:      true | null,
    labName:      string | null                         // the lab, never the patient
  }
}
```

*   **`entered`.** For a number, the value as typed with `.` as the decimal separator (`20.0`).
    For a Limit Result, `"{comparator} {value}"` with an ASCII comparator (`<`, `<=`, `>`, `>=`)
    and one space (`< 1`). The entry sheet builds it from its comparator chooser; an Agent sends it
    directly. `scalarEntered` holds the same text.
*   **Limit Results.** `value` and `scalarValue` are null, and the bound lives only in
    `lab.limit`. `lab.limit` is output only: the normaliser derives it from `entered`, and a
    `limit` an Agent sends is overwritten. Effect and the charts already skip readings whose
    `scalarValue` is null, so none of them changes; the bias this causes is recorded under
    [Risks](#risks--mitigations). The display always shows the comparator.
*   **Text fields.** `printedRange`, `printedFlag` and `labName` are trimmed; a blank result is
    stored as null. Length limits count UTF-16 code units after trimming, so Dart's
    `String.length` and JavaScript's `.length` agree.
*   **Decoding `lab`.** One rule, `decodeLab`, in both languages. A `lab` object is valid when
    `collected` is valid; otherwise the reading is treated as lab-less (see the collapse). A
    missing `reportStatus` decodes as `final`; an unknown `reportStatus` (from a later build)
    ranks as `interim`. Unknown keys are dropped. Other missing optional keys decode as null.
*   **Time.** The writer sends the existing anchor `localDateTime` equal to `collected` (seconds
    `:00`; a date-only `collected` becomes `T12:00:00`) and `timezoneOffsetMinutes`. The app uses
    the offset its own time zone has at that local date and time (the `timeZoneOffset` of a local
    Dart `DateTime` built from it), so an old collection across a daylight-saving change gets its
    own offset. A local time inside a daylight-saving gap or overlap takes whatever offset Dart
    returns. An Agent sends its own offset, which must lie between −720 and 840 minutes. The
    displayed date and time always come from `collected`, never from `atTime`. A date-only
    collection never shows a clock time, like a date-precision Meal.
*   **Printed Range.** Stored as text only. Its numbers and whether it is a reference range or a
    risk target are not stored: the numbers are parsed on read (below) and the kind comes from the
    Lab Test's `printedRangeKind`.
*   **No header data.** No field holds the patient's name, date of birth, address or the lab's
    accession number. `comment` stays the user's own note.

**Order: validate, then normalise.** Every writer (the entry sheet's `saveCollection` and the
Agent batch write) runs [Validation](#validation) first and normalises only readings it
accepted. The normaliser's own lab checks are defensive: they throw, and a writer that reaches
one has a bug.

**The normaliser.** `normalizeMetricReading` in both languages takes the Metric's `labTestKey`
and the value's `lab` object. For a Lab Metric it:

1.  resolves `enteredUnit` to the Lab Test's `unit` or one of its `unitAliases` under the fold;
    any other unit throws, never converts; `value` equals the entered number;
2.  accepts a leading comparator in `entered` (`<`, `<=`, `≤`, `>`, `>=`, `≥`, optionally followed
    by a space), stores it in `lab.limit` with `≤` and `≥` written as `<=` and `>=`, and stores
    `entered` in the canonical form above;
3.  trims the text fields, writes blanks as null, and copies `lab` into `valueJson` in the key
    order above, with absent optional keys written as null and any sent `limit` replaced.

On a Metric without a `labTestKey`, a comparator and a `lab` object are rejected as they are
today. The domain normaliser returns a null `scalarValue` for a Limit Result (PR 2), and the
app's `_NormalizedMetricReadingValues.scalarValue` becomes nullable so one can be written (PR 3).

### Validation

Lab Results follow the shared two-tier module. There are two kinds of rule:

*   **Reading rules** look at one reading and the catalogue entry it names. They are pure, live
    in the shared module, and are golden-vectored. Dart:
    `validateLabResult(LabResultInput input, {required DateTime today})` in
    `apps/mobile/lib/domain/labs/lab_result_validation.dart`. TypeScript: `validateLabResult` in
    `apps/server/src/agent-validation.ts`, beside the other domains' validators. The input is
    `{labTestKey, entered, enteredUnit, lab, timeAnchor}` for a known `labTestKey`. Both return
    `{errors: [{rule, field}], warnings: [{rule, field}]}`, the shape the existing validators
    return. Golden vectors: `m42-lab-result-validation.json` (the next free id at the time of
    writing), domain `lab-result-validation`.
*   **Request rules** need the request, the user's stored data or the entry sheet. They are not in
    m42. The server's are tested in `agent-metrics.test.mjs`; the app's in
    `lab_entry_sheet_test.dart` and `lab_results_repository_test.dart`.

Bounds are inclusive. "Today" is an input to the rule (the device's local date; the server's UTC
date), so vectors are deterministic. Messages carry no value and no Lab Test name, so a message
that reaches a log reveals nothing; the app shows each message beside its row, which names the
Lab Test.

| Code | Kind | Tier | Rule | Message |
|---|---|---|---|---|
| `lab_collected_missing` | Reading | Hard | A lab reading has no `lab.collected` | "Give the collection date." |
| `lab_collected_invalid` | Reading | Hard | `collected` is not `YYYY-MM-DD` or `YYYY-MM-DDTHH:mm`, or not a real date or time | "Collection date must be YYYY-MM-DD or YYYY-MM-DDTHH:mm." |
| `lab_collected_future` | Reading | Hard | `collected`'s date is more than one day after today | "Collection date can't be more than one day in the future." |
| `lab_time_anchor_mismatch` | Reading | Hard | The time anchor is not `localDateTime` + `timezoneOffsetMinutes`; `localDateTime` does not equal `collected` as expanded in [Storage](#storage); or the offset is outside −720 to 840 | "timeAnchor.localDateTime must match lab.collected." |
| `lab_unit_not_accepted` | Reading | Hard | The unit, after the fold, is not the Lab Test's unit or an alias | "Unit not accepted. Use {unit list}." |
| `lab_value_invalid` | Reading | Hard | `entered` is not a number, or a comparator, one space and a number | "Enter a number, optionally after <, <=, > or >=." |
| `lab_value_out_of_bounds` | Reading | Hard | The value or limit bound is outside `hardBounds` | "Value must be between {min} and {max} {unit}." |
| `lab_value_implausible` | Reading | Soft | The value or limit bound is outside `plausibleBounds` | "Value is unusual for this Lab Test. Check it before saving." |
| `lab_text_too_long` | Reading | Hard | After trimming, `printedRange` over 120 UTF-16 code units, `printedFlag` over 8, `labName` over 80 | "{field} is too long." |
| `lab_report_status_invalid` | Reading | Hard | `reportStatus` is present and not `final` or `interim` | "Report status must be final or interim." |
| `lab_fasting_invalid` | Reading | Hard | `fasting` is not `true` or null | "Fasting must be true or empty." |
| `lab_test_unknown` | Request | Hard | `labTestKey` is not in the catalogue (Agent) | "Unknown Lab Test. List Lab Tests with agent_list_lab_tests." |
| `lab_target_ambiguous` | Request | Hard | An Agent reading has both or neither of `metricId` and `labTestKey` | "Give exactly one of metricId and labTestKey." |
| `lab_metric_id_not_allowed` | Request | Hard | An Agent reading's `metricId` names a Lab Metric | "Write lab results by labTestKey." |
| `lab_metric_upsert_not_allowed` | Request | Hard | An Agent `metrics[]` row names a Lab Metric or sends `labTestKey` | "Lab Metrics can't be changed." |
| `lab_fields_on_non_lab_metric` | Request | Hard | `lab` sent for a Metric without a `labTestKey` | "This Metric is not a Lab Test." |
| `lab_result_exists` | Request | Hard | An Agent lab reading's `id` is an existing reading, and the request is not a replay of the request that wrote it | "Lab results can't be changed. Write a new result." |
| `lab_archive_not_allowed` | Request | Hard | An Agent lab reading sends `deletedAt` | "Agents can't archive lab results." |
| `lab_result_repeated` | Request | Hard | The same Lab Test twice in one entry sheet (app) | "This Lab Test is already in this collection." |
| `lab_result_replaces` | Request | Soft | The reading's identity already has a live result with a different value (or a different limit) | "This replaces a saved result for the same collection." |

A hard reject blocks the save and names the field. In the app, every soft warning of one Save is
listed in one confirmation dialog, confirmed once. To an Agent they are returned as warnings, as
for other Metrics. An Agent batch is all-or-nothing, as today: one rejected reading rejects the
batch.

**m42 case shape.** Each case is `{name, input, today, expected}`, run by the existing
`agent-validation.golden.test.mjs` runner and a Dart runner: `input` is a `LabResultInput`,
`today` is `YYYY-MM-DD`, and `expected` is `{accepted, errorRules, warningRules}` with rules in
issue order. The vectors use the real catalogue, so a pull request that widens a bound updates
the affected vectors in the same commit.

### Result identity and the collapse

**Identity.** Two Lab Results are the same result when their Metrics have the same `labTestKey`
and their `lab.collected` strings are equal. Identity is per user and per Lab Test, not per
Metric row, so a second Lab Metric for the same Lab Test (see the next section) changes nothing.
The value is never part of identity, so a final report that revises a value still matches its
interim. The cost is that two different results sharing a Lab Test and a `collected` string
(two draws on one day, both entered date-only) also match, and only one shows. The
`lab_result_replaces` warning tells the user before that happens, and the user can enter the
time to keep them apart. Why the lab's accession number is not part of identity is recorded in
[Alternative J](#alternative-j-a-hash-of-the-labs-accession-number-in-a-results-identity).

**The collapse.** `collapseLabResults(readings)` is a pure function in Dart and TypeScript,
golden-vectored in `m43-lab-result-collapse.json`, domain `lab-result-collapse`. Input: readings
with `id`, `labTestKey`, `lab` (or null), `atTime`, `updatedAt` (ISO 8601) and `deletedAt`.

1.  Drop rows whose `deletedAt` is set.
2.  A row whose `lab` does not decode (see `decodeLab` in [Storage](#storage); for example one
    written by an older app build) is its own group, keyed by its id.
3.  Group the rest by identity.
4.  In each group keep one row: `final` beats `interim`; then the later `updatedAt`, compared in
    whole seconds (the app stores seconds, the server milliseconds, so finer precision would let
    the two disagree); then the greater `id` by code-unit string order.
5.  Return the kept rows, newest first by `atTime`, then by `id`, the greater `id` first.

Every reader of Lab Results applies it to the readings of **every Metric with that
`labTestKey`**: the Lab Results screen, the Lab Test detail list, the app's Effect samples, the
Agent's readings and the Agent's Effect window. Readers that window or filter (Effect, the
Agent's date filters) collapse the whole key series first and window afterwards, so a final
outside a window still hides its interim inside it. Nothing is skipped or replaced on write, so
two devices that save the same collection before they sync show the same result after they
sync, and merge-only restore needs no rule of its own.

**Archiving a result** asks for confirmation, stating how many saved rows it archives ("Archive
this result? 2 saved copies will be archived."), then archives every live row with its identity
in one Batch. Undo restores them all, so the user never has to archive the same result twice.

**Undo of a save** archives the Lab Results the Batch wrote and the Lab Metrics it created, as
undo does for any Batch. An archived Lab Metric is harmless: readers ignore a Lab Metric's own
archive state, and the next save reuses a live Lab Metric for the key or creates one.

### Finding the Lab Metric for a Lab Test

*   **On the device.** `LabResultsRepository` writes to the user's live Metric with that
    `labTestKey` (lowest `sortOrder`, then lowest id). If there is none, it creates one with a
    random id, like any Metric.
*   **From an Agent.** A reading with `labTestKey` resolves the same way on the server. After the
    idempotency check, the server takes `lockMetricIdentity` for the user and key, then looks
    up the live Lab Metric. If there is none, it inserts one at id
    `stableMetricId(userId, "lab:" + key)` with `on conflict do nothing`, then selects that row:
    *   new row: `name` and `unit` from the Lab Test, `valueShape` `scalar`, `metricGroup`
        `custom`, `enabled` true, `pinned` false, `goalType` null, `sortOrder` one more than the
        user's highest;
    *   the row exists archived: it is unarchived;
    *   the row exists live with no key (an older server dropped it): the server sets the key.

    The Metric goes through the batch's `preparedMetrics`, so it gets an Activity Log entry, is
    undone with the Batch, and appears in the response's `metrics[]` outcome. The id is scoped by
    user, so the tenant-isolation skip cannot hit it, and two concurrent Agent writes create one
    Metric, not two.
*   **Matching by key.** When a key is a catalogue Lab Test key, it matches only Metrics whose
    `lab_test_key` equals it, never a hand-made custom Metric whose name happens to match. This
    applies to `listAgentMetrics`, `listAgentMetricReadings` and `readAgentEffectWindow`. The
    other way round, an Agent's `metricKey` matches a Lab Metric only by its `labTestKey`, never by
    its name, so a Lab Metric is never read uncollapsed; a key this build's catalogue does not know
    (a Lab Metric written by a later build) reads collapsed like a catalogue key. In
    `listAgentMetricReadings`, a `metricId` and a `metricKey` that name different keys return an
    empty page.
*   **No fold.** Two Lab Metrics for one Lab Test can still arise (two devices offline, or a
    Metric created through an older server). They are not merged: readers join their readings by
    key. The cost is a Lab Test appearing twice in the Effect and target-outcome pickers; see
    [Risks](#risks--mitigations) and
    [Alternative K2](#alternative-k2-fold-duplicate-lab-metrics-into-one-on-create).

### Default Ranges

**Catalogue shape.** Each `defaultRanges` entry:

```text
{ sex: "female" | "male" | "any",
  ageMin: integer | null, ageMax: integer | null,     // inclusive years; null = unbounded
  low: number | null, high: number | null,             // in the Lab Test's unit; at least one set
  source: { title, url, version } }
```

**The seed's one source.** Every seed entry is copied verbatim from the harmonised adult
reference intervals for Australasia, agreed by the Australasian Association for Clinical
Biochemistry and Laboratory Medicine (AACB) and the Royal College of Pathologists of
Australasia (RCPA):

*   Tate JR et al., "Harmonising Adult and Paediatric Reference Intervals in Australia and New
    Zealand: An Evidence-Based Approach for Establishing a First Panel of Chemistry Analytes",
    *Clin Biochem Rev* 2014 (https://pmc.ncbi.nlm.nih.gov/articles/PMC4310061);
*   updated by Koerbin G et al., "An update report on the harmonization of adult reference
    intervals in Australasia", *Clin Chem Lab Med* 2018, doi:10.1515/cclm-2017-0920
    (https://www.degruyterbrill.com/document/doi/10.1515/cclm-2017-0920/html).

Where the 2018 update changed an interval, the update wins and is the cited `source`;
otherwise the 2014 paper is. `version` is the publication year. The harmonised intervals cover
chemistry only, so only chemistry Lab Tests get a Default Range; the full blood count
(Haemoglobin included), hormones, hs-CRP and lipids get none. "Adult" is written as `ageMin` 18.
Sex and age bands are copied as published (Creatinine's adult bands, for example, stop at 59),
and an age the source does not cover gets no default.

**What the seed has, and what it does not.** The seed's Default Ranges are copied from Tate 2014,
Table 1, and cite it: Sodium, Potassium, Chloride, Bicarbonate, Creatinine, Calcium, Adjusted
Calcium, Phosphate, Magnesium, LD, ALP and Total Protein. The full text of Koerbin 2018 is closed
access and could not be read when the seed was written, so two gaps remain until someone reads it:

*   The twelve intervals above have not been checked against the 2018 update. If it revised one,
    the seed shows the superseded 2014 interval with its 2014 citation.
*   Ten chemistry Lab Tests that the 2014 paper does not cover have no Default Range and so no
    `plausibleBounds`: Urea, Urate, eGFR, Anion Gap, Total Bilirubin, GGT, ALT, AST, Albumin and
    Globulin. A result for one of them with no Printed Range shows no general range, and a value
    outside its range gets no `lab_value_implausible` warning (the hard bounds still apply).

Closing both is a later catalogue pull request: read Koerbin 2018, replace any interval it revised
(with `version` 2018), and add the ten Lab Tests' intervals and `plausibleBounds` by the Bounds rule.
Ranges are never taken from a secondary source to fill these gaps.

**Choosing one, on read.** `defaultRangeFor(labTest, printedRange, sex, age)`, Dart only, pure,
golden-vectored in `m44-lab-default-range.json`, domain `lab-default-range`. `age` is
`UserProfile.ageAt(d)` where `d` is the `collected` date at local midnight; the User Profile read
contract (`UserProfileRepository.watch()`, `sex`, `ageAt`) is used as published.

1.  If the result has a Printed Range, there is no Default Range.
2.  Keep entries whose `sex` is `any` or equals the profile's sex. An entry for one sex is never
    shown when sex is null.
3.  Keep entries whose age band contains `age`. An entry with an age band is never shown when
    birth year is null.
4.  If exactly one entry is left, it is the Default Range; otherwise there is none.

**Parsing a Printed Range, on read.** `parsePrintedRange(text)` in the same vector file returns
`{low, lowInclusive, high, highInclusive}` (a side can be missing) or null when the text does
not parse. Grammar, applied in order:

1.  Trim. Strip one pair of surrounding parentheses or square brackets, then trim again.
    Matching is case-insensitive. Runs of spaces count as one space; spaces around a symbol are
    optional.
2.  A number is `-?digits(.digits)?`; a comma is not a decimal separator, so `4,5` does not
    parse.
3.  The whole remaining text must match one form; trailing text (a unit, a word) means it does
    not parse.

| Form | Result |
|---|---|
| `a-b`, `a–b` (en dash), `a—b` (em dash), `a to b` | low `a` and high `b`, both inclusive; does not parse if `a > b` |
| `< b`, `under b`, `below b`, `less than b` | high `b`, exclusive |
| `<= b`, `≤ b`, `up to b` | high `b`, inclusive |
| `> a`, `over a`, `above a`, `more than a`, `greater than a` | low `a`, exclusive |
| `>= a`, `≥ a` | low `a`, inclusive |
| anything else | null: the text is shown, with no position |

A Default Range's bounds are inclusive.

**Position, on read.** `rangePosition(result, range)` returns `below`, `within`, `above` or
`unknown`, in the same vector file. It is computed against the parsed Printed Range when it
parses, otherwise the Default Range, and never against a Printed Range of a `riskTarget` Lab
Test. A missing side is unbounded. Each side's inclusivity is honoured: a value equal to an
inclusive bound is `within`, and equal to an exclusive bound is outside.

*   A number `v`: `below` if `v` is under the low side; `above` if over the high side; otherwise
    `within`.
*   A Limit Result `< b` or `<= b` (every possible value is at most `b`): `below` if every
    possible value is under the low side; `within` if the low side is missing and every possible
    value is inside the high side; otherwise `unknown`.
*   A Limit Result `> a` or `>= a`: `above` if every possible value is over the high side;
    `within` if the high side is missing and every possible value is inside the low side;
    otherwise `unknown`.

For example, against an inclusive low of 1, `< 1` is `below` and `<= 1` is `unknown`.

`rangePosition` cannot see a Lab Test's `printedRangeKind`, so readers call
`resultPosition({value, printedRange, kind, defaultRange})`, in the same file and vector file,
which applies the precedence above and returns the position with its `RangeSource` (`printed` or
`general`), or none. A Printed Range that parses is used, unless `kind` is `riskTarget`, which
gives no position. Otherwise the Default Range is used, with inclusive bounds. With neither,
there is no position.

It is shown as words, never as colour alone, and never as "normal" or "abnormal". It is never
stored.

**Profile fields.** The Lab Results screen carries one fixed line: "General ranges use your sex
and birth year from Profile.", linking to the Profile screen. It is not an ask and cannot be
dismissed, so User Profile Goal 7 does not apply.

### The display

Uses DESIGN.md components: list rows for results, a Disclosure line for privacy, the Picker sheet
for choosing a Lab Test, and standard form inputs.

*   **Where.** Progress gains a **Lab results** row directly after the Health metrics row. While
    unlocked its subtitle is "{N} lab tests", counting Lab Tests with results, or "No results
    yet". It opens the **Lab Results screen**: the Disclosure line, the profile line above,
    "Perennia recognises {N} lab tests" (opening the Lab Test picker read-only), **Add results**,
    and Lab Tests that have results, grouped by panel in catalogue order, each with its latest
    collapsed result and date. Lab Metrics whose key this build's catalogue does not know are
    listed last under "Other", with their stored name and unit, and no Default Range. Their detail
    opens and their results can be archived; they cannot be chosen in the entry sheet, and their
    Printed Ranges are parsed as `reference`. Empty state: "No lab results yet." with
    **Add results**.
*   **Lab Test detail:** a dated list, newest first, each dated from `lab.collected` (date only
    when no time was printed). Each row, in this order:
    *   the value as entered with its comparator, and the unit as entered;
    *   `Lab range {text}`, or `Target {text}` for a `riskTarget` Lab Test, when printed;
    *   `General range {low}–{high} {unit} · {source title}` when a Default Range applies
        (`Below {high}` or `Above {low}` when one side is missing);
    *   the position sentence: "Below the lab's range", "Within the lab's range", "Above the
        lab's range", or the same with "general range"; nothing for `unknown`;
    *   `Lab flag: {flag}` when printed;
    *   "Interim" when interim; "Fasting" when fasting; the lab's name when given;
    *   an archive action.
*   **Excluded elsewhere.** Lab Metrics are left out of the Health Metrics explorer, which keeps
    them away from its name-based grouping, its daily summing and Trend. Body Tracker and the
    Body card already list only `bodyComposition` Metrics, so they need no change. Lab Metrics
    remain selectable as Effect outcomes and Protocol target outcomes.
*   **No Trend.** Nothing in the app draws a Trend for a Lab Metric. The Agent read omits
    `trendValue` for Lab Metrics even when `includeTrend` is true.
*   **The lock.** The Lab Results screen and the detail sit inside `ProtocolsLockGate`; the entry
    sheet, the Lab Test picker, the warning dialog and the archive confirmation use
    `ProtocolsLockSheetGuard`, so they close when the app locks and an unsaved sheet is
    discarded. While locked, the Progress row shows a lock icon and no names, counts or values.
    The Effect view and
    the target-outcome picker are opened only from Protocols screens, which are already behind the
    lock. Activity feed labels for Metric Readings are generic and name no Lab Test. The lock is a
    device display lock: Agents and sync are not affected by it.

### Collection-based manual entry

The **entry sheet** has two parts.

*   **Collection fields**, set once at the top: collection date (required), time (optional), lab
    name (optional), report status (Final by default, or Interim), and a Fasting switch.
*   **Result rows**, one per result: Lab Test (DESIGN.md's Picker sheet in single-select mode,
    grouped by panel, with a search field that matches names and variants by case-insensitive
    substring), a comparator chooser (none, `<`, `≤`, `>`, `≥`), value, the unit as a fixed label
    showing the Lab Test's `unit`, Printed Range text and Printed Flag. Rows can be added and
    removed.

The sheet's state is a `CollectionDraft`:

```text
CollectionDraft {
  collectedDate: DateTime (date part only),  collectedTime: TimeOfDay?,
  labName: String?,  reportStatus: ReportStatus (final | interim),  fasting: bool,
  rows: List<CollectionDraftRow>
}
CollectionDraftRow {
  labTestKey: String?,  comparator: LabComparator? (lt | le | gt | ge),
  value: String (as typed),  printedRange: String?,  printedFlag: String?
}
```

`collected` is `YYYY-MM-DD`, or `YYYY-MM-DDTHH:mm` when a time is set. `entered` is built from
the comparator and value as in [Storage](#storage); `≤` and `≥` are written `<=` and `>=`.
`fasting` false is stored as null. `enteredUnit` is the Lab Test's `unit`.

**Save** runs the reading rules on every row and the app's request rules (`lab_result_repeated`,
`lab_result_replaces`), shows each hard reject on its row, lists every soft warning in one
confirmation dialog, and then writes every new Lab Metric and Lab Result in one transaction with
one Activity Log Batch. Nothing is written before Save: if the app is killed, only the unsaved
sheet is lost, never half a collection.

### Agent surface

*   **`listAgentLabTests`**: `GET /agent/lab-tests`, MCP tool `agent_list_lab_tests`, CLI command
    `list-lab-tests`. Returns `{labTests: AgentLabTest[]}`, where `AgentLabTest` is `{key, name,
    panel, variants, unit, unitAliases, hardBounds, plausibleBounds (nullable), printedRangeKind,
    defaultRanges}`, from the generated catalogue. Keys are not listed as an enum in the OpenAPI
    or MCP schema, so Agent sessions do not load them into context unless they call this. It is
    authenticated like the other Agent reads (an Agent bearer key; no extra scope).
*   **`batchWriteAgentMetrics`**: the reading item gains an optional `labTestKey`, `metricId`
    becomes optional, and exactly one of the two must be present (`lab_target_ambiguous`, a
    request rule, not a schema check). The scalar value gains an optional `lab` object in the
    shape above. Its zod schema is permissive where a lab rule judges the field: `collected`,
    `reportStatus` and `fasting` each take a string, boolean or number, or null, and unknown keys
    are allowed and dropped by the normaliser, so that a malformed field reaches the lab rules
    and gets its own code rather than a generic schema error. The text fields `printedRange`,
    `printedFlag` and `labName` are typed `string | null`: no lab rule judges a text field's
    type, and the normaliser would write a non-string as null without a word, so a wrong type
    there is a schema error. `limit` is accepted and overwritten. `AgentMetricBatchWriteMetric`
    also declares an optional `labTestKey` (any type) only so that zod does not strip it: a
    `metrics[]` row that sends it is rejected with `lab_metric_upsert_not_allowed` rather than
    silently creating a custom Metric. An omitted `value.unit` on a lab reading is the Lab
    Test's `unit`, as the normaliser reads an omitted unit as its Metric's. Validation runs before
    normalisation, and each issue keeps its rule as its code (never folded into
    `metric_reading_normalization_failed`). The idempotency receipt is the shared one. For a
    reading with `labTestKey`:
    *   a reading `id` that already exists is rejected (`lab_result_exists`), unless the request is
        a replay, which the idempotency receipt answers before any validation;
    *   `deletedAt` is rejected (`lab_archive_not_allowed`): Agents do not archive lab results in
        phase 1;
    *   `updatedAt` is the server clock, whatever the request sends;
    *   `provenance` and `source` are `agent`, whatever the request sends;
    *   `lab.limit` is derived from `entered`; a sent one is overwritten.
*   **`listAgentMetricReadings`**: when the request's `metricId` or `metricKey` filter resolves to
    any Lab Metric, the read expands to every Metric with that Lab Metric's key, collapses them,
    then applies the `source`, `provenance` and date filters, the endpoint's existing order and
    the cursor, so the cursor pages over the collapsed list. Archived rows are never returned for
    Lab Metrics, even with `includeArchived=true`, because the collapse drops them. Each reading
    keeps its own `metricId`, so readings of one Lab Test can name sibling Lab Metrics. Each
    carries its `lab` object in `valueJson`; `trendValue` is never present.
*   **`listAgentMetrics`**: a Lab Metric's `canonicalKey` is its `labTestKey`, and a catalogue key
    in the `metricKey` filter matches only Metrics with that `lab_test_key`. It may list two
    Metrics for one Lab Test (see [Risks](#risks--mitigations)); the tool description says so.
*   **The Agent Effect window** (`readAgentEffectWindow`): `resolveMetric` gains a branch for
    Lab Metrics, which reads samples of every Metric with the key and collapses them before
    windowing, as the app does.
*   **Contract diff:** one new operation and its schemas (`AgentLabTest`, `AgentLabTestList`);
    `metricId` optional and `labTestKey` added on `AgentMetricBatchWriteReading`; optional `lab`
    on `AgentMetricReadingScalarValue`, with `printedRange`, `printedFlag` and `labName` typed
    `string | null`; an optional, untyped `labTestKey` on `AgentMetricBatchWriteMetric`,
    described as not accepted; descriptions noting the key read, the collapse, the controls
    above and the Trend exclusion. No field is removed or narrowed: making `metricId` optional
    widens the request, and the `labTestKey` on a `metrics[]` row was stripped before.
    `agent-skills/perennia/SKILL.md` gains a "Logging lab results" section.

### Privacy

*   **Disclosure.** The Lab Results screen and the entry sheet show one Disclosure line per mode,
    following user-profile.md's copy. `{host}` is the server's host name.
    *   Local-only Mode: "Stored on this phone and in its backups. If you sign in, it syncs to your
        account, where the server's operator and any agent you connect can read it."
    *   Synced Mode: "Synced to {host}. The server's operator and any agent you connect can read it.
        Change history on the server is kept for up to 180 days."
*   **Every Agent key reads lab results,** as it reads every Metric, including archived values in
    `listAgentActivity` images for the 180-day retention period. No redaction is added; see
    [Risks](#risks--mitigations).
*   **Logs and crash reports.** The server scrubber (`apps/server/src/observability.ts`) adds
    `lab`, `labtestkey`, `printedrange`, `printedflag`, `collected`, `labname`, `value`,
    `scalarvalue`, `scalarentered`, `valuejson`, `externalid`, `entered`, `timeanchor`,
    `localdatetime` and `attime` to its denylist (PR 3, with the column that first syncs lab
    data). Keys are matched everywhere, so `externalid` also filters the `externalId` in the
    canonical import's logged reference summaries; only their `source` and counts remain. Lab
    validation messages carry no value and no Lab Test name (see
    [Validation](#validation)); normaliser errors carry the field name and code only.
*   **CSV export** holds no Metrics, so it holds no lab results. **The portable archive** holds
    them, like every Metric.

### Phase 2: Lab Report import

Phase 2 is an Import Adapter (CONTEXT.md): the phone reads a lab report PDF and writes Lab
Results. Its design (text extraction, how lines and columns are rebuilt, the matching algorithm,
the header vocabulary, the review and summary screens, and the "copy failure details" format) is
added to this spec after PR 5 has merged, and is reviewed before its pull request starts. It is
deferred so it can be designed against real reports and what phase 1 teaches. Whatever that
design says, it keeps these constraints, which phase 1 relies on:

*   It runs on the phone, offline, with no account. No third party sees the report.
*   The PDF is never stored or synced. The file picker's temporary copy is deleted after
    extraction, on success and on failure, and a copy left by a crash is deleted on the next app
    start. No header data is kept or logged.
*   The failure details a user can copy hold no text from the report: only counts, codes and
    layout facts.
*   It writes only through `LabResultsRepository`, in the shape and under the validation this
    spec defines, with provenance `manual` and source `labImport`, in one Batch per import.
*   It saves only rows it is sure of. Rows it cannot match are counted and shown, never saved.
*   Tests use minimal invented fixtures, never real or realistic reports.

The parser decisions already made are recorded under
[Parser alternatives](#parser-alternatives).

### Invariants touched

| Invariant | How it is kept |
|---|---|
| Sets are self-describing; values and units stored as entered | Each result keeps `entered`, `enteredUnit`, its Printed Range and Printed Flag. Unit spellings do not change the value. |
| Derived analytics are computed, never stored or synced | The collapse, Default Range, parsed Printed Range and position are computed on read. `scalarValue` keeps its existing meaning; for lab units it equals the entered number, because only spellings are accepted. |
| User-facing delete = archive | Results are archived, never deleted; Lab Metrics are never deleted. |
| Restore/import is merge-only | Restore adds rows by id; the collapse decides what shows. Nothing is replaced or removed. |
| Local writes never block on the network | Entry writes locally in one transaction. |
| Sync is silent LWW with recoverable losers | No new conflict rule. Duplicates are resolved by the collapse, not a dialog. |
| Validation is one shared two-tier module | New lab rules in Dart and TypeScript, golden-vectored (m42), used by entry and the Agent write. |
| No behavioral analytics | No parse telemetry; nothing about lab results leaves the phone except through sync and the user's Agents. |

### Validation and analytics consequence

*   **Validation:** the lab reading rules above (m42). The m12 reading normalisation vectors gain
    lab cases: an alias kept as entered; an unaccepted unit rejected; `< 1` becomes a Limit
    Result with null `scalarValue` and `entered` `"< 1"`; `≤ 1` stored as `"<= 1"`; a sent
    `limit` overwritten; blank text written as null; a comparator on a non-lab Metric rejected;
    `lab` written in canonical key order. Two existing m12 defects are fixed first, in PR 1: the
    file has no reject cases, and TypeScript accepts entered strings with trailing text (`"64 %"`,
    `"1.7 x10^9"`) that Dart rejects.
*   **Analytics:** the collapse (m43, Dart and TypeScript), and Default Range, Printed Range
    parsing and position (m44, Dart only: no server reader computes them; Agents get Default
    Ranges as catalogue data). Effect's rules and the m29 Effect-window vectors are unchanged;
    only the samples given to them change for Lab Metrics.

### Repository doc changes

*   **CONTEXT.md** (PR 2): new terms
    *   **Lab Test**: a catalogue entry for one thing a lab measures, with its key, unit, bounds and
        Default Ranges. Read-only, like the Nutrient registry. Always "Lab Test", never a bare
        "test".
    *   **Lab Metric**: a Metric for one Lab Test. Readers join every Lab Metric with the same Lab
        Test.
    *   **Lab Result**: one value of one Lab Test from one collection: a Metric Reading on a Lab
        Metric, carrying what the lab printed, its Report Status (interim or final) and whether it
        was fasting.
    *   **Limit Result**: a Lab Result reported only as a bound, such as `< 1`. Never treated as
        equal to its bound.
    *   **Printed Range**: the range the lab printed beside a Lab Result, kept as text. Never
        computed.
    *   **Printed Flag**: the flag the lab printed beside a Lab Result, kept as printed. Never
        computed.
    *   **Default Range**: a general range from the catalogue, with its source, shown only where the
        lab printed none, chosen by the User Profile's sex and age. Derived on read.

    The Metric entry changes "readings differ only by provenance (tracked, manual, or agent)" to
    name the provenances the code uses (`manual`, `integration`, `agent`) and to say a Lab Result
    also carries lab metadata.
*   **ARCHITECTURE.md** (PR 2): the repository map lists `packages/lab-catalogue`.
*   **AGENTS.md** (PR 5): the Progress root in the Screen map links to Lab results.
*   **DESIGN.md** (PR 5): Root navigation's Progress description names Lab results.
*   **progress-overview.md** (PR 5): the Progress root's links include Lab results.

## Alternatives Considered

### Storage alternatives

#### Alternative A: A separate lab domain with its own tables and sync entity

*   **Pros**: Lab fields get typed columns. No risk of an older normaliser dropping a `valueJson`
    key.
*   **Cons**: Rebuilds what Metric Readings already have: a Drift table, a Postgres table, a sync
    entity, Agent reads and writes, MCP tools, golden vectors, Activity Log and Batch undo, the
    archive, and a separate place in Effect and Protocol target outcomes. An older server rejects
    pushes for an entity it does not know.
*   **Reason for Rejection**: A lab value is a Metric by CONTEXT.md's own definition ("the body's
    state or response"), and every capability the feature needs already exists for Metrics.

#### Alternative B: Lab metadata in a sibling sync entity that references the Reading

*   **Pros**: Follows the `protocol_skips` precedent. An older app never touches the lab fields.
*   **Cons**: Two rows to keep consistent per result, under last-writer-wins, across archive and
    restore. Every reader joins them. An older server rejects the new entity.
*   **Reason for Rejection**: It protects only against an older app editing a Lab Result, which
    pre-1.0 is accepted and recoverable from the Activity Log, at the cost of a second row per
    result everywhere.

#### Alternative C: New typed columns on `metric_readings`

*   **Pros**: Queryable and typed.
*   **Cons**: An older client pushing a whole row writes the columns back as null, silently, under
    last-writer-wins.
*   **Reason for Rejection**: Silent erasure is worse than the `valueJson` case, where the loser
    stays whole in the Activity Log before-image.

#### Alternative D: A new `MetricGroup` value such as `labResults`

*   **Pros**: Marks Lab Metrics with the field that already exists for grouping.
*   **Cons**: The app decodes `MetricGroup` with `values.byName`, which throws on an unknown
    value, so an older app would fail on every read of a Lab Metric. This is the failure fixed in
    [protocol-target-outcome-sync-shape.md](protocol-target-outcome-sync-shape.md).
*   **Reason for Rejection**: `lab_test_key` marks a Lab Metric with no enum change.

#### Alternative D2: Store the parsed range bounds, the range kind and an IANA zone in `lab`

*   **Pros**: Readers need no parser; the zone records where the collection happened.
*   **Cons**: Low and high are a deterministic parse of the text: derived data stored and synced,
    and an Agent could send numbers that disagree with the text. The kind is a property of the
    Lab Test. No reader uses a zone, and validating IANA names ties the vectors to two time zone
    databases (Dart and Node) that can disagree.
*   **Reason for Rejection**: Store the text and the existing offset; derive the rest.

### Unit alternatives

#### Alternative E: Convert on write between units, with the factor snapshot in `valueJson`

*   **Pros**: Results in mg/dL and mmol/L join one series with no reader change.
*   **Cons**: The factor depends on the Lab Test (each has its own molar mass), and some pairs
    have no factor at all (IU against mass units). A wrong factor stores a wrong value with
    nothing to show it. A Lab Test's unit is fixed forever once results exist.
*   **Reason for Rejection**: The labs the seed targets report in SI units, and the differences
    between them are spellings. A factor per Lab Test can be added later under its own vectors.

#### Alternative F: Convert on read

*   **Pros**: A corrected factor fixes every view at once.
*   **Cons**: Every reader of `scalarValue` changes, in Dart and TypeScript. It contradicts how
    every other Metric works.
*   **Reason for Rejection**: With no conversion in v1 there is nothing to convert on read.

### Identity alternatives

#### Alternative G: Skip duplicates on write by Lab Test, collection date and value

*   **Pros**: The simplest rule.
*   **Cons**: A date is too coarse (morning and afternoon cortisol). Including the value means a
    revised final never matches its interim. It sees only the local replica, so two devices, or
    an entry plus an Agent write, keep permanent duplicates.
*   **Reason for Rejection**: It does not converge, and it cannot express "final replaces interim".

#### Alternative H: Update in place by `(source, externalId)`

*   **Pros**: Uses an existing index. A final overwrites its interim.
*   **Cons**: The existing upsert (`upsertIntegrationReadings`) matches only `integration` rows,
    which the app cannot edit and the imported-data purge can remove. Two devices that write the
    same result before syncing still produce two rows.
*   **Reason for Rejection**: Keeping every row and collapsing on read handles the two-device case
    with no extra rule.

#### Alternative I: Archive the interim and insert the final

*   **Pros**: Every existing reader stays correct with no change.
*   **Cons**: The two-device race leaves a visible duplicate. Archiving automatically blurs what
    the user did.
*   **Reason for Rejection**: The collapse converges with no stored repair.

#### Alternative I2: A write-time "already present" skip in front of the collapse

*   **Pros**: Fewer stored rows when the same collection is entered twice.
*   **Cons**: A skip keyed on identity and value drops a final whose value equals its interim's,
    leaving the interim shown for good. Making it safe needs its own rules and vectors, for
    clutter the collapse already hides.
*   **Reason for Rejection**: Correctness comes from the collapse; the skip adds risk for no
    visible gain.

#### Alternative J: A hash of the lab's accession number in a result's identity

*   **Pros**: Separates two collections of the same Lab Test in the same minute.
*   **Cons**: Accession numbers are 8 to 10 digits, so an unsalted hash is reversed by trying every
    value, and no salt is shared by every device, the server and an Agent in Local-only Mode: the
    hash is the number. Manual entry and Agent writes rarely have one, so identity would differ by
    path for the same result.
*   **Reason for Rejection**: The case it solves is narrower than it looks. Two draws with printed
    times differ by `collected` already. The real collision is two draws on one day entered
    date-only, where only one would show; the `lab_result_replaces` warning catches it at save
    time and the user can add the time. Every row is kept, so nothing is lost either way.

#### Alternative K: Metric ids derived from the Lab Test key

*   **Pros**: Every device and the server compute the same id with no fold.
*   **Cons**: Server ids are global. A second user's push of the same derived id is skipped by the
    tenant-isolation rule with no error, so that user's lab data would never sync. A Local-only
    device has no user id to scope the id with.
*   **Reason for Rejection**: Reading by key gives one series without shared ids. The Agent path
    does use a user-scoped derived id, because the server has the user id.

#### Alternative K2: Fold duplicate Lab Metrics into one on create

*   **Pros**: One Metric row per Lab Test, so pickers show each Lab Test once.
*   **Cons**: The existing fold (`metricAliasTarget`) runs only when the server has no row for the
    pushed id. Duplicates that both reach the server (two offline devices, rows created through an
    older server, an archived row and a new Agent row) are never folded, and identity per Metric
    would then split the series for good. A unique index would turn those legitimate duplicates
    into refused pushes that stall sync.
*   **Reason for Rejection**: Reading by key makes duplicates harmless and needs no fold, adoption
    or restore rule.

### Value alternatives

#### Alternative L: Store a Limit Result's bound in `scalarValue`

*   **Pros**: The result appears on charts and in means with no new handling.
*   **Cons**: A `< 5` would be averaged as 5, biasing every mean and Effect segment upwards for
    the results most often reported as limits.
*   **Reason for Rejection**: A Limit Result is not a number. Leaving `scalarValue` null keeps it
    out of every calculation. That has its own bias: a window's mean covers only the measurable
    results, so a Protocol that pushes a marker below detection shows a higher or missing value in
    Effect. It is recorded under [Risks](#risks--mitigations), and Limit Result markers belong to
    the visualization spec.

#### Alternative M: Compute a flag from the range

*   **Pros**: Every result gets a high/low marker, even where the lab printed none.
*   **Cons**: A stored computed flag goes stale when ranges change and moves towards a medical
    verdict, which CONTEXT.md rules out for Effect ("descriptive, never a causal or medical
    claim").
*   **Reason for Rejection**: The lab's flag is stored as printed. Position against a range is
    computed on read and worded descriptively.

#### Alternative N: No Default Ranges

*   **Pros**: No clinical reference content in the repository. No dependency on the User Profile.
*   **Cons**: Results entered without a range would show no context. The User Profile shipped sex
    and birth year for this use.
*   **Reason for Rejection**: The risks of showing clinical ranges are an unsourced range, a range
    shown over the lab's own, a range for the wrong sex or age, and a range read as a verdict.
    Each is handled: every default cites its source; it shows only where the lab printed none; it
    needs the matching profile fields; and position is worded descriptively, never stored.

#### Alternative N2: An inline card asking for the missing profile field

*   **Pros**: Prompts the user at the moment a Default Range is missing.
*   **Cons**: A dismissible card needs a synced dismissal record. The server stores user settings
    as one payload that Agent settings writes and Settings saves rebuild from fixed fields, so the
    record would be reset; a new settings column would also break restore of every existing
    backup. The fix touches settings sync for every field.
*   **Reason for Rejection**: One fixed line linking to Profile serves the same need with no
    stored state.

### Agent surface alternatives

#### Alternative O: A new operation `batchWriteAgentLabResults`

*   **Pros**: A shape built for labs: one collection with many results.
*   **Cons**: A second write path for Metric Readings, with its own receipt, issue shape and tests,
    that must stay identical in validation to the first.
*   **Reason for Rejection**: Optional `labTestKey` and `lab` fields on `batchWriteAgentMetrics`
    give an Agent the same capability with a small, additive contract diff.

### Display alternatives

#### Alternative P: Show Lab Metrics in the Health Metrics explorer, grouped by panel

*   **Pros**: No new screen.
*   **Cons**: The explorer files Metrics by name-substring rules before it checks the group, sums
    values in daily and weekly modes, and draws Trend. Each lab row would need the Protocols lock
    inside a screen that is otherwise unlocked.
*   **Reason for Rejection**: A Lab Results screen avoids changing the explorer's rules and puts
    the lock on one screen.

#### Alternative Q: Use the Effect view as the lab view

*   **Pros**: It already overlays Metrics on a Protocol's timeline.
*   **Cons**: Its BEFORE and AFTER windows mirror DURING's length and drop earlier samples, so a
    baseline months before a Protocol is excluded. It needs a Protocol to be picked. It has no
    published spec.
*   **Reason for Rejection**: Effect keeps working with Lab Metrics as outcomes. A lab-specific
    baseline and view belong to the visualization spec.

#### Alternative Q2: An edit path for Lab Results

*   **Pros**: A typo can be fixed in place.
*   **Cons**: Every edit path must carry the `lab` object forward, the Agent would need to address
    Lab Metrics by id, and each case needs its own rule and vector.
*   **Reason for Rejection**: Archive and re-enter covers the need in phase 1.

### Privacy alternatives

#### Alternative R: A lock of its own for lab results, or no lock

*   **Pros**: A separate lock lets a user hide labs without hiding Protocols. No lock is simpler.
*   **Cons**: Hormone and blood-count results can reveal what the Protocols lock hides, so no lock
    defeats it. A second lock is a second setting, screen and unlock flow.
*   **Reason for Rejection**: One lock covers the data that reveals the same thing.

### Parser alternatives

These decisions bind the phase 2 design.

#### Alternative S: The parser first, or the parser alone

*   **Pros**: The user-visible feature arrives first, and works offline with no account.
*   **Cons**: Identity, limits, ranges and duplicate handling all have to exist before a parser can
    save anything safely.
*   **Reason for Rejection**: Phase 1 builds those rules once, for manual entry and the Agent write
    as well as the parser.

#### Alternative T: OCR, in-app AI parsing, or one parser per lab

*   **Pros**: OCR reads scanned reports. AI parsing handles any layout. Per-lab parsers are exact
    for the labs they cover.
*   **Cons**: OCR adds a large native dependency and its own error rate for reports that already
    have a text layer. AI parsing sends the report to a third party, which on-device parsing exists
    to avoid. Per-lab parsers need a realistic fixture per lab, which this repository will not
    hold.
*   **Reason for Rejection**: One generic matcher driven by the catalogue, saving nothing it is
    unsure of, is the only option that fits offline use, no third party, and no realistic
    fixtures.

#### Alternative U: Plain-text PDF extraction, or `syncfusion_flutter_pdf`

*   **Pros**: Smaller or already-familiar packages.
*   **Cons**: Plain text loses x and y positions, which a flag column, the columns of a cumulative
    table and sub-rows depend on; platform extractors order text differently on iOS and Android.
    `syncfusion_flutter_pdf` has a proprietary licence that cannot go into this AGPL-3.0 app.
*   **Reason for Rejection**: The matcher needs positioned text from a licence-compatible package.

#### Alternative V: Synthetic, realistic report PDFs as test fixtures

*   **Pros**: End-to-end tests of the whole import.
*   **Cons**: An invented layout validates only itself. A realistic fixture drifts towards real
    patient data.
*   **Reason for Rejection**: Minimal invented fixtures only.

#### Alternative W: A separate spec for the Lab Report import, or designing it now

*   **Pros**: A separate spec is shorter to review. Designing it now gives the whole picture.
*   **Cons**: The parser is part of the Lab Results feature and writes only in phase 1's shape; a
    separate spec would spread the feature's rules across documents. Designing it now fixes a
    matching algorithm before phase 1 or any real report has shown what it must handle.
*   **Reason for Rejection**: One spec, with phase 2's constraints now and its design added after
    phase 1 merges.

--------------------------------------------------------------------------------

## Non-Functional Requirements

*   **Security and privacy.** Lab results are health data. They are protected on the device by
    the Protocols lock (display only), stored in Synced Mode on the user's server without
    end-to-end encryption (ARCHITECTURE.md, Sync), and readable by every Agent the user connects.
    The Disclosure line says so. No report header data is stored. The server scrubber's denylist
    covers every new key.
*   **Performance.** The collapse is linear in the readings of one Lab Test: a few dozen rows, run
    on read. Entry writes in one local transaction and never waits on the network. The generated
    catalogue is about 60 entries.
*   **Rollout and compatibility.** No feature flag: the project is pre-1.0 and only a release tag
    ships. Rollback is a release without the feature; the new column stays, unread.

## Risks & Mitigations

| Risk | Impact | Mitigation or accepted limit |
|---|---|---|
| Two Lab Metrics for one Lab Test (two devices offline; created through an older server) | The Lab Test appears twice in the Effect and target-outcome pickers | Accepted. Every lab reader joins by key, so results never split. Picking either Metric in Effect gives the same samples. |
| Effect leaves out Limit Results | A window's mean covers only measurable results; a marker pushed below detection looks higher or missing | Accepted for phase 1 and stated in Alternative L. Limit Result markers belong to the visualization spec. |
| A date-only result and a timed result of one collection | They have different identities, so both show | Accepted. Manual entry offers the time; revisited with the phase 2 design, where it mostly arises. |
| Two different draws of one Lab Test on one day, both entered date-only | They share an identity, so only one shows | The `lab_result_replaces` soft warning names the clash before saving; adding the time keeps both. Both rows are kept either way. |
| A hand-made custom Metric named like a Lab Test | The Effect and target-outcome pickers show two entries with the same name | Accepted. Key matching on the Agent surface ignores the custom Metric; the pickers are a later visualization spec's concern. |
| An archived Lab Metric (after undo of the save that created it) | It is missing from the Effect and target-outcome pickers until a later save creates or reuses a live one | Accepted. Its results are still read by key everywhere else. |
| Between PR 4 and PR 5, an Agent can write lab results the app does not show (Lab Metrics are already out of the explorer) | No user-visible loss | Accepted: only a release tag ships, and PR 5 lands before one. |
| Agent history shows lab values | Archived values stay readable in `listAgentActivity` for 180 days | Accepted and stated in the Disclosure line's 180-day sentence. Redaction would be a separate change. |
| A catalogue key's unit or meaning changes after release | Stored values are relabelled | The README forbids it; a CI check against the last released catalogue is added with the first release tag. |
| An older app build meets a Lab Test key its catalogue lacks | The Lab Test cannot be added on that device | It is shown under "Other", read-only. |
| An older app build edits a Lab Result in the explorer | The `lab` object is dropped | Pre-1.0 and recoverable: the previous row is the Activity Log before-image. The collapse shows a lab-less row as its own result. |
| An older server drops `lab_test_key` | Metrics created through it reach other devices without the key and show as custom Metrics there | Accepted pre-1.0; app and server release together. |
| A Default Range is transcribed wrongly | A wrong general range is shown | Values are copied verbatim from one cited source, reviewed in PR 2, and always shown with that source. |
| The seed's 2014 intervals were not checked against Koerbin 2018, and ten chemistry Lab Tests have no Default Range | A superseded general range may be shown; those ten show no general range and no plausibility warning | Accepted for now and listed under [What the seed has](#default-ranges); a later catalogue pull request reads the 2018 update and closes both. |
| Age is accurate to ±1 year (User Profile) | A user near an age-band edge may get the neighbouring band's range | Accepted; the range is labelled general and shows its source. |
| Two rows of one Lab Test in one collection on two devices (e.g. typed twice) | Collapse keeps one | Accepted; this is the intended rule. |

### Additional Resources

*   [user-profile.md](user-profile.md): `about_you.sex`, `about_you.birth_year`, `ageAt`, the
    Disclosure copy this spec reuses, and Goal 7 on inline asks.
*   [progress-overview.md](progress-overview.md): the Progress root and how the Protocols lock is
    shown there.
*   [protocol-target-outcome-sync-shape.md](protocol-target-outcome-sync-shape.md): the
    unknown-enum decode failure this spec avoids.
*   [compound-purposes.md](compound-purposes.md): Protocols-locked data left out of CSV export.

### Future Improvements

*   **Phase 2's design**, added to this spec after PR 5.
*   **The visualization spec:** range bands per point, Limit Result markers, a by-collection view,
    and an Effect baseline from the nearest result before a Protocol starts.
*   **Unit factors per Lab Test**, when a contributor's lab reports in a non-SI unit.
*   **Editing a Lab Result.**
*   **Per-domain Agent key scopes**, so a key can be refused lab results.

--------------------------------------------------------------------------------

## Detailed Implementation Plan

Five pull requests, in merge order, each cut from `main` after the one before it merged.

**Numbering.** Schema version 68, Drizzle migration `0038`, and golden vectors `m42`, `m43` and
`m44` are the next free ones at the time of writing. If another change takes one first, take the
next free one and correct this spec in the same pull request.

### PR 1: Fix the m12 reading normalisation defects

A bug fix that restores the specified behaviour; it comes first because PR 2 adds lab cases to
the same vector file. No lab code. Covers V0.

| File | Change | Detail |
|---|---|---|
| `packages/golden-vectors/vectors/m12-reading-normalization.json` | Modify | Add reject cases. A reject case's `expected` is `{rejected: true, error: <message prefix>}`, where the prefix is the start of the thrown message that Dart and TypeScript share. Cases: a non-numeric `entered`; `"64 %"`; `"1.7 x10^9"`; an empty `entered`; a unit the converter does not know; a `structured` value on a `scalar` Metric. |
| `apps/server/src/metric-reading-normalization.ts` | Modify | Replace `Number.parseFloat` with a whole-string parse matching Dart's `double.tryParse` on finite values: the trimmed string must match `^[+-]?(?:\d+(?:\.\d*)?\|\.\d+)(?:[eE][+-]?\d+)?$` (the same language as `^[+-]?(\d+\.?\d*\|\.\d+)([eE][+-]?\d+)?$`, written without overlapping quantifiers so a long digit run fails in linear time), then `Number(trimmed)`; anything else throws the existing "must be finite" error. Trailing text is rejected. |
| `apps/mobile/lib/domain/metrics/reading_normalization.dart` | Modify | The finite error message becomes `Metric Reading value must be finite.`, the TypeScript text Agents already receive, so the two share one message prefix. The Dart parse (`double.tryParse`) does not change. |
| `apps/mobile/test/domain/metric_reading_normalization_test.dart` | Modify | A reject case expects a throw whose message starts with `error`. |
| `apps/server/test/metric-reading-normalization.golden.test.mjs` | Modify | The same. |
| `CHANGELOG.md` | Modify | `Fixed`: the server rejects metric values with trailing text, as the app does. |

An accepted case for `"1e3"` (a Dart double literal) is added too, so the two parsers are pinned
to the same grammar from both sides.

### PR 2: Lab Test catalogue, shared rules and golden vectors

Pure data and pure functions. No database change, no UI, no Agent surface change. Covers V1 to V4.

| File | Change | Detail |
|---|---|---|
| `packages/lab-catalogue/lab-tests.json` | Create | The seed below, in the file shape in [The Lab Test catalogue](#the-lab-test-catalogue). |
| `packages/lab-catalogue/README.md` | Create | What a Lab Test is; the contribution checklist; the immutability rules; the bounds rule; the Default Range source rule; how to regenerate. |
| `tools/generate-lab-test-catalogue.mjs` | Create | Exports `validateCatalogue(json)` (the [generator rules](#the-lab-test-catalogue)) and `emit(json)`; runs them only when executed directly. Writes the two generated files; `--check` exits non-zero when either differs. Emits Dart with single quotes and runs no formatter, so its output is already `dart format` clean. Run as `node tools/generate-lab-test-catalogue.mjs` (write) or with `--check`. |
| `apps/mobile/lib/domain/labs/lab_test_catalogue.generated.dart` | Create (generated) | `const` Lab Test entries and lookups by key and by folded unit spelling. |
| `apps/server/src/data/lab-test-catalogue.generated.ts` | Create (generated) | The same, for the server. |
| `apps/mobile/lib/domain/labs/lab_test.dart` | Create | `LabTest`, `Bounds`, `DefaultRange`, `PrintedRangeKind`; `foldUnit(String)` (remove spaces, keep case); `resolveLabUnit(labTest, enteredUnit)` returning the canonical unit or null. |
| `apps/mobile/lib/domain/labs/lab_result.dart` | Create | `LabFields` (the `lab` object), `LabLimit`, `ReportStatus`, `LabComparator`; `encodeLab` in the canonical key order; `decodeLab` as in [Storage](#storage); `formatEntered(comparator, value)` and `parseEntered(entered)` for the canonical `entered` form. |
| `apps/mobile/lib/domain/labs/lab_result_validation.dart` | Create | `LabResultInput {labTestKey, entered, enteredUnit, lab, timeAnchor}`; `validateLabResult(LabResultInput, {required DateTime today}) → LabValidationResult {errors, warnings}`, each issue `{rule, field}`; the reading rules in [Validation](#validation). |
| `apps/mobile/lib/domain/labs/lab_result_collapse.dart` | Create | `LabReadingRef {id, labTestKey, lab (LabFields?), atTime, updatedAt, deletedAt}`; `collapseLabResults(List<LabReadingRef>) → List<LabReadingRef>`, as in [the collapse](#result-identity-and-the-collapse). |
| `apps/mobile/lib/domain/labs/lab_default_range.dart` | Create | `ParsedRange {low, lowInclusive, high, highInclusive}`; `defaultRangeFor(LabTest, String? printedRange, ProfileSex? sex, int? age) → DefaultRange?` (`ProfileSex` from `lib/domain/profile/user_profile.dart`); `parsePrintedRange(String) → ParsedRange?`; `rangePosition(LabValue, ParsedRange) → RangePosition`, where `LabValue` is a number (`LabNumber`) or a limit (`LabLimitValue`); `resultPosition({value, printedRange, kind, defaultRange}) → ({RangePosition position, RangeSource source})?`, as in [Position, on read](#default-ranges). |
| `apps/mobile/lib/domain/metrics/reading_normalization.dart` | Modify | The three normaliser steps in [Storage](#storage), including a null `scalarValue` for a Limit Result; non-lab behaviour unchanged. |
| `apps/server/src/lab-results.ts` | Create | TypeScript counterparts of `lab_test.dart`, `lab_result.dart` and `lab_result_collapse.dart`. |
| `apps/server/src/agent-validation.ts` | Modify | `validateLabResult`, matching the Dart reading rules, in the existing validators' result shape. |
| `apps/server/src/metric-reading-normalization.ts` | Modify | The same change as the Dart normaliser. |
| `apps/server/src/index.ts` | Modify | Export `validateLabResult` and `collapseLabResults`, which the golden-vector runners import from `../src/index.ts`. |
| `packages/golden-vectors/vectors/m42-lab-result-validation.json` (+ `.schema.json`) | Create | Cases shaped as in [Validation](#validation). Every reading rule, accepted and rejected, including boundaries (equal to `min` and `max`, exclusive limits), a fold match (`x10^9 /L`), an unlisted case variant rejected, blank text accepted as null, a 121-code-unit `printedRange`, and an offset of 841. |
| `packages/golden-vectors/vectors/m43-lab-result-collapse.json` (+ `.schema.json`) | Create | Each case `{name, input: {readings}, expected: {keptIds}}`, `keptIds` in output order. Interim then final → final kept; two finals → later `updatedAt`; `updatedAt` in the same second with different milliseconds → greater id; one archived row → the other kept; a row with no `lab` → kept alone; an unknown `reportStatus` loses to `final`; date-only against date-time → both kept; two Metric rows with one key → one group; different keys → two groups. |
| `packages/golden-vectors/vectors/m44-lab-default-range.json` (+ `.schema.json`) | Create | Each case has a `function` discriminator (`defaultRangeFor`, `parsePrintedRange`, `rangePosition` or `resultPosition`) with that function's `input` and `expected`; `defaultRangeFor` cases give their entries inline rather than from the catalogue, so two matching entries can be expressed. Printed Range wins; sex null with a sex-specific entry → none; birth year null with an age-banded entry → none; `any` entry with no profile → shown; two matching entries → none; age at both band edges and one past each; every grammar form, brackets, an em dash, `a > b`, a comma decimal and trailing text; every `rangePosition` rule for numbers and limits at inclusive and exclusive bounds, including `unknown`; `riskTarget` never positioned and a Printed Range beating a Default Range, through `resultPosition`. |
| `packages/golden-vectors/vectors/m12-reading-normalization.json` | Modify | The lab cases in [Validation and analytics consequence](#validation-and-analytics-consequence). |
| `packages/golden-vectors/vectors/README.md` | Modify | Register m42, m43, m44 and their domains. |
| `apps/mobile/test/domain/lab_result_validation_test.dart` | Create | Runs m42 in Dart. |
| `apps/mobile/test/domain/lab_result_collapse_test.dart` | Create | Runs m43 in Dart. |
| `apps/mobile/test/domain/lab_default_range_test.dart` | Create | Runs m44 in Dart. |
| `apps/mobile/test/domain/metric_reading_normalization_test.dart` | Modify | Runs the new m12 cases. |
| `apps/mobile/test/domain/golden_vector_ownership_test.dart` | Modify | Owners for `lab-result-validation`, `lab-result-collapse`, `lab-default-range`. |
| `apps/server/test/lab-results.golden.test.mjs` | Create | Runs m43 in TypeScript. |
| `apps/server/test/agent-validation.golden.test.mjs` | Modify | `lab-result-validation` in `VALIDATORS_BY_DOMAIN`; `lab-result-collapse` and `lab-default-range` in `DOMAINS_OWNED_ELSEWHERE` (the latter with the comment "Dart only: no server reader"). |
| `apps/server/test/metric-reading-normalization.golden.test.mjs` | Modify | Runs the new m12 cases. |
| `apps/server/test/lab-test-catalogue.test.mjs` | Create | Imports `validateCatalogue` from the generator; one rejected fixture per rule and the real file accepted. Also checks the PRN collision rule in [The Lab Test catalogue](#the-lab-test-catalogue) against `PRN_METRIC_SCHEMAS`. |
| `apps/server/package.json` | Modify | Add `test/lab-results.golden.test.mjs` to `test:golden-vectors`. |
| `.github/workflows/ci.yml` | Modify | Add `node tools/generate-lab-test-catalogue.mjs --check` to the `contract-drift` job beside the other seed checks. Add `packages/lab-catalogue/**`, `tools/generate-lab-test-catalogue.mjs` and both generated files (`apps/mobile/lib/domain/labs/lab_test_catalogue.generated.dart`, `apps/server/src/data/lab-test-catalogue.generated.ts`) to the `contract` path filter, the first two to the `js` filter, and `apps/server/src/lab-results.ts`, `apps/server/src/data/lab-test-catalogue.generated.ts` and `apps/server/test/lab-results.golden.test.mjs` to the `golden_vectors` filter. |
| `tools/ci-local.mjs` | Modify | The same check and paths, in the same commit. |
| `CONTEXT.md` | Modify | The terms and Metric change in [Repository doc changes](#repository-doc-changes). |
| `ARCHITECTURE.md` | Modify | `packages/lab-catalogue` in the repository map. |

**Seed catalogue.** Keys by panel, with `unit`. Aliases are listed explicitly, since the fold
removes only spaces: every unit ending in `/L` also lists its lower-case `l` form; `umol/L` also
lists `µmol/L` and `µmol/l`; `U/L` lists `IU/L` and `IU/l`; `x10^9/L` lists `10^9/L`, `10^9/l`
and `x10^9/l` (and the same pattern for `x10^12/L`); `ug/L` lists `µg/L` and `µg/l`. A spelling
that differs from a listed one only by spaces is not listed, because the generator rejects it:

*   *Sex hormones:* `testosterone_total` `nmol/L`, `testosterone_free_calc` `pmol/L`, `shbg`
    `nmol/L`, `oestradiol` `pmol/L`, `lh` `IU/L`, `fsh` `IU/L`, `progesterone` `nmol/L`.
*   *Pituitary and adrenal:* `prolactin` `mIU/L`, `cortisol` `nmol/L`, `growth_hormone` `ug/L`,
    `igf_1` `nmol/L`, `dhea_s` `umol/L`.
*   *Lipids* (`printedRangeKind: "riskTarget"`): `cholesterol_total`, `triglycerides`,
    `hdl_cholesterol`, `ldl_cholesterol`, `non_hdl_cholesterol` `mmol/L`;
    `cholesterol_hdl_ratio` `ratio`.
*   *Inflammation:* `hs_crp` `mg/L`.
*   *Electrolytes:* `sodium`, `potassium`, `chloride`, `bicarbonate`, `anion_gap` `mmol/L`.
*   *Kidney:* `urea` `mmol/L`, `creatinine` `umol/L`, `egfr` `mL/min/1.73m²` (aliases
    `mL/min/1.73m2`, `ml/min/1.73m²` and `ml/min/1.73m2`), `urate` `mmol/L`.
*   *Liver:* `bilirubin_total` `umol/L`; `alp`, `ggt`, `alt`, `ast`, `ld` `U/L`; `total_protein`,
    `albumin`, `globulin` `g/L`.
*   *Bone and minerals:* `calcium`, `calcium_adjusted`, `phosphate`, `magnesium` `mmol/L`.
*   *Full blood count:* `haemoglobin` `g/L`, `haematocrit` `L/L`, `rcc` `x10^12/L`, `mcv` `fL`,
    `mch` `pg`, `mchc` `g/L`, `rdw` `%`, `wcc` `x10^9/L`, `platelets` `x10^9/L`, and for each of
    neutrophils, lymphocytes, monocytes, eosinophils and basophils a `_percent` (`%`) and a
    `_count` (`x10^9/L`) Lab Test.

That is 60 Lab Tests. `variants` for each: the common report spellings of its name, lower case
(for example `alk phos` and `alkaline phosphatase` for `alp`; `gamma gt` for `ggt`;
`total/hdl ratio` for `cholesterol_hdl_ratio`; `corrected calcium` and
`calcium (adjusted for albumin)` for `calcium_adjusted`).

**Bounds rule.** `hardBounds` catches impossible values and is set by unit: `min` 0 and `max` 100
for `%` and `ratio`; 1 for `L/L`; 1000 for `mmol/L`, `g/L`, `fL`, `pg` and `x10^9/L`; 100 for
`x10^12/L`; 10 000 for `mg/L`, `U/L`, `IU/L` and `mL/min/1.73m²`; 100 000 for `umol/L`, `nmol/L`,
`ug/L` and `mIU/L`; 1 000 000 for `pmol/L`. `plausibleBounds` is set only for Lab Tests the
[Default Range source](#default-ranges) covers: from one fifth of its lowest adult lower limit to
five times its highest adult upper limit, across sexes, rounded outwards to three significant
figures; a missing lower limit gives `min` 0. Every other Lab Test has no `plausibleBounds`.

### PR 3: Storage, identity and sync

Covers V5 to V8, and V10 for sync pushes.

| File | Change | Detail |
|---|---|---|
| `apps/mobile/lib/data/local/app_database.dart` | Modify | `Metrics.labTestKey` (nullable text) with index `metrics_lab_test_key_index`; `schemaVersion` 68 and its migration step. |
| `apps/mobile/drift_schemas/app_database/drift_schema_v68.json` | Create (generated) | Schema snapshot. |
| `apps/mobile/lib/data/local/app_database.g.dart` | Regenerate | Drift codegen. |
| `apps/mobile/test/generated_migrations/app_database/*` | Regenerate | Migration test scaffolding for v68. |
| `apps/server/src/db/schema.ts` | Modify | `metrics.labTestKey` (`lab_test_key`, nullable text) and index `metrics_user_lab_test_key_index` on `(user_id, lab_test_key)`. |
| `apps/server/drizzle/0038_lab_results.sql`, `apps/server/drizzle/meta/0038_snapshot.json` | Create | The migration and its snapshot. |
| `apps/server/drizzle/meta/_journal.json` | Modify | The 0038 entry. |
| `apps/server/src/sync.ts` | Modify | `MetricSyncPayloadSchema` gains optional nullable `lab_test_key`. `pushMetricsInTransaction` applies the write-once rule in [Storage](#storage): it sets `labTestKey` in `rowValues` only when the stored key is null and the push carries a non-null key. `metricSyncPayload` (pull) emits `lab_test_key`. |
| `apps/server/src/observability.ts` | Modify | The denylist keys in [Privacy](#privacy). |
| `apps/mobile/lib/data/repositories/training_repositories.dart` | Modify | **Records:** `MetricRecord.labTestKey`, set by `_metricRecordFromRow`. **Sync and Activity Log:** `_metricImage` carries `lab_test_key`; `_metricCompanionFromImage` (used by pull and undo) applies the write-once rule: it leaves the column absent when the image has no key, or when the stored key is non-null; `_activityLaterAddedKeyDefaults` gains `lab_test_key: null` for Metrics, so undo of an Activity Log entry written before schema 68 still finds its image current. **Write path:** `MetricDraft` gains `labTestKey`, written by `_createMetric`; `ManualMetricReadingDraft` gains optional `lab` (`LabFields`), `localDateTime` and `timezoneOffsetMinutes`; the body of `createManualReading` that normalises and inserts one Reading is factored into a private `_insertMetricReading(MetricRow metric, ManualMetricReadingDraft draft, WriteContext context)`, which `createManualReading` keeps calling under its own context; `_normalizeManualReadingDraft` and `_normalizeMetricReadingValues` pass the metric's `labTestKey`, the draft's `lab` and the local anchor to the domain normaliser (the local anchor replaces `atTime` when set); `_NormalizedMetricReadingValues.scalarValue` and its unwrap become nullable. **Reads:** `watchMetricSummaries` leaves out Metrics with a `labTestKey`; `EffectRepository.samplesFor`, for a Lab Metric, reads the readings of every Metric with its key, ignoring every Lab Metric's own `deletedAt`, and applies `collapseLabResults` before windowing. **Wiring:** `part 'lab_results_repository.dart';` and a `late final LabResultsRepository labResults = LabResultsRepository._(this)` field on `TrainingRepositories`. |
| `apps/mobile/lib/data/repositories/lab_results_repository.dart` | Create | A `part` of `training_repositories.dart`, so it uses the private helpers above. **Reads** (both ignore Lab Metric `deletedAt`, join by key and collapse): `Stream<List<LabTestSummary>> watchLabTests()`, where `LabTestSummary` is `{labTestKey, LabTest? labTest (null for "Other"), name, unit, panel (null for "Other"), latest: LabResultRecord, resultCount}`, in catalogue order with "Other" last; `Stream<List<LabResultRecord>> watchLabResults(String labTestKey)`, where `LabResultRecord` is `{readingId, metricId, labTestKey, entered, enteredUnit, scalarValue (nullable), lab: LabFields, atTime, updatedAt, identityRowCount}`. **Writes:** `Future<String> saveCollection(CollectionDraft draft, {required DateTime today})` returns the Batch id. It runs the reading rules and `lab_result_repeated` first and throws `LabResultValidationException(issuesByRow)` on any hard reject, before opening a transaction; `lab_result_replaces` is computed by `previewCollection(CollectionDraft)` for the sheet's dialog. It then opens one `WriteContext` (one transaction, one Activity Log Batch), finds or creates each Lab Metric (as in [Finding the Lab Metric](#finding-the-lab-metric-for-a-lab-test), creating through `_createMetric` under the same context), and inserts each Reading through `_insertMetricReading` with source `labEntry`, `localDateTime` from `collected` and the device's offset at that local time. `Future<String> archiveResult(String readingId)` archives every live row with the same identity through a private archive helper that shares one `WriteContext`, and returns the Batch id. |
| `apps/mobile/lib/data/repositories/portable_archive_repository.dart` | Modify | The Metric entity's `upsert` applies the write-once rule in [Storage](#storage): it reads the stored row's `labTestKey` first and, when it is non-null, writes the restored row with the stored key; a null stored key takes the restored row's key. A schema-67 archive's Metric rows have no `labTestKey` and decode as null. |
| `apps/mobile/lib/features/labs/controllers/lab_results_providers.dart` | Create | `labResultsRepositoryProvider` (returns `ref.watch(trainingRepositoriesProvider).labResults`), declared like `metricRepositoryProvider` in `features/metrics/controllers/metrics_controller.dart`; `labTestsProvider` (`StreamProvider` over `watchLabTests()`) and `labResultsProvider` (`StreamProvider.family` over `watchLabResults(key)`). |
| `apps/mobile/test/data/lab_results_repository_test.dart` | Create | In-memory SQLite: one Batch per save, including created Lab Metrics; undo archives the Readings and the created Lab Metrics, and a later save reuses or creates a live one; a hard reject writes nothing; `lab_result_repeated` and `lab_result_replaces`; reuse of a live Lab Metric by key; interim then final shows the final; two Lab Metrics with one key read as one series; an archived Lab Metric's results still read; a Limit Result stored with null `scalarValue` and `entered` `"< 1"`; a date-only collection anchored at `T12:00:00`; archiving a result archives its whole identity group and reports its row count; a smoke test of the three providers in `lab_results_providers.dart`. |
| `apps/mobile/test/data/portable_archive_repository_test.dart` | Modify | The archive's Metric rows include `labTestKey`. Restore an archive whose Lab Metric has another id but the same key: results read as one series, and overlapping results collapse. A restored row never changes a stored non-null key. A v67 archive (no `labTestKey`) restores. |
| `apps/mobile/test/data/effect_repository_test.dart` | Modify | Effect samples for a Lab Metric join by key (across two Lab Metrics, one archived), collapse interim and final (a final outside the window still hides its interim inside it), and skip Limit Results; a custom Metric with the Lab Test's name is not joined. |
| `apps/mobile/test/data/schema_snapshot_migration_test.dart` | Modify | v67 to v68 keeps every row; `labTestKey` is null. |
| `apps/mobile/test/features/metrics/metrics_controller_test.dart` | Modify | Lab Metrics are absent from the explorer. |
| `apps/mobile/test/features/sync/sync_lab_metrics_test.dart` | Create | Push carries `lab_test_key`; a pull without the key, with null, or with another key keeps the stored value; a pull with a key fills a null stored key. |
| `apps/server/test/metrics-push-sync.test.mjs` | Modify | `lab_test_key` round-trips; a push without it, with null, or with another key keeps the stored value; no fold happens for lab keys. |
| `apps/server/test/sync-convergence.test.mjs` | Modify | Two devices save the same collection offline, then sync: each device reads one collapsed result per identity. |
| `apps/server/test/metric-migration.test.mjs` | Modify | 0038 adds a nullable column and an index, and contains no `DROP`, `DELETE` or `UPDATE`. |
| `apps/server/test/observability.test.mjs` | Modify | A lab sync push, scrubbed: a known lab number and Lab Test name are absent from the output. |
| `CHANGELOG.md` | Modify | `Changed`: Metric sync carries an optional `lab_test_key`. |

### PR 4: Agent surface

Covers V9, and V10 for Agent requests.

| File | Change | Detail |
|---|---|---|
| `apps/server/src/agent-lab-tests.ts` | Create | `listAgentLabTests` handler and the `AgentLabTest`/`AgentLabTestList` schemas, served from the generated catalogue. |
| `apps/server/src/app.ts` | Modify | Mount `GET /agent/lab-tests` with `app.openapi`, behind the same Agent bearer authentication and rate limit as the other Agent reads. |
| `apps/server/src/index.ts` | Modify | Export `listAgentLabTests`. |
| `apps/server/src/metric-identity.ts` | Modify | `findLabMetric(db, {userId, labTestKey})` (live, lowest sort order, then id); `labMetricIds(db, {userId, labTestKey})` (every row with the key, archived included); `stableMetricId` moved here from `agent-metrics.ts` and exported, so both modules use one copy. |
| `apps/server/src/agent-metrics.ts` | Modify | **Schema:** `AgentMetricBatchWriteReadingSchema` makes `metricId` optional and adds optional `labTestKey`; the scalar value gains the permissive `lab` schema. **Write:** request rules and reading rules run before normalisation, in [Validation](#validation)'s order, each issue keeping its code; the Lab Metric controls and server-set fields in [Agent surface](#agent-surface); find or create the Lab Metric as in [Finding the Lab Metric](#finding-the-lab-metric-for-a-lab-test), adding it to `preparedMetrics`; `lab_result_replaces` computed against the user's stored rows for the identity. **Reads:** `listAgentMetrics` sets `canonicalKey` to the `labTestKey` for Lab Metrics; `metricMatchesMetricKey` matches a catalogue key only against `lab_test_key`; `listAgentMetricReadings` expands, collapses and pages as in [Agent surface](#agent-surface), never returns archived lab rows and never adds `trendValue`. |
| `apps/server/src/agent-protocols.ts` | Modify | `resolveMetric` gains a Lab Metric branch: a catalogue key resolves through `labMetricIds`, never by name. `readAgentEffectWindow` reads the samples of those ids, collapses the whole series, then windows. |
| `apps/server/src/agent-mcp.ts` | Modify | `agent_list_lab_tests` tool; `agent_batch_write_metrics` and `agent_list_metric_readings` descriptions mention `labTestKey`, `lab`, the collapse and the Trend exclusion. |
| `packages/contract/src/agent-skill-reference.ts` | Modify | `listAgentLabTests: "list-lab-tests"` in `AGENT_SKILL_COMMAND_NAMES` and `listAgentLabTests: "agent_list_lab_tests"` in `AGENT_MCP_TOOL_NAMES`. |
| `agent-skills/perennia/scripts/prn-agent.mjs` | Modify | The `list-lab-tests` command. |
| `agent-skills/perennia/scripts/prn-code.mjs` | Modify | The `listAgentLabTests` method. |
| `agent-skills/perennia/SKILL.md` | Modify | A "Logging lab results" section (prose, not a command), and `list-lab-tests` in the common reads: call `agent_list_lab_tests` (CLI `list-lab-tests`); write with `agent_batch_write_metrics` (CLI `log-metrics`) by `labTestKey`, never `metricId` and never a Lab Metric in `metrics[]`, with `lab.collected` and a matching `timeAnchor`; use only listed unit spellings and never convert; send limits as `< 1`; to correct a value, write the same collection as `final`; Agents cannot overwrite, archive or backdate a stored result, and an unknown key or unit rejects the batch; never include the patient's name, date of birth, address or accession number. |
| `agent-skills/perennia/references/api-operations.md` | Regenerate | `pnpm run generate:agent-skill-reference` in `packages/contract`. |
| `packages/contract/openapi.json` | Regenerate | `pnpm run generate` in `packages/contract` (also regenerates the two clients and the skill reference). The contract diff in [Agent surface](#agent-surface). |
| `packages/contract/src/agent-client.ts` | Regenerate | Generated client. |
| `apps/mobile/lib/api/perennia_api_client.dart` | Regenerate (no diff expected) | Regenerated by `pnpm run generate`. `packages/contract/scripts/generate-dart-client.ts` emits only the operations it names, and this spec adds none, so the file must not change; a diff is reviewed as a contract change. |
| `apps/server/test/agent-metrics.test.mjs` | Modify | Write by key creates then reuses one Lab Metric, with the fields in [Finding the Lab Metric](#finding-the-lab-metric-for-a-lab-test), an Activity Log entry and a `metrics[]` outcome; an archived stable-id row is unarchived; a live stable-id row with no key gets the key; replay writes nothing and returns the stored response; each request rule's code, including `lab_result_exists`, `lab_archive_not_allowed` and the `lab_result_replaces` warning; a rejected reading rejects the batch; sent `updatedAt`, `provenance`, `source` and `limit` are overwritten; a malformed `lab` field gets its lab code, not a schema error; read collapses across two Lab Metrics with one key, pages with the cursor over the collapsed list and omits `trendValue` with `includeTrend=true`; a catalogue `metricKey` finds Lab Metrics and not a custom Metric with the Lab Test's name; two concurrent first writes create one Metric. |
| `apps/server/test/agent-protocols.test.mjs` | Modify | The Agent Effect window collapses Lab Metric samples by key before windowing, and ignores a custom Metric with the Lab Test's name. |
| `apps/server/test/agent-lab-tests.test.mjs` | Create | The read returns every catalogue entry with its fields, and requires an Agent key. |
| `apps/server/test/agent-mcp.test.mjs` | Modify | The tool list includes `agent_list_lab_tests`. |
| `apps/server/test/observability.test.mjs` | Modify | A full lab batch-write request, response and validation failure, scrubbed: a known lab number and Lab Test name are absent from the output. |
| `CHANGELOG.md` | Modify | `Added`: Agents can list Lab Tests and write lab results by Lab Test. |

### PR 5: The Lab Results screens

Covers V11 and V12. Sets this spec's Status and its SITEMAP row to **Current** for phase 1; the
Overview keeps saying phase 2 is designed later.

| File | Change | Detail |
|---|---|---|
| `apps/mobile/lib/features/labs/controllers/lab_results_controller.dart` | Create | The Lab Results screen's state from `labTestsProvider`, plus the Progress row's count. |
| `apps/mobile/lib/features/labs/controllers/lab_test_detail_controller.dart` | Create | Collapsed results for one Lab Test from `labResultsProvider(key)`, each with its parsed Printed Range, Default Range and position, using `UserProfileRepository.watch()`; "Other" Lab Tests parse ranges as `reference` and get no Default Range. |
| `apps/mobile/lib/features/labs/controllers/lab_entry_controller.dart` | Create | The `CollectionDraft` state, per-row reading rules through the shared module, `previewCollection` for the warning dialog, Save through `saveCollection`, mapping `LabResultValidationException` back onto rows. |
| `apps/mobile/lib/features/labs/widgets/lab_results_screen.dart` | Create | `LabResultsScreen` (`routeName` `/labs`) inside `ProtocolsLockGate`: the Disclosure line (reusing `ProfileDisclosureLine`, whose copy is the same), profile line, recognised-count link, **Add results**, panels, "Other", empty state. |
| `apps/mobile/lib/features/labs/widgets/lab_test_detail_screen.dart` | Create | `LabTestDetailScreen` (`routeName` `/labs/test`, the Lab Test key as the route argument) inside `ProtocolsLockGate`: the dated list, and archive with its row-count confirmation under `ProtocolsLockSheetGuard`. |
| `apps/mobile/lib/features/labs/widgets/lab_result_row.dart` | Create | One row, as in [The display](#the-display). |
| `apps/mobile/lib/features/labs/widgets/lab_entry_sheet.dart` | Create | The entry sheet and its warning dialog (every soft warning in one list), each under `ProtocolsLockSheetGuard`; the Disclosure line at the top. |
| `apps/mobile/lib/features/labs/widgets/lab_test_picker.dart` | Create | DESIGN.md's Picker sheet, single-select, over catalogue Lab Tests grouped by panel, with case-insensitive substring search over names and variants; a read-only mode for the recognised-tests list; under `ProtocolsLockSheetGuard`. |
| `apps/mobile/lib/features/progress/widgets/progress_overview.dart` | Modify | The **Lab results** row after the Health metrics row: subtitle "{N} lab tests" or "No results yet" while unlocked; only a lock icon while locked. |
| `apps/mobile/lib/app.dart` | Modify | `LabResultsScreen.routeName` in `routes`; `LabTestDetailScreen.routeName` in `onGenerateRoute`, reading the Lab Test key from `settings.arguments` as `WorkoutTemplateEditorScreen` does. |
| `apps/mobile/lib/l10n/app_en.arb` and generated `apps/mobile/lib/l10n/app_localizations*.dart` | Modify | All new copy. |
| `apps/mobile/test/features/labs/lab_results_screen_test.dart` | Create | Panels in catalogue order, latest result, "Other" opens and archives, empty state, lock. |
| `apps/mobile/test/features/labs/lab_test_detail_screen_test.dart` | Create | Comparator always shown; date-only shows no time; Printed Range beats Default Range; position sentences; `riskTarget` shows "Target" and no position; the Creatinine Default Range appears only once sex and birth year are set; archive confirmation states the row count. |
| `apps/mobile/test/features/labs/lab_entry_sheet_test.dart` | Create | Hard reject on its row; every soft warning listed in one confirmation, including `lab_result_replaces`; unit is a fixed label; the comparator builds `entered` as `"<= 1"`; picker search matches a variant; the same Lab Test twice is rejected; one Batch saved; nothing saved if the app is killed before Save; the sheet closes and its rows are discarded when the app locks. |
| `apps/mobile/test/features/labs/lab_accessibility_test.dart` | Create | 48 dp targets, semantics labels for the flag, position and Interim, 200% text scale, contrast in both themes. |
| `apps/mobile/test/features/progress/progress_overview_test.dart` | Modify | The Lab results row and its count subtitle, and no Lab Test names, counts or values while locked. |
| `apps/mobile/test/app_shell_test.dart` | Modify | Progress tile assertions include the new row. |
| `AGENTS.md`, `DESIGN.md`, `docs/designs/progress-overview.md` | Modify | The doc changes in [Repository doc changes](#repository-doc-changes). |
| `docs/designs/lab-results.md`, `docs/designs/SITEMAP.md` | Modify | Status **Current** (phase 1); correct any number that changed. |
| `CHANGELOG.md` | Modify | `Added`: Lab results: enter a collection, see each Lab Test over time with its printed and general ranges. |

### Verification Plan

The gate per pull request is `node tools/ci-local.mjs --changed`. Across the plan, the `mobile`,
`golden`, `contract`, `js` and `sync` jobs must pass (the last two need Docker); PR 2's `ci.yml`
change also runs `workflow_lint`.

*   **V0 m12 defects (PR 1).** The new m12 reject cases and the `"1e3"` case pass in Dart
    (`mobile`) and TypeScript (`golden`).
*   **V1 Catalogue.** `lab-test-catalogue.test.mjs` (`js`): one rejection per generator rule, the
    PRN collision rule, and the real file accepted. `generate-lab-test-catalogue.mjs --check`
    (`contract`) passes.
*   **V2 Validation parity.** m42 passes in Dart (`mobile`) and TypeScript (`golden`).
*   **V3 Collapse and ranges.** m43 passes in Dart and TypeScript; m44 passes in Dart.
*   **V4 Normaliser.** The new m12 lab cases pass in both languages.
*   **V5 Repository.** `lab_results_repository_test.dart` (`mobile`).
*   **V6 Migration.** `schema_snapshot_migration_test.dart` (`mobile`) and
    `metric-migration.test.mjs` (`js`).
*   **V7 Merge-only restore.** `portable_archive_repository_test.dart` (`mobile`): an overlapping
    restore reads as one series and collapses; a stored key is never changed; a v67 archive
    restores.
*   **V8 Sync simulation.** `sync-convergence.test.mjs`, `metrics-push-sync.test.mjs` (`sync`,
    `js`) and `sync_lab_metrics_test.dart` (`mobile`): two devices, one collection, offline then
    synced, read the same collapsed results; `lab_test_key` is write-once on both sides.
*   **V9 Agent write and read.** `agent-metrics.test.mjs`, `agent-protocols.test.mjs`,
    `agent-lab-tests.test.mjs`, `agent-mcp.test.mjs` (`js`). The `contract` job checks that the
    generated files are current; a reviewer checks that the `openapi.json` diff holds only the
    additions in [Agent surface](#agent-surface) and that the Dart client did not change.
*   **V10 Scrubbing.** `observability.test.mjs` (`js`), in PR 3 for a sync push and in PR 4 for
    Agent requests, responses and validation failures: a known lab number and Lab Test name from
    the request are absent from the scrubbed output.
*   **V11 Screens.** The four `features/labs` tests (`mobile`).
*   **V12 Lock and accessibility.** `progress_overview_test.dart`, `lab_results_screen_test.dart`,
    `lab_entry_sheet_test.dart` and `lab_accessibility_test.dart` (`mobile`): no Lab Test name,
    count or value in Progress or any lab screen while locked; targets, semantics, text scale and
    contrast in both themes.
