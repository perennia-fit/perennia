import { parseGarminFitActivityFile } from "../../apps/server/src/index.ts";

const timezone = readArg("--timezone") ?? "UTC";
const chunks = [];

for await (const chunk of process.stdin) {
  chunks.push(chunk);
}

const fitBytes = Buffer.concat(chunks);
const canonical = parseGarminFitActivityFile(fitBytes, { timezone });
process.stdout.write(JSON.stringify(canonical));

function readArg(name) {
  const index = process.argv.indexOf(name);
  if (index === -1) {
    return null;
  }

  return process.argv[index + 1] ?? null;
}
