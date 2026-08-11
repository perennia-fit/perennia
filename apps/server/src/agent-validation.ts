import { createRoute, z } from "@hono/zod-openapi";

import {
  AgentApiKeyUnavailableResponseSchema,
  AgentUnauthorizedResponseSchema
} from "./agent-api-keys.js";
import { RateLimitExceededOpenApiResponse } from "./rate-limit.js";
import type {
  DimensionId,
  ExerciseLoadMode,
  TrainingUnit
} from "./analytics/exercise-analytics.js";

export const SET_VALIDATION_LIMITS = {
  numeric: {
    min: 0,
    maxDecimalPlaces: 5
  },
  load: {
    maxKilograms: 1000,
    maxDecimalPlaces: 2,
    addedWarnKilograms: 350,
    assistedWarnKilograms: 150
  },
  reps: {
    max: 10000,
    warnAbove: 200
  },
  duration: {
    maxSeconds: 24 * 60 * 60,
    warnAboveSeconds: 4 * 60 * 60
  },
  distance: {
    maxKilometers: 1000,
    warnAboveKilometers: 250
  },
  rpe: {
    min: 0,
    max: 10,
    step: 0.5
  },
  speed: {
    warnAboveKilometersPerHour: 50
  },
  side: {
    allowed: ["left", "right"] as const
  }
} as const;

export const NUTRIENT_VALIDATION_LIMITS = {
  numeric: {
    min: 0
  },
  energy: {
    maxKilocalories: 10000
  },
  macro: {
    maxGrams: 2000
  },
  portion: {
    warnBaseQuantity: 2000
  },
  atwater: {
    mismatchTolerance: 0.25
  }
} as const;

/**
 * Bounds and closed enum registries for account-level Settings.
 * The one shared two-tier validator (`validateAgentSettings`) rejects the same
 * impossible values the Dart `validateSettingsFields` does; the golden vector's
 * `limits` block must agree with this constant exactly (AGENTS.md invariant).
 * Settings have no soft-warn tier — a preference is a known enum member / an
 * in-range number, or a hard reject.
 */
export const SETTINGS_VALIDATION_LIMITS = {
  weightIncrementMinKilograms: 0,
  weightIncrementMaxKilograms: 100,
  themePreferences: ["system", "light", "dark"],
  unitSystems: ["metric", "imperial"],
  weekStartDays: ["monday", "sunday"],
  homeScreenDisplays: ["comfortable", "compact"]
} as const;

const DimensionIdSchema = z
  .enum(["load", "reps", "duration", "distance"])
  .openapi("AgentSetDimensionId");

const IssueDimensionIdSchema = DimensionIdSchema.nullable().openapi(
  "AgentSetIssueDimensionId"
);

const ExerciseLoadModeSchema = z
  .enum(["added", "assisted"])
  .openapi("AgentSetExerciseLoadMode");

const UnitSchema = z
  .string()
  .min(1)
  .openapi({
    description:
      "Training unit. load: kilogram or pound; reps: repetition; duration: second; distance: kilometer or mile.",
    enum: ["kilogram", "pound", "repetition", "second", "kilometer", "mile"]
  });

const NutrientIdSchema = z
  .enum([
    "energy",
    "protein",
    "carbohydrate",
    "sugar",
    "fat",
    "saturated_fat",
    "monounsaturated_fat",
    "polyunsaturated_fat",
    "fiber",
    "sodium",
    "cholesterol",
    "vitamin_a",
    "vitamin_c",
    "vitamin_d",
    "vitamin_e",
    "vitamin_k",
    "thiamin",
    "riboflavin",
    "niacin",
    "vitamin_b6",
    "folate",
    "vitamin_b12",
    "calcium",
    "iron",
    "magnesium",
    "phosphorus",
    "potassium",
    "zinc",
    "copper",
    "manganese",
    "selenium",
    "caffeine",
    "water"
  ])
  .openapi("AgentNutrientId");

const NutrientUnitSchema = z
  .enum(["kilocalorie", "gram", "milligram", "microgram", "milliliter"])
  .openapi("AgentNutrientUnit");

const PortionUnitSchema = z
  .enum(["gram", "milliliter", "ounce", "fluidOunce", "serving", "package"])
  .openapi("AgentNutritionPortionUnit");

export const AgentNutrientAmountSchema = z
  .union([
    z.object({
      status: z.literal("complete"),
      value: z.number(),
      entered: z.string().min(1),
      unit: NutrientUnitSchema
    }),
    z.object({
      status: z.literal("unknown"),
      unit: NutrientUnitSchema,
      value: z.number().optional(),
      entered: z.string().optional()
    })
  ])
  .openapi("AgentNutrientAmount");

export const AgentFoodEntryNutrientValidationRequestSchema = z
  .object({
    nutrients: z.record(z.string().min(1), AgentNutrientAmountSchema).openapi({
      description:
        "Food Entry nutrient values keyed by fixed nutrient id. Unknown nutrients are skipped, never coerced to zero."
    }),
    portion: z
      .object({
        value: z.number(),
        entered: z.string().min(1),
        unit: PortionUnitSchema,
        resolvedBaseQuantity: z.number().openapi({
          description:
            "Resolved logged amount in grams or milliliters after serving/package conversion."
        })
      })
      .optional()
      .openapi("AgentFoodEntryPortionForValidation")
  })
  .openapi("AgentFoodEntryNutrientValidationRequest");

export const AgentNutrientValidationIssueSchema = z
  .object({
    field: z.string().min(1).openapi({
      description: "Request field path that triggered the rule."
    }),
    nutrient: NutrientIdSchema.nullable().openapi({
      description: "Nutrient for this issue, or null for Portion-level rules."
    }),
    rule: z.string().min(1).openapi({
      description: "Stable machine-readable validation rule id."
    }),
    message: z.string().min(1).openapi({
      description: "Human-readable explanation of the rule."
    }),
    limit: z.union([z.number(), z.string()]).nullable().openapi({
      description: "Rule limit or allowed value summary."
    })
  })
  .openapi("AgentNutrientValidationIssue");

export const AgentNutrientValidationLimitsSchema = z
  .object({
    numericMin: z.literal(NUTRIENT_VALIDATION_LIMITS.numeric.min),
    energyMaxKilocalories: z.literal(
      NUTRIENT_VALIDATION_LIMITS.energy.maxKilocalories
    ),
    macroMaxGrams: z.literal(NUTRIENT_VALIDATION_LIMITS.macro.maxGrams),
    portionWarnBaseQuantity: z.literal(
      NUTRIENT_VALIDATION_LIMITS.portion.warnBaseQuantity
    ),
    atwaterMismatchTolerance: z.literal(
      NUTRIENT_VALIDATION_LIMITS.atwater.mismatchTolerance
    )
  })
  .openapi("AgentNutrientValidationLimits");

/** The goalable `Nutrient`s in v1: energy + the three macros (NUTRITION.md §4). */
const GoalableNutrientIdSchema = z
  .enum(["energy", "protein", "carbohydrate", "fat"])
  .openapi("AgentNutritionGoalableNutrientId");

export const AgentNutritionGoalTargetForValidationSchema = z
  .object({
    nutrient: GoalableNutrientIdSchema,
    value: z.number()
  })
  .openapi("AgentNutritionGoalTargetForValidation");

export const AgentNutritionGoalValidationRequestSchema = z
  .object({
    targets: z.array(AgentNutritionGoalTargetForValidationSchema).openapi({
      description:
        "Nutrition Goal targets to validate through the same per-nutrient hard-reject rules as a Food Entry (NUTRITION.md §6). Goals carry no Portion and no Atwater relationship, so only the per-nutrient checks apply; there are no soft warnings."
    })
  })
  .openapi("AgentNutritionGoalValidationRequest");

/** Closed enum registries for account-level Settings. */
const SettingsThemePreferenceSchema = z
  .enum(SETTINGS_VALIDATION_LIMITS.themePreferences)
  .openapi("AgentSettingsThemePreference");
const SettingsUnitSystemSchema = z
  .enum(SETTINGS_VALIDATION_LIMITS.unitSystems)
  .openapi("AgentSettingsUnitSystem");
const SettingsWeekStartDaySchema = z
  .enum(SETTINGS_VALIDATION_LIMITS.weekStartDays)
  .openapi("AgentSettingsWeekStartDay");
const SettingsHomeScreenDisplaySchema = z
  .enum(SETTINGS_VALIDATION_LIMITS.homeScreenDisplays)
  .openapi("AgentSettingsHomeScreenDisplay");

/**
 * A partial account-level Settings write to validate. Every field is optional;
 * only the keys present in the write are checked. Enum members are validated
 * as raw strings here (not as zod enums) so an unknown value produces a
 * two-tier `setting_enum_membership` issue rather than a schema parse error —
 * the same posture the Dart validator takes.
 */
export const AgentSettingsValidationRequestSchema = z
  .object({
    fields: z
      .object({
        themePreference: z.string().optional(),
        unitSystem: z.string().optional(),
        weekStartDay: z.string().optional(),
        defaultWeightIncrement: z.number().optional(),
        homeScreenDisplay: z.string().optional(),
        prTrackingEnabled: z.boolean().optional(),
        markSetsCompleteByDefault: z.boolean().optional(),
        autoSelectNextSet: z.boolean().optional()
      })
      .openapi({
        description:
          "Account-level Settings fields to validate through the shared two-tier rules: enum membership and default-weight-increment bounds. Only supplied keys are checked; there are no soft warnings."
      })
  })
  .openapi("AgentSettingsValidationRequest");

export const AgentSettingsValidationIssueSchema = z
  .object({
    field: z.string().min(1).openapi({
      description: "Settings field that triggered the rule."
    }),
    rule: z.string().min(1).openapi({
      description: "Stable machine-readable validation rule id."
    }),
    message: z.string().min(1).openapi({
      description: "Human-readable explanation of the rule."
    }),
    limit: z.union([z.number(), z.string(), z.array(z.string())]).nullable().openapi({
      description: "Rule limit or allowed-value summary."
    })
  })
  .openapi("AgentSettingsValidationIssue");

export const AgentSetDimensionValueSchema = z
  .object({
    entered: z.string().trim().min(1).openapi({
      description:
        "Raw user-entered numeric value. Must be finite, non-negative, and no more than 5 decimal places; load is stricter at 2 decimal places."
    }),
    unit: UnitSchema
  })
  .openapi("AgentSetDimensionValue");

export const AgentSetValidationValuesSchema = z
  .object({
    load: AgentSetDimensionValueSchema.optional().openapi({
      description:
        "Load value. Hard reject: <0, >1000 kg, NaN/infinity, >2 decimals. Soft warn: added >350 kg or assisted >150 kg."
    }),
    reps: AgentSetDimensionValueSchema.optional().openapi({
      description:
        "Reps value. Hard reject: <0, >10000, NaN/infinity, non-integer. Soft warn: >200."
    }),
    duration: AgentSetDimensionValueSchema.optional().openapi({
      description:
        "Duration value in seconds. Hard reject: <0, >86400 seconds, NaN/infinity, >5 decimals. Soft warn: >14400 seconds."
    }),
    distance: AgentSetDimensionValueSchema.optional().openapi({
      description:
        "Distance value. Hard reject: <0, >1000 km, NaN/infinity, >5 decimals. Soft warn: >250 km."
    })
  })
  .default({})
  .openapi("AgentSetValidationValues");

export const AgentSetValidationRequestSchema = z
  .object({
    exercise: z
      .object({
        dimensions: z.array(DimensionIdSchema).max(4).openapi({
          description:
            "Exercise Type dimensions used for cross-field validation. Completion-only exercises pass an empty array."
        }),
        loadMode: ExerciseLoadModeSchema.default("added").openapi({
          description:
            "Controls load warnings: added load warns above 350 kg, assisted load warns above 150 kg."
        })
      })
      .openapi("AgentSetValidationExercise"),
    values: AgentSetValidationValuesSchema,
    rpe: z.union([z.string(), z.number()]).optional().openapi({
      description:
        "Optional rate of perceived exertion. Hard reject: outside 0-10 or not a 0.5 step."
    }),
    side: z.string().optional().openapi({
      description: "Optional side annotation. Hard reject: not left or right.",
      enum: ["left", "right"]
    })
  })
  .openapi("AgentSetValidationRequest");

export const AgentSetValidationIssueSchema = z
  .object({
    field: z.string().min(1).openapi({
      description: "Request field path that triggered the rule."
    }),
    dimension: IssueDimensionIdSchema.openapi({
      description: "Set dimension for this issue, or null for cross-field rules."
    }),
    rule: z.string().min(1).openapi({
      description: "Stable machine-readable validation rule id."
    }),
    message: z.string().min(1).openapi({
      description: "Human-readable explanation of the rule."
    }),
    limit: z.union([z.number(), z.string()]).nullable().openapi({
      description: "Rule limit or allowed value summary."
    })
  })
  .openapi("AgentSetValidationIssue");

export const AgentSetValidationLimitsSchema = z
  .object({
    numericMin: z.literal(SET_VALIDATION_LIMITS.numeric.min),
    maxDecimalPlaces: z.literal(SET_VALIDATION_LIMITS.numeric.maxDecimalPlaces),
    loadMaxKilograms: z.literal(SET_VALIDATION_LIMITS.load.maxKilograms),
    loadMaxDecimalPlaces: z.literal(
      SET_VALIDATION_LIMITS.load.maxDecimalPlaces
    ),
    addedLoadWarnKilograms: z.literal(
      SET_VALIDATION_LIMITS.load.addedWarnKilograms
    ),
    assistedLoadWarnKilograms: z.literal(
      SET_VALIDATION_LIMITS.load.assistedWarnKilograms
    ),
    repsMax: z.literal(SET_VALIDATION_LIMITS.reps.max),
    repsWarnAbove: z.literal(SET_VALIDATION_LIMITS.reps.warnAbove),
    durationMaxSeconds: z.literal(SET_VALIDATION_LIMITS.duration.maxSeconds),
    durationWarnAboveSeconds: z.literal(
      SET_VALIDATION_LIMITS.duration.warnAboveSeconds
    ),
    distanceMaxKilometers: z.literal(SET_VALIDATION_LIMITS.distance.maxKilometers),
    distanceWarnAboveKilometers: z.literal(
      SET_VALIDATION_LIMITS.distance.warnAboveKilometers
    ),
    rpeMin: z.literal(SET_VALIDATION_LIMITS.rpe.min),
    rpeMax: z.literal(SET_VALIDATION_LIMITS.rpe.max),
    rpeStep: z.literal(SET_VALIDATION_LIMITS.rpe.step),
    speedWarnAboveKilometersPerHour: z.literal(
      SET_VALIDATION_LIMITS.speed.warnAboveKilometersPerHour
    ),
    allowedSides: z.array(z.enum(SET_VALIDATION_LIMITS.side.allowed)).openapi({
      description: "Allowed side annotation values."
    })
  })
  .openapi("AgentSetValidationLimits");

export const AgentSetValidationResponseSchema = z
  .object({
    accepted: z.literal(true),
    warnings: z.array(AgentSetValidationIssueSchema),
    limits: AgentSetValidationLimitsSchema
  })
  .openapi("AgentSetValidationResponse");

export const AgentSetValidationErrorResponseSchema = z
  .object({
    code: z.literal("agent_set_validation_failed"),
    message: z.string().min(1),
    errors: z.array(AgentSetValidationIssueSchema),
    warnings: z.array(AgentSetValidationIssueSchema),
    limits: AgentSetValidationLimitsSchema
  })
  .openapi("AgentSetValidationErrorResponse");

export const agentSetValidationRoute = createRoute({
  method: "post",
  path: "/agent/validate-set",
  operationId: "validateAgentSet",
  tags: ["Agent Validation"],
  summary: "Validate one candidate logged set and return soft warnings.",
  security: [{ bearerAuth: [] }],
  request: {
    body: {
      required: true,
      content: {
        "application/json": {
          schema: AgentSetValidationRequestSchema
        }
      }
    }
  },
  responses: {
    200: {
      description:
        "The set passed hard validation. Improbable values are returned in warnings[].",
      content: {
        "application/json": {
          schema: AgentSetValidationResponseSchema
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
    422: {
      description:
        "The set failed one or more hard validation rules with field-level errors.",
      content: {
        "application/json": {
          schema: AgentSetValidationErrorResponseSchema
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

export type AgentSetValidationInput = z.infer<
  typeof AgentSetValidationRequestSchema
>;
export type AgentSetValidationIssue = z.infer<
  typeof AgentSetValidationIssueSchema
>;
export type AgentSetValidationResult = {
  errors: AgentSetValidationIssue[];
  warnings: AgentSetValidationIssue[];
};
export type AgentFoodEntryNutrientValidationInput = z.infer<
  typeof AgentFoodEntryNutrientValidationRequestSchema
>;
export type AgentNutritionGoalValidationInput = z.infer<
  typeof AgentNutritionGoalValidationRequestSchema
>;
export type AgentSettingsValidationInput = z.infer<
  typeof AgentSettingsValidationRequestSchema
>;
export type AgentSettingsValidationIssue = z.infer<
  typeof AgentSettingsValidationIssueSchema
>;
export type AgentSettingsValidationResult = {
  errors: AgentSettingsValidationIssue[];
  warnings: AgentSettingsValidationIssue[];
};
export type AgentNutrientValidationIssue = z.infer<
  typeof AgentNutrientValidationIssueSchema
>;
export type AgentNutrientValidationResult = {
  errors: AgentNutrientValidationIssue[];
  warnings: AgentNutrientValidationIssue[];
};

type ParsedDimension = {
  dimension: DimensionId;
  field: string;
  metricValue: number;
};

export function validateAgentSet(
  input: AgentSetValidationInput
): AgentSetValidationResult {
  const errors: AgentSetValidationIssue[] = [];
  const warnings: AgentSetValidationIssue[] = [];
  const parsed = new Map<DimensionId, ParsedDimension>();

  validateDimensionValue({
    dimension: "load",
    input,
    errors,
    warnings,
    parsed
  });
  validateDimensionValue({
    dimension: "reps",
    input,
    errors,
    warnings,
    parsed
  });
  validateDimensionValue({
    dimension: "duration",
    input,
    errors,
    warnings,
    parsed
  });
  validateDimensionValue({
    dimension: "distance",
    input,
    errors,
    warnings,
    parsed
  });
  validateRpe(input.rpe, errors);
  validateSide(input.side, errors);
  validateCrossField(input, parsed, warnings);

  return { errors, warnings };
}

export function validateAgentFoodEntry(
  input: AgentFoodEntryNutrientValidationInput
): AgentNutrientValidationResult {
  const errors: AgentNutrientValidationIssue[] = [];
  const warnings: AgentNutrientValidationIssue[] = [];
  const parsed = new Map<string, number>();

  for (const [nutrient, amount] of Object.entries(input.nutrients)) {
    if (amount.status !== "complete") {
      continue;
    }
    validateNutrientAmount({
      nutrient,
      value: amount.value,
      errors,
      parsed
    });
  }

  validatePortionSize(input.portion?.resolvedBaseQuantity, warnings);
  validateAtwater(parsed, warnings);

  return { errors, warnings };
}

/**
 * Validates a set of Nutrition Goal targets through the **same** shared
 * two-tier nutrient validator that guards a Food Entry (NUTRITION.md §6) —
 * `validateNutrientAmount`, with no parallel goal-only check. Mirrors
 * `validateNutritionGoalTargets` in the Dart `set_validation.dart`
 * (golden-vectored together, AGENTS.md invariant).
 */
export function validateAgentNutritionGoalTargets(
  input: AgentNutritionGoalValidationInput
): AgentNutrientValidationResult {
  const errors: AgentNutrientValidationIssue[] = [];
  const parsed = new Map<string, number>();

  for (const target of input.targets) {
    validateNutrientAmount({
      nutrient: target.nutrient,
      value: target.value,
      errors,
      parsed
    });
  }

  return { errors, warnings: [] };
}

/**
 * Validates a partial account-level Settings write through the
 * shared two-tier rules: closed-enum membership for theme/unit/week-start/
 * home-display, and default-weight-increment bounds. Mirrors the Dart
 * `validateSettingsFields` (`settings_validation.dart`), golden-vectored
 * together (AGENTS.md invariant). Fields are checked in a fixed canonical
 * order so the error list is deterministic across both languages. Boolean
 * preferences (prTrackingEnabled, markSetsCompleteByDefault, autoSelectNextSet)
 * carry no impossible value, so they are not checked here.
 */
export function validateAgentSettings(
  input: AgentSettingsValidationInput
): AgentSettingsValidationResult {
  const errors: AgentSettingsValidationIssue[] = [];
  const { fields } = input;

  validateSettingsEnumMembership(
    "themePreference",
    fields.themePreference,
    SETTINGS_VALIDATION_LIMITS.themePreferences,
    errors
  );
  validateSettingsEnumMembership(
    "unitSystem",
    fields.unitSystem,
    SETTINGS_VALIDATION_LIMITS.unitSystems,
    errors
  );
  validateSettingsEnumMembership(
    "weekStartDay",
    fields.weekStartDay,
    SETTINGS_VALIDATION_LIMITS.weekStartDays,
    errors
  );
  validateSettingsWeightIncrement(fields.defaultWeightIncrement, errors);
  validateSettingsEnumMembership(
    "homeScreenDisplay",
    fields.homeScreenDisplay,
    SETTINGS_VALIDATION_LIMITS.homeScreenDisplays,
    errors
  );

  return { errors, warnings: [] };
}

function validateSettingsEnumMembership(
  field: string,
  value: string | undefined,
  allowed: readonly string[],
  errors: AgentSettingsValidationIssue[]
) {
  if (value === undefined || allowed.includes(value)) {
    return;
  }
  errors.push(
    AgentSettingsValidationIssueSchema.parse({
      field,
      rule: "setting_enum_membership",
      message: `${field} must be one of: ${allowed.join(", ")}.`,
      limit: [...allowed]
    })
  );
}

function validateSettingsWeightIncrement(
  value: number | undefined,
  errors: AgentSettingsValidationIssue[]
) {
  if (value === undefined) {
    return;
  }
  if (
    !Number.isFinite(value) ||
    value <= SETTINGS_VALIDATION_LIMITS.weightIncrementMinKilograms
  ) {
    errors.push(
      AgentSettingsValidationIssueSchema.parse({
        field: "defaultWeightIncrement",
        rule: "setting_weight_increment_positive",
        message: "Default weight increment must be greater than 0.",
        limit: SETTINGS_VALIDATION_LIMITS.weightIncrementMinKilograms
      })
    );
    return;
  }
  if (value > SETTINGS_VALIDATION_LIMITS.weightIncrementMaxKilograms) {
    errors.push(
      AgentSettingsValidationIssueSchema.parse({
        field: "defaultWeightIncrement",
        rule: "setting_weight_increment_max",
        message: "Default weight increment must be no more than 100.",
        limit: SETTINGS_VALIDATION_LIMITS.weightIncrementMaxKilograms
      })
    );
  }
}

export function setValidationLimitsResponse() {
  return AgentSetValidationLimitsSchema.parse({
    numericMin: SET_VALIDATION_LIMITS.numeric.min,
    maxDecimalPlaces: SET_VALIDATION_LIMITS.numeric.maxDecimalPlaces,
    loadMaxKilograms: SET_VALIDATION_LIMITS.load.maxKilograms,
    loadMaxDecimalPlaces: SET_VALIDATION_LIMITS.load.maxDecimalPlaces,
    addedLoadWarnKilograms: SET_VALIDATION_LIMITS.load.addedWarnKilograms,
    assistedLoadWarnKilograms: SET_VALIDATION_LIMITS.load.assistedWarnKilograms,
    repsMax: SET_VALIDATION_LIMITS.reps.max,
    repsWarnAbove: SET_VALIDATION_LIMITS.reps.warnAbove,
    durationMaxSeconds: SET_VALIDATION_LIMITS.duration.maxSeconds,
    durationWarnAboveSeconds: SET_VALIDATION_LIMITS.duration.warnAboveSeconds,
    distanceMaxKilometers: SET_VALIDATION_LIMITS.distance.maxKilometers,
    distanceWarnAboveKilometers: SET_VALIDATION_LIMITS.distance.warnAboveKilometers,
    rpeMin: SET_VALIDATION_LIMITS.rpe.min,
    rpeMax: SET_VALIDATION_LIMITS.rpe.max,
    rpeStep: SET_VALIDATION_LIMITS.rpe.step,
    speedWarnAboveKilometersPerHour:
      SET_VALIDATION_LIMITS.speed.warnAboveKilometersPerHour,
    allowedSides: [...SET_VALIDATION_LIMITS.side.allowed]
  });
}

export function nutrientValidationLimitsResponse() {
  return AgentNutrientValidationLimitsSchema.parse({
    numericMin: NUTRIENT_VALIDATION_LIMITS.numeric.min,
    energyMaxKilocalories: NUTRIENT_VALIDATION_LIMITS.energy.maxKilocalories,
    macroMaxGrams: NUTRIENT_VALIDATION_LIMITS.macro.maxGrams,
    portionWarnBaseQuantity: NUTRIENT_VALIDATION_LIMITS.portion.warnBaseQuantity,
    atwaterMismatchTolerance:
      NUTRIENT_VALIDATION_LIMITS.atwater.mismatchTolerance
  });
}

function validateNutrientAmount({
  nutrient,
  value,
  errors,
  parsed
}: {
  nutrient: string;
  value: number;
  errors: AgentNutrientValidationIssue[];
  parsed: Map<string, number>;
}) {
  const field = `nutrients.${nutrient}.value`;
  const knownNutrient = parseNutrientId(nutrient);
  if (knownNutrient === null) {
    return;
  }
  if (!Number.isFinite(value)) {
    errors.push(
      nutrientIssue({
        field,
        nutrient: knownNutrient,
        rule: "numeric_finite",
        message: "Nutrient value must be finite.",
        limit: "finite"
      })
    );
    return;
  }
  if (value < NUTRIENT_VALIDATION_LIMITS.numeric.min) {
    errors.push(
      nutrientIssue({
        field,
        nutrient: knownNutrient,
        rule: "nutrient_non_negative",
        message: "Nutrient value must be non-negative.",
        limit: NUTRIENT_VALIDATION_LIMITS.numeric.min
      })
    );
    return;
  }
  if (
    nutrient === "energy" &&
    value > NUTRIENT_VALIDATION_LIMITS.energy.maxKilocalories
  ) {
    errors.push(
      nutrientIssue({
        field: "nutrients.energy.value",
        nutrient: "energy",
        rule: "nutrient_energy_max_kilocalories",
        message: "Energy must be no more than 10000 kcal per Food Entry.",
        limit: NUTRIENT_VALIDATION_LIMITS.energy.maxKilocalories
      })
    );
    return;
  }
  if (isMacroNutrient(nutrient) && value > NUTRIENT_VALIDATION_LIMITS.macro.maxGrams) {
    errors.push(
      nutrientIssue({
        field,
        nutrient: knownNutrient,
        rule: "nutrient_macro_max_grams",
        message: "Macro nutrients must be no more than 2000 g per Food Entry.",
        limit: NUTRIENT_VALIDATION_LIMITS.macro.maxGrams
      })
    );
    return;
  }

  parsed.set(nutrient, value);
}

function validatePortionSize(
  resolvedBaseQuantity: number | undefined,
  warnings: AgentNutrientValidationIssue[]
) {
  if (
    resolvedBaseQuantity === undefined ||
    !Number.isFinite(resolvedBaseQuantity) ||
    resolvedBaseQuantity <= NUTRIENT_VALIDATION_LIMITS.portion.warnBaseQuantity
  ) {
    return;
  }

  warnings.push(
    nutrientIssue({
      field: "portion.resolvedBaseQuantity",
      nutrient: null,
      rule: "portion_size_improbable",
      message: "Portion above 2000 g/ml is improbable.",
      limit: NUTRIENT_VALIDATION_LIMITS.portion.warnBaseQuantity
    })
  );
}

function validateAtwater(
  parsed: Map<string, number>,
  warnings: AgentNutrientValidationIssue[]
) {
  const energy = parsed.get("energy");
  const protein = parsed.get("protein");
  const carbohydrate = parsed.get("carbohydrate");
  const fat = parsed.get("fat");
  if (
    energy === undefined ||
    protein === undefined ||
    carbohydrate === undefined ||
    fat === undefined
  ) {
    return;
  }

  const estimatedEnergy = 4 * protein + 4 * carbohydrate + 9 * fat;
  const denominator = Math.max(Math.abs(energy), Math.abs(estimatedEnergy), 1);
  const relativeDifference = Math.abs(energy - estimatedEnergy) / denominator;
  if (relativeDifference > NUTRIENT_VALIDATION_LIMITS.atwater.mismatchTolerance) {
    warnings.push(
      nutrientIssue({
        field: "nutrients.energy.value",
        nutrient: "energy",
        rule: "energy_atwater_mismatch",
        message:
          "Energy is far from the Atwater estimate from protein, carbohydrate, and fat.",
        limit: NUTRIENT_VALIDATION_LIMITS.atwater.mismatchTolerance
      })
    );
  }
}

function parseNutrientId(nutrient: string) {
  const parsed = NutrientIdSchema.safeParse(nutrient);
  return parsed.success ? parsed.data : null;
}

function isMacroNutrient(nutrient: string) {
  return nutrient === "protein" || nutrient === "carbohydrate" || nutrient === "fat";
}

function validateDimensionValue({
  dimension,
  input,
  errors,
  warnings,
  parsed
}: {
  dimension: DimensionId;
  input: AgentSetValidationInput;
  errors: AgentSetValidationIssue[];
  warnings: AgentSetValidationIssue[];
  parsed: Map<DimensionId, ParsedDimension>;
}) {
  const value = input.values[dimension];
  if (value === undefined) {
    return;
  }

  const field = `values.${dimension}.entered`;
  const unitField = `values.${dimension}.unit`;
  const unitError = validateUnit(dimension, value.unit, unitField);
  if (unitError !== null) {
    errors.push(unitError);
  }

  const numericValue = parseFiniteNonNegativeNumber({
    rawValue: value.entered,
    field,
    dimension,
    errors
  });
  if (numericValue === null || unitError !== null) {
    return;
  }

  const decimalLimit =
    dimension === "load"
      ? SET_VALIDATION_LIMITS.load.maxDecimalPlaces
      : SET_VALIDATION_LIMITS.numeric.maxDecimalPlaces;
  if (decimalPlaces(value.entered) > decimalLimit) {
    errors.push(
      issue({
        field,
        dimension,
        rule:
          dimension === "load"
            ? "load_max_two_decimal_places"
            : "numeric_max_five_decimal_places",
        message:
          dimension === "load"
            ? "Load must use no more than 2 decimal places."
            : "Numeric values must use no more than 5 decimal places.",
        limit: decimalLimit
      })
    );
    return;
  }

  const errorsBeforeDimensionRules = errors.length;
  switch (dimension) {
    case "load":
      validateLoad(numericValue, value.unit, input.exercise.loadMode, errors, warnings);
      if (errors.length === errorsBeforeDimensionRules) {
        parsed.set("load", {
          dimension,
          field,
          metricValue: convertLoadToKilograms(numericValue, value.unit)
        });
      }
      break;
    case "reps":
      validateReps(numericValue, errors, warnings);
      if (errors.length === errorsBeforeDimensionRules) {
        parsed.set("reps", { dimension, field, metricValue: numericValue });
      }
      break;
    case "duration":
      validateDuration(numericValue, errors, warnings);
      if (errors.length === errorsBeforeDimensionRules) {
        parsed.set("duration", { dimension, field, metricValue: numericValue });
      }
      break;
    case "distance":
      validateDistance(numericValue, value.unit, errors, warnings);
      if (errors.length === errorsBeforeDimensionRules) {
        parsed.set("distance", {
          dimension,
          field,
          metricValue: convertDistanceToKilometers(numericValue, value.unit)
        });
      }
      break;
  }
}

function validateLoad(
  enteredValue: number,
  unit: string,
  loadMode: ExerciseLoadMode,
  errors: AgentSetValidationIssue[],
  warnings: AgentSetValidationIssue[]
) {
  const kilograms = convertLoadToKilograms(enteredValue, unit);
  if (kilograms > SET_VALIDATION_LIMITS.load.maxKilograms) {
    errors.push(
      issue({
        field: "values.load.entered",
        dimension: "load",
        rule: "load_max_kilograms",
        message: "Load must be no more than 1000 kg.",
        limit: SET_VALIDATION_LIMITS.load.maxKilograms
      })
    );
    return;
  }

  const warningLimit =
    loadMode === "assisted"
      ? SET_VALIDATION_LIMITS.load.assistedWarnKilograms
      : SET_VALIDATION_LIMITS.load.addedWarnKilograms;
  if (kilograms > warningLimit) {
    warnings.push(
      issue({
        field: "values.load.entered",
        dimension: "load",
        rule:
          loadMode === "assisted"
            ? "assisted_load_improbable"
            : "added_load_improbable",
        message:
          loadMode === "assisted"
            ? "Assisted load above 150 kg is improbable."
            : "Added load above 350 kg is improbable.",
        limit: warningLimit
      })
    );
  }
}

function validateReps(
  reps: number,
  errors: AgentSetValidationIssue[],
  warnings: AgentSetValidationIssue[]
) {
  if (!Number.isInteger(reps)) {
    errors.push(
      issue({
        field: "values.reps.entered",
        dimension: "reps",
        rule: "reps_integer",
        message: "Reps must be an integer.",
        limit: "integer"
      })
    );
    return;
  }
  if (reps > SET_VALIDATION_LIMITS.reps.max) {
    errors.push(
      issue({
        field: "values.reps.entered",
        dimension: "reps",
        rule: "reps_max",
        message: "Reps must be no more than 10000.",
        limit: SET_VALIDATION_LIMITS.reps.max
      })
    );
    return;
  }
  if (reps > SET_VALIDATION_LIMITS.reps.warnAbove) {
    warnings.push(
      issue({
        field: "values.reps.entered",
        dimension: "reps",
        rule: "reps_improbable",
        message: "Reps above 200 are improbable.",
        limit: SET_VALIDATION_LIMITS.reps.warnAbove
      })
    );
  }
}

function validateDuration(
  seconds: number,
  errors: AgentSetValidationIssue[],
  warnings: AgentSetValidationIssue[]
) {
  if (seconds > SET_VALIDATION_LIMITS.duration.maxSeconds) {
    errors.push(
      issue({
        field: "values.duration.entered",
        dimension: "duration",
        rule: "duration_max_seconds",
        message: "Duration must be no more than 24 hours per set.",
        limit: SET_VALIDATION_LIMITS.duration.maxSeconds
      })
    );
    return;
  }
  if (seconds > SET_VALIDATION_LIMITS.duration.warnAboveSeconds) {
    warnings.push(
      issue({
        field: "values.duration.entered",
        dimension: "duration",
        rule: "duration_improbable",
        message: "Duration above 4 hours is improbable.",
        limit: SET_VALIDATION_LIMITS.duration.warnAboveSeconds
      })
    );
  }
}

function validateDistance(
  enteredValue: number,
  unit: string,
  errors: AgentSetValidationIssue[],
  warnings: AgentSetValidationIssue[]
) {
  const kilometers = convertDistanceToKilometers(enteredValue, unit);
  if (kilometers > SET_VALIDATION_LIMITS.distance.maxKilometers) {
    errors.push(
      issue({
        field: "values.distance.entered",
        dimension: "distance",
        rule: "distance_max_kilometers",
        message: "Distance must be no more than 1000 km per set.",
        limit: SET_VALIDATION_LIMITS.distance.maxKilometers
      })
    );
    return;
  }
  if (kilometers > SET_VALIDATION_LIMITS.distance.warnAboveKilometers) {
    warnings.push(
      issue({
        field: "values.distance.entered",
        dimension: "distance",
        rule: "distance_improbable",
        message: "Distance above 250 km is improbable.",
        limit: SET_VALIDATION_LIMITS.distance.warnAboveKilometers
      })
    );
  }
}

function validateRpe(
  rawValue: string | number | undefined,
  errors: AgentSetValidationIssue[]
) {
  if (rawValue === undefined) {
    return;
  }
  const value = parseFiniteNonNegativeNumber({
    rawValue,
    field: "rpe",
    dimension: null,
    errors
  });
  if (value === null) {
    return;
  }
  if (decimalPlaces(rawValue) > SET_VALIDATION_LIMITS.numeric.maxDecimalPlaces) {
    errors.push(
      issue({
        field: "rpe",
        dimension: null,
        rule: "numeric_max_five_decimal_places",
        message: "Numeric values must use no more than 5 decimal places.",
        limit: SET_VALIDATION_LIMITS.numeric.maxDecimalPlaces
      })
    );
    return;
  }
  if (value > SET_VALIDATION_LIMITS.rpe.max) {
    errors.push(
      issue({
        field: "rpe",
        dimension: null,
        rule: "rpe_range",
        message: "RPE must be between 0 and 10.",
        limit: "0-10"
      })
    );
    return;
  }
  if (!isHalfStep(value)) {
    errors.push(
      issue({
        field: "rpe",
        dimension: null,
        rule: "rpe_half_step",
        message: "RPE must be a half-step value.",
        limit: SET_VALIDATION_LIMITS.rpe.step
      })
    );
  }
}

function validateSide(
  side: string | undefined,
  errors: AgentSetValidationIssue[]
) {
  if (
    side !== undefined &&
    !(SET_VALIDATION_LIMITS.side.allowed as readonly string[]).includes(side)
  ) {
    errors.push(
      issue({
        field: "side",
        dimension: null,
        rule: "side_allowed",
        message: "Side must be left or right.",
        limit: SET_VALIDATION_LIMITS.side.allowed.join("|")
      })
    );
  }
}

function validateCrossField(
  input: AgentSetValidationInput,
  parsed: Map<DimensionId, ParsedDimension>,
  warnings: AgentSetValidationIssue[]
) {
  const exerciseDimensions = uniqueDimensions(input.exercise.dimensions);
  if (
    exerciseDimensions.length > 1 &&
    exerciseDimensions.every((dimension) => parsed.get(dimension)?.metricValue === 0)
  ) {
    warnings.push(
      issue({
        field: "values",
        dimension: null,
        rule: "all_zero_multi_dimension_set",
        message: "All-zero sets on multi-dimension exercises are improbable.",
        limit: "not all dimensions zero"
      })
    );
  }

  const distance = parsed.get("distance")?.metricValue;
  const duration = parsed.get("duration")?.metricValue;
  if (distance !== undefined && duration !== undefined && distance > 0) {
    const speed =
      duration === 0 ? Number.POSITIVE_INFINITY : distance / (duration / 3600);
    if (speed > SET_VALIDATION_LIMITS.speed.warnAboveKilometersPerHour) {
      warnings.push(
        issue({
          field: "values.distance",
          dimension: null,
          rule: "implied_speed_improbable",
          message: "Implied speed above 50 km/h is improbable.",
          limit: SET_VALIDATION_LIMITS.speed.warnAboveKilometersPerHour
        })
      );
    }
  }
}

function parseFiniteNonNegativeNumber({
  rawValue,
  field,
  dimension,
  errors
}: {
  rawValue: string | number;
  field: string;
  dimension: DimensionId | null;
  errors: AgentSetValidationIssue[];
}) {
  const parsed =
    typeof rawValue === "number"
      ? rawValue
      : rawValue.trim().length === 0
        ? Number.NaN
        : Number(rawValue.trim());

  if (!Number.isFinite(parsed)) {
    errors.push(
      issue({
        field,
        dimension,
        rule: "numeric_finite",
        message: "Numeric value must be finite.",
        limit: "finite"
      })
    );
    return null;
  }
  if (parsed < SET_VALIDATION_LIMITS.numeric.min) {
    errors.push(
      issue({
        field,
        dimension,
        rule: "numeric_non_negative",
        message: "Numeric value must be non-negative.",
        limit: SET_VALIDATION_LIMITS.numeric.min
      })
    );
    return null;
  }

  return parsed;
}

function validateUnit(
  dimension: DimensionId,
  unit: string,
  field: string
): AgentSetValidationIssue | null {
  if (isUnitAllowed(dimension, unit)) {
    return null;
  }

  return issue({
    field,
    dimension,
    rule: "unit_allowed_for_dimension",
    message: `Unit is not valid for ${dimension}.`,
    limit: allowedUnits(dimension).join("|")
  });
}

function issue(input: AgentSetValidationIssue): AgentSetValidationIssue {
  return AgentSetValidationIssueSchema.parse(input);
}

function nutrientIssue(
  input: AgentNutrientValidationIssue
): AgentNutrientValidationIssue {
  return AgentNutrientValidationIssueSchema.parse(input);
}

function isUnitAllowed(dimension: DimensionId, unit: string): unit is TrainingUnit {
  return (allowedUnits(dimension) as readonly string[]).includes(unit);
}

function allowedUnits(dimension: DimensionId): readonly TrainingUnit[] {
  switch (dimension) {
    case "load":
      return ["kilogram", "pound"];
    case "reps":
      return ["repetition"];
    case "duration":
      return ["second"];
    case "distance":
      return ["kilometer", "mile"];
  }
}

function convertLoadToKilograms(value: number, unit: string) {
  return unit === "pound" ? value * 0.45359237 : value;
}

function convertDistanceToKilometers(value: number, unit: string) {
  return unit === "mile" ? value * 1.609344 : value;
}

function decimalPlaces(rawValue: string | number) {
  const text =
    typeof rawValue === "number"
      ? rawValue.toString().toLowerCase()
      : rawValue.trim().toLowerCase();
  const [coefficient, exponentText] = text.split("e");
  const fractionalLength = coefficient.split(".")[1]?.length ?? 0;
  if (exponentText === undefined) {
    return fractionalLength;
  }

  const exponent = Number.parseInt(exponentText, 10);
  if (!Number.isFinite(exponent)) {
    return fractionalLength;
  }

  return Math.max(0, fractionalLength - exponent);
}

function isHalfStep(value: number) {
  return Number.isInteger(value * 2);
}

function uniqueDimensions(dimensions: readonly DimensionId[]) {
  return [...new Set(dimensions)];
}

// ---------------------------------------------------------------------------
// Dose tier (PROTOCOLS.md §6) — the SAME shared two-tier validator,
// extended for the Protocols domain. This twins the Dart `validateDose`
// (apps/mobile/lib/domain/protocols/dose_validation.dart) byte-for-byte: the
// same stable rule ids, the same numeric limits, agreeing on the shared golden
// vector (packages/golden-vectors/vectors/m26-dose-validation.json). Not a
// parallel/forked validator.
// ---------------------------------------------------------------------------

/// The curated `Dose` amount units (PROTOCOLS.md §1.3). Members match the Dart
/// `DoseUnit` enum names exactly — a sealed registry, never free-text.
export const DOSE_UNITS = [
  "milligram",
  "microgram",
  "gram",
  "internationalUnit",
  "milliliter",
  "tablet",
  "capsule",
  "drop",
  "spray",
  "puff",
  "patch",
  "unit"
] as const;

/// The curated `Dose` administration routes (PROTOCOLS.md §1.3). Members match
/// the Dart `DoseRoute` enum names exactly.
export const DOSE_ROUTES = [
  "oral",
  "sublingual",
  "subcutaneous",
  "intramuscular",
  "transdermal",
  "intranasal",
  "inhaled",
  "topical",
  "other"
] as const;

export type DoseUnit = (typeof DOSE_UNITS)[number];
export type DoseRoute = (typeof DOSE_ROUTES)[number];

/// The dose validator's limits. Kept in lockstep with the Dart
/// `DoseValidationLimits` and the golden vector's `limits` block.
/// `warnAbove` is the improbable (soft-warn) boundary; `maxPerDose` is the
/// absurd (hard-reject) cap. Both are exclusive-greater.
export const DOSE_VALIDATION_LIMITS = {
  amountMin: 0,
  units: {
    milligram: { warnAbove: 5000, maxPerDose: 100000 },
    microgram: { warnAbove: 5000000, maxPerDose: 100000000 },
    gram: { warnAbove: 100, maxPerDose: 1000 },
    internationalUnit: { warnAbove: 100000, maxPerDose: 10000000 },
    milliliter: { warnAbove: 100, maxPerDose: 1000 },
    tablet: { warnAbove: 20, maxPerDose: 100 },
    capsule: { warnAbove: 20, maxPerDose: 100 },
    drop: { warnAbove: 100, maxPerDose: 1000 },
    spray: { warnAbove: 20, maxPerDose: 100 },
    puff: { warnAbove: 20, maxPerDose: 100 },
    patch: { warnAbove: 10, maxPerDose: 100 },
    unit: { warnAbove: 1000, maxPerDose: 100000 }
  }
} as const satisfies {
  amountMin: number;
  units: Record<DoseUnit, { warnAbove: number; maxPerDose: number }>;
};

export const AgentDoseValidationRequestSchema = z
  .object({
    amount: z.union([z.string(), z.number()]).openapi({
      description:
        "Dose amount as entered. Hard reject: <0, NaN/infinity, or above the per-unit maximum. Soft warn: out of the usual range for the entered unit."
    }),
    unit: z.string().min(1).openapi({
      description:
        "Dose unit. Hard reject: outside the curated registry.",
      enum: [...DOSE_UNITS]
    }),
    route: z.string().min(1).openapi({
      description:
        "Dose administration route. Hard reject: outside the curated registry.",
      enum: [...DOSE_ROUTES]
    })
  })
  .openapi("AgentDoseValidationRequest");

export const AgentDoseValidationIssueSchema = z
  .object({
    field: z.string().min(1).openapi({
      description: "Request field path that triggered the rule."
    }),
    rule: z.string().min(1).openapi({
      description: "Stable machine-readable validation rule id."
    }),
    message: z.string().min(1).openapi({
      description: "Human-readable explanation of the rule."
    }),
    limit: z.union([z.number(), z.string()]).nullable().openapi({
      description: "Rule limit or allowed value summary."
    })
  })
  .openapi("AgentDoseValidationIssue");

const DoseUnitLimitSchema = z.object({
  warnAbove: z.number(),
  maxPerDose: z.number()
});

export const AgentDoseValidationLimitsSchema = z
  .object({
    amountMin: z.literal(DOSE_VALIDATION_LIMITS.amountMin),
    units: z.object({
      milligram: DoseUnitLimitSchema,
      microgram: DoseUnitLimitSchema,
      gram: DoseUnitLimitSchema,
      internationalUnit: DoseUnitLimitSchema,
      milliliter: DoseUnitLimitSchema,
      tablet: DoseUnitLimitSchema,
      capsule: DoseUnitLimitSchema,
      drop: DoseUnitLimitSchema,
      spray: DoseUnitLimitSchema,
      puff: DoseUnitLimitSchema,
      patch: DoseUnitLimitSchema,
      unit: DoseUnitLimitSchema
    })
  })
  .openapi("AgentDoseValidationLimits");

export const AgentDoseValidationResponseSchema = z
  .object({
    accepted: z.literal(true),
    warnings: z.array(AgentDoseValidationIssueSchema),
    limits: AgentDoseValidationLimitsSchema
  })
  .openapi("AgentDoseValidationResponse");

export const AgentDoseValidationErrorResponseSchema = z
  .object({
    code: z.literal("agent_dose_validation_failed"),
    message: z.string().min(1),
    errors: z.array(AgentDoseValidationIssueSchema),
    warnings: z.array(AgentDoseValidationIssueSchema),
    limits: AgentDoseValidationLimitsSchema
  })
  .openapi("AgentDoseValidationErrorResponse");

export const agentDoseValidationRoute = createRoute({
  method: "post",
  path: "/agent/validate-dose",
  operationId: "validateAgentDose",
  tags: ["Agent Validation"],
  summary: "Validate one candidate logged dose and return soft warnings.",
  security: [{ bearerAuth: [] }],
  request: {
    body: {
      required: true,
      content: {
        "application/json": {
          schema: AgentDoseValidationRequestSchema
        }
      }
    }
  },
  responses: {
    200: {
      description:
        "The dose passed hard validation. Improbable values are returned in warnings[].",
      content: {
        "application/json": {
          schema: AgentDoseValidationResponseSchema
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
    422: {
      description:
        "The dose failed one or more hard validation rules with field-level errors.",
      content: {
        "application/json": {
          schema: AgentDoseValidationErrorResponseSchema
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

export type AgentDoseValidationInput = z.infer<
  typeof AgentDoseValidationRequestSchema
>;
export type AgentDoseValidationIssue = z.infer<
  typeof AgentDoseValidationIssueSchema
>;
export type AgentDoseValidationResult = {
  errors: AgentDoseValidationIssue[];
  warnings: AgentDoseValidationIssue[];
};

export function validateAgentDose(
  input: AgentDoseValidationInput
): AgentDoseValidationResult {
  const errors: AgentDoseValidationIssue[] = [];
  const warnings: AgentDoseValidationIssue[] = [];

  const unit = parseDoseUnit(input.unit);
  if (unit === null) {
    errors.push(
      doseIssue({
        field: "unit",
        rule: "dose_unit_allowed",
        message: "Unit is not in the curated dose unit registry.",
        limit: DOSE_UNITS.join("|")
      })
    );
  }

  if (parseDoseRoute(input.route) === null) {
    errors.push(
      doseIssue({
        field: "route",
        rule: "dose_route_allowed",
        message: "Route is not in the curated dose route registry.",
        limit: DOSE_ROUTES.join("|")
      })
    );
  }

  validateDoseAmount({ amount: input.amount, unit, errors, warnings });

  return { errors, warnings };
}

export function doseValidationLimitsResponse() {
  return AgentDoseValidationLimitsSchema.parse(DOSE_VALIDATION_LIMITS);
}

function validateDoseAmount({
  amount,
  unit,
  errors,
  warnings
}: {
  amount: string | number;
  unit: DoseUnit | null;
  errors: AgentDoseValidationIssue[];
  warnings: AgentDoseValidationIssue[];
}) {
  const value = parseDoseAmount(amount);
  if (value === null || !Number.isFinite(value)) {
    errors.push(
      doseIssue({
        field: "amount",
        rule: "numeric_finite",
        message: "Dose amount must be a finite number.",
        limit: "finite"
      })
    );
    return;
  }
  if (value < DOSE_VALIDATION_LIMITS.amountMin) {
    errors.push(
      doseIssue({
        field: "amount",
        rule: "dose_amount_non_negative",
        message: "Dose amount must be non-negative.",
        limit: DOSE_VALIDATION_LIMITS.amountMin
      })
    );
    return;
  }

  // A malformed unit is already hard-rejected and suppresses the unit-relative
  // range checks (there is no scale to judge the amount against).
  if (unit === null) {
    return;
  }
  const limit = DOSE_VALIDATION_LIMITS.units[unit];

  if (value > limit.maxPerDose) {
    errors.push(
      doseIssue({
        field: "amount",
        rule: "dose_amount_max_per_dose",
        message: "Dose amount is above the maximum for the entered unit.",
        limit: limit.maxPerDose
      })
    );
    return;
  }
  if (value > limit.warnAbove) {
    warnings.push(
      doseIssue({
        field: "amount",
        rule: "dose_amount_out_of_range_for_unit",
        message: "Dose amount is out of the usual range for the entered unit.",
        limit: limit.warnAbove
      })
    );
  }
}

function doseIssue(input: AgentDoseValidationIssue): AgentDoseValidationIssue {
  return AgentDoseValidationIssueSchema.parse(input);
}

function parseDoseAmount(rawValue: string | number): number | null {
  if (typeof rawValue === "number") {
    return rawValue;
  }
  const trimmed = rawValue.trim();
  if (trimmed.length === 0) {
    return null;
  }
  const parsed = Number(trimmed);
  return Number.isNaN(parsed) ? null : parsed;
}

function parseDoseUnit(unit: string): DoseUnit | null {
  return (DOSE_UNITS as readonly string[]).includes(unit)
    ? (unit as DoseUnit)
    : null;
}

function parseDoseRoute(route: string): DoseRoute | null {
  return (DOSE_ROUTES as readonly string[]).includes(route)
    ? (route as DoseRoute)
    : null;
}

// ---------------------------------------------------------------------------
// Predefined Set tier (HIGH_LEVEL_DESIGN.md §5) — the SAME shared
// two-tier validator, extended for the Routines domain. This twins the Dart
// `validatePredefinedSet`
// (apps/mobile/lib/domain/training/predefined_set_validation.dart) rule-for-rule
// against the shared golden vector
// (packages/golden-vectors/vectors/m34-predefined-set-validation.json). A
// predefined set is prescription data: its dimension values (fixed mode only)
// reuse the exact set-value rules of `validateAgentSet`, plus two
// prescription-specific hard-reject rules for `repeat` and `restAfterSeconds`.
// A copy-previous prescription carries no fixed values — the values are resolved
// from history at materialize time — so its value fields are never validated.
// ---------------------------------------------------------------------------

export const PREDEFINED_SET_VALIDATION_LIMITS = {
  repeatMin: 1,
  restAfterSecondsMin: 0
} as const;

const PredefinedSetModeSchema = z
  .enum(["fixed", "copyPrevious"])
  .openapi("AgentPredefinedSetMode");

export const AgentPredefinedSetValidationRequestSchema = z
  .object({
    mode: PredefinedSetModeSchema.openapi({
      description:
        "Prescription mode. `fixed` validates the supplied values as set values; `copyPrevious` resolves values from history at materialize time and ignores any supplied values."
    }),
    dimensions: z.array(DimensionIdSchema).max(4).openapi({
      description:
        "Exercise Type dimensions used for cross-field validation of fixed values. Completion-only exercises pass an empty array."
    }),
    loadMode: ExerciseLoadModeSchema.default("added").openapi({
      description:
        "Controls load warnings on fixed values: added load warns above 350 kg, assisted load warns above 150 kg."
    }),
    repeat: z.number().openapi({
      description:
        "How many identical logged sets this prescription expands to. Hard reject: below 1, or non-integer."
    }),
    restAfterSeconds: z.number().nullable().default(null).openapi({
      description:
        "Planned rest after the set, in seconds, or null. Hard reject: negative."
    }),
    values: AgentSetValidationValuesSchema
  })
  .openapi("AgentPredefinedSetValidationRequest");

export const AgentPredefinedSetValidationLimitsSchema = z
  .object({
    repeatMin: z.literal(PREDEFINED_SET_VALIDATION_LIMITS.repeatMin),
    restAfterSecondsMin: z.literal(
      PREDEFINED_SET_VALIDATION_LIMITS.restAfterSecondsMin
    )
  })
  .openapi("AgentPredefinedSetValidationLimits");

export type AgentPredefinedSetValidationInput = z.infer<
  typeof AgentPredefinedSetValidationRequestSchema
>;
export type AgentPredefinedSetValidationResult = {
  errors: AgentSetValidationIssue[];
  warnings: AgentSetValidationIssue[];
};

/**
 * Validates one candidate `Predefined Set` through the shared two-tier
 * validator. Prescription hard-reject rules (`predefined_set_repeat_min`,
 * `predefined_set_repeat_integer`, `predefined_set_rest_after_non_negative`)
 * come first, then — for `fixed` mode only — the exact set-value rules of
 * `validateAgentSet` (dimension ranges, decimals, cross-field). Mirrors the Dart
 * `validatePredefinedSet` (golden-vectored together, AGENTS.md invariant).
 */
export function validateAgentPredefinedSet(
  input: AgentPredefinedSetValidationInput
): AgentPredefinedSetValidationResult {
  const errors: AgentSetValidationIssue[] = [];
  const warnings: AgentSetValidationIssue[] = [];

  if (!Number.isInteger(input.repeat)) {
    if (input.repeat < PREDEFINED_SET_VALIDATION_LIMITS.repeatMin) {
      errors.push(
        issue({
          field: "repeat",
          dimension: null,
          rule: "predefined_set_repeat_min",
          message: "Repeat must be at least 1.",
          limit: PREDEFINED_SET_VALIDATION_LIMITS.repeatMin
        })
      );
    } else {
      errors.push(
        issue({
          field: "repeat",
          dimension: null,
          rule: "predefined_set_repeat_integer",
          message: "Repeat must be an integer.",
          limit: "integer"
        })
      );
    }
  } else if (input.repeat < PREDEFINED_SET_VALIDATION_LIMITS.repeatMin) {
    errors.push(
      issue({
        field: "repeat",
        dimension: null,
        rule: "predefined_set_repeat_min",
        message: "Repeat must be at least 1.",
        limit: PREDEFINED_SET_VALIDATION_LIMITS.repeatMin
      })
    );
  }

  if (
    input.restAfterSeconds !== null &&
    input.restAfterSeconds < PREDEFINED_SET_VALIDATION_LIMITS.restAfterSecondsMin
  ) {
    errors.push(
      issue({
        field: "restAfterSeconds",
        dimension: null,
        rule: "predefined_set_rest_after_non_negative",
        message: "Rest after must not be negative.",
        limit: PREDEFINED_SET_VALIDATION_LIMITS.restAfterSecondsMin
      })
    );
  }

  if (input.mode === "fixed") {
    const valueResult = validateAgentSet({
      exercise: { dimensions: input.dimensions, loadMode: input.loadMode },
      values: input.values
    });
    errors.push(...valueResult.errors);
    warnings.push(...valueResult.warnings);
  }

  return { errors, warnings };
}

export function predefinedSetValidationLimitsResponse() {
  return AgentPredefinedSetValidationLimitsSchema.parse(
    PREDEFINED_SET_VALIDATION_LIMITS
  );
}

// ---------------------------------------------------------------------------
// Workout Template Prescription tier (ROUTINES.md §5).
// This is the canonical replacement plan-layer validator; the legacy
// predefined-set validator above remains intact until the old routines cutover.
// ---------------------------------------------------------------------------

export const PRESCRIPTION_VALIDATION_LIMITS = {
  repeatMin: 1,
  repeatWarnAbove: 100,
  restAfterSecondsMin: 0
} as const;

const PrescriptionModeSchema = z.enum(["fixed", "copyPrevious"]);

export const AgentPrescriptionValidationRequestSchema = z.object({
  mode: PrescriptionModeSchema,
  dimensions: z.array(DimensionIdSchema).max(4),
  loadMode: ExerciseLoadModeSchema.default("added"),
  repeat: z.number(),
  restAfterSeconds: z.number().nullable().default(null),
  values: AgentSetValidationValuesSchema
});

export type AgentPrescriptionValidationInput = z.infer<
  typeof AgentPrescriptionValidationRequestSchema
>;
export type AgentPrescriptionValidationResult = {
  errors: AgentSetValidationIssue[];
  warnings: AgentSetValidationIssue[];
};

export function validateAgentPrescription(
  input: AgentPrescriptionValidationInput
): AgentPrescriptionValidationResult {
  const errors: AgentSetValidationIssue[] = [];
  const warnings: AgentSetValidationIssue[] = [];

  if (new Set(input.dimensions).size !== input.dimensions.length) {
    errors.push(
      issue({
        field: "dimensions",
        dimension: null,
        rule: "prescription_dimensions_duplicate",
        message: "Prescription dimensions must be unique.",
        limit: "unique"
      })
    );
  }

  if (input.mode !== "fixed" && input.mode !== "copyPrevious") {
    errors.push(
      issue({
        field: "mode",
        dimension: null,
        rule: "prescription_mode_invalid",
        message: "Mode must be fixed or copyPrevious.",
        limit: "fixed|copyPrevious"
      })
    );
  }

  if (!Number.isInteger(input.repeat)) {
    if (input.repeat < PRESCRIPTION_VALIDATION_LIMITS.repeatMin) {
      errors.push(prescriptionRepeatMinIssue());
    } else {
      errors.push(
        issue({
          field: "repeat",
          dimension: null,
          rule: "prescription_repeat_integer",
          message: "Repeat must be an integer.",
          limit: "integer"
        })
      );
    }
  } else if (input.repeat < PRESCRIPTION_VALIDATION_LIMITS.repeatMin) {
    errors.push(prescriptionRepeatMinIssue());
  } else if (input.repeat > PRESCRIPTION_VALIDATION_LIMITS.repeatWarnAbove) {
    warnings.push(
      issue({
        field: "repeat",
        dimension: null,
        rule: "prescription_repeat_improbable",
        message: "Repeat above 100 is improbable.",
        limit: PRESCRIPTION_VALIDATION_LIMITS.repeatWarnAbove
      })
    );
  }

  if (input.restAfterSeconds !== null) {
    if (!Number.isFinite(input.restAfterSeconds)) {
      errors.push(
        issue({
          field: "restAfterSeconds",
          dimension: null,
          rule: "prescription_rest_after_finite",
          message: "Rest after must be finite.",
          limit: "finite"
        })
      );
    } else if (
      input.restAfterSeconds < PRESCRIPTION_VALIDATION_LIMITS.restAfterSecondsMin
    ) {
      errors.push(
        issue({
          field: "restAfterSeconds",
          dimension: null,
          rule: "prescription_rest_after_non_negative",
          message: "Rest after must not be negative.",
          limit: PRESCRIPTION_VALIDATION_LIMITS.restAfterSecondsMin
        })
      );
    }
  }

  if (input.mode === "fixed") {
    const valueResult = validateAgentSet({
      exercise: { dimensions: input.dimensions, loadMode: input.loadMode },
      values: input.values
    });
    errors.push(...valueResult.errors);
    warnings.push(...valueResult.warnings);
  }

  return { errors, warnings };
}

function prescriptionRepeatMinIssue(): AgentSetValidationIssue {
  return issue({
    field: "repeat",
    dimension: null,
    rule: "prescription_repeat_min",
    message: "Repeat must be at least 1.",
    limit: PRESCRIPTION_VALIDATION_LIMITS.repeatMin
  });
}

// ---------------------------------------------------------------------------
// Workout Template Group tier (ROUTINES.md §1.3).
// Relationship checks that require storage remain repository invariants. This
// validator twins Dart for the portable value-shape that UI and agent writes
// can reject identically before starting any mutation.
// ---------------------------------------------------------------------------

export const TEMPLATE_GROUP_VALIDATION_LIMITS = {
  roundsMin: 1,
  membersMin: 2,
  colorHexFormat: "#RRGGBB"
} as const;

export const ROUTINE_CADENCE_VALIDATION_LIMITS = {
  cadenceKinds: ["weekly", "rotating"],
  rotatingWindowMin: 1,
  rotatingWindowWarnAbove: 31,
  weeklySlotMin: 1,
  weeklySlotMax: 7,
  routineEntrySlotMin: 1
} as const;

export const PLAN_VALIDATION_LIMITS = {
  repeatMin: PRESCRIPTION_VALIDATION_LIMITS.repeatMin,
  repeatWarnAbove: PRESCRIPTION_VALIDATION_LIMITS.repeatWarnAbove,
  restAfterSecondsMin: PRESCRIPTION_VALIDATION_LIMITS.restAfterSecondsMin,
  templateGroupRoundsMin: TEMPLATE_GROUP_VALIDATION_LIMITS.roundsMin,
  templateGroupMembersMin: TEMPLATE_GROUP_VALIDATION_LIMITS.membersMin,
  templateGroupColorHexFormat: TEMPLATE_GROUP_VALIDATION_LIMITS.colorHexFormat,
  cadenceKinds: ROUTINE_CADENCE_VALIDATION_LIMITS.cadenceKinds,
  rotatingWindowMin: ROUTINE_CADENCE_VALIDATION_LIMITS.rotatingWindowMin,
  rotatingWindowWarnAbove:
    ROUTINE_CADENCE_VALIDATION_LIMITS.rotatingWindowWarnAbove,
  weeklySlotMin: ROUTINE_CADENCE_VALIDATION_LIMITS.weeklySlotMin,
  weeklySlotMax: ROUTINE_CADENCE_VALIDATION_LIMITS.weeklySlotMax,
  routineEntrySlotMin: ROUTINE_CADENCE_VALIDATION_LIMITS.routineEntrySlotMin
} as const;

export const AgentTemplateGroupValidationRequestSchema = z.object({
  name: z.string(),
  colorHex: z.string(),
  rounds: z.number(),
  memberIds: z.array(z.string())
});

export type AgentTemplateGroupValidationInput = z.infer<
  typeof AgentTemplateGroupValidationRequestSchema
>;
export type AgentTemplateGroupValidationResult = {
  errors: AgentSetValidationIssue[];
  warnings: AgentSetValidationIssue[];
};

export function validateAgentTemplateGroup(
  input: AgentTemplateGroupValidationInput
): AgentTemplateGroupValidationResult {
  const errors: AgentSetValidationIssue[] = [];
  const normalizedMemberIds = input.memberIds.map((memberId) => memberId.trim());

  if (input.name.trim().length === 0) {
    errors.push(
      issue({
        field: "name",
        dimension: null,
        rule: "template_group_name_required",
        message: "Template Group name is required.",
        limit: "non-empty"
      })
    );
  }

  if (!/^#[0-9a-f]{6}$/i.test(input.colorHex.trim())) {
    errors.push(
      issue({
        field: "colorHex",
        dimension: null,
        rule: "template_group_color_hex",
        message: "Template Group color must use #RRGGBB.",
        limit: TEMPLATE_GROUP_VALIDATION_LIMITS.colorHexFormat
      })
    );
  }

  if (!Number.isFinite(input.rounds)) {
    errors.push(
      issue({
        field: "rounds",
        dimension: null,
        rule: "template_group_rounds_finite",
        message: "Rounds must be finite.",
        limit: "finite"
      })
    );
  } else if (input.rounds < TEMPLATE_GROUP_VALIDATION_LIMITS.roundsMin) {
    errors.push(templateGroupRoundsMinIssue());
  } else if (!Number.isInteger(input.rounds)) {
    errors.push(
      issue({
        field: "rounds",
        dimension: null,
        rule: "template_group_rounds_integer",
        message: "Rounds must be an integer.",
        limit: "integer"
      })
    );
  }

  const nonEmptyMemberIds = normalizedMemberIds.filter(
    (memberId) => memberId.length > 0
  );
  if (nonEmptyMemberIds.length !== normalizedMemberIds.length) {
    errors.push(
      issue({
        field: "memberIds",
        dimension: null,
        rule: "template_group_member_id_required",
        message: "Template Group member IDs must not be empty.",
        limit: "non-empty"
      })
    );
  }

  if (new Set(nonEmptyMemberIds).size !== nonEmptyMemberIds.length) {
    errors.push(
      issue({
        field: "memberIds",
        dimension: null,
        rule: "template_group_members_unique",
        message: "Template Group members must be unique.",
        limit: "unique"
      })
    );
  }

  if (normalizedMemberIds.length < TEMPLATE_GROUP_VALIDATION_LIMITS.membersMin) {
    errors.push(
      issue({
        field: "memberIds",
        dimension: null,
        rule: "template_group_members_min",
        message: "Template Group must contain at least 2 members.",
        limit: TEMPLATE_GROUP_VALIDATION_LIMITS.membersMin
      })
    );
  }

  return { errors, warnings: [] };
}

function templateGroupRoundsMinIssue(): AgentSetValidationIssue {
  return issue({
    field: "rounds",
    dimension: null,
    rule: "template_group_rounds_min",
    message: "Rounds must be at least 1.",
    limit: TEMPLATE_GROUP_VALIDATION_LIMITS.roundsMin
  });
}

export const AgentRoutineCadenceValidationRequestSchema = z.object({
  cadenceKind: z.string().nullable(),
  cadenceWindow: z.number().nullable(),
  slots: z.array(z.number().nullable())
});

export type AgentRoutineCadenceValidationInput = z.infer<
  typeof AgentRoutineCadenceValidationRequestSchema
>;
export type AgentRoutineCadenceValidationResult = {
  errors: AgentSetValidationIssue[];
  warnings: AgentSetValidationIssue[];
};

export function validateAgentRoutineCadence(
  input: AgentRoutineCadenceValidationInput
): AgentRoutineCadenceValidationResult {
  const errors: AgentSetValidationIssue[] = [];
  const warnings: AgentSetValidationIssue[] = [];
  const addError = (validationIssue: AgentSetValidationIssue): void => {
    if (!errors.some((existing) => existing.rule === validationIssue.rule)) {
      errors.push(validationIssue);
    }
  };
  const kindIsValid =
    input.cadenceKind === null ||
    ROUTINE_CADENCE_VALIDATION_LIMITS.cadenceKinds.includes(
      input.cadenceKind as "weekly" | "rotating"
    );

  if (!kindIsValid) {
    addError(
      issue({
        field: "cadenceKind",
        dimension: null,
        rule: "cadence_kind_invalid",
        message: "Cadence must be weekly, rotating, or absent.",
        limit: "weekly|rotating|null"
      })
    );
  }

  if (input.cadenceKind === null) {
    if (input.cadenceWindow !== null) {
      addError(cadenceWindowForbiddenIssue());
    }
    if (input.slots.some((slot) => slot !== null)) {
      addError(
        issue({
          field: "slots",
          dimension: null,
          rule: "routine_entry_slot_requires_cadence",
          message: "Routine Entry slots require a Cadence.",
          limit: "cadence-required"
        })
      );
    }
  } else if (kindIsValid) {
    let validRotatingWindow: number | null = null;
    if (input.cadenceKind === "weekly") {
      if (input.cadenceWindow !== null) {
        addError(cadenceWindowForbiddenIssue());
      }
    } else {
      const window = input.cadenceWindow;
      if (window === null) {
        addError(
          issue({
            field: "cadenceWindow",
            dimension: null,
            rule: "cadence_window_required",
            message: "A rotating Cadence requires a window.",
            limit: "required"
          })
        );
      } else if (!Number.isFinite(window)) {
        addError(
          issue({
            field: "cadenceWindow",
            dimension: null,
            rule: "cadence_window_finite",
            message: "Cadence window must be finite.",
            limit: "finite"
          })
        );
      } else if (window < ROUTINE_CADENCE_VALIDATION_LIMITS.rotatingWindowMin) {
        addError(
          issue({
            field: "cadenceWindow",
            dimension: null,
            rule: "cadence_window_min",
            message: "Cadence window must be at least 1.",
            limit: ROUTINE_CADENCE_VALIDATION_LIMITS.rotatingWindowMin
          })
        );
      } else if (!Number.isInteger(window)) {
        addError(
          issue({
            field: "cadenceWindow",
            dimension: null,
            rule: "cadence_window_integer",
            message: "Cadence window must be an integer.",
            limit: "integer"
          })
        );
      } else {
        validRotatingWindow = window;
        if (window > ROUTINE_CADENCE_VALIDATION_LIMITS.rotatingWindowWarnAbove) {
          warnings.push(
            issue({
              field: "cadenceWindow",
              dimension: null,
              rule: "cadence_window_improbable",
              message: "A rotating Cadence above 31 slots is improbable.",
              limit: ROUTINE_CADENCE_VALIDATION_LIMITS.rotatingWindowWarnAbove
            })
          );
        }
      }
    }

    for (const slot of input.slots) {
      if (slot === null) {
        addError(
          issue({
            field: "slots",
            dimension: null,
            rule: "routine_entry_slot_required",
            message: "Every Routine Entry requires a slot under a Cadence.",
            limit: "required"
          })
        );
        continue;
      }
      if (!Number.isFinite(slot)) {
        addError(
          issue({
            field: "slots",
            dimension: null,
            rule: "routine_entry_slot_finite",
            message: "Routine Entry slots must be finite.",
            limit: "finite"
          })
        );
        continue;
      }
      if (!Number.isInteger(slot)) {
        addError(
          issue({
            field: "slots",
            dimension: null,
            rule: "routine_entry_slot_integer",
            message: "Routine Entry slots must be integers.",
            limit: "integer"
          })
        );
        continue;
      }
      const minimum =
        input.cadenceKind === "weekly"
          ? ROUTINE_CADENCE_VALIDATION_LIMITS.weeklySlotMin
          : ROUTINE_CADENCE_VALIDATION_LIMITS.routineEntrySlotMin;
      const maximum =
        input.cadenceKind === "weekly"
          ? ROUTINE_CADENCE_VALIDATION_LIMITS.weeklySlotMax
          : validRotatingWindow;
      if (slot < minimum || (maximum !== null && slot > maximum)) {
        addError(
          issue({
            field: "slots",
            dimension: null,
            rule: "routine_entry_slot_range",
            message: "Routine Entry slot is outside the Cadence window.",
            limit: maximum === null ? "valid-window" : `1..${maximum}`
          })
        );
      }
    }
  }

  return { errors, warnings };
}

function cadenceWindowForbiddenIssue(): AgentSetValidationIssue {
  return issue({
    field: "cadenceWindow",
    dimension: null,
    rule: "cadence_window_forbidden",
    message: "Only a rotating Cadence may have a window.",
    limit: "null"
  });
}
