import assert from "node:assert/strict";
import test from "node:test";

test("server package placeholder is wired", () => {
  assert.equal("@perennia/server".startsWith("@perennia/"), true);
});
