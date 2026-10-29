import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { SERVER_VERSION } from "../src/server-version.ts";

test("SERVER_VERSION is the version in apps/server/package.json", () => {
  const packageJson = JSON.parse(
    readFileSync(new URL("../package.json", import.meta.url), "utf8")
  );

  assert.equal(SERVER_VERSION, packageJson.version);
  assert.match(SERVER_VERSION, /^\d+\.\d+\.\d+$/);
});
