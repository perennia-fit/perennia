export function applyPlatformExerciseCleanup(exercises, manifest) {
  if (!Array.isArray(exercises)) {
    throw new TypeError("Platform exercises must be an array.");
  }

  const reviewedAt = String(manifest?.reviewedAt ?? "").trim();
  if (!reviewedAt || !Number.isFinite(Date.parse(reviewedAt))) {
    throw new Error("Platform exercise cleanup requires a valid reviewedAt timestamp.");
  }

  const normalizedExercises = exercises.map((exercise) => ({
    ...exercise,
    id: normalizeId(exercise?.id, "Platform exercise"),
  }));
  const exercisesById = new Map();
  for (const exercise of normalizedExercises) {
    const { id } = exercise;
    if (exercisesById.has(id)) {
      throw new Error(`Duplicate Platform exercise id: ${id}`);
    }
    exercisesById.set(id, exercise);
  }

  const excludedIds = new Set(
    (manifest.excludedExerciseIds ?? []).map((id) =>
      normalizeId(id, "Excluded exercise"),
    ),
  );
  const mergeTargets = new Map();
  for (const merge of manifest.merges ?? []) {
    const removeExerciseId = normalizeId(
      merge.removeExerciseId,
      "Merge removal",
    );
    const keepExerciseId = normalizeId(merge.keepExerciseId, "Merge target");
    requireExercise(exercisesById, removeExerciseId, "merge removal");
    requireExercise(exercisesById, keepExerciseId, "merge target");
    const targets = mergeTargets.get(removeExerciseId) ?? new Set();
    targets.add(keepExerciseId);
    mergeTargets.set(removeExerciseId, targets);
  }
  for (const id of excludedIds) requireExercise(exercisesById, id, "exclusion");

  const redirects = new Map();
  const resolving = new Set();
  function resolveMergeTarget(id) {
    if (redirects.has(id)) return redirects.get(id);
    if (resolving.has(id)) throw new Error(`Merge cycle includes ${id}.`);
    const targets = mergeTargets.get(id);
    if (!targets) return id;

    resolving.add(id);
    const canonicalTargets = new Set(
      [...targets].map((target) => resolveMergeTarget(target)),
    );
    resolving.delete(id);
    if (canonicalTargets.size !== 1) {
      throw new Error(
        `Merge decisions for ${id} do not converge on one retained exercise.`,
      );
    }
    const [canonicalId] = canonicalTargets;
    if (excludedIds.has(canonicalId)) {
      throw new Error(`Merge target ${canonicalId} is also excluded.`);
    }
    redirects.set(id, canonicalId);
    return canonicalId;
  }
  for (const id of mergeTargets.keys()) resolveMergeTarget(id);

  const replacements = new Map();
  for (const replacement of manifest.replacements ?? []) {
    const id = normalizeId(
      replacement.exerciseId,
      "English name replacement",
    );
    requireExercise(exercisesById, id, "English name replacement");
    if (excludedIds.has(id) || redirects.has(id)) {
      throw new Error(`English name replacement targets removed exercise ${id}.`);
    }
    const englishName = String(replacement.englishName ?? "").trim();
    if (!englishName) throw new Error(`English name replacement for ${id} is empty.`);
    const previous = replacements.get(id);
    if (previous && previous !== englishName) {
      throw new Error(`Conflicting English names were supplied for ${id}.`);
    }
    replacements.set(id, englishName);
  }

  const cleanedExercises = normalizedExercises
    .filter(
      (exercise) =>
        !excludedIds.has(exercise.id) && !redirects.has(exercise.id),
    )
    .map((exercise) => {
      const englishName = replacements.get(exercise.id);
      if (!englishName) return exercise;
      const sourceAttribution = exercise.source_attribution;
      return {
        ...exercise,
        name: englishName,
        updated_at: reviewedAt,
        ...(sourceAttribution && typeof sourceAttribution === "object"
          ? {
              source_attribution: {
                ...sourceAttribution,
                reviewed_name_cleanup: {
                  decision: "replace_with_english",
                  english_name: englishName,
                  original_name: exercise.name,
                  reviewed_at: reviewedAt,
                },
              },
            }
          : {}),
      };
    });

  return {
    exercises: cleanedExercises,
    excludedIds,
    redirects,
    stats: {
      excludedExercises: excludedIds.size,
      mergedExercises: redirects.size,
      renamedExercises: replacements.size,
    },
  };
}

/**
 * Builds the seed's `retired_exercises` list from the previous seed and this
 * run's cleanup.
 *
 * The list is append-only: a device may hold any id that ever shipped, and the
 * `retired_at` stamp is what lets devices that update at different times agree,
 * so a record once listed never changes. A newly retired id prefers its previous
 * seed record over the source record, so a corrected name survives.
 *
 * `sourceRecords` is the input given to `applyPlatformExerciseCleanup`, so its
 * ids are not normalized yet. `reviewedAt` is the manifest's top-level timestamp.
 */
export function buildRetiredExercises({
  previousSeed,
  sourceRecords,
  cleanup,
  retiredAt,
  reviewedAt,
  categories,
  focusIdsFor,
}) {
  const stamp = String(retiredAt ?? "").trim();
  if (!stamp || !Number.isFinite(Date.parse(stamp))) {
    throw new Error("Retired exercises require a valid retiredAt timestamp.");
  }

  const previousRetired = previousSeed?.retired_exercises ?? [];
  const previousLive = previousSeed?.exercises ?? [];
  const previousLiveById = new Map(
    previousLive.map((exercise) => [exercise.id, exercise]),
  );
  const carriedIds = new Set(previousRetired.map((record) => record.id));
  const sourceById = new Map(
    sourceRecords.map((record) => [
      normalizeId(record?.id, "Platform exercise"),
      record,
    ]),
  );

  const newlyRetired = [
    ...new Set([...cleanup.excludedIds, ...cleanup.redirects.keys()]),
  ]
    .filter((id) => !carriedIds.has(id))
    .map((id) => {
      const previous = previousLiveById.get(id);
      if (previous) return retiredRecord(id, previous, previous.focus_ids, stamp);
      const source = sourceById.get(id);
      if (!source) {
        throw new Error(
          `Newly retired exercise ${id} has no previous seed or source record.`,
        );
      }
      return retiredRecord(id, source, focusIdsFor(source), stamp);
    });

  if (
    newlyRetired.length > 0 &&
    !(Date.parse(stamp) > Date.parse(reviewedAt))
  ) {
    throw new Error(
      `retiredAt ${stamp} must be later than reviewedAt ${reviewedAt} to retire ${newlyRetired[0].id}.`,
    );
  }

  const retired = [...previousRetired, ...newlyRetired].sort((left, right) =>
    left.id.localeCompare(right.id, "en-US"),
  );
  const categoryIds = new Set(categories.map((category) => category.id));
  for (const record of retired) {
    if (!categoryIds.has(record.category_id)) {
      throw new Error(
        `Retired exercise ${record.id} names unknown category ${record.category_id}.`,
      );
    }
    // By instant, not by string: the seed has both ...Z and ....000Z forms.
    if (!(Date.parse(record.retired_at) > Date.parse(record.updated_at))) {
      throw new Error(
        `Retired exercise ${record.id} has retired_at ${record.retired_at} not later than updated_at ${record.updated_at}.`,
      );
    }
  }

  const retiredIds = new Set(retired.map((record) => record.id));
  const liveIds = new Set();
  for (const exercise of cleanup.exercises) {
    liveIds.add(exercise.id);
    if (retiredIds.has(exercise.id)) {
      throw new Error(`Exercise ${exercise.id} is both live and retired.`);
    }
    const previous = previousLiveById.get(exercise.id);
    if (
      previous &&
      JSON.stringify(previous.dimension_ids) !==
        JSON.stringify(exercise.dimension_ids)
    ) {
      throw new Error(
        `Live exercise ${exercise.id} changed dimension_ids from the previous seed.`,
      );
    }
  }
  for (const { id } of [...previousLive, ...previousRetired]) {
    if (!liveIds.has(id) && !retiredIds.has(id)) {
      throw new Error(
        `Exercise ${id} from the previous seed is neither live nor retired.`,
      );
    }
  }

  return retired;
}

// The seed format's exact keys and order; other source keys are not copied.
function retiredRecord(id, record, focusIds, retiredAt) {
  const sourceAttribution = record.source_attribution;
  return {
    id,
    name: record.name,
    dimension_ids: record.dimension_ids,
    category_id: record.category_id,
    equipment_ids: record.equipment_ids,
    focus_ids: focusIds,
    notes: record.notes ?? null,
    updated_at: record.updated_at,
    retired_at: retiredAt,
    ...(sourceAttribution == null
      ? {}
      : { source_attribution: sourceAttribution }),
  };
}

function normalizeId(value, label) {
  const id = String(value ?? "").trim();
  if (!id) throw new Error(`${label} must have an id.`);
  return id;
}

function requireExercise(exercisesById, id, decisionType) {
  if (!exercisesById.has(id)) {
    throw new Error(`Reviewed ${decisionType} references unknown exercise ${id}.`);
  }
}
