export type MetricReadingNormalizationInput = {
  metric: {
    valueShape: "scalar" | "structured" | "series";
    unit: string;
  };
  value: {
    shape: "scalar" | "structured" | "series";
    entered?: string;
    unit?: string;
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
  if (input.value.shape !== valueShape) {
    throw new Error("Reading value shape must match Metric value shape.");
  }

  const warnings: string[] = [];
  const normalizedValue = normalizeValue({
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
  const parsed = Number.parseFloat(trimmed);
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
