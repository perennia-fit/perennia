import { readFileSync } from "node:fs";
import { gunzipSync } from "node:zlib";

import { barcodeCandidates } from "./barcode-candidates.js";

/**
 * The Open Food Facts bundle the app ships
 * (apps/mobile/assets/seeds/open_food_facts_bundle.ndjson.gz), read by the
 * server so that an agent searches the same products the app has offline.
 * The server never calls Open Food Facts: the bundle is the only Open Food
 * Facts data it serves.
 *
 * The file is one header line, then one product line per product, sorted by
 * code (docs/designs/open-food-facts.md, "The bundle file"). The app's reader
 * is decodeBundleProductLine in apps/mobile/lib/domain/nutrition/open_food_facts.dart;
 * this one reads the same lines, so a barcode's record here is the record an
 * app with the same dataset version decodes.
 */

export const OPEN_FOOD_FACTS_BUNDLE_FORMAT = "perennia-open-food-facts-bundle";
export const OPEN_FOOD_FACTS_BUNDLE_FORMAT_VERSION = 1;

/** Shown with every Open Food Facts food (the spec's Goal 7). */
export const OPEN_FOOD_FACTS_DISCLAIMER =
  "Values come from Open Food Facts contributors and may be incomplete or wrong. Check the label. Not for medical use.";

/** The product's own page, where a user can check and correct its data. */
export function openFoodFactsProductUrl(code: string): string {
  return `https://world.openfoodfacts.org/product/${encodeURIComponent(code)}`;
}

// A name search uses at most this many query parts, as the app's does.
const MAX_SEARCH_PARTS = 8;

export type OpenFoodFactsBundleHeader = {
  format: string;
  formatVersion: number;
  datasetVersion: string;
  contentHash: string;
  sourceName: string;
  sourceUrl: string;
  licenseName: string;
  licenseUrl: string;
  contentsLicenseUrl: string;
  attributionText: string;
  countries: string[];
  perCountryLimit: number;
  productCount: number;
};

export type BundleProduct = {
  code: string;
  name: string;
  brand: string | null;
  isLiquid: boolean;
  servingLabel: string | null;
  servingSize: number | null;
  packageSize: number | null;
  /** Nutrient id → value per 100 g or ml as text, in the default unit. */
  nutrients: Record<string, string>;
  /** The change date, in Unix seconds. */
  modifiedAt: number;
  scans: number;
  /** The normalized words of the name and the brand, for name search. */
  words: readonly string[];
};

export type OpenFoodFactsBundle = {
  header: OpenFoodFactsBundleHeader;
  byCode: Map<string, BundleProduct>;
  /** Every product, in name-search order: `scans` descending, then `code`. */
  products: BundleProduct[];
};

/**
 * The bundle file could not be read or parsed. The agent surface answers
 * with 503 `agent_foods_unavailable` and this error's message; the reason is
 * kept as `cause`.
 */
export class OpenFoodFactsBundleUnavailableError extends Error {
  constructor(cause: unknown) {
    super("The Open Food Facts bundle is not available on this server.", {
      cause
    });
    this.name = "OpenFoodFactsBundleUnavailableError";
  }
}

/**
 * Reads and parses the bundle synchronously. This blocks the event loop for
 * the read, the gunzip and the parse (a few hundred milliseconds), which is
 * why getOpenFoodFactsBundle does it once per process.
 */
export function loadOpenFoodFactsBundle(file: URL): OpenFoodFactsBundle {
  try {
    const text = gunzipSync(readFileSync(file)).toString("utf8");
    return parseBundle(text);
  } catch (error) {
    throw new OpenFoodFactsBundleUnavailableError(error);
  }
}

const BUNDLE_FILE = new URL(
  // apps/server/src in development and apps/server/dist in the image both
  // resolve this to apps/mobile/assets/seeds/; the Dockerfile copies the file
  // there, so development and the image read the one committed copy.
  "../../mobile/assets/seeds/open_food_facts_bundle.ndjson.gz",
  import.meta.url
);

const defaultLoader = () => loadOpenFoodFactsBundle(BUNDLE_FILE);

let loader: () => OpenFoodFactsBundle = defaultLoader;
// The load's outcome, kept for the life of the process. A failure is kept
// too: the file is part of the deployed image and does not change while the
// process runs, so retrying would only block the event loop again on every
// request without a different result.
let cached:
  | { bundle: OpenFoodFactsBundle }
  | { error: OpenFoodFactsBundleUnavailableError }
  | undefined;

/**
 * The bundle, loaded on first use and cached for the life of the process.
 * Throws OpenFoodFactsBundleUnavailableError when the file cannot be read.
 */
export function getOpenFoodFactsBundle(): OpenFoodFactsBundle {
  if (cached === undefined) {
    try {
      cached = { bundle: loader() };
    } catch (error) {
      cached = {
        error:
          error instanceof OpenFoodFactsBundleUnavailableError
            ? error
            : new OpenFoodFactsBundleUnavailableError(error)
      };
    }
  }
  if ("error" in cached) {
    throw cached.error;
  }
  return cached.bundle;
}

/** Replaces the loader (null restores the default) and clears the cache. */
export function setOpenFoodFactsBundleLoaderForTesting(
  replacement: (() => OpenFoodFactsBundle) | null
): void {
  loader = replacement ?? defaultLoader;
  cached = undefined;
}

/**
 * Searches the bundle (docs/designs/open-food-facts.md, "Agent surface"):
 * the products whose codes match the query's barcode candidates come first,
 * in candidate order; then the products whose name or brand has, for every
 * query part (up to 8), a word starting with it, by `scans` descending then
 * `code`. Each product appears once, and `limit` applies last. An undefined
 * query, or one with no parts and no candidates, returns nothing: listing the
 * whole bundle is not supported.
 *
 * The order can differ from the app's FTS5 search, which ranks by bm25.
 */
export function searchBundle(
  bundle: OpenFoodFactsBundle,
  query: string | undefined,
  limit: number
): BundleProduct[] {
  if (query === undefined) {
    return [];
  }
  // The candidates are distinct codes, so these products are too.
  const found = barcodeCandidates(query).flatMap(
    (code) => bundle.byCode.get(code) ?? []
  );
  const parts = normalizedWords(query).slice(0, MAX_SEARCH_PARTS);
  if (parts.length > 0) {
    const seen = new Set(found.map((product) => product.code));
    for (const product of bundle.products) {
      if (found.length >= limit) {
        break;
      }
      if (
        !seen.has(product.code) &&
        parts.every((part) => product.words.some((word) => word.startsWith(part)))
      ) {
        found.push(product);
      }
    }
  }
  return found.slice(0, limit);
}

/**
 * Lower-cased, Unicode NFKD, combining marks removed, split on everything
 * that is not a letter or a digit; empty words dropped. Names, brands and
 * queries all go through it, so "creme" finds "Crème".
 */
export function normalizedWords(text: string): string[] {
  // Lower-cased first: a few capitals lower-case to a letter plus a combining
  // mark ("İ" to "i" and U+0307), which would otherwise split the word.
  return text
    .toLowerCase()
    .normalize("NFKD")
    .replace(/\p{M}/gu, "")
    .split(/[^\p{L}\p{N}]+/u)
    .filter((word) => word.length > 0);
}

function parseBundle(text: string): OpenFoodFactsBundle {
  const lines = text.split("\n");
  // Every line ends with a newline, so the last part is empty.
  if (lines.pop() !== "") {
    throw new Error("The bundle does not end with a newline.");
  }
  const headerLine = lines.shift();
  if (headerLine === undefined) {
    throw new Error("The bundle has no header line.");
  }
  const header = parseHeader(headerLine);
  if (lines.length !== header.productCount) {
    throw new Error(
      `The bundle header counts ${header.productCount} products, but the file has ${lines.length}.`
    );
  }

  const byCode = new Map<string, BundleProduct>();
  const products = lines.map((line, index) => {
    const product = parseProductLine(line, index + 2);
    if (byCode.has(product.code)) {
      throw new Error(`Bundle line ${index + 2} repeats code ${product.code}.`);
    }
    byCode.set(product.code, product);
    return product;
  });
  products.sort(
    (a, b) => b.scans - a.scans || (a.code < b.code ? -1 : a.code > b.code ? 1 : 0)
  );
  return { header, byCode, products };
}

function parseHeader(line: string): OpenFoodFactsBundleHeader {
  const json = parseObject(line, 1);
  if (json.format !== OPEN_FOOD_FACTS_BUNDLE_FORMAT) {
    throw new Error(`Unknown bundle format ${JSON.stringify(json.format)}.`);
  }
  if (json.formatVersion !== OPEN_FOOD_FACTS_BUNDLE_FORMAT_VERSION) {
    throw new Error(
      `Unsupported bundle format version ${JSON.stringify(json.formatVersion)}.`
    );
  }
  const countries = json.countries;
  if (
    !Array.isArray(countries) ||
    !countries.every((country) => typeof country === "string")
  ) {
    throw new Error("The bundle header's countries are not a list of text.");
  }
  return {
    format: OPEN_FOOD_FACTS_BUNDLE_FORMAT,
    formatVersion: OPEN_FOOD_FACTS_BUNDLE_FORMAT_VERSION,
    datasetVersion: requiredText(json, "datasetVersion", 1),
    contentHash: requiredText(json, "contentHash", 1),
    sourceName: requiredText(json, "sourceName", 1),
    sourceUrl: requiredText(json, "sourceUrl", 1),
    licenseName: requiredText(json, "licenseName", 1),
    licenseUrl: requiredText(json, "licenseUrl", 1),
    contentsLicenseUrl: requiredText(json, "contentsLicenseUrl", 1),
    attributionText: requiredText(json, "attributionText", 1),
    countries,
    perCountryLimit: requiredInteger(json, "perCountryLimit", 1),
    productCount: requiredInteger(json, "productCount", 1)
  };
}

function parseProductLine(line: string, lineNumber: number): BundleProduct {
  const json = parseObject(line, lineNumber);
  const name = requiredText(json, "name", lineNumber);
  const brand = optionalText(json, "brand", lineNumber);
  const isLiquid = json.isLiquid;
  if (typeof isLiquid !== "boolean") {
    throw lineError(lineNumber, "isLiquid");
  }
  const nutrients = json.nutrients;
  if (typeof nutrients !== "object" || nutrients === null || Array.isArray(nutrients)) {
    throw lineError(lineNumber, "nutrients");
  }
  const nutrientText: Record<string, string> = {};
  for (const [id, entered] of Object.entries(nutrients)) {
    // The app reads the text as `entered` and its parsed number as `value`
    // (Dart's double.parse). Only plain decimal text is accepted, which
    // Number() and double.parse read as the same nearest double; Number()
    // alone would also take "0x10" or "", which double.parse rejects.
    if (
      typeof entered !== "string" ||
      !DECIMAL_TEXT.test(entered) ||
      !Number.isFinite(Number(entered))
    ) {
      throw lineError(lineNumber, `nutrients.${id}`);
    }
    nutrientText[id] = entered;
  }
  return {
    code: requiredText(json, "code", lineNumber),
    name,
    brand,
    isLiquid,
    servingLabel: optionalText(json, "servingLabel", lineNumber),
    servingSize: optionalPositiveNumber(json, "servingSize", lineNumber),
    packageSize: optionalPositiveNumber(json, "packageSize", lineNumber),
    nutrients: nutrientText,
    modifiedAt: requiredInteger(json, "modifiedAt", lineNumber),
    scans: requiredInteger(json, "scans", lineNumber),
    words: [...normalizedWords(name), ...(brand === null ? [] : normalizedWords(brand))]
  };
}

const DECIMAL_TEXT = /^-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/;

type JsonObject = Record<string, unknown>;

function parseObject(line: string, lineNumber: number): JsonObject {
  const json: unknown = JSON.parse(line);
  if (typeof json !== "object" || json === null || Array.isArray(json)) {
    throw new Error(`Bundle line ${lineNumber} is not an object.`);
  }
  return json as JsonObject;
}

function requiredText(json: JsonObject, key: string, lineNumber: number): string {
  const value = json[key];
  if (typeof value !== "string" || value.length === 0) {
    throw lineError(lineNumber, key);
  }
  return value;
}

function optionalText(
  json: JsonObject,
  key: string,
  lineNumber: number
): string | null {
  const value = json[key];
  if (value === null) {
    return null;
  }
  if (typeof value !== "string" || value.length === 0) {
    throw lineError(lineNumber, key);
  }
  return value;
}

function optionalPositiveNumber(
  json: JsonObject,
  key: string,
  lineNumber: number
): number | null {
  const value = json[key];
  if (value === null) {
    return null;
  }
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) {
    throw lineError(lineNumber, key);
  }
  return value;
}

function requiredInteger(json: JsonObject, key: string, lineNumber: number): number {
  const value = json[key];
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) {
    throw lineError(lineNumber, key);
  }
  return value;
}

function lineError(lineNumber: number, key: string): Error {
  return new Error(`Bundle line ${lineNumber} has an invalid ${key}.`);
}
