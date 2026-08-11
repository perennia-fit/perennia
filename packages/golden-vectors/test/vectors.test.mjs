import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import test from "node:test";

test("m0 smoke vector is valid JSON", async () => {
  const raw = await readFile(new URL("../vectors/m0-smoke.json", import.meta.url), "utf8");
  const vector = JSON.parse(raw);

  assert.equal(vector.name, "m0-smoke");
  assert.deepEqual(vector.cases, []);
});

test("all vector fixtures are valid JSON case files", async () => {
  const vectorsUrl = new URL("../vectors/", import.meta.url);
  const filenames = (await readdir(vectorsUrl)).filter(
    (name) => name.endsWith(".json") && !name.endsWith(".schema.json"),
  );

  assert.ok(filenames.length > 0);
  for (const filename of filenames) {
    const raw = await readFile(new URL(filename, vectorsUrl), "utf8");
    const vector = JSON.parse(raw);

    assert.equal(typeof vector.name, "string", filename);
    assert.ok(Array.isArray(vector.cases), filename);
  }
});

test("workout capture publishes its versioned language-neutral schema", async () => {
  const schema = JSON.parse(
    await readFile(
      new URL("../vectors/m33-workout-capture.schema.json", import.meta.url),
      "utf8",
    ),
  );
  const vector = JSON.parse(
    await readFile(
      new URL("../vectors/m33-workout-capture.json", import.meta.url),
      "utf8",
    ),
  );

  assert.equal(schema.$schema, "https://json-schema.org/draft/2020-12/schema");
  assert.equal(schema.properties.schemaVersion.const, 1);
  assert.equal(vector.schemaVersion, schema.properties.schemaVersion.const);
  assert.equal(vector.schema, "m33-workout-capture.schema.json");
});
