#!/usr/bin/env node
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));

function read(relativePath) {
  return readFileSync(join(root, relativePath), 'utf8');
}

function requireFile(relativePath) {
  if (!existsSync(join(root, relativePath))) {
    throw new Error(`Missing required file: ${relativePath}`);
  }
}

function requireText(text, needle, label) {
  if (!text.includes(needle)) {
    throw new Error(`${label} must contain ${needle}`);
  }
}

function dependabotEntryFor(ecosystem) {
  const pattern = new RegExp(
    [
      `^  - package-ecosystem: "${ecosystem}"`,
      '[\\s\\S]*?',
      '(?=^  - package-ecosystem: |(?![\\s\\S]))',
    ].join(''),
    'm',
  );
  const match = dependabot.match(pattern);
  if (!match) {
    throw new Error(`Dependabot config must contain ${ecosystem}`);
  }

  return match[0];
}

function quotedListValues(text) {
  return Array.from(text.matchAll(/^\s+-\s+"([^"]+)"\s*$/gm), (match) => {
    return match[1];
  });
}

function workspacePackageDirectories() {
  const workspace = read('pnpm-workspace.yaml');
  return quotedListValues(workspace)
    .concat(
      Array.from(
        workspace.matchAll(/^\s+-\s+([^"'\s][^\s]*)\s*$/gm),
        (match) => {
          return match[1];
        },
      ),
    )
    .filter((directory) => {
      return !directory.includes('*') && !directory.startsWith('!');
    });
}

const dependabot = read('.github/dependabot.yml');

requireText(dependabot, 'version: 2', 'Dependabot config');
for (const ecosystem of ['github-actions', 'npm', 'pub', 'bundler']) {
  dependabotEntryFor(ecosystem);
}

const npmEntry = dependabotEntryFor('npm');
const npmDirectories = [
  '/',
  ...workspacePackageDirectories().map((directory) => {
    return `/${directory}`;
  }),
];
for (const directory of npmDirectories) {
  requireText(npmEntry, `"${directory}"`, 'Dependabot npm config');
  if (directory !== '/') {
    requireFile(`${directory.slice(1)}/package.json`);
  }
}

const pubEntry = dependabotEntryFor('pub');
requireText(pubEntry, '"/"', 'Dependabot pub config');
requireText(pubEntry, '"/apps/mobile"', 'Dependabot pub config');

const bundlerEntry = dependabotEntryFor('bundler');
requireText(bundlerEntry, 'directory: "/apps/mobile"', 'Dependabot bundler config');

requireFile('pnpm-lock.yaml');
requireFile('pubspec.lock');
requireFile('apps/mobile/Gemfile.lock');

const gemfileLock = read('apps/mobile/Gemfile.lock');
requireText(gemfileLock, 'fastlane ', 'Gemfile.lock');
requireText(gemfileLock, 'BUNDLED WITH', 'Gemfile.lock');

console.log(
  'Dependency hygiene config covers GitHub Actions, pnpm/npm, pub, and Fastlane.',
);
