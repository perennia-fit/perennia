import assert from "node:assert/strict";
import test from "node:test";

import { createApp } from "../src/app.ts";

test("GET /healthz returns the validated health payload", async () => {
  const logEvents = [];
  const app = createApp({
    logger: {
      info(payload, message) {
        logEvents.push({ payload, message });
      }
    }
  });

  const response = await app.request("/healthz");

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("content-type"), "application/json");
  assert.deepEqual(await response.json(), {
    status: "ok",
    version: "0.0.0"
  });
  assert.equal(logEvents.length, 1);
  assert.equal(logEvents[0].message, "request completed");
  assert.equal(logEvents[0].payload.method, "GET");
  assert.equal(logEvents[0].payload.path, "/healthz");
  assert.equal(logEvents[0].payload.status, 200);
  assert.equal(typeof logEvents[0].payload.durationMs, "number");
});
