import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  emit,
  validateCatalogue
} from "../../../tools/generate-lab-test-catalogue.mjs";
import {
  normalizeMetricLookupKey,
  PRN_METRIC_SCHEMAS
} from "../src/metric-catalog.ts";

const repoRoot = new URL("../../../", import.meta.url);

function readRepoFile(path) {
  return readFileSync(new URL(path, repoRoot), "utf8");
}

const realCatalogue = JSON.parse(
  readRepoFile("packages/lab-catalogue/lab-tests.json")
);

const SOURCE = {
  title: "A source",
  url: "https://example.org/source",
  version: "2014"
};

function entry(overrides = {}) {
  return {
    key: "sodium",
    name: "Sodium",
    panel: "Electrolytes",
    variants: ["na"],
    unit: "mmol/L",
    unitAliases: ["mmol/l"],
    hardBounds: { min: 0, max: 1000 },
    ...overrides
  };
}

function range(overrides = {}) {
  return {
    sex: "any",
    ageMin: 18,
    ageMax: null,
    low: 135,
    high: 145,
    source: SOURCE,
    ...overrides
  };
}

function catalogue(...entries) {
  return { labTests: entries };
}

function assertRule(json, rule) {
  assert.throws(
    () => validateCatalogue(json),
    (error) => {
      assert.ok(error instanceof Error);
      assert.match(error.message, new RegExp(`rule "${rule}" failed`));
      return true;
    }
  );
}

test("the real catalogue passes every generator rule", () => {
  assert.doesNotThrow(() => validateCatalogue(realCatalogue));
});

test("a minimal valid fixture passes, so each rejection below is its own rule", () => {
  assert.doesNotThrow(() =>
    validateCatalogue(
      catalogue(
        entry({ defaultRanges: [range()], plausibleBounds: { min: 27, max: 725 } })
      )
    )
  );
});

const REJECTIONS = [
  ["top-level", "a bare array", []],
  ["top-level", "an extra top-level key", { labTests: [], version: 1 }],
  ["top-level", "labTests not an array", { labTests: {} }],
  [
    "required-field",
    "a missing hardBounds",
    catalogue(
      (() => {
        const value = entry();
        delete value.hardBounds;
        return value;
      })()
    )
  ],
  ["field-type", "a numeric name", catalogue(entry({ name: 7 }))],
  ["field-type", "variants not an array", catalogue(entry({ variants: "na" }))],
  ["non-empty-string", "a blank panel", catalogue(entry({ panel: "   " }))],
  ["non-empty-string", "a blank alias", catalogue(entry({ unitAliases: [" "] }))],
  [
    "unknown-key",
    "an unknown entry key",
    catalogue(entry({ conversionFactor: 88.4 }))
  ],
  [
    "unknown-key",
    "an unknown bounds key",
    catalogue(entry({ hardBounds: { min: 0, max: 1000, step: 1 } }))
  ],
  [
    "unknown-key",
    "an unknown range key",
    catalogue(entry({ defaultRanges: [range({ factor: 2 })] }))
  ],
  [
    "unknown-key",
    "an unknown source key",
    catalogue(
      entry({ defaultRanges: [range({ source: { ...SOURCE, page: 3 } })] })
    )
  ],
  ["key-format", "an upper-case key", catalogue(entry({ key: "Sodium" }))],
  ["key-format", "a key starting with a digit", catalogue(entry({ key: "1sodium" }))],
  [
    "key-unique",
    "a repeated key",
    catalogue(entry(), entry({ name: "Sodium again", variants: ["na2"] }))
  ],
  [
    "unit-spellings-distinct",
    "an alias equal to the unit after the fold",
    catalogue(entry({ unitAliases: ["mmol / L"] }))
  ],
  [
    "variant-format",
    "an upper-case variant",
    catalogue(entry({ variants: ["Na"] }))
  ],
  [
    "variant-format",
    "a double-spaced variant",
    catalogue(entry({ variants: ["serum  sodium"] }))
  ],
  [
    "variant-unique",
    "a variant shared by two Lab Tests",
    catalogue(
      entry(),
      entry({ key: "potassium", name: "Potassium", variants: ["na"] })
    )
  ],
  [
    "bounds",
    "hardBounds min above max",
    catalogue(entry({ hardBounds: { min: 10, max: 1 } }))
  ],
  [
    "bounds",
    "a non-numeric bound",
    catalogue(entry({ hardBounds: { min: "0", max: 1000 } }))
  ],
  [
    "plausible-within-hard",
    "plausibleBounds past hardBounds",
    catalogue(entry({ plausibleBounds: { min: 0, max: 2000 } }))
  ],
  [
    "printed-range-kind",
    "an unknown printedRangeKind",
    catalogue(entry({ printedRangeKind: "target" }))
  ],
  [
    "risk-target-no-default-ranges",
    "a riskTarget Lab Test with defaultRanges",
    catalogue(entry({ printedRangeKind: "riskTarget", defaultRanges: [range()] }))
  ],
  [
    "default-range-sex",
    "an unknown sex",
    catalogue(entry({ defaultRanges: [range({ sex: "other" })] }))
  ],
  [
    "default-range-limits",
    "neither low nor high",
    catalogue(entry({ defaultRanges: [range({ low: null, high: null })] }))
  ],
  [
    "default-range-limits",
    "low above high",
    catalogue(entry({ defaultRanges: [range({ low: 150, high: 140 })] }))
  ],
  [
    "default-range-age",
    "a fractional age",
    catalogue(entry({ defaultRanges: [range({ ageMin: 18.5 })] }))
  ],
  [
    "default-range-age",
    "ageMin above ageMax",
    catalogue(entry({ defaultRanges: [range({ ageMin: 60, ageMax: 18 })] }))
  ],
  [
    "default-range-source",
    "an empty source url",
    catalogue(
      entry({ defaultRanges: [range({ source: { ...SOURCE, url: "" } })] })
    )
  ],
  [
    "default-range-overlap",
    "two entries for one sex with overlapping ages",
    catalogue(
      entry({
        defaultRanges: [
          range({ sex: "male", ageMin: 18, ageMax: 59 }),
          range({ sex: "male", ageMin: 59, ageMax: null })
        ]
      })
    )
  ],
  [
    "default-range-overlap",
    "an any entry overlapping a sex-specific one",
    catalogue(
      entry({
        defaultRanges: [range({ sex: "any" }), range({ sex: "female" })]
      })
    )
  ],
  [
    "default-range-overlap",
    "an unbounded age overlapping a bounded one",
    catalogue(
      entry({
        defaultRanges: [
          range({ sex: "female", ageMin: null, ageMax: null }),
          range({ sex: "female", ageMin: 18, ageMax: 59 })
        ]
      })
    )
  ]
];

for (const [rule, description, json] of REJECTIONS) {
  test(`rejects ${description} (${rule})`, () => assertRule(json, rule));
}

test("ranges for different sexes, or for adjacent age bands, do not overlap", () => {
  assert.doesNotThrow(() =>
    validateCatalogue(
      catalogue(
        entry({
          defaultRanges: [
            range({ sex: "female", ageMin: 18, ageMax: 59 }),
            range({ sex: "male", ageMin: 18, ageMax: 59 }),
            range({ sex: "male", ageMin: 60, ageMax: null })
          ]
        })
      )
    )
  );
});

test("no Lab Test key or name collides with a PRN Metric", () => {
  const prnLookupKeys = new Map();
  for (const schema of PRN_METRIC_SCHEMAS) {
    for (const spelling of [
      schema.canonicalKey,
      schema.displayName,
      ...(schema.aliases ?? [])
    ]) {
      prnLookupKeys.set(normalizeMetricLookupKey(spelling), schema.canonicalKey);
    }
  }
  for (const labTest of realCatalogue.labTests) {
    for (const spelling of [labTest.key, labTest.name]) {
      const prn = prnLookupKeys.get(normalizeMetricLookupKey(spelling));
      assert.equal(
        prn,
        undefined,
        `Lab Test ${labTest.key} ("${spelling}") collides with PRN Metric ${prn}`
      );
    }
  }
});

test("the committed generated files match the generator's output byte for byte", () => {
  const { dart, ts } = emit(realCatalogue);
  assert.equal(
    readRepoFile("apps/mobile/lib/domain/labs/lab_test_catalogue.generated.dart"),
    dart,
    "Dart catalogue is stale: run node tools/generate-lab-test-catalogue.mjs"
  );
  assert.equal(
    readRepoFile("apps/server/src/data/lab-test-catalogue.generated.ts"),
    ts,
    "TypeScript catalogue is stale: run node tools/generate-lab-test-catalogue.mjs"
  );
});

test("the generated server catalogue resolves each folded spelling to the canonical unit", async () => {
  const { LAB_TEST_CATALOGUE, labTestByKey } = await import(
    "../src/data/lab-test-catalogue.generated.ts"
  );
  assert.equal(LAB_TEST_CATALOGUE.length, realCatalogue.labTests.length);
  assert.equal(labTestByKey("unknown_lab_test"), null);
  const creatinine = labTestByKey("creatinine");
  assert.equal(creatinine.unit, "umol/L");
  assert.equal(creatinine.foldedUnits["µmol/l"], "umol/L");
  assert.equal(labTestByKey("wcc").foldedUnits["10^9/L"], "x10^9/L");
});
