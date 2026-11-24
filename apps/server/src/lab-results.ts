/**
 * Lab Results' shared rules on the server (docs/designs/lab-results.md,
 * "Storage" and "Result identity and the collapse"): the unit fold, the
 * stored `lab` object, the canonical `entered` form and the collapse. The app
 * twins are apps/mobile/lib/domain/labs/lab_test.dart, lab_result.dart and
 * lab_result_collapse.dart; the m43 golden vectors pin the collapse in both.
 */

import type { LabTestEntry } from "./data/lab-test-catalogue.generated.js";

/**
 * The one unit fold every comparison uses: remove every whitespace character
 * and keep case. The generator (tools/generate-lab-test-catalogue.mjs) builds
 * each entry's `foldedUnits` with the same fold.
 */
export function foldUnit(unit: string): string {
  return unit.replace(/\s/g, "");
}

/**
 * The canonical unit of `entry` when `enteredUnit`, after the fold, is its
 * unit or one of its aliases; otherwise null. Own keys only, so a spelling
 * such as `constructor` never resolves through the prototype.
 */
export function resolveLabUnit(entry: LabTestEntry, enteredUnit: string): string | null {
  const folded = foldUnit(enteredUnit);
  return Object.hasOwn(entry.foldedUnits, folded) ? (entry.foldedUnits[folded] ?? null) : null;
}

/** A Limit Result's comparator, in its ASCII stored form. */
export type LabComparator = "<" | "<=" | ">" | ">=";

export const LAB_COMPARATORS: readonly LabComparator[] = ["<", "<=", ">", ">="];

export type LabLimit = { comparator: LabComparator; bound: number };

/** The statuses this build knows. */
export type KnownReportStatus = "final" | "interim";

/**
 * A stored `reportStatus`. Text a later build wrote is kept as it is and ranks
 * as interim in the collapse, so a known `final` always beats it.
 */
export type ReportStatus = KnownReportStatus | (string & {});

/** The `lab` object of a Lab Result, in its stored shape. */
export type LabFields = {
  collected: string;
  limit: LabLimit | null;
  printedRange: string | null;
  printedFlag: string | null;
  reportStatus: ReportStatus;
  fasting: true | null;
  labName: string | null;
};

/**
 * The stored `lab` object for `fields`, with keys in exactly the order
 * collected, limit, printedRange, printedFlag, reportStatus, fasting, labName,
 * and every absent optional key written as null.
 */
export function encodeLab(fields: {
  collected: string;
  limit?: LabLimit | null;
  printedRange?: string | null;
  printedFlag?: string | null;
  reportStatus?: ReportStatus;
  fasting?: true | null;
  labName?: string | null;
}): LabFields {
  return {
    collected: fields.collected,
    limit:
      fields.limit == null
        ? null
        : { comparator: fields.limit.comparator, bound: fields.limit.bound },
    printedRange: fields.printedRange ?? null,
    printedFlag: fields.printedFlag ?? null,
    reportStatus: fields.reportStatus ?? "final",
    fasting: fields.fasting ?? null,
    labName: fields.labName ?? null
  };
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function stringOrNull(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

function decodeLimit(value: unknown): LabLimit | null {
  if (!isPlainObject(value)) return null;
  const { comparator, bound } = value;
  if (
    typeof comparator !== "string" ||
    !(LAB_COMPARATORS as readonly string[]).includes(comparator) ||
    typeof bound !== "number" ||
    !Number.isFinite(bound)
  ) {
    return null;
  }
  return { comparator: comparator as LabComparator, bound };
}

/**
 * Decodes a stored `lab` object; the one rule every reader uses, identical to
 * the app's `decodeLab`.
 *
 * Returns null unless `value` is an object whose `collected` passes
 * `isValidCollected`: such a reading is treated as lab-less. Otherwise it is
 * tolerant: a missing or null `reportStatus` decodes as final, other text is
 * kept as it is (a non-string as its JSON text); a malformed `limit`, a
 * non-string text field and a `fasting` other than `true` decode as null;
 * unknown keys are dropped.
 */
export function decodeLab(value: unknown): LabFields | null {
  if (!isPlainObject(value)) return null;
  const { collected } = value;
  if (typeof collected !== "string" || !isValidCollected(collected)) return null;
  const rawStatus = value.reportStatus;
  const reportStatus: ReportStatus =
    rawStatus === undefined || rawStatus === null
      ? "final"
      : typeof rawStatus === "string"
        ? rawStatus
        : JSON.stringify(rawStatus);
  return {
    collected,
    limit: decodeLimit(value.limit),
    printedRange: stringOrNull(value.printedRange),
    printedFlag: stringOrNull(value.printedFlag),
    reportStatus,
    fasting: value.fasting === true ? true : null,
    labName: stringOrNull(value.labName)
  };
}

/**
 * The canonical `entered` text: `"{comparator} {value}"` with the ASCII
 * comparator and one space (`"< 1"`) for a Limit Result, else `value`.
 */
export function formatEntered(comparator: LabComparator | null, value: string): string {
  return comparator === null ? value : `${comparator} ${value}`;
}

/** The m12 number grammar (metric-reading-normalization.ts, DECIMAL_LITERAL). */
const DECIMAL_LITERAL = /^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/;

// Two-character comparators first, so `<=` is not read as `<` and `=`.
const ENTERED_PREFIXES: ReadonlyArray<readonly [string, LabComparator]> = [
  ["<=", "<="],
  [">=", ">="],
  ["≤", "<="],
  ["≥", ">="],
  ["<", "<"],
  [">", ">"]
];

/**
 * Splits `entered` into an optional comparator and the number text. Accepts a
 * leading `<`, `<=`, `≤`, `>`, `>=` or `≥`, optionally followed by one space,
 * then a finite number in the m12 grammar; `≤` and `≥` become `<=` and `>=`.
 * The whole string must match: callers trim it first, as the normaliser does.
 */
export function parseEntered(
  entered: string
): { comparator: LabComparator | null; number: string } | null {
  let comparator: LabComparator | null = null;
  let rest = entered;
  for (const [prefix, parsed] of ENTERED_PREFIXES) {
    if (rest.startsWith(prefix)) {
      comparator = parsed;
      rest = rest.slice(prefix.length);
      if (rest.startsWith(" ")) rest = rest.slice(1);
      break;
    }
  }
  if (!DECIMAL_LITERAL.test(rest) || !Number.isFinite(Number(rest))) return null;
  return { comparator, number: rest };
}

const COLLECTED_PATTERN = /^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2}))?$/;

function daysInMonth(year: number, month: number): number {
  if (month === 2) {
    return year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0) ? 29 : 28;
  }
  return [4, 6, 9, 11].includes(month) ? 30 : 31;
}

/**
 * Whether `collected` is `YYYY-MM-DD` or `YYYY-MM-DDTHH:mm` naming a real date
 * (and, with a time, a real time from 00:00 to 23:59).
 */
export function isValidCollected(collected: string): boolean {
  const match = COLLECTED_PATTERN.exec(collected);
  if (match === null) return false;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  if (month < 1 || month > 12 || day < 1 || day > daysInMonth(year, month)) return false;
  if (match[4] === undefined) return true;
  return Number(match[4]) <= 23 && Number(match[5]) <= 59;
}

/**
 * The time anchor's `localDateTime` for `collected`: a date only becomes
 * `T12:00:00`, a date and time gains `:00` seconds. Throws a RangeError when
 * `collected` is not valid.
 */
export function collectedLocalDateTime(collected: string): string {
  if (!isValidCollected(collected)) {
    throw new RangeError("Invalid collection date.");
  }
  return collected.length === 10 ? `${collected}T12:00:00` : `${collected}:00`;
}

/**
 * One stored Lab Result, as the collapse needs it. `lab` is the stored `lab`
 * object (decoded here with `decodeLab`) or null; times are ISO 8601.
 */
export type LabReadingRef = {
  id: string;
  labTestKey: string;
  lab: unknown;
  atTime: string;
  updatedAt: string;
  deletedAt: string | null;
};

function epochMs(value: string, field: string): number {
  const ms = Date.parse(value);
  if (!Number.isFinite(ms)) {
    throw new RangeError(`Invalid ${field}.`);
  }
  return ms;
}

/**
 * Keeps one row per Lab Result and returns them newest first, as the app's
 * `collapseLabResults` does:
 *
 * 1. rows with a `deletedAt` are dropped;
 * 2. a row whose `lab` does not decode is its own group, keyed by its id;
 * 3. the rest are grouped by the Lab Test key and the `lab.collected` string;
 * 4. each group keeps one row: `final` beats `interim` (and an unknown status,
 *    which ranks as interim); then the later `updatedAt`; then the greater id
 *    by code-unit order (`<` on strings, never `localeCompare`);
 * 5. the kept rows are returned newest first by `atTime`; on an equal
 *    `atTime`, the greater id first.
 *
 * `updatedAt` is compared in whole epoch seconds, `Math.floor(ms / 1000)`,
 * never finer: the app stores it to the second and the server to the
 * millisecond, so a finer comparison would let the app and an Agent keep
 * different rows of one group. `atTime` is ordered by epoch milliseconds.
 */
export function collapseLabResults<T extends LabReadingRef>(readings: readonly T[]): T[] {
  type Candidate = {
    reading: T;
    final: boolean;
    updatedSecond: number;
    atMs: number;
  };
  const kept = new Map<string, Candidate>();
  for (const reading of readings) {
    if (reading.deletedAt !== null && reading.deletedAt !== undefined) continue;
    const lab = decodeLab(reading.lab);
    // The two key spaces cannot collide: a lab key always starts with "lab:".
    const key =
      lab === null
        ? `id:${reading.id}`
        : `lab:${JSON.stringify([reading.labTestKey, lab.collected])}`;
    const candidate: Candidate = {
      reading,
      final: lab !== null && lab.reportStatus === "final",
      updatedSecond: Math.floor(epochMs(reading.updatedAt, "updatedAt") / 1000),
      atMs: epochMs(reading.atTime, "atTime")
    };
    const current = kept.get(key);
    if (current === undefined || beats(candidate, current)) {
      kept.set(key, candidate);
    }
  }
  return [...kept.values()]
    .sort((a, b) => {
      if (a.atMs !== b.atMs) return b.atMs - a.atMs;
      return compareCodeUnits(b.reading.id, a.reading.id);
    })
    .map((candidate) => candidate.reading);
}

function beats(
  candidate: { reading: LabReadingRef; final: boolean; updatedSecond: number },
  current: { reading: LabReadingRef; final: boolean; updatedSecond: number }
): boolean {
  if (candidate.final !== current.final) return candidate.final;
  if (candidate.updatedSecond !== current.updatedSecond) {
    return candidate.updatedSecond > current.updatedSecond;
  }
  return compareCodeUnits(candidate.reading.id, current.reading.id) > 0;
}

function compareCodeUnits(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}
