import { mkdir, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { createOpenApiDocument } from "../../../apps/server/src/openapi.js";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const contractDir = resolve(scriptDir, "..");
const outputPath = resolve(contractDir, "openapi.json");

await mkdir(dirname(outputPath), { recursive: true });
await writeFile(
  outputPath,
  `${JSON.stringify(await createOpenApiDocument(), null, 2)}\n`,
  "utf8"
);
