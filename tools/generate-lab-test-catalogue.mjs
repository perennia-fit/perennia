#!/usr/bin/env node
// Generates the app's and the server's Lab Test catalogue from the one source
// contributors edit:
//   packages/lab-catalogue/lab-tests.json
//
// The catalogue is generated code rather than a Flutter asset because the
// Lab Result validation and the reading normaliser are synchronous domain
// code that cannot await an asset load, and the server image copies only
// apps/server (see Dockerfile). Both outputs are committed; `--check` fails
// the contract-drift gate when either is stale, as
// tools/generate-server-usda-food-seed.mjs does for the food seed.
//
// `validateCatalogue` enforces the generator rules in
// docs/designs/lab-results.md ("The Lab Test catalogue"). It is exported so
// apps/server/test/lab-test-catalogue.test.mjs can feed it one bad fixture per
// rule; the rule that needs the server's tracker catalogue (no Lab Test key or
// name may collide with a PRN Metric) lives in that test, because this script
// is plain JavaScript and cannot import TypeScript.
//
// The Dart output is written to be `dart format` clean (the short style, since
// the app's language version is 3.6) without running a formatter: single
// quotes, trailing commas on every split list and call, and no line over 80
// columns. The TypeScript output is JSON data under exported types.
//
// Usage: node tools/generate-lab-test-catalogue.mjs [--check]

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath, pathToFileURL } from "node:url";

const repoRoot = new URL("../", import.meta.url);
const sourceUrl = new URL("packages/lab-catalogue/lab-tests.json", repoRoot);
const dartUrl = new URL(
  "apps/mobile/lib/domain/labs/lab_test_catalogue.generated.dart",
  repoRoot
);
const tsUrl = new URL(
  "apps/server/src/data/lab-test-catalogue.generated.ts",
  repoRoot
);

const REGENERATE = "node tools/generate-lab-test-catalogue.mjs";

const ENTRY_KEYS = [
  "key",
  "name",
  "panel",
  "variants",
  "unit",
  "unitAliases",
  "hardBounds",
  "plausibleBounds",
  "printedRangeKind",
  "defaultRanges"
];
const BOUNDS_KEYS = ["min", "max"];
const RANGE_KEYS = ["sex", "ageMin", "ageMax", "low", "high", "source"];
const SOURCE_KEYS = ["title", "url", "version"];
const PRINTED_RANGE_KINDS = ["reference", "riskTarget"];
const SEXES = ["female", "male", "any"];
const KEY_PATTERN = /^[a-z][a-z0-9_]*$/;
// Lower case is checked separately; this is "single spaces": no leading,
// trailing or repeated space, and no whitespace other than a space.
const SINGLE_SPACED = /^[^\s]+( [^\s]+)*$/;

/**
 * The one unit fold every comparison uses (generator, normaliser, entry
 * sheet): remove every whitespace character and keep case. So `x10^9 /L`
 * matches `x10^9/L`, but `nmol/l` matches `nmol/L` only because the catalogue
 * lists it as an alias.
 */
export function foldUnit(unit) {
  return unit.replace(/\s/g, "");
}

function fail(rule, where, detail) {
  throw new Error(
    `Lab Test catalogue rule "${rule}" failed at ${where}: ${detail}`
  );
}

function isPlainObject(value) {
  return (
    value !== null &&
    typeof value === "object" &&
    !Array.isArray(value) &&
    Object.getPrototypeOf(value) === Object.prototype
  );
}

function isNullish(value) {
  return value === null || value === undefined;
}

function checkKnownKeys(object, allowed, where) {
  for (const key of Object.keys(object)) {
    if (!allowed.includes(key)) {
      fail("unknown-key", where, `"${key}" is not a catalogue field`);
    }
  }
}

function checkString(value, field, where) {
  if (typeof value !== "string") {
    fail("field-type", where, `${field} must be a string`);
  }
  if (value.trim() === "") {
    fail("non-empty-string", where, `${field} must be non-empty after trimming`);
  }
}

function checkStringArray(value, field, where) {
  if (!Array.isArray(value)) {
    fail("field-type", where, `${field} must be an array of strings`);
  }
  value.forEach((item, index) => checkString(item, `${field}[${index}]`, where));
}

function checkBounds(value, field, where) {
  if (!isPlainObject(value)) {
    fail("field-type", where, `${field} must be an object {min, max}`);
  }
  checkKnownKeys(value, BOUNDS_KEYS, `${where} ${field}`);
  for (const side of BOUNDS_KEYS) {
    if (typeof value[side] !== "number" || !Number.isFinite(value[side])) {
      fail("bounds", where, `${field}.${side} must be a finite number`);
    }
  }
  if (value.min > value.max) {
    fail("bounds", where, `${field}.min must be <= ${field}.max`);
  }
}

function checkOptionalNumber(value, field, where) {
  if (isNullish(value)) return;
  if (typeof value !== "number" || !Number.isFinite(value)) {
    fail("default-range-limits", where, `${field} must be a number or null`);
  }
}

function checkOptionalAge(value, field, where) {
  if (isNullish(value)) return;
  if (!Number.isInteger(value) || value < 0) {
    fail("default-range-age", where, `${field} must be a whole year or null`);
  }
}

function checkDefaultRange(range, where) {
  if (!isPlainObject(range)) {
    fail("field-type", where, "a defaultRanges entry must be an object");
  }
  checkKnownKeys(range, RANGE_KEYS, where);
  if (!SEXES.includes(range.sex)) {
    fail("default-range-sex", where, "sex must be female, male or any");
  }
  checkOptionalAge(range.ageMin, "ageMin", where);
  checkOptionalAge(range.ageMax, "ageMax", where);
  if (
    !isNullish(range.ageMin) &&
    !isNullish(range.ageMax) &&
    range.ageMin > range.ageMax
  ) {
    fail("default-range-age", where, "ageMin must be <= ageMax");
  }
  checkOptionalNumber(range.low, "low", where);
  checkOptionalNumber(range.high, "high", where);
  if (isNullish(range.low) && isNullish(range.high)) {
    fail("default-range-limits", where, "set at least one of low and high");
  }
  if (!isNullish(range.low) && !isNullish(range.high) && range.low > range.high) {
    fail("default-range-limits", where, "low must be <= high");
  }
  if (!isPlainObject(range.source)) {
    fail("default-range-source", where, "source must be {title, url, version}");
  }
  checkKnownKeys(range.source, SOURCE_KEYS, `${where} source`);
  for (const field of SOURCE_KEYS) {
    const value = range.source[field];
    if (typeof value !== "string" || value.trim() === "") {
      fail("default-range-source", where, `source.${field} must be non-empty`);
    }
  }
}

function sexesOverlap(a, b) {
  return a === "any" || b === "any" || a === b;
}

function agesOverlap(a, b) {
  const aMin = isNullish(a.ageMin) ? -Infinity : a.ageMin;
  const aMax = isNullish(a.ageMax) ? Infinity : a.ageMax;
  const bMin = isNullish(b.ageMin) ? -Infinity : b.ageMin;
  const bMax = isNullish(b.ageMax) ? Infinity : b.ageMax;
  return aMin <= bMax && bMin <= aMax;
}

/**
 * Throws an Error naming the rule and the entry when the catalogue breaks any
 * generator rule; returns the catalogue unchanged otherwise.
 */
export function validateCatalogue(json) {
  if (
    !isPlainObject(json) ||
    Object.keys(json).length !== 1 ||
    !Object.hasOwn(json, "labTests") ||
    !Array.isArray(json.labTests)
  ) {
    fail(
      "top-level",
      "the top level",
      "it must be an object with only labTests, an array"
    );
  }

  const keys = new Set();
  const variantOwners = new Map();

  json.labTests.forEach((entry, index) => {
    let where = `labTests[${index}]`;
    if (!isPlainObject(entry)) {
      fail("field-type", where, "an entry must be an object");
    }
    if (typeof entry.key === "string") where = `${where} (${entry.key})`;
    checkKnownKeys(entry, ENTRY_KEYS, where);

    for (const field of ["key", "name", "panel", "variants", "unit", "hardBounds"]) {
      if (!Object.hasOwn(entry, field)) {
        fail("required-field", where, `${field} is required`);
      }
    }
    for (const field of ["key", "name", "panel", "unit"]) {
      checkString(entry[field], field, where);
    }
    checkStringArray(entry.variants, "variants", where);
    if (Object.hasOwn(entry, "unitAliases")) {
      checkStringArray(entry.unitAliases, "unitAliases", where);
    }

    if (!KEY_PATTERN.test(entry.key)) {
      fail("key-format", where, `key must match ${KEY_PATTERN}`);
    }
    if (keys.has(entry.key)) {
      fail("key-unique", where, `key "${entry.key}" is used twice`);
    }
    keys.add(entry.key);

    const folded = new Set();
    for (const spelling of [entry.unit, ...(entry.unitAliases ?? [])]) {
      const fold = foldUnit(spelling);
      if (folded.has(fold)) {
        fail(
          "unit-spellings-distinct",
          where,
          `"${spelling}" equals another spelling of this Lab Test after the fold`
        );
      }
      folded.add(fold);
    }

    for (const variant of entry.variants) {
      if (variant !== variant.toLowerCase() || !SINGLE_SPACED.test(variant)) {
        fail(
          "variant-format",
          where,
          `variant "${variant}" must be lower case with single spaces`
        );
      }
      const owner = variantOwners.get(variant);
      if (owner !== undefined) {
        fail(
          "variant-unique",
          where,
          `variant "${variant}" is also listed by ${owner}`
        );
      }
      variantOwners.set(variant, where);
    }

    checkBounds(entry.hardBounds, "hardBounds", where);
    if (Object.hasOwn(entry, "plausibleBounds")) {
      checkBounds(entry.plausibleBounds, "plausibleBounds", where);
      if (
        entry.plausibleBounds.min < entry.hardBounds.min ||
        entry.plausibleBounds.max > entry.hardBounds.max
      ) {
        fail(
          "plausible-within-hard",
          where,
          "plausibleBounds must lie within hardBounds"
        );
      }
    }

    if (
      Object.hasOwn(entry, "printedRangeKind") &&
      !PRINTED_RANGE_KINDS.includes(entry.printedRangeKind)
    ) {
      fail(
        "printed-range-kind",
        where,
        "printedRangeKind must be reference or riskTarget"
      );
    }

    if (Object.hasOwn(entry, "defaultRanges")) {
      if (entry.printedRangeKind === "riskTarget") {
        fail(
          "risk-target-no-default-ranges",
          where,
          "a riskTarget Lab Test has no defaultRanges"
        );
      }
      if (!Array.isArray(entry.defaultRanges)) {
        fail("field-type", where, "defaultRanges must be an array");
      }
      entry.defaultRanges.forEach((range, rangeIndex) =>
        checkDefaultRange(range, `${where} defaultRanges[${rangeIndex}]`)
      );
      entry.defaultRanges.forEach((a, i) => {
        entry.defaultRanges.forEach((b, j) => {
          if (j <= i) return;
          if (sexesOverlap(a.sex, b.sex) && agesOverlap(a, b)) {
            fail(
              "default-range-overlap",
              where,
              `defaultRanges[${i}] and defaultRanges[${j}] match the same sex and age`
            );
          }
        });
      });
    }
  });

  return json;
}

/** One entry with every optional field filled in, in the output order. */
function normalise(entry) {
  const unitAliases = entry.unitAliases ?? [];
  const foldedUnits = {};
  for (const spelling of [entry.unit, ...unitAliases]) {
    foldedUnits[foldUnit(spelling)] = entry.unit;
  }
  return {
    key: entry.key,
    name: entry.name,
    panel: entry.panel,
    variants: entry.variants,
    unit: entry.unit,
    unitAliases,
    hardBounds: { min: entry.hardBounds.min, max: entry.hardBounds.max },
    plausibleBounds: entry.plausibleBounds
      ? { min: entry.plausibleBounds.min, max: entry.plausibleBounds.max }
      : null,
    printedRangeKind: entry.printedRangeKind ?? "reference",
    defaultRanges: (entry.defaultRanges ?? []).map((range) => ({
      sex: range.sex,
      ageMin: range.ageMin ?? null,
      ageMax: range.ageMax ?? null,
      low: range.low ?? null,
      high: range.high ?? null,
      source: {
        title: range.source.title,
        url: range.source.url,
        version: range.source.version
      }
    })),
    foldedUnits
  };
}

// --- Dart -----------------------------------------------------------------

const DART_LINE = 80;

function dartEscape(text) {
  return text.replace(/[\\'$]/g, (c) => `\\${c}`);
}

function dartQuoted(text) {
  return `'${dartEscape(text)}'`;
}

/**
 * Splits [text] into pieces whose quoted form fits [width] columns, breaking
 * after a space where it can and anywhere otherwise. Splitting happens before
 * escaping, so an escape is never cut in half.
 */
function splitForWidth(text, width) {
  const pieces = [];
  let rest = text;
  while (dartQuoted(rest).length > width) {
    let cut = 0;
    let lastSpace = -1;
    while (cut < rest.length && dartQuoted(rest.slice(0, cut + 1)).length <= width) {
      if (rest[cut] === " ") lastSpace = cut;
      cut += 1;
    }
    if (cut === 0) cut = 1;
    const end = lastSpace > 0 && cut < rest.length ? lastSpace + 1 : cut;
    pieces.push(rest.slice(0, end));
    rest = rest.slice(end);
  }
  pieces.push(rest);
  return pieces;
}

/**
 * A string argument `name: '...'`, at [indent], as `dart format` lays it out:
 * on one line when it fits, otherwise as adjacent strings, each continuation
 * indented four more columns.
 */
function dartStringArg(name, text, indent) {
  const pad = " ".repeat(indent);
  const head = `${pad}${name}: `;
  const single = `${head}${dartQuoted(text)},`;
  if (single.length <= DART_LINE) return [single];
  const firstWidth = DART_LINE - head.length;
  const contPad = " ".repeat(indent + 4);
  const contWidth = DART_LINE - contPad.length;
  const [first, ...more] = splitForWidth(text, firstWidth);
  const tail = splitForWidth(more.join(""), contWidth - 1);
  const lines = [`${head}${dartQuoted(first)}`];
  tail.forEach((piece, index) => {
    const comma = index === tail.length - 1 ? "," : "";
    lines.push(`${contPad}${dartQuoted(piece)}${comma}`);
  });
  return lines;
}

function dartNumber(value) {
  if (!Number.isFinite(value)) throw new Error(`not a finite number: ${value}`);
  return String(value);
}

function dartStringList(name, items, indent) {
  const pad = " ".repeat(indent);
  if (items.length === 0) return [`${pad}${name}: [],`];
  return [
    `${pad}${name}: [`,
    ...items.map((item) => `${pad}  ${dartQuoted(item)},`),
    `${pad}],`
  ];
}

function dartBounds(name, bounds, indent) {
  const pad = " ".repeat(indent);
  return [
    `${pad}${name}: Bounds(`,
    `${pad}  min: ${dartNumber(bounds.min)},`,
    `${pad}  max: ${dartNumber(bounds.max)},`,
    `${pad}),`
  ];
}

function sourceId(source) {
  return JSON.stringify([source.title, source.url, source.version]);
}

function emitDart(entries) {
  const sources = new Map();
  for (const entry of entries) {
    for (const range of entry.defaultRanges) {
      const id = sourceId(range.source);
      if (!sources.has(id)) {
        sources.set(id, { name: `_source${sources.size}`, source: range.source });
      }
    }
  }

  const lines = [
    "// GENERATED FILE — do not edit by hand.",
    `// Regenerate with: ${REGENERATE}`,
    "//",
    "// Source: packages/lab-catalogue/lab-tests.json, the Lab Test catalogue",
    "// (docs/designs/lab-results.md). The server carries the same entries in",
    "// apps/server/src/data/lab-test-catalogue.generated.ts; the contract-drift",
    "// gate re-runs the generator and fails when either file is stale.",
    "",
    "import 'lab_test.dart';",
    ""
  ];

  for (const { name, source } of sources.values()) {
    lines.push(
      `const ${name} = DefaultRangeSource(`,
      ...dartStringArg("title", source.title, 2),
      ...dartStringArg("url", source.url, 2),
      ...dartStringArg("version", source.version, 2),
      ");",
      ""
    );
  }

  lines.push(
    "/// Every Lab Test, in display order.",
    "const List<LabTest> labTestCatalogue = ["
  );
  for (const entry of entries) {
    lines.push(
      "  LabTest(",
      ...dartStringArg("key", entry.key, 4),
      ...dartStringArg("name", entry.name, 4),
      ...dartStringArg("panel", entry.panel, 4),
      ...dartStringList("variants", entry.variants, 4),
      ...dartStringArg("unit", entry.unit, 4),
      ...dartStringList("unitAliases", entry.unitAliases, 4),
      ...dartBounds("hardBounds", entry.hardBounds, 4)
    );
    if (entry.plausibleBounds) {
      lines.push(...dartBounds("plausibleBounds", entry.plausibleBounds, 4));
    }
    lines.push(
      `    printedRangeKind: PrintedRangeKind.${entry.printedRangeKind},`
    );
    if (entry.defaultRanges.length === 0) {
      lines.push("    defaultRanges: [],");
    } else {
      lines.push("    defaultRanges: [");
      for (const range of entry.defaultRanges) {
        lines.push("      DefaultRange(", `        sex: DefaultRangeSex.${range.sex},`);
        for (const field of ["ageMin", "ageMax", "low", "high"]) {
          if (range[field] !== null) {
            lines.push(`        ${field}: ${dartNumber(range[field])},`);
          }
        }
        lines.push(
          `        source: ${sources.get(sourceId(range.source)).name},`,
          "      ),"
        );
      }
      lines.push("    ],");
    }
    lines.push("  ),");
  }
  lines.push("];", "");

  lines.push(
    "/// Per Lab Test key, each folded spelling of its unit (see [foldUnit])",
    "/// mapped to its canonical unit.",
    "const Map<String, Map<String, String>> labTestFoldedUnits = {"
  );
  for (const entry of entries) {
    lines.push(`  ${dartQuoted(entry.key)}: {`);
    for (const [fold, unit] of Object.entries(entry.foldedUnits)) {
      lines.push(`    ${dartQuoted(fold)}: ${dartQuoted(unit)},`);
    }
    lines.push("  },");
  }
  lines.push("};", "");

  lines.push(
    "final Map<String, LabTest> _labTestsByKey = {",
    "  for (final labTest in labTestCatalogue) labTest.key: labTest,",
    "};",
    "",
    "/// The Lab Test with [key], or null when the catalogue has none.",
    "LabTest? labTestByKey(String key) => _labTestsByKey[key];",
    ""
  );

  for (const line of lines) {
    if (line.length > DART_LINE) {
      throw new Error(`Dart line over ${DART_LINE} columns: ${line}`);
    }
  }
  return lines.join("\n");
}

// --- TypeScript -------------------------------------------------------------

function emitTs(entries) {
  return `// GENERATED FILE — do not edit by hand.
// Regenerate with: ${REGENERATE}
//
// Source: packages/lab-catalogue/lab-tests.json, the Lab Test catalogue
// (docs/designs/lab-results.md). The app carries the same entries in
// apps/mobile/lib/domain/labs/lab_test_catalogue.generated.dart; the
// contract-drift gate re-runs the generator and fails when either file is
// stale.

export type LabTestBounds = {
  min: number;
  max: number;
};

export type DefaultRangeSex = "female" | "male" | "any";

export type DefaultRangeSource = {
  title: string;
  url: string;
  version: string;
};

/** Ages are inclusive whole years; a null side is unbounded. */
export type LabTestDefaultRange = {
  sex: DefaultRangeSex;
  ageMin: number | null;
  ageMax: number | null;
  low: number | null;
  high: number | null;
  source: DefaultRangeSource;
};

export type PrintedRangeKind = "reference" | "riskTarget";

export type LabTestEntry = {
  key: string;
  name: string;
  panel: string;
  variants: readonly string[];
  unit: string;
  unitAliases: readonly string[];
  hardBounds: LabTestBounds;
  plausibleBounds: LabTestBounds | null;
  printedRangeKind: PrintedRangeKind;
  defaultRanges: readonly LabTestDefaultRange[];
  /** Each folded spelling of the unit (whitespace removed, case kept) mapped
   * to the canonical unit. */
  foldedUnits: Readonly<Record<string, string>>;
};

/** Every Lab Test, in display order. */
export const LAB_TEST_CATALOGUE: readonly LabTestEntry[] = ${JSON.stringify(entries, null, 2)};

const LAB_TESTS_BY_KEY: ReadonlyMap<string, LabTestEntry> = new Map(
  LAB_TEST_CATALOGUE.map((entry) => [entry.key, entry])
);

/** The Lab Test with \`key\`, or null when the catalogue has none. */
export function labTestByKey(key: string): LabTestEntry | null {
  return LAB_TESTS_BY_KEY.get(key) ?? null;
}
`;
}

/** The two generated files for a catalogue, which must already be valid. */
export function emit(json) {
  const entries = json.labTests.map(normalise);
  return { dart: emitDart(entries), ts: emitTs(entries) };
}

function main() {
  const check = process.argv.includes("--check");
  const json = validateCatalogue(JSON.parse(readFileSync(sourceUrl, "utf8")));
  const { dart, ts } = emit(json);
  const outputs = [
    [dartUrl, dart],
    [tsUrl, ts]
  ];

  if (check) {
    const stale = outputs.filter(([url, text]) => {
      try {
        return readFileSync(url, "utf8") !== text;
      } catch {
        return true;
      }
    });
    if (stale.length > 0) {
      for (const [url] of stale) {
        console.error(`Lab Test catalogue output is stale: ${fileURLToPath(url)}`);
      }
      console.error(`Run:\n  ${REGENERATE}`);
      process.exit(1);
    }
    console.log("Lab Test catalogue outputs are up to date.");
    return;
  }

  for (const [url, text] of outputs) {
    writeFileSync(url, text);
    console.log(`Wrote ${fileURLToPath(url)}`);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}
