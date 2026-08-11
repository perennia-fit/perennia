import { createHash } from "node:crypto";

import {
  CanonicalActivitySchema,
  CanonicalSeriesSchema,
  type CanonicalActivity,
  type CanonicalMetricReading,
  type CanonicalSeries,
  type CanonicalSet
} from "./canonical-import.js";

const FIT_EPOCH_MS = Date.UTC(1989, 11, 31, 0, 0, 0);
const FIT_TIMESTAMP_FIELD = 253;

type GarminFitImportOptions = {
  source?: string;
  timezone?: string;
};

export type GarminFitCanonicalImport = {
  activities: CanonicalActivity[];
  metricReadings: CanonicalMetricReading[];
  series: CanonicalSeries[];
};

type FitFieldDefinition = {
  fieldNumber: number;
  size: number;
  baseType: number;
};

type FitDeveloperFieldDefinition = {
  size: number;
};

type FitMessageDefinition = {
  globalMessageNumber: number;
  littleEndian: boolean;
  fields: FitFieldDefinition[];
  developerFields: FitDeveloperFieldDefinition[];
};

type FitDataMessage = {
  globalMessageNumber: number;
  fields: Map<number, FitFieldValue>;
};

type FitFieldValue = number | string | Array<number | string>;

export function parseGarminFitActivityFile(
  input: ArrayBuffer | Uint8Array,
  { source = "garmin", timezone = "UTC" }: GarminFitImportOptions = {}
): GarminFitCanonicalImport {
  const buffer = toBuffer(input);
  const messages = parseFitDataMessages(buffer);
  const activity = buildCanonicalActivity({
    buffer,
    messages,
    source,
    timezone
  });
  const series = buildCanonicalSeries({ activity, messages, source, timezone });

  return {
    activities: [activity],
    metricReadings: [],
    series
  };
}

function parseFitDataMessages(buffer: Buffer): FitDataMessage[] {
  if (buffer.byteLength < 14) {
    throw new Error("FIT file is too small to contain a header.");
  }

  const headerSize = buffer.readUInt8(0);
  if (headerSize !== 12 && headerSize !== 14) {
    throw new Error(`Unsupported FIT header size: ${headerSize}.`);
  }
  if (buffer.toString("ascii", 8, 12) !== ".FIT") {
    throw new Error("Input is not a FIT file.");
  }

  const dataSize = buffer.readUInt32LE(4);
  const dataStart = headerSize;
  const dataEnd = dataStart + dataSize;
  if (dataEnd > buffer.byteLength) {
    throw new Error("FIT data section is truncated.");
  }

  const definitions = new Map<number, FitMessageDefinition>();
  const messages: FitDataMessage[] = [];
  let offset = dataStart;
  let lastTimestamp: number | null = null;

  while (offset < dataEnd) {
    const recordHeader = buffer.readUInt8(offset);
    offset += 1;

    if ((recordHeader & 0x80) !== 0) {
      const localMessageType = (recordHeader >> 5) & 0x03;
      const timeOffset = recordHeader & 0x1f;
      const compressedTimestamp = expandCompressedTimestamp(
        lastTimestamp,
        timeOffset
      );
      const parsed = readFitDataMessage({
        buffer,
        definitions,
        localMessageType,
        offset
      });
      offset = parsed.offset;
      parsed.message.fields.set(FIT_TIMESTAMP_FIELD, compressedTimestamp);
      lastTimestamp = compressedTimestamp;
      messages.push(parsed.message);
      continue;
    }

    const isDefinition = (recordHeader & 0x40) !== 0;
    const localMessageType = recordHeader & 0x0f;
    if (isDefinition) {
      const parsed = readFitDefinitionMessage({
        buffer,
        localMessageType,
        offset,
        hasDeveloperFields: (recordHeader & 0x20) !== 0
      });
      offset = parsed.offset;
      definitions.set(localMessageType, parsed.definition);
      continue;
    }

    const parsed = readFitDataMessage({
      buffer,
      definitions,
      localMessageType,
      offset
    });
    offset = parsed.offset;
    const timestamp = numberField(parsed.message, FIT_TIMESTAMP_FIELD);
    if (timestamp !== null) {
      lastTimestamp = timestamp;
    }
    messages.push(parsed.message);
  }

  return messages;
}

function readFitDefinitionMessage({
  buffer,
  localMessageType,
  offset,
  hasDeveloperFields
}: {
  buffer: Buffer;
  localMessageType: number;
  offset: number;
  hasDeveloperFields: boolean;
}): { definition: FitMessageDefinition; offset: number } {
  ensureAvailable(buffer, offset, 5);
  offset += 1; // reserved
  const architecture = buffer.readUInt8(offset);
  offset += 1;
  const littleEndian = architecture === 0;
  const globalMessageNumber = readUnsignedInteger({
    buffer,
    offset,
    size: 2,
    littleEndian
  });
  offset += 2;
  const fieldCount = buffer.readUInt8(offset);
  offset += 1;

  const fields: FitFieldDefinition[] = [];
  ensureAvailable(buffer, offset, fieldCount * 3);
  for (let index = 0; index < fieldCount; index += 1) {
    fields.push({
      fieldNumber: buffer.readUInt8(offset),
      size: buffer.readUInt8(offset + 1),
      baseType: buffer.readUInt8(offset + 2)
    });
    offset += 3;
  }

  const developerFields: FitDeveloperFieldDefinition[] = [];
  if (hasDeveloperFields) {
    ensureAvailable(buffer, offset, 1);
    const developerFieldCount = buffer.readUInt8(offset);
    offset += 1;
    ensureAvailable(buffer, offset, developerFieldCount * 3);
    for (let index = 0; index < developerFieldCount; index += 1) {
      developerFields.push({
        size: buffer.readUInt8(offset + 1)
      });
      offset += 3;
    }
  }

  return {
    definition: {
      globalMessageNumber,
      littleEndian,
      fields,
      developerFields
    },
    offset
  };
}

function readFitDataMessage({
  buffer,
  definitions,
  localMessageType,
  offset
}: {
  buffer: Buffer;
  definitions: Map<number, FitMessageDefinition>;
  localMessageType: number;
  offset: number;
}): { message: FitDataMessage; offset: number } {
  const definition = definitions.get(localMessageType);
  if (definition === undefined) {
    throw new Error(
      `FIT data message referenced undefined local message type ${localMessageType}.`
    );
  }

  const fields = new Map<number, FitFieldValue>();
  for (const field of definition.fields) {
    ensureAvailable(buffer, offset, field.size);
    const value = readFitFieldValue({
      buffer,
      field,
      littleEndian: definition.littleEndian,
      offset
    });
    if (value !== undefined) {
      fields.set(field.fieldNumber, value);
    }
    offset += field.size;
  }

  for (const developerField of definition.developerFields) {
    ensureAvailable(buffer, offset, developerField.size);
    offset += developerField.size;
  }

  return {
    message: {
      globalMessageNumber: definition.globalMessageNumber,
      fields
    },
    offset
  };
}

function readFitFieldValue({
  buffer,
  field,
  littleEndian,
  offset
}: {
  buffer: Buffer;
  field: FitFieldDefinition;
  littleEndian: boolean;
  offset: number;
}): FitFieldValue | undefined {
  const type = fitBaseType(field.baseType);
  if (type.name === "string") {
    return readFitString(buffer.subarray(offset, offset + field.size));
  }

  const values: number[] = [];
  const count = Math.floor(field.size / type.size);
  for (let index = 0; index < count; index += 1) {
    const value = readBaseTypeNumber({
      buffer,
      offset: offset + index * type.size,
      size: type.size,
      signed: type.signed,
      floating: type.floating,
      littleEndian
    });
    if (!isInvalidFitValue(value, type)) {
      values.push(value);
    }
  }

  if (values.length === 0) {
    return undefined;
  }

  return values.length === 1 ? values[0] : values;
}

function buildCanonicalActivity({
  buffer,
  messages,
  source,
  timezone
}: {
  buffer: Buffer;
  messages: FitDataMessage[];
  source: string;
  timezone: string;
}): CanonicalActivity {
  const fileId = firstMessage(messages, 0);
  const session = lastMessage(messages, 18);
  if (session === null) {
    throw new Error("FIT activity file does not contain a session message.");
  }

  const startSeconds =
    numberField(session, 2) ??
    firstTimestamp(messages) ??
    numberField(fileId, 4);
  if (startSeconds === null) {
    throw new Error("FIT activity file does not contain an activity start time.");
  }

  const durationSeconds =
    scaledNumberField(session, 8, 1000) ??
    scaledNumberField(session, 7, 1000);
  const endSeconds =
    durationSeconds === null
      ? numberField(session, FIT_TIMESTAMP_FIELD) ?? startSeconds
      : startSeconds + durationSeconds;
  const startedAt = fitTimestampToIso(startSeconds);
  const endedAt = fitTimestampToIso(endSeconds);
  const externalId = fitExternalId({
    buffer,
    fileId,
    startedAt
  });
  const summary = optionalObject({
    distance: metricValue(scaledNumberField(session, 9, 100), "meter"),
    duration: metricValue(durationSeconds, "second")
  });
  const summaryMetrics = buildSummaryMetrics({
    externalId,
    session,
    source,
    startedAt,
    endedAt,
    timezone
  });
  const sets = buildCanonicalSets({
    externalId,
    messages,
    source,
    timezone
  });

  return CanonicalActivitySchema.parse(
    optionalObject({
      source,
      externalId,
      startedAt,
      endedAt,
      timezone,
      activityType: fitActivityType(session),
      summary,
      summaryMetrics,
      sets: sets.length > 0 ? sets : undefined
    })
  );
}

function buildSummaryMetrics({
  externalId,
  session,
  source,
  startedAt,
  endedAt,
  timezone
}: {
  externalId: string;
  session: FitDataMessage;
  source: string;
  startedAt: string;
  endedAt: string;
  timezone: string;
}): CanonicalActivity["summaryMetrics"] {
  const at = {
    kind: "window" as const,
    startedAt,
    endedAt,
    timezone
  };
  const metrics = [
    ["averageHeartRate", numberField(session, 16), "beatsPerMinute"],
    ["maxHeartRate", numberField(session, 17), "beatsPerMinute"],
    ["activeKilocalories", numberField(session, 11), "kilocalorie"],
    ["averageCadence", numberField(session, 18), "revolutionsPerMinute"],
    ["maxCadence", numberField(session, 19), "revolutionsPerMinute"],
    ["averagePower", numberField(session, 20), "watt"],
    ["maxPower", numberField(session, 21), "watt"]
  ] as const;

  return metrics.flatMap(([metricKey, value, unit]) =>
    value === null
      ? []
      : [
          {
            source,
            externalId: `${externalId}:summary:${metricKey}`,
            metricKey,
            value: { value, unit },
            at
          }
        ]
  );
}

function buildCanonicalSets({
  externalId,
  messages,
  source,
  timezone
}: {
  externalId: string;
  messages: FitDataMessage[];
  source: string;
  timezone: string;
}): CanonicalSet[] {
  return messages
    .filter((message) => message.globalMessageNumber === 225)
    .map((message, index) => {
      const performedAtSeconds =
        numberField(message, 2) ?? numberField(message, FIT_TIMESTAMP_FIELD);
      const reps = numberField(message, 3);
      const weight = scaledNumberField(message, 4, 16);
      return {
        source,
        externalId: `${externalId}:set:${index + 1}`,
        timezone,
        performedAt:
          performedAtSeconds === null
            ? undefined
            : fitTimestampToIso(performedAtSeconds),
        dimensions: optionalObject({
          load: metricValue(weight, "kilogram"),
          reps:
            reps === null
              ? undefined
              : {
                  value: reps,
                  unit: "repetition" as const
                }
        })
      };
    })
    .filter((set) => Object.keys(set.dimensions).length > 0)
    .map((set) => ({
      ...set,
      dimensions: set.dimensions
    }));
}

function buildCanonicalSeries({
  activity,
  messages,
  source,
  timezone
}: {
  activity: CanonicalActivity;
  messages: FitDataMessage[];
  source: string;
  timezone: string;
}): CanonicalSeries[] {
  const records = messages.filter((message) => message.globalMessageNumber === 20);
  const builders = [
    scalarSeriesBuilder("heartRate", 3, "beatsPerMinute"),
    locationSeriesBuilder(),
    scalarSeriesBuilder("cadence", 4, "revolutionsPerMinute"),
    scalarSeriesBuilder("power", 7, "watt"),
    speedSeriesBuilder(),
    elevationSeriesBuilder()
  ];

  return builders.flatMap((builder) => {
    const samples = records.flatMap((record) => {
      const timestamp = numberField(record, FIT_TIMESTAMP_FIELD);
      if (timestamp === null) {
        return [];
      }
      const value = builder.value(record);
      return value === null
        ? []
        : [
            {
              timestamp,
              value
            }
          ];
    });

    if (samples.length === 0) {
      return [];
    }

    const baseTime = samples[0].timestamp;
    return [
      CanonicalSeriesSchema.parse({
        source,
        externalId: `${activity.externalId}:series:${builder.type}`,
        type: builder.type,
        anchor: {
          kind: "activity",
          source,
          externalId: activity.externalId
        },
        baseTime: fitTimestampToIso(baseTime),
        timezone,
        samples: samples.map((sample) => ({
          offsetSeconds: roundNumber(sample.timestamp - baseTime),
          value: sample.value
        }))
      })
    ];
  });
}

type SeriesBuilder = {
  type: CanonicalSeries["type"];
  value(record: FitDataMessage): CanonicalSeries["samples"][number]["value"] | null;
};

function scalarSeriesBuilder(
  type: CanonicalSeries["type"],
  fieldNumber: number,
  unit: string
): SeriesBuilder {
  return {
    type,
    value(record) {
      return metricValue(numberField(record, fieldNumber), unit) ?? null;
    }
  };
}

function locationSeriesBuilder(): SeriesBuilder {
  return {
    type: "location",
    value(record) {
      const latitude = semicirclesToDegrees(numberField(record, 0));
      const longitude = semicirclesToDegrees(numberField(record, 1));
      if (latitude === null || longitude === null) {
        return null;
      }

      return {
        latitude: { value: latitude, unit: "degree" },
        longitude: { value: longitude, unit: "degree" }
      };
    }
  };
}

function speedSeriesBuilder(): SeriesBuilder {
  return {
    type: "speed",
    value(record) {
      const speed =
        scaledNumberField(record, 73, 1000) ??
        scaledNumberField(record, 6, 1000);
      return metricValue(speed, "meterPerSecond") ?? null;
    }
  };
}

function elevationSeriesBuilder(): SeriesBuilder {
  return {
    type: "elevation",
    value(record) {
      const enhancedAltitude = scaledOffsetNumberField(record, 78, 5, 500);
      const altitude = scaledOffsetNumberField(record, 2, 5, 500);
      return metricValue(enhancedAltitude ?? altitude, "meter") ?? null;
    }
  };
}

function firstMessage(messages: FitDataMessage[], globalMessageNumber: number) {
  return (
    messages.find((message) => message.globalMessageNumber === globalMessageNumber) ??
    null
  );
}

function lastMessage(messages: FitDataMessage[], globalMessageNumber: number) {
  return (
    messages
      .slice()
      .reverse()
      .find((message) => message.globalMessageNumber === globalMessageNumber) ?? null
  );
}

function firstTimestamp(messages: FitDataMessage[]) {
  for (const message of messages) {
    const timestamp = numberField(message, FIT_TIMESTAMP_FIELD);
    if (timestamp !== null) {
      return timestamp;
    }
  }

  return null;
}

function fitExternalId({
  buffer,
  fileId,
  startedAt
}: {
  buffer: Buffer;
  fileId: FitDataMessage | null;
  startedAt: string;
}) {
  const serialNumber = numberField(fileId, 3);
  if (serialNumber !== null) {
    return `fit:${serialNumber}:${startedAt}`;
  }

  return `fit:${createHash("sha256").update(buffer).digest("hex").slice(0, 16)}:${startedAt}`;
}

function fitActivityType(session: FitDataMessage) {
  const subSport = numberField(session, 6);
  const sport = numberField(session, 5);
  const subSportName =
    subSport === null ? null : FIT_SUB_SPORT_NAMES.get(subSport);
  if (subSportName !== null && subSportName !== undefined && subSportName !== "generic") {
    return subSportName;
  }

  return sport === null ? "generic" : FIT_SPORT_NAMES.get(sport) ?? `sport_${sport}`;
}

const FIT_SPORT_NAMES = new Map([
  [0, "generic"],
  [1, "running"],
  [2, "cycling"],
  [4, "fitness_equipment"],
  [5, "swimming"],
  [10, "training"],
  [11, "walking"],
  [15, "rowing"],
  [17, "hiking"],
  [31, "rock_climbing"],
  [37, "stand_up_paddleboarding"],
  [41, "kayaking"]
]);

const FIT_SUB_SPORT_NAMES = new Map([
  [0, "generic"],
  [1, "treadmill_running"],
  [2, "road_running"],
  [3, "trail_running"],
  [4, "track_running"],
  [5, "spin"],
  [6, "indoor_cycling"],
  [7, "road_biking"],
  [14, "indoor_rowing"],
  [17, "lap_swimming"],
  [18, "open_water_swimming"],
  [19, "flexibility_training"],
  [20, "strength_training"],
  [26, "cardio_training"],
  [45, "indoor_running"],
  [46, "gravel_cycling"],
  [58, "virtual_activity"],
  [67, "ultra_running"]
]);

function numberField(message: FitDataMessage | null, fieldNumber: number) {
  if (message === null) {
    return null;
  }

  const value = message.fields.get(fieldNumber);
  if (typeof value === "number") {
    return value;
  }
  if (Array.isArray(value) && typeof value[0] === "number") {
    return value[0];
  }

  return null;
}

function scaledNumberField(
  message: FitDataMessage | null,
  fieldNumber: number,
  scale: number
) {
  const value = numberField(message, fieldNumber);
  return value === null ? null : roundNumber(value / scale);
}

function scaledOffsetNumberField(
  message: FitDataMessage | null,
  fieldNumber: number,
  scale: number,
  offset: number
) {
  const value = numberField(message, fieldNumber);
  return value === null ? null : roundNumber(value / scale - offset);
}

function metricValue<Unit extends string>(
  value: number | null,
  unit: Unit
): { value: number; unit: Unit } | undefined {
  return value === null ? undefined : { value, unit };
}

function optionalObject<T extends Record<string, unknown>>(input: T) {
  return Object.fromEntries(
    Object.entries(input).filter(([, value]) => value !== undefined)
  ) as {
    [K in keyof T as T[K] extends undefined ? never : K]: Exclude<
      T[K],
      undefined
    >;
  };
}

function fitTimestampToIso(timestampSeconds: number) {
  return new Date(FIT_EPOCH_MS + timestampSeconds * 1000).toISOString();
}

function semicirclesToDegrees(value: number | null) {
  return value === null ? null : roundNumber((value * 180) / 2 ** 31, 6);
}

function expandCompressedTimestamp(
  lastTimestamp: number | null,
  timeOffset: number
) {
  if (lastTimestamp === null) {
    return timeOffset;
  }

  let timestamp = (lastTimestamp & ~0x1f) + timeOffset;
  if (timestamp < lastTimestamp) {
    timestamp += 32;
  }

  return timestamp;
}

function fitBaseType(baseType: number) {
  const baseTypeNumber = baseType & 0x1f;
  switch (baseTypeNumber) {
    case 0:
      return { name: "enum", size: 1, signed: false, floating: false };
    case 1:
      return { name: "sint8", size: 1, signed: true, floating: false };
    case 2:
      return { name: "uint8", size: 1, signed: false, floating: false };
    case 3:
      return { name: "sint16", size: 2, signed: true, floating: false };
    case 4:
      return { name: "uint16", size: 2, signed: false, floating: false };
    case 5:
      return { name: "sint32", size: 4, signed: true, floating: false };
    case 6:
      return { name: "uint32", size: 4, signed: false, floating: false };
    case 7:
      return { name: "string", size: 1, signed: false, floating: false };
    case 8:
      return { name: "float32", size: 4, signed: true, floating: true };
    case 9:
      return { name: "float64", size: 8, signed: true, floating: true };
    case 10:
      return { name: "uint8z", size: 1, signed: false, floating: false };
    case 11:
      return { name: "uint16z", size: 2, signed: false, floating: false };
    case 12:
      return { name: "uint32z", size: 4, signed: false, floating: false };
    case 13:
      return { name: "byte", size: 1, signed: false, floating: false };
    case 14:
      return { name: "sint64", size: 8, signed: true, floating: false };
    case 15:
      return { name: "uint64", size: 8, signed: false, floating: false };
    case 16:
      return { name: "uint64z", size: 8, signed: false, floating: false };
    default:
      throw new Error(`Unsupported FIT base type: ${baseType}.`);
  }
}

function readBaseTypeNumber({
  buffer,
  offset,
  size,
  signed,
  floating,
  littleEndian
}: {
  buffer: Buffer;
  offset: number;
  size: number;
  signed: boolean;
  floating: boolean;
  littleEndian: boolean;
}) {
  if (floating) {
    return size === 4
      ? littleEndian
        ? buffer.readFloatLE(offset)
        : buffer.readFloatBE(offset)
      : littleEndian
        ? buffer.readDoubleLE(offset)
        : buffer.readDoubleBE(offset);
  }

  if (size === 8) {
    const value = signed
      ? littleEndian
        ? buffer.readBigInt64LE(offset)
        : buffer.readBigInt64BE(offset)
      : littleEndian
        ? buffer.readBigUInt64LE(offset)
        : buffer.readBigUInt64BE(offset);
    return Number(value);
  }

  return signed
    ? readSignedInteger({ buffer, offset, size, littleEndian })
    : readUnsignedInteger({ buffer, offset, size, littleEndian });
}

function readUnsignedInteger({
  buffer,
  offset,
  size,
  littleEndian
}: {
  buffer: Buffer;
  offset: number;
  size: number;
  littleEndian: boolean;
}) {
  return littleEndian
    ? buffer.readUIntLE(offset, size)
    : buffer.readUIntBE(offset, size);
}

function readSignedInteger({
  buffer,
  offset,
  size,
  littleEndian
}: {
  buffer: Buffer;
  offset: number;
  size: number;
  littleEndian: boolean;
}) {
  return littleEndian
    ? buffer.readIntLE(offset, size)
    : buffer.readIntBE(offset, size);
}

function isInvalidFitValue(
  value: number,
  type: ReturnType<typeof fitBaseType>
) {
  if (Number.isNaN(value)) {
    return true;
  }

  switch (type.name) {
    case "enum":
    case "uint8":
      return value === 0xff;
    case "uint8z":
      return value === 0;
    case "uint16":
      return value === 0xffff;
    case "uint16z":
      return value === 0;
    case "uint32":
      return value === 0xffffffff;
    case "uint32z":
      return value === 0;
    case "sint8":
      return value === 0x7f;
    case "sint16":
      return value === 0x7fff;
    case "sint32":
      return value === 0x7fffffff;
    default:
      return false;
  }
}

function readFitString(bytes: Buffer) {
  const terminator = bytes.indexOf(0);
  return bytes
    .subarray(0, terminator === -1 ? bytes.byteLength : terminator)
    .toString("utf8");
}

function ensureAvailable(buffer: Buffer, offset: number, byteLength: number) {
  if (offset + byteLength > buffer.byteLength) {
    throw new Error("FIT file ended while reading a record.");
  }
}

function toBuffer(input: ArrayBuffer | Uint8Array) {
  if (Buffer.isBuffer(input)) {
    return input;
  }
  if (input instanceof ArrayBuffer) {
    return Buffer.from(input);
  }

  return Buffer.from(input.buffer, input.byteOffset, input.byteLength);
}

function roundNumber(value: number, precision = 4) {
  const multiplier = 10 ** precision;
  return Math.round(value * multiplier) / multiplier;
}
