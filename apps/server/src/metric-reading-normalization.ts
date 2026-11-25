import { labTestByKey } from "./data/lab-test-catalogue.generated.js";
import {
  encodeLab,
  formatEntered,
  isValidCollected,
  parseEntered,
  resolveLabUnit
} from "./lab-results.js";

export type MetricReadingNormalizationInput = {
  metric: {
    valueShape: "scalar" | "structured" | "series";
    unit: string;
    /** Set for a Lab Metric: the Lab Test its readings are results of. */
    labTestKey?: string | null;
  };
  value: {
    shape: "scalar" | "structured" | "series";
    entered?: string;
    unit?: string;
    /** A Lab Result's `lab` object, as sent; only a Lab Metric takes one. */
    lab?: Record<string, unknown> | null;
    fields?: Record<string, { entered: string; unit?: string }>;
    samples?: Array<{ offsetSeconds: number; entered: string; unit?: string }>;
  };
  timeAnchor: {
    atTime?: string;
    windowStartedAt?: string;
    windowEndedAt?: string;
    localDateTime?: string;
    timezoneOffsetMinutes?: number;
  };
};

export type NormalizedMetricReading = {
  valueShape: string;
  unit: string;
  valueJson: string;
  scalarValue: number | null;
  atTime: string | null;
  windowStartedAt: string | null;
  windowEndedAt: string | null;
  warnings: string[];
};

export function normalizeMetricReading(
  input: MetricReadingNormalizationInput
): NormalizedMetricReading {
  const { valueShape, unit } = input.metric;
  const labTestKey = input.metric.labTestKey ?? null;
  if (input.value.shape !== valueShape) {
    throw new Error("Reading value shape must match Metric value shape.");
  }

  const warnings: string[] = [];
  const normalizedValue =
    labTestKey !== null && valueShape === "scalar"
      ? normalizeLabValue({ labTestKey, unit, value: input.value })
      : normalizeValue({
          valueShape,
          unit,
          value: input.value
        });
  const normalizedAnchor = normalizeTimeAnchor(input.timeAnchor, warnings);

  return {
    valueShape,
    unit,
    valueJson: normalizedValue.valueJson,
    scalarValue: normalizedValue.scalarValue,
    atTime: normalizedAnchor.atTime,
    windowStartedAt: normalizedAnchor.windowStartedAt,
    windowEndedAt: normalizedAnchor.windowEndedAt,
    warnings
  };
}

function normalizeValue({
  valueShape,
  unit,
  value
}: {
  valueShape: string;
  unit: string;
  value: MetricReadingNormalizationInput["value"];
}) {
  switch (valueShape) {
    case "scalar": {
      if (value.lab !== undefined && value.lab !== null) {
        throw new Error("Lab fields need a Lab Metric.");
      }
      const normalized = normalizeNumericValue({
        entered: requireString(value.entered, "entered"),
        enteredUnit: value.unit ?? unit,
        targetUnit: unit
      });
      return {
        valueJson: JSON.stringify({
          shape: "scalar",
          unit,
          value: normalized.value,
          entered: normalized.entered,
          enteredUnit: normalized.enteredUnit
        }),
        scalarValue: normalized.value
      };
    }
    case "structured": {
      const fields = requireObject(value.fields, "fields");
      const normalizedFields: Record<string, unknown> = {};
      for (const fieldName of Object.keys(fields).sort()) {
        const field = fields[fieldName];
        const normalized = normalizeNumericValue({
          entered: requireString(field.entered, `${fieldName}.entered`),
          enteredUnit: field.unit ?? unit,
          targetUnit: unit
        });
        normalizedFields[fieldName] = {
          unit,
          value: normalized.value,
          entered: normalized.entered,
          enteredUnit: normalized.enteredUnit
        };
      }
      return {
        valueJson: JSON.stringify({
          shape: "structured",
          fields: normalizedFields
        }),
        scalarValue: null
      };
    }
    case "series": {
      const samples = requireArray(value.samples, "samples")
        .slice()
        .sort((left, right) => left.offsetSeconds - right.offsetSeconds);
      const normalizedSamples = samples.map((sample) => {
        const normalized = normalizeNumericValue({
          entered: requireString(sample.entered, "sample.entered"),
          enteredUnit: sample.unit ?? unit,
          targetUnit: unit
        });
        return {
          offsetSeconds: canonicalNumber(sample.offsetSeconds),
          value: normalized.value,
          entered: normalized.entered,
          enteredUnit: normalized.enteredUnit
        };
      });
      return {
        valueJson: JSON.stringify({
          shape: "series",
          unit,
          samples: normalizedSamples
        }),
        scalarValue: null
      };
    }
    default:
      throw new Error(`Unknown Reading value shape: ${valueShape}.`);
  }
}

/**
 * A Lab Result's value (docs/designs/lab-results.md, "The normaliser"). Every
 * writer validates first (`validateLabResult`), so each throw here is a
 * defensive check a writer reaching it has a bug for; no message names a
 * value. The steps:
 *
 * 1. the entered unit (`value.unit`, else the Metric's) must be the Lab
 *    Test's unit or an alias under the fold; it is stored as sent and never
 *    converted, so `value` is the entered number;
 * 2. a leading comparator (`<`, `<=`, `≤`, `>`, `>=`, `≥`, optionally then a
 *    space) makes a Limit Result: `value` and `scalarValue` are null, the
 *    bound lives in `lab.limit`, `entered` takes the canonical `"< 1"` form,
 *    and any `limit` sent is replaced;
 * 3. the text fields are trimmed with a blank (or a non-string) written as
 *    null, an absent `reportStatus` becomes `final`, and `lab` is written
 *    last, in `encodeLab`'s key order.
 */
function normalizeLabValue({
  labTestKey,
  unit,
  value
}: {
  labTestKey: string;
  unit: string;
  value: MetricReadingNormalizationInput["value"];
}) {
  const labTest = labTestByKey(labTestKey);
  if (labTest === null) {
    throw new Error("Unknown Lab Test.");
  }
  const enteredUnit = value.unit ?? unit;
  if (resolveLabUnit(labTest, enteredUnit) === null) {
    throw new Error("Lab result unit not accepted.");
  }
  const lab = value.lab;
  const collected =
    typeof lab === "object" && lab !== null && !Array.isArray(lab) ? lab.collected : undefined;
  if (typeof collected !== "string" || !isValidCollected(collected)) {
    throw new Error("Lab result collected date is invalid.");
  }
  const parsed = parseEntered(requireString(value.entered, "entered").trim());
  if (parsed === null) {
    throw new Error("Metric Reading value must be finite.");
  }
  const number = canonicalNumber(Number(parsed.number));
  const isLimit = parsed.comparator !== null;
  const reportStatus = lab?.reportStatus;
  return {
    valueJson: JSON.stringify({
      shape: "scalar",
      unit,
      value: isLimit ? null : number,
      entered: formatEntered(parsed.comparator, parsed.number),
      enteredUnit,
      lab: encodeLab({
        collected,
        limit: parsed.comparator === null ? null : { comparator: parsed.comparator, bound: number },
        printedRange: labText(lab?.printedRange),
        printedFlag: labText(lab?.printedFlag),
        reportStatus: typeof reportStatus === "string" ? reportStatus : "final",
        fasting: lab?.fasting === true ? true : null,
        labName: labText(lab?.labName)
      })
    }),
    scalarValue: isLimit ? null : number
  };
}

/** A text field trimmed, with a blank or a non-string as null. */
function labText(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed === "" ? null : trimmed;
}

/**
 * The whole-string number grammar for an entered Metric value. It mirrors the
 * app's Dart `double.tryParse` on finite values: `1.`, `.5`, `+5`, `1e3` and
 * `1E+3` are accepted; trailing text (`"64 %"`, `"1.7 x10^9"`), hex, `_`,
 * `NaN` and `Infinity` are rejected. It is the unambiguous form of the Lab
 * Results spec's `^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$`, written without
 * overlapping quantifiers so a long digit run fails in linear time (`entered`
 * has no maximum length on the Agent surface). Parity with Dart is pinned by
 * the m12 golden vectors.
 */
const DECIMAL_LITERAL = /^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/;

function normalizeNumericValue({
  entered,
  enteredUnit,
  targetUnit
}: {
  entered: string;
  enteredUnit: string;
  targetUnit: string;
}) {
  const trimmed = entered.trim();
  if (!DECIMAL_LITERAL.test(trimmed)) {
    throw new Error("Metric Reading value must be finite.");
  }
  const parsed = Number(trimmed);
  if (!Number.isFinite(parsed)) {
    throw new Error("Metric Reading value must be finite.");
  }
  return {
    entered: trimmed,
    enteredUnit,
    value: canonicalNumber(convertUnit(parsed, enteredUnit, targetUnit))
  };
}

function normalizeTimeAnchor(
  timeAnchor: MetricReadingNormalizationInput["timeAnchor"],
  warnings: string[]
) {
  const hasWindow =
    timeAnchor.windowStartedAt !== undefined ||
    timeAnchor.windowEndedAt !== undefined;
  if (hasWindow) {
    if (timeAnchor.atTime !== undefined) {
      warnings.push("time_anchor_window_preferred");
    }
    if (
      timeAnchor.windowStartedAt === undefined ||
      timeAnchor.windowEndedAt === undefined
    ) {
      throw new Error("Window anchors require start and end times.");
    }
    let start = new Date(timeAnchor.windowStartedAt);
    let end = new Date(timeAnchor.windowEndedAt);
    if (end.getTime() < start.getTime()) {
      const originalStart = start;
      start = end;
      end = originalStart;
      warnings.push("window_bounds_reordered");
    }
    return {
      atTime: null,
      windowStartedAt: isoUtc(start),
      windowEndedAt: isoUtc(end)
    };
  }
  if (timeAnchor.atTime !== undefined) {
    return {
      atTime: isoUtc(new Date(timeAnchor.atTime)),
      windowStartedAt: null,
      windowEndedAt: null
    };
  }
  if (timeAnchor.localDateTime !== undefined) {
    if (timeAnchor.timezoneOffsetMinutes === undefined) {
      throw new Error("Local time anchors require timezoneOffsetMinutes.");
    }
    const localUtc = parseLocalDateTimeAsUtc(timeAnchor.localDateTime);
    return {
      atTime: isoUtc(
        new Date(
          localUtc.getTime() - timeAnchor.timezoneOffsetMinutes * 60 * 1000
        )
      ),
      windowStartedAt: null,
      windowEndedAt: null
    };
  }
  throw new Error("Reading requires an instant or window time anchor.");
}

function parseLocalDateTimeAsUtc(value: string) {
  const match =
    /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?$/.exec(
      value
    );
  if (match === null) {
    throw new Error(`Invalid local time: ${value}.`);
  }
  const [, year, month, day, hour, minute, second, fraction = "0"] = match;
  const milliseconds = Number.parseInt(fraction.padEnd(3, "0").slice(0, 3), 10);
  return new Date(
    Date.UTC(
      Number.parseInt(year, 10),
      Number.parseInt(month, 10) - 1,
      Number.parseInt(day, 10),
      Number.parseInt(hour, 10),
      Number.parseInt(minute, 10),
      Number.parseInt(second, 10),
      milliseconds
    )
  );
}

function isoUtc(value: Date) {
  return value.toISOString();
}

function convertUnit(value: number, from: string, to: string) {
  if (from === to) {
    return value;
  }
  if (from === "pound" && to === "kilogram") {
    return value * 0.45359237;
  }
  if (from === "kilogram" && to === "pound") {
    return value / 0.45359237;
  }
  if (from === "inch" && to === "centimeter") {
    return value * 2.54;
  }
  if (from === "centimeter" && to === "inch") {
    return value / 2.54;
  }
  throw new Error(`Cannot convert Metric Reading unit ${from} to ${to}.`);
}

function canonicalNumber(value: number) {
  const rounded = Number(value.toFixed(10));
  return Number.isInteger(rounded) ? Math.trunc(rounded) : rounded;
}

function requireString(value: unknown, key: string) {
  if (typeof value !== "string") {
    throw new Error(`${key} must be a string.`);
  }
  return value;
}

function requireObject<T extends Record<string, unknown>>(
  value: T | undefined,
  key: string
): T {
  if (value === undefined || value === null || typeof value !== "object") {
    throw new Error(`${key} must be an object.`);
  }
  return value;
}

function requireArray<T>(value: T[] | undefined, key: string): T[] {
  if (!Array.isArray(value)) {
    throw new Error(`${key} must be an array.`);
  }
  return value;
}
