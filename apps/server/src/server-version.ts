import { readFileSync } from "node:fs";

/**
 * The release this server was built from: the `version` field of
 * `apps/server/package.json`, which a release bumps alongside the app's
 * pubspec version (they share one version; see docs/releasing.md).
 *
 * Read from the file rather than `npm_package_version`. That variable only
 * exists when a package manager launches the process, and the Docker image
 * runs `node dist/index.js` directly, so every deployed server reported
 * `0.0.0` and there was no way to tell which release was live. The image
 * copies `package.json` next to `dist/`, and the file sits one directory
 * above both `src/` (run with tsx) and `dist/` (compiled), so the same
 * relative URL resolves in each.
 */
export function readServerVersion(): string {
  const packageJson = JSON.parse(
    readFileSync(new URL("../package.json", import.meta.url), "utf8")
  ) as { version?: unknown };
  if (typeof packageJson.version !== "string" || packageJson.version === "") {
    throw new Error("apps/server/package.json has no version.");
  }
  return packageJson.version;
}

export const SERVER_VERSION = readServerVersion();
