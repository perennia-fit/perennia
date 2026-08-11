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

test("Render Blueprint defines production, staging, and paid Postgres services", async () => {
  const renderYaml = await readRepoFile("render.yaml");

  assert.match(renderYaml, /name: open-workout-logger-server[\s\S]*branch: main/);
  assert.match(
    renderYaml,
    /name: open-workout-logger-server-staging[\s\S]*branch: staging/
  );
  assert.match(renderYaml, /runtime: docker/);
  assert.match(renderYaml, /dockerfilePath: \.\/Dockerfile/);
  assert.match(renderYaml, /dockerContext: \./);
  assert.match(renderYaml, /autoDeployTrigger: checksPass/);
  assert.match(renderYaml, /healthCheckPath: \/healthz/);
  assert.match(
    renderYaml,
    /DATABASE_URL[\s\S]*fromDatabase:[\s\S]*name: open-workout-logger-db[\s\S]*property: connectionString/
  );
  assert.match(
    renderYaml,
    /DATABASE_URL[\s\S]*fromDatabase:[\s\S]*name: open-workout-logger-db-staging[\s\S]*property: connectionString/
  );
  assert.match(
    renderYaml,
    /SERVER_CRASH_REPORTING_ENABLED[\s\S]*sync: false[\s\S]*SERVER_CRASH_REPORTING_DSN[\s\S]*sync: false/
  );
  assert.match(renderYaml, /type: worker[\s\S]*name: open-workout-logger-worker[\s\S]*branch: main/);
  assert.match(
    renderYaml,
    /name: open-workout-logger-worker[\s\S]*dockerCommand: node dist\/worker\.js[\s\S]*DATABASE_URL[\s\S]*fromDatabase:[\s\S]*name: open-workout-logger-db[\s\S]*property: connectionString/
  );
  assert.match(
    renderYaml,
    /type: worker[\s\S]*name: open-workout-logger-worker-staging[\s\S]*branch: staging/
  );
  assert.match(
    renderYaml,
    /name: open-workout-logger-worker-staging[\s\S]*dockerCommand: node dist\/worker\.js[\s\S]*DATABASE_URL[\s\S]*fromDatabase:[\s\S]*name: open-workout-logger-db-staging[\s\S]*property: connectionString/
  );
  assert.match(renderYaml, /name: open-workout-logger-db[\s\S]*plan: basic-256mb/);
  assert.match(
    renderYaml,
    /name: open-workout-logger-db-staging[\s\S]*plan: basic-256mb/
  );
  assert.match(renderYaml, /postgresMajorVersion: "16"/);
  assert.doesNotMatch(renderYaml, /plan: free/);
});
