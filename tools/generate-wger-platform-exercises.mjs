#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { applyPlatformExerciseCleanup } from "./platform-exercise-cleanup.mjs";

const repoRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
);
const wgerRoot = resolveWgerRoot();
const fixtureRoot = path.join(wgerRoot, "wger", "exercises", "fixtures");
const coreFixtureRoot = path.join(wgerRoot, "wger", "core", "fixtures");
const outputPath = path.join(
  repoRoot,
  "apps",
  "mobile",
  "assets",
  "seeds",
  "platform_exercises.json",
);
const dataLicensePath = path.join(
  repoRoot,
  "apps",
  "mobile",
  "assets",
  "seeds",
  "platform_exercises.LICENSE.md",
);
const reviewDecisionsPath = path.join(
  repoRoot,
  "analysis",
  "exercises",
  "review_decisions.json",
);
const workoutCoolSourceUrl = "https://github.com/Snouzy/workout-cool";
const workoutCoolApiUrl =
  process.env.WORKOUT_COOL_API_URL ?? "https://workout.cool/api/exercises/all";
const workoutCoolExercisesPath = process.env.WORKOUT_COOL_EXERCISES_PATH;
const workoutCoolImportEnabled = process.env.WORKOUT_COOL_IMPORT !== "0";
const workoutCoolPageSize = parsePositiveInt(
  process.env.WORKOUT_COOL_PAGE_SIZE,
  100,
);

const sourceCommit = readGitCommit(wgerRoot);
const reviewDecisions = JSON.parse(readFileSync(reviewDecisionsPath, "utf8"));
const seedUpdatedAt = "2026-06-29T00:00:00Z";
const wgerLicensesByPk = readWgerLicenses();

const categories = [
  category("01910000-0000-7000-8000-000000000007", "Chest", 0, "#E06C5A"),
  category("01910000-0000-7000-8000-000000000008", "Back", 1, "#4A8FE0"),
  category("01910000-0000-7000-8000-000000000009", "Legs", 2, "#5FB05C"),
  category("01910000-0000-7000-8000-000000000010", "Shoulders", 3, "#E0A23F"),
  category("01910000-0000-7000-8000-000000000011", "Arms", 4, "#A06CD5"),
  category("01910000-0000-7000-8000-000000000012", "Core", 5, "#3FBFB0"),
  category("01910000-0000-7000-8000-000000000013", "Calves", 6, "#5FB05C"),
  category("01910000-0000-7000-8000-000000000002", "Cardio", 7, "#E0608F"),
  category("01910000-0000-7000-8000-000000000004", "Running", 8, "#12A4A6"),
  category("01910000-0000-7000-8000-000000000005", "Cycling", 9, "#8B5CF6"),
  category("01910000-0000-7000-8000-000000000006", "Swimming", 10, "#0EA5E9"),
  category("01910000-0000-7000-8000-000000000003", "Mobility", 11, "#8A969E"),
  category("01910000-0000-7000-8000-000000000001", "Strength", 12, "#8A969E"),
];

const categoryIdByName = new Map(
  categories.map((entry) => [entry.name, entry.id]),
);
const categoryOrderById = new Map(
  categories.map((entry) => [entry.id, entry.sort_order]),
);

const canonicalExercises = [
  exercise(
    "01910000-0000-7000-8000-000000000101",
    "Barbell Squat",
    ["load", "reps"],
    categoryIdByName.get("Legs"),
    "Platform strength template for load and reps.",
    "2026-01-01T00:00:00Z",
    ["barbell"],
  ),
  exercise(
    "01910000-0000-7000-8000-000000000102",
    "Bench Press",
    ["load", "reps"],
    categoryIdByName.get("Chest"),
    "Platform strength template for load and reps.",
    "2026-01-01T00:00:00Z",
    ["barbell", "bench"],
  ),
  exercise(
    "01910000-0000-7000-8000-000000000103",
    "Deadlift",
    ["load", "reps"],
    categoryIdByName.get("Back"),
    "Platform strength template for load and reps.",
    "2026-01-01T00:00:00Z",
    ["barbell"],
  ),
  exercise(
    "01910000-0000-7000-8000-000000000120",
    "Strength Training",
    ["load", "reps"],
    categoryIdByName.get("Strength"),
    "Generic strength fallback for imported FIT set activities.",
    "2026-06-25T00:00:00Z",
  ),
  exercise(
    "01910000-0000-7000-8000-000000000104",
    "Pull-Up",
    ["reps"],
    categoryIdByName.get("Back"),
    "Platform bodyweight template for reps.",
    "2026-01-01T00:00:00Z",
    ["bodyweight", "pullUpBar"],
  ),
  exercise(
    "01910000-0000-7000-8000-000000000105",
    "Plank",
    ["duration"],
    categoryIdByName.get("Core"),
    "Platform timed hold template.",
    "2026-01-01T00:00:00Z",
    ["bodyweight"],
  ),
  exercise(
    "01910000-0000-7000-8000-000000000106",
    "Run",
    ["duration", "distance"],
    categoryIdByName.get("Cardio"),
    "Platform cardio template for time and distance.",
    "2026-01-01T00:00:00Z",
  ),
  exercise(
    "01910000-0000-7000-8000-000000000107",
    "Walk",
    ["duration", "distance"],
    categoryIdByName.get("Cardio"),
    "Platform cardio template for time and distance.",
    "2026-01-01T00:00:00Z",
  ),
  exercise(
    "01910000-0000-7000-8000-000000000109",
    "Running",
    ["distance", "duration"],
    categoryIdByName.get("Running"),
    "Generic running fallback for imported activities.",
    "2026-06-25T00:00:00Z",
  ),
  exercise(
    "01910000-0000-7000-8000-000000000110",
    "Road Running",
    ["distance", "duration"],
    categoryIdByName.get("Running"),
    "Canonical road-running Platform exercise for imported activities.",
    "2026-06-25T00:00:00Z",
  ),
  exercise(
    "01910000-0000-7000-8000-000000000111",
    "Trail Running",
    ["distance", "duration"],
    categoryIdByName.get("Running"),
    "Canonical trail-running Platform exercise for imported activities.",
    "2026-06-25T00:00:00Z",
  ),
  exercise(
    "01910000-0000-7000-8000-000000000112",
    "Treadmill Running",
    ["distance", "duration"],
    categoryIdByName.get("Running"),
    "Canonical treadmill-running Platform exercise for imported activities.",
    "2026-06-25T00:00:00Z",
  ),
  exercise(
    "01910000-0000-7000-8000-000000000113",
    "Track Running",
    ["distance", "duration"],
    categoryIdByName.get("Running"),
    "Canonical track-running Platform exercise for imported activities.",
    "2026-06-25T00:00:00Z",
  ),
  exercise(
    "01910000-0000-7000-8000-000000000114",
    "Cycling",
    ["distance", "duration"],
    categoryIdByName.get("Cycling"),
    "Generic cycling fallback for imported activities.",
    "2026-06-25T00:00:00Z",
  ),
  exercise(
    "01910000-0000-7000-8000-000000000115",
    "Indoor Cycling",
    ["distance", "duration"],
    categoryIdByName.get("Cycling"),
    "Canonical indoor-cycling Platform exercise for imported activities.",
    "2026-06-25T00:00:00Z",
  ),
  exercise(
    "01910000-0000-7000-8000-000000000116",
    "Outdoor Cycling",
    ["distance", "duration"],
    categoryIdByName.get("Cycling"),
    "Canonical outdoor-cycling Platform exercise for imported activities.",
    "2026-06-25T00:00:00Z",
  ),
  exercise(
    "01910000-0000-7000-8000-000000000117",
    "Swimming",
    ["distance", "duration"],
    categoryIdByName.get("Swimming"),
    "Generic swimming fallback for imported activities.",
    "2026-06-25T00:00:00Z",
  ),
  exercise(
    "01910000-0000-7000-8000-000000000118",
    "Pool Swim",
    ["distance", "duration"],
    categoryIdByName.get("Swimming"),
    "Canonical pool-swim Platform exercise for imported activities.",
    "2026-06-25T00:00:00Z",
  ),
  exercise(
    "01910000-0000-7000-8000-000000000119",
    "Open-Water Swim",
    ["distance", "duration"],
    categoryIdByName.get("Swimming"),
    "Canonical open-water-swim Platform exercise for imported activities.",
    "2026-06-25T00:00:00Z",
  ),
  exercise(
    "01910000-0000-7000-8000-000000000108",
    "Mobility Flow",
    [],
    categoryIdByName.get("Mobility"),
    "Completion-only platform template.",
    "2026-01-01T00:00:00Z",
  ),
];

const canonicalNames = new Set(
  canonicalExercises.map((entry) => nameKey(entry.name)),
);

await main();

async function main() {
  const wgerExercises = buildWgerExercises();
  const workoutCoolComparison = await compareAndMergeWorkoutCool(
    canonicalExercises.concat(wgerExercises),
  );
  const reviewedCleanup = applyPlatformExerciseCleanup(
    workoutCoolComparison.exercises,
    reviewDecisions,
  );
  const allExercises = reviewedCleanup.exercises.sort((left, right) => {
    const categoryDelta =
      categoryOrderById.get(left.category_id) -
      categoryOrderById.get(right.category_id);
    if (categoryDelta !== 0) {
      return categoryDelta;
    }
    return left.name.localeCompare(right.name, "en-US");
  });
  const exerciseRedirects = [...reviewedCleanup.redirects]
    .map(([fromExerciseId, toExerciseId]) => ({
      from_exercise_id: fromExerciseId,
      to_exercise_id: toExerciseId,
    }))
    .sort((left, right) =>
      left.from_exercise_id.localeCompare(right.from_exercise_id, "en-US"),
    );

  const seed = {
    metadata: {
      source_name:
        "wger English exercise fixtures enriched with Workout.cool exercise attributes",
      source_url: "https://github.com/wger-project/wger",
      source_commit: sourceCommit,
      license_summary:
        "The bundled Platform Exercise Library data pack is offered under CC-BY-SA 4.0 because it adapts wger CC-BY-SA exercise fixture records. Per-record wger source license and author metadata is retained in source_attribution. Missing names and structured attributes are compared with Workout.cool; only factual English names and structured attributes are imported from Workout.cool, whose application code is MIT licensed but whose exercise-data provenance is not declared upstream. No wger or Workout.cool images, videos, generated descriptions, thumbnails, or UI assets are bundled.",
      generated_by: "tools/generate-wger-platform-exercises.mjs",
      generated_at: reviewDecisions.reviewedAt,
      reviewed_cleanup: {
        source: reviewDecisions.source,
        source_exported_at: reviewDecisions.sourceExportedAt,
        decision_count: reviewDecisions.sourceDecisionCount,
        excluded_exercises: reviewedCleanup.stats.excludedExercises,
        merged_exercises: reviewedCleanup.stats.mergedExercises,
        renamed_exercises: reviewedCleanup.stats.renamedExercises,
      },
      source_details: [
        {
          name: "wger",
          url: "https://github.com/wger-project/wger",
          commit: sourceCommit,
          imported_fields: ["English names", "categories", "equipment"],
          derived_data_license: "CC-BY-SA-4.0",
        },
        {
          name: "Workout.cool",
          url: workoutCoolSourceUrl,
          api_url: workoutCoolApiUrl,
          imported_fields: [
            "English names",
            "type attributes",
            "muscle attributes",
            "equipment attributes",
          ],
          excluded_fields: [
            "descriptions",
            "videos",
            "thumbnails",
            "UI assets",
          ],
          source_code_license: "MIT",
          exercise_data_provenance: "undeclared upstream",
          imported_records: workoutCoolComparison.stats.sourceRecords,
          matched_records: workoutCoolComparison.stats.matchedRecords,
          added_exercises: workoutCoolComparison.stats.addedExercises,
          enriched_exercises: workoutCoolComparison.stats.enrichedExercises,
        },
      ],
    },
    categories,
    exercise_redirects: exerciseRedirects,
    exercises: allExercises,
  };

  writeFileSync(outputPath, `${JSON.stringify(seed, null, 2)}\n`);
  writeFileSync(
    dataLicensePath,
    buildDataLicenseNotice(seed, workoutCoolComparison),
  );

  console.log(
    [
      `Wrote ${allExercises.length} exercises to ${outputPath}`,
      `wrote data notice to ${dataLicensePath}`,
      `${wgerExercises.length} from wger`,
      `${workoutCoolComparison.stats.sourceRecords} read from Workout.cool`,
      `${workoutCoolComparison.stats.matchedRecords} matched`,
      `${workoutCoolComparison.stats.enrichedExercises} enriched`,
      `${workoutCoolComparison.stats.addedExercises} added`,
      `${reviewedCleanup.stats.excludedExercises} excluded by review`,
      `${reviewedCleanup.stats.mergedExercises} merged by review`,
      `${reviewedCleanup.stats.renamedExercises} renamed by review`,
    ].join("; "),
  );
}

function buildWgerExercises() {
  const bases = readFixture("exercise-base-data.json");
  const translations = readFixture("translations.json");
  const wgerCategories = readFixture("categories.json");
  const equipment = readFixture("equipment.json");
  const baseByPk = new Map(bases.map((entry) => [entry.pk, entry]));
  const categoryNameByPk = new Map(
    wgerCategories.map((entry) => [entry.pk, entry.fields.name]),
  );
  const equipmentNameByPk = new Map(
    equipment.map((entry) => [entry.pk, entry.fields.name]),
  );
  const selectedByName = new Map();

  for (const translation of translations) {
    const fields = translation.fields;
    if (fields.language !== 2) {
      continue;
    }

    const base = baseByPk.get(fields.exercise);
    if (!base) {
      continue;
    }

    const name = cleanExerciseName(fields.name);
    if (!name || canonicalNames.has(nameKey(name))) {
      continue;
    }

    const categoryName = categoryNameByPk.get(base.fields.category);
    const mappedCategoryName = mapWgerCategory(categoryName);
    const equipmentNames = (base.fields.equipment ?? [])
      .map((equipmentId) => equipmentNameByPk.get(equipmentId))
      .filter(Boolean);
    const updatedAt = latestIso(fields.last_update, base.fields.last_update);
    const candidate = exercise(
      wgerExerciseId(base.pk),
      name,
      inferDimensions({
        name,
        wgerCategoryName: categoryName,
        equipmentNames,
      }),
      categoryIdByName.get(mappedCategoryName),
      null,
      updatedAt,
      equipmentIdsFromWger(equipmentNames),
    );
    candidate.source_pk = base.pk;
    candidate.source_attribution = {
      source: "wger",
      exercise_pk: base.pk,
      exercise_uuid: base.fields.uuid,
      exercise_license: wgerLicenseAttribution(base.fields),
      translation_pk: translation.pk,
      translation_license: wgerLicenseAttribution(fields),
    };

    const key = nameKey(name);
    const current = selectedByName.get(key);
    if (!current || isBetterCandidate(candidate, current)) {
      selectedByName.set(key, candidate);
    }
  }

  return [...selectedByName.values()].map((entry) => {
    const { source_pk: _sourcePk, ...seedExercise } = entry;
    return seedExercise;
  });
}

async function compareAndMergeWorkoutCool(baseExercises) {
  const exercises = baseExercises.map((entry) => ({
    ...entry,
    dimension_ids: [...entry.dimension_ids],
    equipment_ids: [...entry.equipment_ids],
  }));
  const index = buildExerciseIndex(exercises);
  const usedIds = new Set(exercises.map((entry) => entry.id));
  const records = workoutCoolImportEnabled
    ? await loadWorkoutCoolRecords()
    : [];
  const normalizedRecords = records
    .map(normalizeWorkoutCoolRecord)
    .filter(Boolean)
    .sort((left, right) => left.name.localeCompare(right.name, "en-US"));
  const importedByName = new Set();
  const stats = {
    sourceRecords: normalizedRecords.length,
    matchedRecords: 0,
    enrichedExercises: 0,
    addedExercises: 0,
  };

  for (const record of normalizedRecords) {
    const recordNameKey = nameKey(record.name);
    if (importedByName.has(recordNameKey)) {
      continue;
    }
    importedByName.add(recordNameKey);

    const existing = findIndexedExercise(index, record.name);
    if (existing) {
      stats.matchedRecords += 1;
      if (mergeEquipmentIds(existing, record.equipmentIds)) {
        appendWorkoutCoolEnrichmentAttribution(existing, record);
        stats.enrichedExercises += 1;
      }
      continue;
    }

    const addedExercise = exercise(
      workoutCoolExerciseId(record.sourceId, record.name, usedIds),
      record.name,
      inferDimensions({
        name: record.name,
        workoutCoolTypes: record.typeAttributes,
        workoutCoolEquipmentIds: record.equipmentIds,
      }),
      categoryIdByName.get(mapWorkoutCoolCategory(record)),
      null,
      seedUpdatedAt,
      record.equipmentIds,
    );
    addedExercise.source_attribution = workoutCoolSourceAttribution(record, [
      "English name",
      "type attributes",
      "muscle attributes",
      "equipment attributes",
    ]);
    exercises.push(addedExercise);
    indexExercise(index, addedExercise);
    stats.addedExercises += 1;
  }

  return { exercises, stats };
}

function appendWorkoutCoolEnrichmentAttribution(exercise, record) {
  const sourceAttribution = exercise.source_attribution ?? {
    source: "Perennia",
  };
  const enrichmentSources = sourceAttribution.enrichment_sources ?? [];
  exercise.source_attribution = {
    ...sourceAttribution,
    enrichment_sources: [
      ...enrichmentSources,
      workoutCoolSourceAttribution(record, ["equipment attributes"]),
    ],
  };
}

function workoutCoolSourceAttribution(record, importedFields) {
  return {
    source: "Workout.cool",
    source_id: record.sourceId,
    source_url: workoutCoolSourceUrl,
    api_url: workoutCoolApiUrl,
    imported_fields: importedFields,
    excluded_fields: ["description", "video", "thumbnail"],
    source_code_license: "MIT",
    exercise_data_provenance: "undeclared upstream",
  };
}

async function loadWorkoutCoolRecords() {
  if (workoutCoolExercisesPath) {
    const fixture = JSON.parse(readFileSync(workoutCoolExercisesPath, "utf8"));
    return workoutCoolPayloadRecords(fixture);
  }

  const firstPage = await fetchWorkoutCoolPage(1);
  const records = workoutCoolPayloadRecords(firstPage);
  const totalPages = Number(firstPage.pagination?.totalPages ?? 1);

  for (let page = 2; page <= totalPages; page += 1) {
    const payload = await fetchWorkoutCoolPage(page);
    records.push(...workoutCoolPayloadRecords(payload));
  }

  return records;
}

async function fetchWorkoutCoolPage(page) {
  const url = new URL(workoutCoolApiUrl);
  url.searchParams.set("page", String(page));
  url.searchParams.set("limit", String(workoutCoolPageSize));
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(
      `Workout.cool exercise fetch failed (${response.status} ${response.statusText}) for ${url}`,
    );
  }
  return response.json();
}

function workoutCoolPayloadRecords(payload) {
  if (Array.isArray(payload)) {
    return payload;
  }
  if (Array.isArray(payload?.data)) {
    return payload.data;
  }
  if (Array.isArray(payload?.exercises)) {
    return payload.exercises;
  }
  return [];
}

function normalizeWorkoutCoolRecord(rawRecord) {
  const name = cleanExerciseName(rawRecord?.nameEn ?? rawRecord?.name);
  if (!name) {
    return null;
  }

  const attributes = Array.isArray(rawRecord.attributes)
    ? rawRecord.attributes
    : [];
  const valuesByName = new Map();
  for (const attribute of attributes) {
    const attributeName =
      attribute?.attributeName?.name ??
      attribute?.attributeName ??
      attribute?.name;
    const attributeValue =
      attribute?.attributeValue?.value ??
      attribute?.attributeValue ??
      attribute?.value;
    if (!attributeName || !attributeValue) {
      continue;
    }

    const key = String(attributeName).toLocaleUpperCase("en-US");
    const values = valuesByName.get(key) ?? [];
    values.push(String(attributeValue).toLocaleUpperCase("en-US"));
    valuesByName.set(key, values);
  }

  return {
    sourceId: String(
      rawRecord.id ?? rawRecord.slugEn ?? rawRecord.slug ?? name,
    ),
    name,
    typeAttributes: valuesByName.get("TYPE") ?? [],
    primaryMuscles: valuesByName.get("PRIMARY_MUSCLE") ?? [],
    secondaryMuscles: valuesByName.get("SECONDARY_MUSCLE") ?? [],
    equipmentIds: equipmentIdsFromWorkoutCool(
      valuesByName.get("EQUIPMENT") ?? [],
    ),
  };
}

function buildExerciseIndex(exercises) {
  const index = {
    byName: new Map(),
    byCompactName: new Map(),
  };
  for (const entry of exercises) {
    indexExercise(index, entry);
  }
  return index;
}

function indexExercise(index, entry) {
  index.byName.set(nameKey(entry.name), entry);
  index.byCompactName.set(compactNameKey(entry.name), entry);
}

function findIndexedExercise(index, name) {
  return (
    index.byName.get(nameKey(name)) ??
    index.byCompactName.get(compactNameKey(name))
  );
}

function mergeEquipmentIds(target, incomingEquipmentIds) {
  if (incomingEquipmentIds.length === 0) {
    return false;
  }

  const mergedIds = [
    ...new Set([...(target.equipment_ids ?? []), ...incomingEquipmentIds]),
  ];
  if (mergedIds.length === target.equipment_ids.length) {
    return false;
  }

  target.equipment_ids = mergedIds;
  return true;
}

function mapWorkoutCoolCategory(record) {
  const bodyPart = [...record.primaryMuscles, ...record.secondaryMuscles].find(
    Boolean,
  );
  switch (bodyPart) {
    case "CHEST":
      return "Chest";
    case "BACK":
    case "LATS":
    case "TRAPS":
      return "Back";
    case "QUADRICEPS":
    case "HAMSTRINGS":
    case "GLUTES":
    case "ADDUCTORS":
    case "ABDUCTORS":
    case "HIP_FLEXOR":
    case "GROIN":
      return "Legs";
    case "CALVES":
    case "ACHILLES_TENDON":
      return "Calves";
    case "SHOULDERS":
    case "ROTATOR_CUFF":
    case "NECK":
      return "Shoulders";
    case "BICEPS":
    case "TRICEPS":
    case "FOREARMS":
    case "FINGERS":
      return "Arms";
    case "ABDOMINALS":
    case "OBLIQUES":
      return "Core";
    default:
      break;
  }

  if (record.typeAttributes.includes("CARDIO")) {
    return "Cardio";
  }
  if (
    record.typeAttributes.includes("STRETCHING") ||
    record.typeAttributes.includes("STABILIZATION")
  ) {
    return "Mobility";
  }
  return "Strength";
}

function buildDataLicenseNotice(seed, workoutCoolComparison) {
  const wgerAttributions = seed.exercises
    .map((entry) => entry.source_attribution)
    .filter((entry) => entry?.source === "wger");
  const authorBuckets = buildWgerAuthorBuckets(wgerAttributions);
  const authorLines = [...authorBuckets.entries()]
    .sort(([left], [right]) => left.localeCompare(right, "en-US"))
    .map(([licenseName, authors]) => {
      const authorText = [...authors].sort((left, right) =>
        left.localeCompare(right, "en-US"),
      );
      return [
        `### ${licenseName}`,
        "",
        `Distinct source author count: ${authorText.length}.`,
        "",
        ...authorText.map((author) => `- ${author}`),
        "",
      ].join("\n");
    })
    .join("\n");

  return `# Perennia Platform Exercise Library Data License

SPDX-License-Identifier: CC-BY-SA-4.0

This file applies to \`platform_exercises.json\`, the bundled Platform Exercise
Library data asset. The application source code in the rest of the repository is
licensed separately by the repository root \`LICENSE\`.

The bundled data asset is offered under the Creative Commons Attribution-ShareAlike
4.0 International license: https://creativecommons.org/licenses/by-sa/4.0/

## Sources And Changes

- wger exercise fixtures: https://github.com/wger-project/wger
- wger commit: ${sourceCommit ?? "unknown"}
- Workout.cool exercise API and repository: ${workoutCoolSourceUrl}
- Workout.cool API endpoint used by the generator: ${workoutCoolApiUrl}

Changes were made by Perennia:

- English exercise names were cleaned for app display.
- wger categories were mapped into Perennia Categories.
- Perennia Exercise Type input dimensions were inferred.
- Structured equipment identifiers were normalized into Perennia Equipment.
- Workout.cool English names and structured type/muscle/equipment attributes were
  compared with the wger-derived seed to enrich matched records and add missing
  exercise rows.
- Images, videos, thumbnails, generated descriptions, and UI assets were not copied.

## Source License Posture

wger fixture records carry per-record license and author metadata. The generated
JSON retains that metadata in each wger-derived exercise's \`source_attribution\`
object. Because the data pack adapts CC-BY-SA records, the complete bundled data
asset is distributed under CC-BY-SA 4.0.

Workout.cool's application source is MIT licensed, but the upstream exercise-data
provenance is not declared. Perennia imports only factual English names and
structured attributes from Workout.cool, and records that source boundary in the
generated JSON. Workout.cool contribution counts for this generation:

- ${workoutCoolComparison.stats.sourceRecords} source records read.
- ${workoutCoolComparison.stats.matchedRecords} source records matched existing rows.
- ${workoutCoolComparison.stats.enrichedExercises} existing rows enriched.
- ${workoutCoolComparison.stats.addedExercises} missing exercise rows added.

## wger Author Attribution Buckets

The following names are copied from wger's \`license_author\` fixture fields for
records that contributed to this generated seed. Names are grouped by the source
license id/title reported by wger.

${authorLines}`.trimEnd() + "\n";
}

function buildWgerAuthorBuckets(attributions) {
  const buckets = new Map();
  for (const attribution of attributions) {
    for (const license of [
      attribution.exercise_license,
      attribution.translation_license,
    ]) {
      if (!license?.author) {
        continue;
      }
      const label =
        license.short_name ?? `wger license ${license.id ?? "unknown"}`;
      const authors = buckets.get(label) ?? new Set();
      authors.add(license.author);
      buckets.set(label, authors);
    }
  }
  return buckets;
}

function category(id, name, sortOrder, colorHex) {
  return {
    id,
    name,
    sort_order: sortOrder,
    color_hex: colorHex,
    updated_at: seedUpdatedAt,
  };
}

function exercise(
  id,
  name,
  dimensions,
  categoryId,
  notes,
  updatedAt,
  equipmentIds = [],
) {
  return {
    id,
    name,
    dimension_ids: dimensions,
    category_id: categoryId,
    equipment_ids: equipmentIds,
    notes,
    updated_at: updatedAt,
  };
}

function readFixture(filename) {
  return JSON.parse(readFileSync(path.join(fixtureRoot, filename), "utf8"));
}

function readWgerLicenses() {
  const licenses = JSON.parse(
    readFileSync(path.join(coreFixtureRoot, "licenses.json"), "utf8"),
  );
  return new Map(
    licenses.map((entry) => [
      entry.pk,
      {
        id: entry.pk,
        full_name: entry.fields.full_name.trim(),
        short_name: entry.fields.short_name.trim(),
        url: entry.fields.url,
      },
    ]),
  );
}

function wgerLicenseAttribution(fields) {
  const license = wgerLicensesByPk.get(fields.license) ?? {
    id: fields.license,
    full_name: null,
    short_name: null,
    url: null,
  };
  return {
    ...license,
    author: String(fields.license_author ?? "").trim() || null,
    author_url: String(fields.license_author_url ?? "").trim() || null,
    object_url: String(fields.license_object_url ?? "").trim() || null,
    derivative_source_url:
      String(fields.license_derivative_source_url ?? "").trim() || null,
  };
}

function readGitCommit(gitRoot) {
  try {
    return execFileSync("git", ["-C", gitRoot, "rev-parse", "HEAD"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return null;
  }
}

function resolveWgerRoot() {
  const root = process.env.WGER_REPO;
  if (!root) {
    throw new Error(
      "Set WGER_REPO to the root of a checked-out wger repository before running this generator.",
    );
  }
  return path.resolve(root);
}

function cleanExerciseName(rawName) {
  let name = String(rawName ?? "")
    .trim()
    .replace(/\s+/g, " ");
  name = name
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[’]/g, "'")
    .replace(/[–—]/g, "-")
    .replace(/[°]/g, " Degree");
  name = name.replace(/^\d+\s+/, "");
  name = name.replace(/\s+HD$/i, "");
  name = name.replace(/\bDB\b/g, "Dumbbell");
  name = name.replace(/\bKB\b/g, "Kettlebell");
  name = name.replace(/\bBB\b/g, "Barbell");
  name = name.replace(/\bw\s*\/\s*(?!o\b)/gi, "with ");

  if (!/[a-z]/.test(name) && /[A-Z]/.test(name)) {
    name = name
      .toLowerCase()
      .replace(/\b[a-z]/g, (letter) => letter.toUpperCase());
  }

  return name.trim();
}

function nameKey(name) {
  return String(name).trim().replace(/\s+/g, " ").toLocaleLowerCase("en-US");
}

function mapWgerCategory(categoryName) {
  if (categoryName === "Abs") {
    return "Core";
  }
  return categoryName;
}

function inferDimensions({
  name,
  wgerCategoryName,
  equipmentNames = [],
  workoutCoolTypes = [],
  workoutCoolEquipmentIds = [],
}) {
  const lower = name.toLocaleLowerCase("en-US");
  const workoutCoolTypeSet = new Set(workoutCoolTypes);
  if (
    wgerCategoryName === "Cardio" ||
    /\b(run|running|walk|walking|bike|bicycle|cycling|swim|swimming|elliptical|stair master|treadmill|jump rope|rower|rowing machine)\b/.test(
      lower,
    ) ||
    /\b(rowing machine|recumbent bike|stationary bike)\b/.test(lower)
  ) {
    return ["distance", "duration"];
  }

  if (
    workoutCoolTypeSet.has("STRETCHING") ||
    workoutCoolTypeSet.has("STABILIZATION") ||
    /\b(plank|hold|wall[- ]?sit|l[- ]?sit|stretch|dead hang|support hold|isometric hold)\b/.test(
      lower,
    )
  ) {
    return ["duration"];
  }

  if (
    isBodyweightEquipment(equipmentNames) ||
    isBodyweightEquipmentIds(workoutCoolEquipmentIds) ||
    workoutCoolTypeSet.has("PLYOMETRICS") ||
    workoutCoolTypeSet.has("CALISTHENIC") ||
    /\b(push[- ]?ups?|pull[- ]?ups?|chin[- ]?ups?|dips?|crunch(?:es)?|sit[- ]?ups?|leg raises?|burpees?|jumping jacks?|mountain climbers?|bodyweight)\b/.test(
      lower,
    )
  ) {
    return ["reps"];
  }

  if (workoutCoolTypeSet.has("CARDIO")) {
    return ["duration"];
  }

  return ["load", "reps"];
}

function isBodyweightEquipment(equipmentNames) {
  if (equipmentNames.length === 0) {
    return false;
  }

  const bodyweightEquipment = new Set([
    "Gym mat",
    "Pull-up bar",
    "none (bodyweight exercise)",
    "Resistance band",
  ]);

  return equipmentNames.every((name) => bodyweightEquipment.has(name));
}

function equipmentIdsFromWger(equipmentNames) {
  const ids = equipmentNames.map(equipmentIdFromWgerName).filter(Boolean);
  return [...new Set(ids)];
}

function equipmentIdsFromWorkoutCool(equipmentValues) {
  const ids = equipmentValues
    .map(equipmentIdFromWorkoutCoolValue)
    .filter(Boolean);
  return [...new Set(ids)];
}

function equipmentIdFromWgerName(name) {
  switch (name) {
    case "none (bodyweight exercise)":
      return "bodyweight";
    case "Resistance band":
      return "band";
    case "Pull-up bar":
      return "pullUpBar";
    case "Incline bench":
      return "inclineBench";
    case "Gym mat":
      return "gymMat";
    case "Swiss Ball":
      return "swissBall";
    case "SZ-Bar":
      return "ezBar";
    case "Barbell":
      return "barbell";
    case "Bench":
      return "bench";
    case "Dumbbell":
      return "dumbbell";
    case "Kettlebell":
      return "kettlebell";
    default:
      return equipmentIdFromName(name);
  }
}

function equipmentIdFromWorkoutCoolValue(value) {
  switch (value) {
    case "BODY_ONLY":
    case "NONE":
      return "bodyweight";
    case "DUMBBELL":
      return "dumbbell";
    case "KETTLEBELLS":
      return "kettlebell";
    case "BARBELL":
    case "BAR":
      return "barbell";
    case "BANDS":
      return "band";
    case "WEIGHT_PLATE":
      return "plate";
    case "PULLUP_BAR":
      return "pullUpBar";
    case "BENCH":
      return "bench";
    case "CABLE":
      return "cable";
    case "MACHINE":
      return "machine";
    case "SMITH_MACHINE":
      return "smithMachine";
    case "EZ_BAR":
      return "ezBar";
    case "MEDICINE_BALL":
      return "medicineBall";
    case "SWISS_BALL":
      return "swissBall";
    case "FOAM_ROLL":
      return "foamRoll";
    case "TRX":
      return "trx";
    case "BOX":
      return "box";
    case "BOSU":
      return "bosu";
    case "ROPES":
    case "ROPE":
      return "rope";
    case "SPIN_BIKE":
      return "spinBike";
    case "STEP":
      return "step";
    case "SLED":
      return "sled";
    case "SANDBAG":
      return "sandbag";
    case "WALL":
      return "wall";
    case "RACK":
      return "rack";
    case "SKIERG":
      return "skiErg";
    case "OTHER":
    case "NA":
      return null;
    default:
      return null;
  }
}

function equipmentIdFromName(name) {
  const words = String(name ?? "")
    .trim()
    .toLocaleLowerCase("en-US")
    .replace(/[^a-z0-9]+/g, " ")
    .split(/\s+/)
    .filter(Boolean);
  if (words.length === 0) {
    return null;
  }

  return words
    .map((word, index) =>
      index === 0
        ? word
        : `${word[0].toLocaleUpperCase("en-US")}${word.slice(1)}`,
    )
    .join("");
}

function wgerExerciseId(sourcePk) {
  return `01910000-0000-7000-8000-${String(200000 + sourcePk).padStart(12, "0")}`;
}

function workoutCoolExerciseId(sourceId, name, usedIds) {
  let hash = stableHash(`${sourceId}:${name}`);
  while (true) {
    const candidate = `01910000-0000-7000-8000-${String(800000000000 + hash).padStart(12, "0")}`;
    if (!usedIds.has(candidate)) {
      usedIds.add(candidate);
      return candidate;
    }
    hash = (hash + 1) >>> 0;
  }
}

function compactNameKey(name) {
  return nameKey(name).replace(/[^a-z0-9]+/g, "");
}

function isBodyweightEquipmentIds(equipmentIds) {
  if (equipmentIds.length === 0) {
    return false;
  }

  const bodyweightOnlyIds = new Set([
    "bodyweight",
    "band",
    "gymMat",
    "pullUpBar",
    "trx",
    "foamRoll",
    "box",
    "bosu",
    "bench",
    "rope",
    "step",
    "wall",
  ]);

  return equipmentIds.every((id) => bodyweightOnlyIds.has(id));
}

function stableHash(value) {
  let hash = 2166136261;
  for (const character of String(value)) {
    hash ^= character.charCodeAt(0);
    hash = Math.imul(hash, 16777619) >>> 0;
  }
  return hash;
}

function parsePositiveInt(value, fallback) {
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function latestIso(left, right) {
  const leftTime = Date.parse(left);
  const rightTime = Date.parse(right);
  if (!Number.isFinite(leftTime) && !Number.isFinite(rightTime)) {
    return seedUpdatedAt;
  }
  if (!Number.isFinite(leftTime)) {
    return new Date(rightTime).toISOString().replace(".000Z", "Z");
  }
  if (!Number.isFinite(rightTime)) {
    return new Date(leftTime).toISOString().replace(".000Z", "Z");
  }
  const latest = leftTime >= rightTime ? leftTime : rightTime;
  return new Date(latest).toISOString().replace(".000Z", "Z");
}

function isBetterCandidate(candidate, current) {
  const candidateTime = Date.parse(candidate.updated_at);
  const currentTime = Date.parse(current.updated_at);
  if (candidateTime !== currentTime) {
    return candidateTime > currentTime;
  }

  return candidate.source_pk < current.source_pk;
}
