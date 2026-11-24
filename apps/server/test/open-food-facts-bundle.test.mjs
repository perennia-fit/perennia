import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { gunzipSync, gzipSync } from "node:zlib";
import test from "node:test";

import {
  FOOD_AISLE_LABELS,
  FOOD_AISLES,
  getOpenFoodFactsBundle,
  loadOpenFoodFactsBundle,
  normalizedWords,
  OPEN_FOOD_FACTS_BUNDLE_FORMAT,
  OPEN_FOOD_FACTS_BUNDLE_FORMAT_VERSION,
  OpenFoodFactsBundleUnavailableError,
  searchBundle,
  setOpenFoodFactsBundleLoaderForTesting
} from "../src/open-food-facts-bundle.ts";

// The committed bundle the app ships and the server reads
// (docs/designs/open-food-facts.md, "The bundle file", and
// docs/designs/food-aisles.md, "The bundle file, format version 2").
const bundleUrl = new URL(
  "../../mobile/assets/seeds/open_food_facts_bundle.ndjson.gz",
  import.meta.url
);
// The app's bundle format constants, which its asset test checks
// (apps/mobile/test/data/open_food_facts_bundle_asset_test.dart).
const dartModuleUrl = new URL(
  "../../mobile/lib/domain/nutrition/open_food_facts.dart",
  import.meta.url
);
// The app's FoodAisle enum, which the server's FOOD_AISLES copies.
const dartAisleUrl = new URL(
  "../../mobile/lib/domain/nutrition/food_aisle.dart",
  import.meta.url
);

test("the committed bundle loads, and the load time is reported", (t) => {
  const started = performance.now();
  const bundle = loadOpenFoodFactsBundle(bundleUrl);
  const elapsed = performance.now() - started;
  t.diagnostic(
    `Loaded ${bundle.products.length} Open Food Facts products in ${elapsed.toFixed(0)} ms.`
  );

  assert.equal(bundle.products.length, bundle.header.productCount);
  assert.equal(bundle.byCode.size, bundle.header.productCount);
  assert.equal(bundle.header.sourceName, "Open Food Facts");
  assert.match(bundle.header.datasetVersion, /^\d{4}-\d{2}-\d{2}$/);
  assert.match(bundle.header.attributionText, /Open Database License/);
});

test("the header's format and format version are the ones the app's asset test checks", () => {
  const dart = readFileSync(dartModuleUrl, "utf8");
  const dartFormat = /const bundleFormat = '([^']+)';/.exec(dart)?.[1];
  const dartFormatVersion = /const bundleFormatVersion = (\d+);/.exec(dart)?.[1];
  assert.equal(dartFormat, OPEN_FOOD_FACTS_BUNDLE_FORMAT);
  assert.equal(Number(dartFormatVersion), OPEN_FOOD_FACTS_BUNDLE_FORMAT_VERSION);

  const header = JSON.parse(rawBundleLines()[0]);
  assert.equal(header.format, dartFormat);
  assert.equal(header.formatVersion, Number(dartFormatVersion));
  assert.equal(header.formatVersion, 2);
});

test("FOOD_AISLES and FOOD_AISLE_LABELS match the app's FoodAisle enum, in order", () => {
  const dart = readFileSync(dartAisleUrl, "utf8");
  const start = dart.indexOf("enum FoodAisle {");
  assert.notEqual(start, -1, "food_aisle.dart has no FoodAisle enum");
  const body = dart.slice(start + "enum FoodAisle {".length, dart.indexOf(";", start));
  const dartAisles = [...body.matchAll(/(\w+)\('([^']+)'\)/g)].map(([, id, label]) => [
    id,
    label
  ]);

  assert.equal(dartAisles.length, 14);
  assert.deepEqual(
    dartAisles.map(([id]) => id),
    [...FOOD_AISLES]
  );
  assert.deepEqual(Object.entries(FOOD_AISLE_LABELS), dartAisles);
});

test("the committed bundle gives every Aisle at least one product", () => {
  const bundle = loadOpenFoodFactsBundle(bundleUrl);
  const counts = new Map();
  for (const found of bundle.products) {
    counts.set(found.aisle, (counts.get(found.aisle) ?? 0) + 1);
  }
  assert.deepEqual(
    FOOD_AISLES.filter((aisle) => !counts.has(aisle)),
    []
  );
});

test("a sample of bundled barcodes returns the record in that barcode's line", () => {
  const bundle = loadOpenFoodFactsBundle(bundleUrl);
  const lines = rawBundleLines().slice(1);
  const step = Math.floor(lines.length / 25);
  let checked = 0;
  for (let index = 0; index < lines.length; index += step) {
    const line = JSON.parse(lines[index]);
    const [found] = searchBundle(bundle, line.code, 1);
    assert.ok(found, `code ${line.code} was not found`);
    assert.equal(found.code, line.code);
    assert.equal(found.name, line.name);
    assert.equal(found.brand, line.brand);
    assert.equal(found.isLiquid, line.isLiquid);
    assert.equal(found.servingLabel, line.servingLabel);
    assert.equal(found.servingSize, line.servingSize);
    assert.equal(found.packageSize, line.packageSize);
    assert.deepEqual(found.nutrients, line.nutrients);
    assert.equal(found.modifiedAt, line.modifiedAt);
    assert.equal(found.scans, line.scans);
    assert.ok(Object.hasOwn(line, "aisle"), `line ${line.code} has no aisle`);
    assert.equal(found.aisle, line.aisle);
    checked += 1;
  }
  assert.ok(checked >= 25);
});

test("name search matches word prefixes of the name or the brand", () => {
  const bundle = fixtureBundle([
    product({ code: "1000001", name: "Greek Yogurt Plain", brand: "Chobani" }),
    product({ code: "1000002", name: "Plain Oats", brand: null })
  ]);

  assert.deepEqual(codes(searchBundle(bundle, "gre yog", 10)), ["1000001"]);
  assert.deepEqual(codes(searchBundle(bundle, "chob plain", 10)), ["1000001"]);
  assert.deepEqual(codes(searchBundle(bundle, "PLAIN", 10)), ["1000001", "1000002"]);
  // A part must start a word; the middle of a word does not match.
  assert.deepEqual(codes(searchBundle(bundle, "ogurt", 10)), []);
  // Every part must match.
  assert.deepEqual(codes(searchBundle(bundle, "plain chob oats", 10)), []);
});

test("name search folds case and diacritics in names and queries alike", () => {
  const bundle = fixtureBundle([
    product({ code: "2000001", name: "Crème Fraîche", brand: null }),
    product({ code: "2000002", name: "Creme Brulee", brand: "Café Noir" })
  ]);

  assert.deepEqual(codes(searchBundle(bundle, "creme", 10)), ["2000001", "2000002"]);
  assert.deepEqual(codes(searchBundle(bundle, "CRÈME fraiche", 10)), ["2000001"]);
  // "Crème" typed in decomposed form (e, then U+0300) is one part.
  assert.deepEqual(codes(searchBundle(bundle, "Crème bru", 10)), ["2000002"]);
  assert.deepEqual(codes(searchBundle(bundle, "cafe", 10)), ["2000002"]);
  assert.deepEqual(normalizedWords("Crème-Fraîche, 200g!"), ["creme", "fraiche", "200g"]);
  // A capital whose lower case carries a mark stays one word.
  assert.deepEqual(normalizedWords("İSTANBUL Lokum"), ["istanbul", "lokum"]);
});

test("name search uses at most the first 8 query parts", () => {
  const bundle = fixtureBundle([
    product({ code: "3000001", name: "a b c d e f g h", brand: null })
  ]);

  assert.deepEqual(codes(searchBundle(bundle, "a b c d e f g h", 10)), ["3000001"]);
  // A 9th part that matches nothing is ignored.
  assert.deepEqual(codes(searchBundle(bundle, "a b c d e f g h zzz", 10)), ["3000001"]);
  assert.deepEqual(codes(searchBundle(bundle, "zzz a b c d e f g h", 10)), []);
});

test("barcode candidates come first, in candidate order, and each product appears once", () => {
  const bundle = fixtureBundle([
    product({ code: "0012345678905", name: "Rolled Oats", scans: 1 }),
    product({ code: "012345678905", name: "Bar 012345678905", scans: 2 }),
    product({ code: "5000001", name: "Snack 012345678905 Pack", scans: 900 })
  ]);

  // A 12-digit code is tried as given, then with a leading 0; the products
  // whose names contain the code follow, and the one already found by its
  // barcode is not repeated.
  assert.deepEqual(codes(searchBundle(bundle, "0123-4567-8905", 10)), [
    "012345678905",
    "0012345678905"
  ]);
  assert.deepEqual(codes(searchBundle(bundle, "012345678905", 10)), [
    "012345678905",
    "0012345678905",
    "5000001"
  ]);
  // A 13-digit code starting with 0 is also tried without it.
  assert.deepEqual(codes(searchBundle(bundle, "0012345678905", 10)), [
    "0012345678905",
    "012345678905"
  ]);
  // The limit applies after duplicates are removed.
  assert.deepEqual(codes(searchBundle(bundle, "012345678905", 2)), [
    "012345678905",
    "0012345678905"
  ]);
});

test("name matches are ordered by scans descending, then code ascending", () => {
  const bundle = fixtureBundle([
    product({ code: "4000003", name: "Milk", scans: 5 }),
    product({ code: "4000001", name: "Milk Chocolate", scans: 5 }),
    product({ code: "4000002", name: "Milk Powder", scans: 50 }),
    product({ code: "4000004", name: "Oat Milk", scans: 0 })
  ]);

  assert.deepEqual(codes(searchBundle(bundle, "milk", 10)), [
    "4000002",
    "4000001",
    "4000003",
    "4000004"
  ]);
  assert.deepEqual(codes(searchBundle(bundle, "milk", 2)), ["4000002", "4000001"]);
});

test("no query, or one with no parts and no barcode candidates, finds nothing", () => {
  const bundle = fixtureBundle([product({ code: "6000001", name: "Milk" })]);

  assert.deepEqual(searchBundle(bundle, undefined, 10), []);
  assert.deepEqual(searchBundle(bundle, "", 10), []);
  assert.deepEqual(searchBundle(bundle, "!!! ---", 10), []);
});

test("with an Aisle and no query, lists the Aisle by scans descending, then code", () => {
  const bundle = fixtureBundle([
    product({ code: "9000003", name: "Crisps", scans: 5, aisle: "snacks" }),
    product({ code: "9000001", name: "Pretzels", scans: 50, aisle: "snacks" }),
    product({ code: "9000002", name: "Popcorn", scans: 50, aisle: "snacks" }),
    product({ code: "9000004", name: "Cola", scans: 900, aisle: "drinks" }),
    product({ code: "9000005", name: "Mystery", scans: 1000, aisle: null })
  ]);

  assert.deepEqual(codes(searchBundle(bundle, undefined, 10, "snacks")), [
    "9000001",
    "9000002",
    "9000003"
  ]);
  assert.deepEqual(codes(searchBundle(bundle, undefined, 2, "snacks")), [
    "9000001",
    "9000002"
  ]);
  assert.deepEqual(codes(searchBundle(bundle, undefined, 10, "babyFood")), []);
  // Without an Aisle, no query still finds nothing.
  assert.deepEqual(searchBundle(bundle, undefined, 10), []);
});

test("with an Aisle and a query, name matches are the Aisle's and barcode matches are kept", () => {
  const bundle = fixtureBundle([
    product({ code: "9100001", name: "Greek Yogurt", scans: 10, aisle: "dairyEggs" }),
    product({ code: "9100002", name: "Greek Yogurt Bar", scans: 900, aisle: "snacks" }),
    product({ code: "9100003", name: "Greek Yogurt Plain", scans: 5, aisle: "dairyEggs" }),
    product({ code: "0012345678905", name: "Cola", scans: 1, aisle: "drinks" })
  ]);

  assert.deepEqual(codes(searchBundle(bundle, "greek yo", 10, "dairyEggs")), [
    "9100001",
    "9100003"
  ]);
  assert.deepEqual(codes(searchBundle(bundle, "greek yo", 10)), [
    "9100002",
    "9100001",
    "9100003"
  ]);
  // A typed barcode finds its product, even in another Aisle.
  assert.deepEqual(codes(searchBundle(bundle, "0012345678905", 10, "dairyEggs")), [
    "0012345678905"
  ]);
  // The limit applies after the filter.
  assert.deepEqual(codes(searchBundle(bundle, "greek", 1, "dairyEggs")), ["9100001"]);
});

test("a product line's aisle is parsed, and a missing or unknown aisle is rejected", () => {
  const bundle = fixtureBundle([
    product({ code: "9200001", name: "Milk", aisle: "dairyEggs" }),
    product({ code: "9200002", name: "Mystery", aisle: null })
  ]);
  assert.equal(bundle.byCode.get("9200001").aisle, "dairyEggs");
  assert.equal(bundle.byCode.get("9200002").aisle, null);

  const directory = mkdtempSync(path.join(tmpdir(), "off-bundle-"));
  try {
    const { aisle: _omitted, ...withoutAisle } = product({ code: "9200003", name: "Milk" });
    const missing = writeBundle(directory, "missing-aisle.gz", [withoutAisle]);
    assert.throws(
      () => loadOpenFoodFactsBundle(missing),
      (error) =>
        error instanceof OpenFoodFactsBundleUnavailableError &&
        /invalid aisle/.test(error.cause.message)
    );

    for (const aisle of ["frozen", "", "DairyEggs", 3, false]) {
      const unknown = writeBundle(directory, "unknown-aisle.gz", [
        product({ code: "9200004", name: "Milk", aisle })
      ]);
      assert.throws(
        () => loadOpenFoodFactsBundle(unknown),
        (error) =>
          error instanceof OpenFoodFactsBundleUnavailableError &&
          /invalid aisle/.test(error.cause.message),
        `aisle ${JSON.stringify(aisle)}`
      );
    }

    // A format version 1 file, whose lines have no aisle, is not read.
    const versionOne = writeBundle(directory, "version-one.gz", [], { formatVersion: 1 });
    assert.throws(
      () => loadOpenFoodFactsBundle(versionOne),
      (error) =>
        error instanceof OpenFoodFactsBundleUnavailableError &&
        /format version/.test(error.cause.message)
    );
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("an unreadable or unknown bundle file throws OpenFoodFactsBundleUnavailableError", () => {
  const directory = mkdtempSync(path.join(tmpdir(), "off-bundle-"));
  try {
    assert.throws(
      () => loadOpenFoodFactsBundle(pathToFileURL(path.join(directory, "missing.gz"))),
      OpenFoodFactsBundleUnavailableError
    );

    const notGzip = path.join(directory, "not-gzip.gz");
    writeFileSync(notGzip, "not gzip");
    assert.throws(
      () => loadOpenFoodFactsBundle(pathToFileURL(notGzip)),
      OpenFoodFactsBundleUnavailableError
    );

    const nextVersion = writeBundle(directory, "next-version.gz", [], {
      formatVersion: OPEN_FOOD_FACTS_BUNDLE_FORMAT_VERSION + 1
    });
    assert.throws(
      () => loadOpenFoodFactsBundle(nextVersion),
      (error) =>
        error instanceof OpenFoodFactsBundleUnavailableError &&
        error.message === "The Open Food Facts bundle is not available on this server." &&
        /format version/.test(error.cause.message)
    );

    const badNutrient = writeBundle(directory, "bad-nutrient.gz", [
      product({ code: "7000001", name: "Milk", nutrients: { energy: "64kcal" } })
    ]);
    assert.throws(
      () => loadOpenFoodFactsBundle(badNutrient),
      OpenFoodFactsBundleUnavailableError
    );

    // Number() reads "0x10" as 16, but Dart's double.parse rejects it.
    const hexNutrient = writeBundle(directory, "hex-nutrient.gz", [
      product({ code: "7000002", name: "Milk", nutrients: { energy: "0x10" } })
    ]);
    assert.throws(
      () => loadOpenFoodFactsBundle(hexNutrient),
      OpenFoodFactsBundleUnavailableError
    );

    // The app's decoder throws on an id that is not a Nutrient id.
    const unknownNutrient = writeBundle(directory, "unknown-nutrient.gz", [
      product({ code: "7000003", name: "Milk", nutrients: { energy: "64", taurine: "1" } })
    ]);
    assert.throws(
      () => loadOpenFoodFactsBundle(unknownNutrient),
      (error) =>
        error instanceof OpenFoodFactsBundleUnavailableError &&
        /nutrients\.taurine/.test(error.cause.message)
    );

    // A safe integer past the Date range (8.64e12 seconds) would make
    // toISOString throw on every request that returns the product.
    const outOfRangeDate = writeBundle(directory, "out-of-range-date.gz", [
      product({ code: "7000004", name: "Milk", modifiedAt: 8.64e12 + 1 })
    ]);
    assert.throws(
      () => loadOpenFoodFactsBundle(outOfRangeDate),
      (error) =>
        error instanceof OpenFoodFactsBundleUnavailableError &&
        /modifiedAt/.test(error.cause.message)
    );
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("getOpenFoodFactsBundle loads once per process, and keeps a failure", () => {
  const bundle = fixtureBundle([product({ code: "8000001", name: "Milk" })]);
  let loads = 0;
  try {
    setOpenFoodFactsBundleLoaderForTesting(() => {
      loads += 1;
      return bundle;
    });
    assert.equal(getOpenFoodFactsBundle(), bundle);
    assert.equal(getOpenFoodFactsBundle(), bundle);
    assert.equal(loads, 1);

    loads = 0;
    setOpenFoodFactsBundleLoaderForTesting(() => {
      loads += 1;
      throw new Error("disk on fire");
    });
    assert.throws(() => getOpenFoodFactsBundle(), OpenFoodFactsBundleUnavailableError);
    assert.throws(() => getOpenFoodFactsBundle(), OpenFoodFactsBundleUnavailableError);
    assert.equal(loads, 1);
  } finally {
    setOpenFoodFactsBundleLoaderForTesting(null);
  }
  assert.equal(
    getOpenFoodFactsBundle().header.format,
    OPEN_FOOD_FACTS_BUNDLE_FORMAT
  );
});

function rawBundleLines() {
  return gunzipSync(readFileSync(bundleUrl))
    .toString("utf8")
    .split("\n")
    .filter((line) => line.length > 0);
}

function codes(products) {
  return products.map((found) => found.code);
}

function product({
  code,
  name,
  brand = null,
  scans = 1,
  nutrients = { energy: "100", protein: "1", carbohydrate: "2", fat: "3" },
  modifiedAt = 1745020800,
  aisle = null
}) {
  return {
    code,
    name,
    brand,
    isLiquid: false,
    servingLabel: null,
    servingSize: null,
    packageSize: null,
    nutrients,
    modifiedAt,
    scans,
    aisle
  };
}

function fixtureBundle(products) {
  const directory = mkdtempSync(path.join(tmpdir(), "off-bundle-"));
  try {
    return loadOpenFoodFactsBundle(writeBundle(directory, "bundle.gz", products));
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

function writeBundle(directory, name, products, headerOverrides = {}) {
  const header = {
    format: OPEN_FOOD_FACTS_BUNDLE_FORMAT,
    formatVersion: OPEN_FOOD_FACTS_BUNDLE_FORMAT_VERSION,
    datasetVersion: "2026-10-26",
    contentHash: "0".repeat(64),
    sourceName: "Open Food Facts",
    sourceUrl: "https://world.openfoodfacts.org/",
    licenseName: "Open Database License (ODbL) 1.0",
    licenseUrl: "https://opendatacommons.org/licenses/odbl/1-0/",
    contentsLicenseUrl: "https://opendatacommons.org/licenses/dbcl/1-0/",
    attributionText: "Contains information from Open Food Facts.",
    countries: ["au"],
    perCountryLimit: 10000,
    productCount: products.length,
    ...headerOverrides
  };
  const sorted = [...products].sort((a, b) => (a.code < b.code ? -1 : 1));
  const text = [header, ...sorted].map((line) => `${JSON.stringify(line)}\n`).join("");
  const file = path.join(directory, name);
  writeFileSync(file, gzipSync(text));
  return pathToFileURL(file);
}
