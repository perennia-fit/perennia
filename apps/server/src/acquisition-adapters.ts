import { z } from "@hono/zod-openapi";

import {
  CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS,
  type CanonicalActivityPlatformExerciseId
} from "./canonical-activity-mapping.js";
import {
  CANONICAL_IMPORT_CONSENT_DATA_CLASSES,
  CanonicalImportConsentDataClassSchema,
  type CanonicalImportConsentDataClass
} from "./canonical-import.js";

export const AcquisitionAdapterKindSchema = z
  .enum(["integration", "import"])
  .openapi("AcquisitionAdapterKind");

export const AcquisitionAdapterExerciseMappingSchema = z
  .object({
    vendorActivityType: z.string().min(1),
    canonicalExerciseId: z.string().min(1)
  })
  .strict()
  .openapi("AcquisitionAdapterExerciseMapping");

export const AcquisitionAdapterRegistrationSchema = z
  .object({
    sourceKey: z.string().min(1),
    adapterKind: AcquisitionAdapterKindSchema,
    exerciseMappings: z.array(AcquisitionAdapterExerciseMappingSchema),
    consentDataClasses: z.array(CanonicalImportConsentDataClassSchema)
  })
  .strict()
  .openapi("AcquisitionAdapterRegistration");

export type AcquisitionAdapterKind = z.infer<
  typeof AcquisitionAdapterKindSchema
>;
export type AcquisitionAdapterExerciseMapping = {
  vendorActivityType: string;
  canonicalExerciseId: CanonicalActivityPlatformExerciseId;
};
export type AcquisitionAdapterRegistration = {
  sourceKey: string;
  adapterKind: AcquisitionAdapterKind;
  exerciseMappings: readonly AcquisitionAdapterExerciseMapping[];
  consentDataClasses: readonly CanonicalImportConsentDataClass[];
};

export type AcquisitionAdapterRegistry = {
  get(sourceKey: string): AcquisitionAdapterRegistration;
  list(): AcquisitionAdapterRegistration[];
  register(adapter: AcquisitionAdapterRegistration): AcquisitionAdapterRegistration;
};

// The explicit seam from INTEGRATIONS.md section 14: each Acquisition adapter
// declares identity, vendor activity mappings, and consent scopes. Downstream
// ingestion stays canonical and vendor-neutral.
export function createAcquisitionAdapterRegistry(
  adapters: readonly AcquisitionAdapterRegistration[] = []
): AcquisitionAdapterRegistry {
  const registry = new Map<string, AcquisitionAdapterRegistration>();
  const api = {
    get(sourceKey) {
      const adapter = registry.get(sourceKey);
      if (adapter === undefined) {
        throw new Error(`Acquisition adapter ${sourceKey} is not registered.`);
      }
      return adapter;
    },
    list() {
      return Array.from(registry.values());
    },
    register(adapter) {
      const parsed = parseAcquisitionAdapterRegistration(adapter);
      if (registry.has(parsed.sourceKey)) {
        throw new Error(
          `Acquisition adapter ${parsed.sourceKey} is already registered.`
        );
      }
      registry.set(parsed.sourceKey, parsed);
      return parsed;
    }
  } satisfies AcquisitionAdapterRegistry;

  for (const adapter of adapters) {
    api.register(adapter);
  }

  return api;

  function parseAcquisitionAdapterRegistration(
    adapter: AcquisitionAdapterRegistration
  ): AcquisitionAdapterRegistration {
    return AcquisitionAdapterRegistrationSchema.parse(
      adapter
    ) as AcquisitionAdapterRegistration;
  }
}

export const GARMIN_OFFICIAL_ACQUISITION_ADAPTER =
  AcquisitionAdapterRegistrationSchema.parse({
    sourceKey: "garmin",
    adapterKind: "integration",
    exerciseMappings: [
      {
        vendorActivityType: "strength_training",
        canonicalExerciseId:
          CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.strengthTraining
      },
      {
        vendorActivityType: "running",
        canonicalExerciseId: CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.running
      },
      {
        vendorActivityType: "cycling",
        canonicalExerciseId: CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.cycling
      },
      {
        vendorActivityType: "swimming",
        canonicalExerciseId: CANONICAL_ACTIVITY_PLATFORM_EXERCISE_IDS.swimming
      }
    ],
    consentDataClasses: CANONICAL_IMPORT_CONSENT_DATA_CLASSES
  }) as AcquisitionAdapterRegistration;

export function createDefaultAcquisitionAdapterRegistry() {
  const registry = createAcquisitionAdapterRegistry();
  registry.register(GARMIN_OFFICIAL_ACQUISITION_ADAPTER);
  return registry;
}
