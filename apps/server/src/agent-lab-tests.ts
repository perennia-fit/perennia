/**
 * The Agent read of the Lab Test catalogue (`listAgentLabTests`,
 * `GET /agent/lab-tests`, MCP tool `agent_list_lab_tests`).
 *
 * The catalogue is the generated `LAB_TEST_CATALOGUE`, the same entries the
 * app carries; there is no per-user data and no store behind this read.
 *
 * Lab Test keys are deliberately not an enum anywhere in the OpenAPI or MCP
 * schema (not on `labTestKey`, not here): an enum would put every key into
 * the context of every Agent session that loads the contract. Agents load the
 * keys, units and bounds only by calling this read, before writing lab
 * results with `batchWriteAgentMetrics` by `labTestKey`.
 *
 * The generated entry's `foldedUnits` is an implementation detail of the
 * unit fold and is not exposed: Agents send the listed `unit` or one of
 * `unitAliases`. Each field is picked explicitly so a field added to the
 * generated entry is not published without a decision.
 */
import { createRoute, z } from "@hono/zod-openapi";

import {
  AgentApiKeyUnavailableResponseSchema,
  AgentUnauthorizedResponseSchema
} from "./agent-api-keys.js";
import { LAB_TEST_CATALOGUE } from "./data/lab-test-catalogue.generated.js";
import { RateLimitExceededOpenApiResponse } from "./rate-limit.js";

export const AGENT_LAB_TESTS_DESCRIPTION =
  "Returns the Lab Test catalogue, in display order: each Lab Test's key, name, panel, printed-name variants, unit and accepted unit spellings, hard and plausible bounds, printed range kind and Default Ranges. Write lab results with batchWriteAgentMetrics by labTestKey, using only the listed unit or one of its unitAliases. Lab Test keys are not enumerated anywhere else in the contract, so call this before writing lab results.";

const LabTestBoundsShape = {
  min: z.number(),
  max: z.number()
};

export const AgentLabTestSchema = z
  .object({
    key: z.string().min(1).openapi({
      description:
        "The Lab Test key, as batchWriteAgentMetrics' reading labTestKey carries it."
    }),
    name: z.string().min(1),
    panel: z.string().min(1),
    variants: z.array(z.string()).openapi({
      description:
        "Other names this Lab Test is printed under on lab reports, lower-cased."
    }),
    unit: z.string().min(1).openapi({
      description: "The canonical unit; a reading in this unit is accepted."
    }),
    unitAliases: z.array(z.string()).openapi({
      description:
        "Other accepted spellings of the same unit. No other unit is accepted, and no conversion is made."
    }),
    hardBounds: z.object(LabTestBoundsShape).openapi({
      description:
        "Inclusive bounds; a value or limit outside them is rejected (lab_value_out_of_bounds)."
    }),
    plausibleBounds: z
      .object(LabTestBoundsShape)
      .nullable()
      .openapi({
        description:
          "Inclusive bounds; a value or limit outside them is accepted with the lab_value_implausible warning. Null when none is set."
      }),
    printedRangeKind: z.enum(["reference", "riskTarget"]).openapi({
      description:
        "Whether a lab's printed range for this Lab Test is a reference interval or a risk target."
    }),
    defaultRanges: z
      .array(
        z.object({
          sex: z.enum(["female", "male", "any"]),
          ageMin: z.number().int().nullable(),
          ageMax: z.number().int().nullable(),
          low: z.number().nullable(),
          high: z.number().nullable(),
          source: z.object({
            title: z.string(),
            url: z.string(),
            version: z.string()
          })
        })
      )
      .openapi({
        description:
          "Published ranges the app shows when a result has no printed range. Ages are inclusive whole years; a null side is unbounded."
      })
  })
  .openapi("AgentLabTest");

export const AgentLabTestListSchema = z
  .object({
    labTests: z.array(AgentLabTestSchema)
  })
  .openapi("AgentLabTestList");

export type AgentLabTest = z.infer<typeof AgentLabTestSchema>;
export type AgentLabTestList = z.infer<typeof AgentLabTestListSchema>;

/** Every catalogue entry, in catalogue order, with only the listed fields. */
export function listAgentLabTests(): AgentLabTestList {
  return {
    labTests: LAB_TEST_CATALOGUE.map((entry) => ({
      key: entry.key,
      name: entry.name,
      panel: entry.panel,
      variants: [...entry.variants],
      unit: entry.unit,
      unitAliases: [...entry.unitAliases],
      hardBounds: { min: entry.hardBounds.min, max: entry.hardBounds.max },
      plausibleBounds:
        entry.plausibleBounds === null
          ? null
          : {
              min: entry.plausibleBounds.min,
              max: entry.plausibleBounds.max
            },
      printedRangeKind: entry.printedRangeKind,
      defaultRanges: entry.defaultRanges.map((range) => ({
        sex: range.sex,
        ageMin: range.ageMin,
        ageMax: range.ageMax,
        low: range.low,
        high: range.high,
        source: {
          title: range.source.title,
          url: range.source.url,
          version: range.source.version
        }
      }))
    }))
  };
}

export const agentLabTestsRoute = createRoute({
  method: "get",
  path: "/agent/lab-tests",
  operationId: "listAgentLabTests",
  tags: ["Agent Reads"],
  summary: "List the Lab Test catalogue Agents write lab results against.",
  description: AGENT_LAB_TESTS_DESCRIPTION,
  security: [{ bearerAuth: [] }],
  responses: {
    200: {
      description: "The Lab Test catalogue.",
      content: {
        "application/json": {
          schema: AgentLabTestListSchema
        }
      }
    },
    401: {
      description: "The request is missing a valid agent API key.",
      content: {
        "application/json": {
          schema: AgentUnauthorizedResponseSchema
        }
      }
    },
    429: RateLimitExceededOpenApiResponse,
    503: {
      description: "Agent API key storage is not configured.",
      content: {
        "application/json": {
          schema: AgentApiKeyUnavailableResponseSchema
        }
      }
    }
  }
});
