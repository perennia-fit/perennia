import * as Sentry from "@sentry/node";
import { randomUUID } from "node:crypto";

export const CORRELATION_ID_HEADER = "x-correlation-id";
export const FILTERED_OBSERVABILITY_VALUE = "[Filtered]";

export type StructuredLogger = {
  info(payload: Record<string, unknown>, message: string): void;
  error?(payload: Record<string, unknown>, message: string): void;
  warn?(payload: Record<string, unknown>, message: string): void;
  fatal?(payload: Record<string, unknown>, message: string): void;
};

export type CrashReportContext = {
  correlationId: string;
  method: string;
  path: string;
  userId?: string;
};

export type CrashReporter = {
  captureException(error: unknown, context: CrashReportContext): void;
};

type SentryLikeScope = {
  setTag(key: string, value: string): void;
  setUser(user: { id: string } | null): void;
  setContext(key: string, context: Record<string, unknown>): void;
  setExtra(key: string, value: unknown): void;
};

type SentryLikeSdk = {
  init(options: Record<string, unknown>): unknown;
  withScope(callback: (scope: SentryLikeScope) => void): void;
  captureException(error: unknown): unknown;
};

export type CrashReportingEnv = Record<string, string | undefined>;

export type CreateSentryCrashReporterOptions = {
  release?: string;
  sdk?: SentryLikeSdk;
};

export function createPrivacyLogger(logger: StructuredLogger): StructuredLogger {
  return {
    info(payload, message) {
      logger.info(scrubLogPayload(payload), message);
    },
    error:
      logger.error === undefined
        ? undefined
        : (payload, message) => {
            logger.error?.(scrubLogPayload(payload), message);
          },
    warn:
      logger.warn === undefined
        ? undefined
        : (payload, message) => {
            logger.warn?.(scrubLogPayload(payload), message);
          },
    fatal:
      logger.fatal === undefined
        ? undefined
        : (payload, message) => {
            logger.fatal?.(scrubLogPayload(payload), message);
          }
  };
}

export function createSentryCrashReporterFromEnv(
  env: CrashReportingEnv = process.env,
  { release, sdk = Sentry }: CreateSentryCrashReporterOptions = {}
): CrashReporter | undefined {
  const config = readCrashReportingConfig(env);
  if (config === undefined) {
    return undefined;
  }

  sdk.init({
    dsn: config.dsn,
    enabled: true,
    environment: env.NODE_ENV,
    release,
    sendDefaultPii: false,
    beforeSend(event: unknown) {
      return scrubObservabilityData(event);
    }
  });

  return {
    captureException(error, context) {
      sdk.withScope((scope) => {
        scope.setTag("correlation_id", context.correlationId);
        scope.setContext("request", {
          method: context.method,
          path: safeRequestPath(context.path)
        });
        scope.setExtra("request", scrubObservabilityData(context));
        scope.setExtra("error", serializeErrorForObservability(error));
        if (context.userId !== undefined) {
          scope.setUser({ id: context.userId });
        }

        sdk.captureException(error);
      });
    }
  };
}

export function resolveCorrelationId(headerValue: string | undefined): string {
  const candidate = headerValue?.trim();
  if (
    candidate !== undefined &&
    candidate.length > 0 &&
    candidate.length <= 200 &&
    /^[A-Za-z0-9._:-]+$/.test(candidate)
  ) {
    return candidate;
  }

  return randomUUID();
}

export function safeRequestPath(pathOrUrl: string): string {
  const withoutQuery = requestPathname(pathOrUrl);

  return withoutQuery
    .replace(
      /\/agent\/analytics\/exercises\/[^/]+/g,
      "/agent/analytics/exercises/:exerciseId"
    )
    .replace(
      /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi,
      ":id"
    );
}

export function scrubObservabilityData(value: unknown): unknown {
  return scrubValue(value, new WeakSet<object>(), undefined);
}

function readCrashReportingConfig(env: CrashReportingEnv) {
  const enabled = truthy(
    env.SERVER_CRASH_REPORTING_ENABLED ??
      env.CRASH_REPORTING_ENABLED ??
      env.SENTRY_ENABLED
  );
  const dsn =
    nonEmpty(env.SERVER_CRASH_REPORTING_DSN) ??
    nonEmpty(env.CRASH_REPORTING_DSN) ??
    nonEmpty(env.SENTRY_DSN);

  if (!enabled || dsn === undefined) {
    return undefined;
  }

  return { dsn };
}

function scrubLogPayload(payload: Record<string, unknown>): Record<string, unknown> {
  const scrubbed = scrubObservabilityData(payload);
  return isRecord(scrubbed) ? scrubbed : { value: scrubbed };
}

function scrubValue(
  value: unknown,
  seen: WeakSet<object>,
  key: string | undefined
): unknown {
  const normalized = normalizedKey(key);
  if (key !== undefined && shouldFilterKey(key)) {
    return FILTERED_OBSERVABILITY_VALUE;
  }
  if (typeof value === "string" && (normalized === "path" || normalized === "url")) {
    return safeRequestPath(value);
  }
  if (value === null || typeof value !== "object") {
    return value;
  }
  if (value instanceof Date) {
    return value.toISOString();
  }
  if (value instanceof Error) {
    return serializeErrorForObservability(value);
  }
  if (seen.has(value)) {
    return "[Circular]";
  }

  seen.add(value);

  if (Array.isArray(value)) {
    return value.map((item) => scrubValue(item, seen, undefined));
  }

  if (normalizedKey(key) === "user") {
    return scrubUser(value);
  }

  const result: Record<string, unknown> = {};
  for (const [entryKey, entryValue] of Object.entries(value)) {
    const normalizedEntryKey = normalizedKey(entryKey);
    if (
      typeof entryValue === "string" &&
      (normalizedEntryKey === "path" || normalizedEntryKey === "url")
    ) {
      result[entryKey] = safeRequestPath(entryValue);
      continue;
    }

    result[entryKey] = scrubValue(entryValue, seen, entryKey);
  }

  return result;
}

function scrubUser(value: object) {
  if (!isRecord(value)) {
    return FILTERED_OBSERVABILITY_VALUE;
  }

  const id = value.id ?? value.userId;
  return typeof id === "string" && id.length > 0
    ? { id }
    : FILTERED_OBSERVABILITY_VALUE;
}

function serializeErrorForObservability(error: unknown): unknown {
  if (!(error instanceof Error)) {
    return scrubObservabilityData(error);
  }

  return scrubObservabilityData({
    name: error.name,
    message: error.message,
    stack: error.stack,
    ...Object.fromEntries(Object.entries(error))
  });
}

function shouldFilterKey(key: string) {
  const normalized = normalizedKey(key);

  return (
    PII_KEYS.has(normalized) ||
    TRAINING_DATA_KEYS.has(normalized) ||
    COMMENT_KEYS.has(normalized)
  );
}

function requestPathname(pathOrUrl: string) {
  try {
    if (pathOrUrl.startsWith("http://") || pathOrUrl.startsWith("https://")) {
      return new URL(pathOrUrl).pathname;
    }
    if (pathOrUrl.startsWith("/")) {
      return new URL(pathOrUrl, "http://localhost").pathname;
    }
  } catch {
    // Fall through to the conservative query-stripping path below.
  }

  return pathOrUrl.split("?")[0] ?? pathOrUrl;
}

function normalizedKey(key: string | undefined) {
  return key?.toLowerCase().replace(/[^a-z0-9]/g, "") ?? "";
}

function truthy(value: string | undefined) {
  return value === "true" || value === "1" || value === "yes";
}

function nonEmpty(value: string | undefined) {
  return value === undefined || value.trim().length === 0
    ? undefined
    : value.trim();
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

const PII_KEYS = new Set([
  "authorization",
  "cookie",
  "email",
  "fullname",
  "ip",
  "ipaddress",
  "name",
  "password",
  "phone",
  "querystring",
  "secret",
  "setcookie",
  "token",
  "username"
]);

const COMMENT_KEYS = new Set(["comment", "comments", "note", "notes"]);

const TRAINING_DATA_KEYS = new Set([
  "activity",
  "afterimage",
  "beforeimage",
  "bodymeasurement",
  "bodymeasurements",
  "calories",
  "changes",
  "distance",
  "duration",
  "exercise",
  "exerciseid",
  "exercisename",
  "exercisequery",
  "externalactivity",
  "food",
  "foodentries",
  "foodentry",
  "foods",
  "loggedset",
  "loggedsets",
  "load",
  "meal",
  "meals",
  "measurement",
  "measurements",
  "metric",
  "metrics",
  "monitoringdata",
  "nutrition",
  "pace",
  "payload",
  "recipe",
  "reps",
  "rpe",
  "set",
  "sets",
  "unit",
  "value",
  "weight",
  "trainingday",
  "workout",
  "workouts",
  // Protocols domain (PROTOCOLS.md §8): the strictest privacy tier —
  // Protocols values must NEVER appear in logs or crash reports. Denies the
  // authored intake (Dose), its catalogue (Compound), the plan (Protocol/
  // Schedule), and the fields carrying dose magnitudes/routes/strengths. Key
  // names are normalized (lowercased, non-alphanumerics stripped) before lookup,
  // so e.g. `compound_name` matches `compoundname`.
  "compound",
  "compounds",
  "compoundid",
  "compoundname",
  "compoundstrength",
  "dose",
  "doses",
  "doseid",
  "doseamount",
  "doseamountentered",
  "doseamountvalue",
  "amount",
  "amountentered",
  "amountvalue",
  "route",
  "strength",
  "protocol",
  "protocols",
  "protocolid",
  "protocolname",
  "protocolcompound",
  "protocolcompounds",
  "protocolcompoundid",
  "protocoltargetoutcome",
  "protocoltargetoutcomes",
  "targetoutcome",
  "targetoutcomes",
  "outcomekind",
  "schedule",
  "schedules",
  "effectwindow",
  "tookat"
]);
