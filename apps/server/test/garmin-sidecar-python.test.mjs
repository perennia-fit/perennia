import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import test from "node:test";

test("Garmin edge sidecar keeps acquisition outside Perennia core and posts canonical imports", () => {
  const python = resolvePythonCommand();
  const result = spawnSync(
    python.command,
    ["-m", "unittest", "discover", "-s", "sidecars/garmin", "-p", "*_test.py"],
    {
      cwd: new URL("../../..", import.meta.url),
      encoding: "utf8",
      shell: python.shell
    }
  );

  assert.equal(
    result.status,
    0,
    `Garmin sidecar Python tests failed using ${python.command}.\nSTDOUT:\n${result.stdout}\nSTDERR:\n${result.stderr}`
  );
});

function resolvePythonCommand() {
  const candidates = [
    process.env.PYTHON,
    ...windowsPythonCandidates(),
    "python3",
    "python",
    "py -3"
  ].filter(Boolean);

  for (const command of candidates) {
    const result = spawnSync(command, ["--version"], {
      encoding: "utf8",
      shell: command.includes(" ")
    });
    if (result.status === 0) {
      return {
        command,
        shell: command.includes(" ")
      };
    }
  }

  throw new Error("Python 3 is required for Garmin sidecar tests.");
}

function windowsPythonCandidates() {
  if (process.platform !== "win32") {
    return [];
  }

  const result = spawnSync("where.exe", ["python"], { encoding: "utf8" });
  if (result.status !== 0) {
    return [];
  }

  return result.stdout
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .filter((line) => !line.includes("\\Microsoft\\WindowsApps\\"));
}
