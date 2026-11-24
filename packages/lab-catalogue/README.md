# Lab Test catalogue

The list of blood tests Perennia knows how to file, in one JSON file:
[`lab-tests.json`](lab-tests.json). The app and the server both read it, through generated
code, so the entry sheet, the validation rules and the Agent surface always agree on which
Lab Tests exist and which units each accepts.

The design is in [docs/designs/lab-results.md](../../docs/designs/lab-results.md) ("The Lab
Test catalogue" and "Default Ranges"); the terms are in [CONTEXT.md](../../CONTEXT.md).

## What a Lab Test is

A **Lab Test** is one thing a pathology lab measures and prints on a report, in one unit:
Testosterone in `nmol/L`, Creatinine in `umol/L`. A user's results for a Lab Test are stored
as a Lab Metric, which names the Lab Test only by its `key`. Where labs report the same
quantity in different units, each form is its own Lab Test (`neutrophils_percent` and
`neutrophils_count`). The catalogue holds no conversion factors, ever.

Each entry:

| Field | Required | Meaning |
|---|---|---|
| `key` | yes | Stable id, lower snake case (`testosterone_total`). |
| `name` | yes | Display name ("Testosterone"). |
| `panel` | yes | Display grouping ("Sex hormones"). Never stored on a result. |
| `variants` | yes | Other names labs print, lower case with single spaces (`alk phos`). Used by search. |
| `unit` | yes | The canonical unit. A fraction uses `L/L`; a ratio uses `ratio`. |
| `unitAliases` | no | Other spellings of the same unit (`µmol/L`). |
| `hardBounds` | yes | `{min, max}` in `unit`, inclusive. Outside is rejected. |
| `plausibleBounds` | no | `{min, max}` in `unit`, inclusive. Outside asks the user to check. Never shown as a range. |
| `printedRangeKind` | no | `reference` (the default) or `riskTarget` (the lipids, whose printed ranges are guideline targets). |
| `defaultRanges` | no | General reference intervals, shown only when a result has no printed range. |

Unit spellings are compared after one fold: every whitespace character is removed and case
is kept. So `x10^9 /L` already matches `x10^9/L`, but `nmol/l` matches `nmol/L` only because
the entry lists `nmol/l`. List the lower-case `l` form of every unit that ends in `/L`, and
never list two spellings that differ only by whitespace (the generator rejects them).

## Adding a Lab Test

A new Lab Test needs no design spec. Open a pull request that:

1. Adds the entry to `lab-tests.json` in its panel, in display order.
2. Picks a `key` that is new, lower snake case, and not a key or name of a tracker Metric
   (the server test checks this).
3. Lists the common report spellings as `variants`, none already used by another Lab Test.
4. Lists every unit spelling labs print as `unitAliases`, following the fold rule above.
5. Sets `hardBounds` by the bounds rule below, and `plausibleBounds` only when it adds
   Default Ranges.
6. Adds `defaultRanges` only when copied from a source by the Default Range rule below.
7. Regenerates the code and commits the JSON with both generated files.
8. Runs `pnpm ci:local --changed` until it is green.

## What never changes

Released entries are referenced by stored results on users' phones and servers, so:

- A `key`, a `name` and a `unit` never change once released. A key is never renamed, reused
  or removed.
- `unitAliases` and `variants` are only added to, never removed or edited.
- Bounds are only widened, never narrowed: a narrower bound would reject a result that was
  accepted before.

## The bounds rule

`hardBounds` catches impossible values. Its `min` is 0, and its `max` is set by unit:

| Unit | `max` |
|---|---|
| `%`, `ratio` | 100 |
| `L/L` | 1 |
| `mmol/L`, `g/L`, `fL`, `pg`, `x10^9/L` | 1000 |
| `x10^12/L` | 100 |
| `mg/L`, `U/L`, `IU/L`, `mL/min/1.73m²` | 10 000 |
| `umol/L`, `nmol/L`, `ug/L`, `mIU/L` | 100 000 |
| `pmol/L` | 1 000 000 |

`plausibleBounds` is set only for a Lab Test with Default Ranges: from one fifth of its
lowest adult lower limit to five times its highest adult upper limit, across sexes, rounded
outwards to three significant figures. A missing lower limit gives `min` 0. It must lie
within `hardBounds`.

## The Default Range rule

Every Default Range is copied **verbatim** from **one cited source**, with its sex and age
bands as published, and carries that source as `{title, url, version}` (`version` is the
publication year). "Adult" is written as `ageMin` 18; an age the source does not cover gets
no Default Range. Two entries of one Lab Test may never match the same sex and age.

The seed's ranges come from the harmonised adult reference intervals for Australasia (AACB
and RCPA). Only chemistry is harmonised there, so the full blood count, hormones, hs-CRP and
lipids have none. Never transcribe a range you cannot read in the source itself.

## Regenerating

```bash
node tools/generate-lab-test-catalogue.mjs           # validate, then write both files
node tools/generate-lab-test-catalogue.mjs --check   # fail when either file is stale
```

The generator validates the file first and names the rule and entry it rejects. It writes
`apps/mobile/lib/domain/labs/lab_test_catalogue.generated.dart` and
`apps/server/src/data/lab-test-catalogue.generated.ts`. CI runs `--check` in the
contract-drift job, and `apps/server/test/lab-test-catalogue.test.mjs` tests the rules.
