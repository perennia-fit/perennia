import { createHash } from "node:crypto";
import { createRoute, z } from "@hono/zod-openapi";

import { CanonicalImportResponseSchema } from "./canonical-import-endpoint.js";
import { RateLimitExceededOpenApiResponse } from "./rate-limit.js";

export const GARMIN_FIT_IMPORT_ROUTE_PATH = "/integrations/garmin/fit-import";
export const GARMIN_FIT_IMPORT_MAX_BYTES = 50 * 1024 * 1024;
export const GARMIN_FIT_IMPORT_DEFAULT_TIMEZONE = "UTC";

export const GarminFitImportJsonRequestSchema = z
  .object({
    fileBase64: z.string().min(1),
    filename: z.string().min(1).max(255).optional(),
    timezone: z.string().min(1).max(100).optional(),
    idempotencyKey: z.string().min(1).max(200).optional(),
    credentialId: z.string().min(1).max(200).optional()
  })
  .strict()
  .openapi("GarminFitImportJsonRequest");

export const GarminFitImportQuerySchema = z
  .object({
    timezone: z.string().min(1).max(100).optional(),
    idempotencyKey: z.string().min(1).max(200).optional(),
    credentialId: z.string().min(1).max(200).optional()
  })
  .strict();

export const GarminFitImportInvalidResponseSchema = z
  .object({
    code: z.literal("garmin_fit_import_invalid"),
    message: z.string().min(1)
  })
  .strict()
  .openapi("GarminFitImportInvalidResponse");

export const GarminFitImportUnauthorizedResponseSchema = z
  .object({
    code: z.literal("garmin_fit_import_unauthorized"),
    message: z.string().min(1)
  })
  .strict()
  .openapi("GarminFitImportUnauthorizedResponse");

export const GarminFitImportForbiddenResponseSchema = z
  .object({
    code: z.literal("garmin_fit_import_forbidden"),
    message: z.string().min(1)
  })
  .strict()
  .openapi("GarminFitImportForbiddenResponse");

export const GarminFitImportUnavailableResponseSchema = z
  .object({
    code: z.literal("garmin_fit_import_unavailable"),
    message: z.string().min(1)
  })
  .strict()
  .openapi("GarminFitImportUnavailableResponse");

const GarminFitImportMultipartBodySchema = z.unknown().openapi({
  type: "object",
  properties: {
    file: {
      type: "string",
      format: "binary",
      description: "Garmin FIT file."
    },
    timezone: {
      type: "string",
      minLength: 1,
      maxLength: 100
    },
    idempotencyKey: {
      type: "string",
      minLength: 1,
      maxLength: 200
    },
    credentialId: {
      type: "string",
      minLength: 1,
      maxLength: 200
    }
  },
  required: ["file"],
  additionalProperties: false
});

export const garminFitImportRoute = createRoute({
  method: "post",
  path: GARMIN_FIT_IMPORT_ROUTE_PATH,
  operationId: "importGarminFitFile",
  tags: ["Integrations"],
  summary: "Import a Garmin FIT activity file.",
  description:
    "Accepts a FIT file from user-run GarminDB automation or manual app upload, parses it into the canonical import contract, and ingests it through the shared Integration pipeline. Persisted consent remains authoritative.",
  security: [{ bearerAuth: [] }],
  request: {
    query: GarminFitImportQuerySchema,
    body: {
      required: true,
      content: {
        "multipart/form-data": {
          schema: GarminFitImportMultipartBodySchema
        },
        "application/octet-stream": {
          schema: z.string().openapi({
            type: "string",
            format: "binary",
            description:
              "Raw Garmin FIT bytes. Use query parameters for timezone/idempotencyKey."
          })
        },
        "application/json": {
          schema: GarminFitImportJsonRequestSchema
        }
      }
    }
  },
  responses: {
    200: {
      description:
        "The FIT file was parsed and accepted, or recognized as an idempotent replay.",
      content: {
        "application/json": {
          schema: CanonicalImportResponseSchema
        }
      }
    },
    400: {
      description: "The request did not contain a valid FIT file.",
      content: {
        "application/json": {
          schema: GarminFitImportInvalidResponseSchema
        }
      }
    },
    401: {
      description:
        "The request is missing a valid Integration credential or session bearer.",
      content: {
        "application/json": {
          schema: GarminFitImportUnauthorizedResponseSchema
        }
      }
    },
    403: {
      description: "The Integration credential is not scoped for imports.",
      content: {
        "application/json": {
          schema: GarminFitImportForbiddenResponseSchema
        }
      }
    },
    429: RateLimitExceededOpenApiResponse,
    503: {
      description: "FIT import storage or auth is not configured.",
      content: {
        "application/json": {
          schema: GarminFitImportUnavailableResponseSchema
        }
      }
    }
  }
});

export type GarminFitImportPayload = {
  bytes: Uint8Array;
  credentialId?: string;
  idempotencyKey?: string;
  timezone: string;
};

export function garminFitImportIdempotencyKey(bytes: Uint8Array) {
  return `garmin-fit:${createHash("sha256").update(bytes).digest("hex")}`;
}
