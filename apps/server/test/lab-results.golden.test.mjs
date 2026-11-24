import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import {
  collapseLabResults,
  collectedLocalDateTime,
  decodeLab,
  encodeLab,
  formatEntered,
  isValidCollected,
  parseEntered
} from "../src/index.ts";

// Moves with the vector file's `schemaVersion` and its schema's constant, and
// with the app runner's labResultCollapseGoldenSchemaVersion
// (apps/mobile/test/domain/lab_result_collapse_test.dart): an incompatible
// case-shape change bumps all of them together.
const LAB_RESULT_COLLAPSE_GOLDEN_SCHEMA_VERSION = 1;

// The app runs the same file, so the Lab Results screen and an Agent's reads
// keep the same row of every Lab Result.
test("collapseLabResults matches the shared M43 golden vectors", async () => {
  const vector = JSON.parse(
    await readFile(
      new URL("../../../packages/golden-vectors/vectors/m43-lab-result-collapse.json", import.meta.url),
      "utf8"
    )
  );

  assert.equal(vector.name, "m43-lab-result-collapse");
  assert.equal(vector.domain, "lab-result-collapse");
  assert.equal(vector.schemaVersion, LAB_RESULT_COLLAPSE_GOLDEN_SCHEMA_VERSION);
  assert.equal(vector.schema, "m43-lab-result-collapse.schema.json");
  assert.ok(vector.cases.length > 0);

  for (const vectorCase of vector.cases) {
    const kept = collapseLabResults(vectorCase.input.readings);
    assert.deepEqual(
      kept.map((reading) => reading.id),
      vectorCase.expected.keptIds,
      vectorCase.name
    );
  }
});

test("encodeLab writes every key in the canonical order, nulls included", () => {
  const encoded = encodeLab({ collected: "2026-03-04" });
  assert.deepEqual(Object.keys(encoded), [
    "collected",
    "limit",
    "printedRange",
    "printedFlag",
    "reportStatus",
    "fasting",
    "labName"
  ]);
  assert.deepEqual(encoded, {
    collected: "2026-03-04",
    limit: null,
    printedRange: null,
    printedFlag: null,
    reportStatus: "final",
    fasting: null,
    labName: null
  });
  assert.equal(
    JSON.stringify(
      encodeLab({
        labName: "Example Pathology",
        fasting: true,
        reportStatus: "interim",
        printedFlag: "L",
        printedRange: "< 5",
        limit: { comparator: "<", bound: 1 },
        collected: "2026-03-04T08:15"
      })
    ),
    '{"collected":"2026-03-04T08:15","limit":{"comparator":"<","bound":1},' +
      '"printedRange":"< 5","printedFlag":"L","reportStatus":"interim",' +
      '"fasting":true,"labName":"Example Pathology"}'
  );
});

test("decodeLab applies the defaults and drops unknown keys", () => {
  assert.deepEqual(decodeLab({ collected: "2026-03-04", accession: "A1" }), {
    collected: "2026-03-04",
    limit: null,
    printedRange: null,
    printedFlag: null,
    reportStatus: "final",
    fasting: null,
    labName: null
  });
  assert.equal(decodeLab({ collected: "2026-03-04", reportStatus: "corrected" }).reportStatus, "corrected");
  assert.equal(decodeLab({ collected: "2026-03-04", reportStatus: null }).reportStatus, "final");
  assert.equal(decodeLab({ collected: "2026-03-04", fasting: false }).fasting, null);
  assert.equal(decodeLab({ collected: "2026-03-04", limit: { comparator: "=", bound: 1 } }).limit, null);
  assert.deepEqual(decodeLab({ collected: "2026-03-04", limit: { comparator: ">=", bound: 2.5 } }).limit, {
    comparator: ">=",
    bound: 2.5
  });
  const roundTrip = encodeLab({ collected: "2026-03-04T08:15", printedFlag: "H" });
  assert.deepEqual(decodeLab(roundTrip), roundTrip);

  for (const invalid of [null, "2026-03-04", [], {}, { collected: "2026-02-30" }, { collected: "2026-03-04T24:00" }, { collected: "2026-03-04 08:15" }]) {
    assert.equal(decodeLab(invalid), null, JSON.stringify(invalid));
  }
});

test("isValidCollected and collectedLocalDateTime", () => {
  for (const valid of ["2026-03-04", "2026-03-04T00:00", "2026-03-04T23:59", "2024-02-29"]) {
    assert.equal(isValidCollected(valid), true, valid);
  }
  for (const invalid of ["2026-3-04", "2025-02-29", "2026-13-01", "2026-04-31", "2026-03-04T08:60", "2026-03-04T08:15:00", "2026-03-04Z", ""]) {
    assert.equal(isValidCollected(invalid), false, invalid);
  }
  assert.equal(collectedLocalDateTime("2026-03-04"), "2026-03-04T12:00:00");
  assert.equal(collectedLocalDateTime("2026-03-04T08:15"), "2026-03-04T08:15:00");
  assert.throws(() => collectedLocalDateTime("2026-02-30"), RangeError);
});

test("parseEntered and formatEntered agree on the canonical entered form", () => {
  assert.deepEqual(parseEntered("20.0"), { comparator: null, number: "20.0" });
  assert.deepEqual(parseEntered("< 1"), { comparator: "<", number: "1" });
  assert.deepEqual(parseEntered("<1"), { comparator: "<", number: "1" });
  assert.deepEqual(parseEntered("<= 0.5"), { comparator: "<=", number: "0.5" });
  assert.deepEqual(parseEntered("≤0.5"), { comparator: "<=", number: "0.5" });
  assert.deepEqual(parseEntered("> 90"), { comparator: ">", number: "90" });
  assert.deepEqual(parseEntered(">=90"), { comparator: ">=", number: "90" });
  assert.deepEqual(parseEntered("≥ 90"), { comparator: ">=", number: "90" });
  assert.deepEqual(parseEntered("1e3"), { comparator: null, number: "1e3" });
  for (const invalid of ["", "<", "<  1", "< x", "1.7 x10^9", "=1", "1e999", "NaN", " 1", "1 "]) {
    assert.equal(parseEntered(invalid), null, invalid);
  }

  assert.equal(formatEntered(null, "20.0"), "20.0");
  assert.equal(formatEntered("<", "1"), "< 1");
  assert.equal(formatEntered(">=", "90"), ">= 90");
  const parsed = parseEntered("≤0.5");
  assert.equal(formatEntered(parsed.comparator, parsed.number), "<= 0.5");
});
