import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { gunzipSync, gzipSync } from "node:zlib";
import test from "node:test";

import {
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
// (docs/designs/open-food-facts.md, "The bundle file").
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
  nutrients = { energy: "100", protein: "1", carbohydrate: "2", fat: "3" }
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
    modifiedAt: 1745020800,
    scans
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
