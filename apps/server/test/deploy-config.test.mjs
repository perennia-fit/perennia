import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const repoRoot = new URL("../../../", import.meta.url);

async function readRepoFile(path) {
  return readFile(new URL(path, repoRoot), "utf8");
}

test("server package exposes the production build used by the Docker image", async () => {
  const packageJson = JSON.parse(
    await readFile(new URL("../package.json", import.meta.url), "utf8")
  );

  assert.equal(packageJson.scripts.build, "tsc -p tsconfig.build.json");
  assert.equal(packageJson.scripts["start:worker"], "node --import tsx src/worker.ts");
  assert.match(packageJson.dependencies["@sentry/node"], /^\^?[0-9]+\./);
  assert.equal(packageJson.dependencies["pg-boss"], "12.25.1");
});

test("Docker image builds the server once and runs the compiled app", async () => {
  const dockerfile = await readRepoFile("Dockerfile");

  assert.match(
    dockerfile,
    /corepack pnpm --filter @perennia\/server build/
  );
  assert.match(
    dockerfile,
    /COPY --from=build \/app\/apps\/server\/dist \.\/apps\/server\/dist/
  );
  assert.match(
    dockerfile,
    /COPY --from=build \/app\/apps\/server\/drizzle \.\/apps\/server\/drizzle/
  );
  assert.match(dockerfile, /CMD \["node", "dist\/index\.js"\]/);
});

