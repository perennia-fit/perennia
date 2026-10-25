import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import {
  computeEffectWindowSegments,
  deriveEffectWindow
} from "../src/agent-protocols.ts";

// The app runs the same file (apps/mobile/test/domain/effect_window_golden_test.dart),
// so an agent and the app never report a different Effect window for the same data.
test("the agent Effect window matches the shared M29 golden vectors", async () => {
  const vector = JSON.parse(
    await readFile(
      new URL(
        "../../../packages/golden-vectors/vectors/m29-effect-window.json",
        import.meta.url
      ),
      "utf8"
    )
  );

  assert.equal(vector.domain, "effect-window");
  assert.equal(vector.schemaVersion, 1);
  assert.equal(vector.schema, "m29-effect-window.schema.json");
  assert.ok(vector.cases.length > 0);

  for (const vectorCase of vector.cases) {
    const { input, expected, name } = vectorCase;
    const window = deriveEffectWindow(
      sourceFrom(input.source),
      new Date(input.now)
    );
    assert.deepEqual(windowToJson(window), expected.window, `${name} window`);

    const segments = computeEffectWindowSegments({
      window,
      samples: input.samples.map((sample) => ({
        at: new Date(sample.at),
        value: sample.value
      }))
    });
    for (const key of ["before", "during", "after"]) {
      assert.equal(
        segments[key].count,
        expected.segments[key].count,
        `${name} ${key} count`
      );
      assertNullableClose(
        segments[key].mean,
        expected.segments[key].mean,
        `${name} ${key} mean`
      );
    }

    // The agent surface returns the segment means and leaves the deltas to
    // the caller; these are the same differences the app's
    // OutcomeEffectResult reports, taken from this side's own means.
    assertNullableClose(
      difference(segments.during.mean, segments.before.mean),
      expected.deltas.during,
      `${name} during delta`
    );
    assertNullableClose(
      difference(segments.after.mean, segments.during.mean),
      expected.deltas.after,
      `${name} after delta`
    );
    assertNullableClose(
      difference(segments.after.mean, segments.before.mean),
      expected.deltas.overall,
      `${name} overall delta`
    );
  }
});

function sourceFrom(source) {
  switch (source.kind) {
    case "protocol":
      return {
        kind: "protocol",
        startDate: new Date(source.startDate),
        endDate: source.endDate === null ? null : new Date(source.endDate)
      };
    case "compound":
      return {
        kind: "compound",
        doseTimes: source.doseTimes.map((tookAt) => new Date(tookAt))
      };
    default:
      throw new Error(`Unknown Effect window source: ${source.kind}`);
  }
}

function windowToJson(window) {
  if (window === null) {
    return null;
  }
  return {
    duringStart: window.duringStart.toISOString(),
    duringEnd: window.duringEnd?.toISOString() ?? null,
    duringEndOrNow: window.duringEndOrNow.toISOString(),
    beforeStart: window.beforeStart.toISOString(),
    afterEnd: window.afterEnd.toISOString()
  };
}

function difference(left, right) {
  return left === null || right === null ? null : left - right;
}

function assertNullableClose(actual, expected, message) {
  if (expected === null) {
    assert.equal(actual, null, message);
    return;
  }
  assert.notEqual(actual, null, message);
  assert.ok(
    Math.abs(actual - expected) < 1e-6,
    `${message}: expected ${expected}, got ${actual}`
  );
}
