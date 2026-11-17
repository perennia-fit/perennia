import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import test from "node:test";

import { barcodeCandidates } from "../src/barcode-candidates.ts";

// The app runs the same vectors (apps/mobile/test/domain/barcode_candidates_golden_test.dart),
// so an agent and the app try the same barcodes for the same code.
test("barcode candidates match the shared golden vectors", async () => {
  const vectorsUrl = new URL("../../../packages/golden-vectors/vectors/", import.meta.url);
  const filenames = (await readdir(vectorsUrl)).filter(
    (name) => name.endsWith(".json") && !name.endsWith(".schema.json")
  );

  let casesRun = 0;
  for (const filename of filenames) {
    const vector = JSON.parse(await readFile(new URL(filename, vectorsUrl), "utf8"));
    if (vector.domain !== "barcode-candidates") {
      continue;
    }
    for (const { name, input, expected } of vector.cases) {
      assert.deepEqual(barcodeCandidates(input), expected, `${filename}: ${name}`);
      casesRun += 1;
    }
  }
  assert.ok(casesRun > 0, "no barcode-candidates golden vector case ran");
});
