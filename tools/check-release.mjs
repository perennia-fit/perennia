#!/usr/bin/env node
// Check that a release's version is stated the same way everywhere it lives.
//
//   node tools/check-release.mjs                    # the versions agree (CI, every PR)
//   node tools/check-release.mjs --tag v0.0.1       # ...and the tag names them, on main
//   node tools/check-release.mjs --tag v0.0.1 --notes-file notes.md
//                                                   # ...and write that CHANGELOG section
//
// The app and the server share one version (CHANGELOG.md says so), stated in
// three places: `version:` in apps/mobile/pubspec.yaml (the part before `+`;
// after it is the Android versionCode / iOS build number), `version` in
// apps/server/package.json (what /healthz reports), and a `## [x.y.z]` heading
// in CHANGELOG.md. A release tag `vX.Y.Z` must name that version and point at a
// commit on main, because deploys and store builds are cut only from release
// tags (docs/releasing.md). Run from the release workflow, this is the gate
// that stops a tag from publishing an image whose /healthz disagrees with it.

import { spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import process from 'node:process';

const ROOT = new URL('..', import.meta.url);
const read = (path) => readFileSync(new URL(path, ROOT), 'utf8');

const args = process.argv.slice(2);
const flag = (name) => {
  const index = args.indexOf(name);
  return index === -1 ? undefined : args[index + 1];
};
const tag = flag('--tag');
const notesFile = flag('--notes-file');

const problems = [];

const pubspecVersion = read('apps/mobile/pubspec.yaml')
  .split('\n')
  .find((line) => line.startsWith('version:'))
  ?.split(/\s+/)[1];
const [appVersion, buildNumber] = (pubspecVersion ?? '').split('+');
const serverVersion = JSON.parse(read('apps/server/package.json')).version;

if (!/^\d+\.\d+\.\d+$/.test(appVersion ?? '')) {
  problems.push(`apps/mobile/pubspec.yaml version is not x.y.z+n: ${pubspecVersion}`);
}
if (!/^[1-9]\d*$/.test(buildNumber ?? '')) {
  problems.push(
    `apps/mobile/pubspec.yaml build number (after +) must be a positive integer: ${pubspecVersion}`,
  );
}
if (serverVersion !== appVersion) {
  problems.push(
    `apps/server/package.json version ${serverVersion} != apps/mobile/pubspec.yaml version ${appVersion}`,
  );
}

const changelog = read('CHANGELOG.md');
const heading = new RegExp(`^## \\[${appVersion?.replaceAll('.', '\\.')}\\]`, 'm');
const section = changelog.split(/^(?=## \[)/m).find((part) => heading.test(part));
if (section === undefined) {
  problems.push(`CHANGELOG.md has no "## [${appVersion}]" section`);
}

if (tag !== undefined) {
  if (tag !== `v${appVersion}`) {
    problems.push(`tag ${tag} does not name version ${appVersion} (expected v${appVersion})`);
  }
  const onMain = spawnSync('git', ['merge-base', '--is-ancestor', 'HEAD', 'origin/main']);
  if (onMain.status !== 0) {
    problems.push(`tag ${tag} points at a commit that is not on origin/main`);
  }
}

if (problems.length > 0) {
  console.error(`Release check failed:\n${problems.map((p) => `  - ${p}`).join('\n')}`);
  process.exit(1);
}

if (notesFile !== undefined) {
  writeFileSync(notesFile, section.replace(/^## .*\n/, '').trim() + '\n');
}
console.log(`Release version ${appVersion} (build ${buildNumber}) is consistent${tag ? ` with ${tag}` : ''}.`);
