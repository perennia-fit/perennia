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
    redirects,
    stats: {
      excludedExercises: excludedIds.size,
      mergedExercises: redirects.size,
      renamedExercises: replacements.size,
    },
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
