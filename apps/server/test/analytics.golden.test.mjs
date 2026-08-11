import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import test from "node:test";

import { ExerciseAnalyticsEngine } from "../src/analytics/exercise-analytics.ts";

const engine = new ExerciseAnalyticsEngine();

test("server analytics matches the shared golden vectors", async () => {
  const vectorsUrl = new URL("../../../packages/golden-vectors/vectors/", import.meta.url);
  const filenames = (await readdir(vectorsUrl)).filter(
    (name) => name.endsWith(".json") && !name.endsWith(".schema.json")
  );

  for (const filename of filenames) {
    const vector = JSON.parse(await readFile(new URL(filename, vectorsUrl), "utf8"));
    if (vector.domain !== undefined && vector.domain !== "analytics") {
      continue;
    }
    for (const vectorCase of vector.cases) {
      const result = engine.compute({
        profile: {
          type: vectorCase.exercise.dimensions,
          loadMode: vectorCase.exercise.loadMode,
          recordProfile: vectorCase.exercise.recordProfile
        },
        sets: vectorCase.sets.map((set) => ({
          id: set.id,
          performedAt: new Date(set.performedAt),
          sequence: set.position,
          values: set.values
        }))
      });
      const reason = `${filename} ${vectorCase.name}`;
      const expected = vectorCase.expected;

      assert.equal(result.estimatedOneRepMax.isDefined, expected.e1rmDefined, reason);
      assert.equal(result.volume.isDefined, expected.volumeDefined, reason);

      if (expected.repMaxRecords !== undefined) {
        assertRecordsEqual(
          result.recordCatalog.repMaxRecords,
          expected.repMaxRecords,
          reason
        );
      }

      if (expected.minAssistanceRecords !== undefined) {
        assertRecordsEqual(
          result.recordCatalog.minAssistanceRecords,
          expected.minAssistanceRecords,
          reason
        );
      }

      if (expected.e1rmValues !== undefined) {
        assert.equal(result.estimatedOneRepMax.points.length, 10, reason);
        expected.e1rmValues.forEach((expectedValue, index) => {
          assertAlmostEqual(
            result.estimatedOneRepMax.points[index].value,
            expectedValue,
            `${reason} e1RM[${index}]`
          );
        });
      }

      if (expected.maxDistanceRecord !== undefined) {
        assertRecordEqual(
          result.recordCatalog.maxDistance,
          expected.maxDistanceRecord,
          reason
        );
      }

      if (expected.fastestPaceRecord !== undefined) {
        assertRecordEqual(
          result.recordCatalog.fastestPace,
          expected.fastestPaceRecord,
          reason
        );
      }

      if (expected.volumeValues !== undefined) {
        assert.equal(result.volume.points.length, expected.volumeValues.length, reason);
        expected.volumeValues.forEach((expectedValue, index) => {
          assertAlmostEqual(
            result.volume.points[index].value,
            expectedValue,
            `${reason} volume[${index}]`
          );
        });
      }
    }
  }
});

function assertRecordEqual(actual, expected, reason) {
  assert.notEqual(actual, null, reason);
  assert.equal(actual.setId, expected.setId, reason);
  assertAlmostEqual(actual.value, expected.value, reason);
  assert.equal(actual.unit, expected.unit, reason);
}

function assertRecordsEqual(actual, expected, reason) {
  assert.equal(actual.length, expected.length, reason);

  expected.forEach((expectedRecord, index) => {
    const actualRecord = actual[index];

    assert.equal(actualRecord.setId, expectedRecord.setId, reason);
    assert.equal(actualRecord.reps, expectedRecord.reps, reason);
    assertAlmostEqual(actualRecord.value, expectedRecord.value, reason);
    assert.equal(actualRecord.unit, expectedRecord.unit, reason);
  });
}

function assertAlmostEqual(actual, expected, reason) {
  assert.ok(
    Math.abs(actual - expected) <= 0.000001,
    `${reason}: expected ${actual} to be within 0.000001 of ${expected}`
  );
}
