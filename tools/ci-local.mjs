#!/usr/bin/env node
// Local mirror of .github/workflows/ci.yml — run the CI gate on your machine
// before pushing, so you find failures in seconds rather than after a round
// trip. Hosted CI on the pull request is the authoritative gate; this is the
// contributor convenience that matches it command-for-command.
//
//   pnpm ci:local                # run every job (the full gate)
//   pnpm ci:local mobile js      # run only the named jobs
//   pnpm ci:local --changed      # run only jobs whose paths changed vs `main`
//   pnpm ci:local --list         # list job names and exit
//   pnpm ci:local --skip-db      # skip jobs that need Postgres (js, sync)
//
// Optionally publish the verdict to a PR as a commit status + sticky comment
// (useful when hosted CI is unavailable, e.g. a fork without Actions enabled):
//   pnpm ci:local --changed --publish        # run, then post result to the branch's PR
//   pnpm ci:local --publish --pr 159         # publish to a specific PR number
//   pnpm ci:local --no-run --publish --pr 7  # mark a docs-only PR green w/o running
//   pnpm ci:local --publish --dry-run        # print what would be posted, send nothing
//
// Jobs that need Postgres spin up an ephemeral postgres:16-alpine container
// (host port 55432, auto-removed on exit). Requires Docker to be running.
//
// This script intentionally runs the SAME commands as ci.yml so a green run
// here means a green run there. When you change ci.yml, update this file too.

import { spawnSync } from 'node:child_process';
import process from 'node:process';

const ROOT = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const MOBILE = `${ROOT}/apps/mobile`;

const PG_CONTAINER = 'prn-ci-local-postgres';
const PG_IMAGE = 'postgres:16-alpine';
const PG_PORT = 55432; // host port; avoids clashing with any local 5432
const PG_BOOTSTRAP_DB = 'perennia_test';

// Every DB job gets its OWN database, recreated immediately before it runs.
// ci.yml declares a `services: postgres` block per job, so on hosted CI each job
// starts against a virgin database; sharing one locally let rows from an earlier
// job satisfy — or contradict — a later job's assertions, which is exactly the
// kind of divergence this script exists to rule out.
const dbNameFor = (job) => `${PG_BOOTSTRAP_DB}_${job}`;
const dbUrlFor = (job) =>
  `postgres://postgres:postgres@localhost:${PG_PORT}/${dbNameFor(job)}`;

// ---- shell helpers ---------------------------------------------------------

function sleep(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

// Run a command, streaming its output. Returns true on exit code 0.
function run(cmd, { cwd = ROOT, env } = {}) {
  console.log(`\n  $ ${cmd}${cwd !== ROOT ? `   (in ${cwd.replace(ROOT, '.')})` : ''}`);
  const res = spawnSync(cmd, {
    cwd,
    stdio: 'inherit',
    shell: true, // resolves corepack/flutter/dart shims on Windows
    // CI=true matches GitHub Actions: pnpm/test tools run non-interactively
    // (no "remove modules and reinstall?" prompt that would hang the run).
    env: { ...process.env, CI: 'true', ...env },
  });
  return res.status === 0;
}

// Run a command silently and capture stdout (used for probes / git).
function capture(cmd, { cwd = ROOT } = {}) {
  const res = spawnSync(cmd, { cwd, shell: true, encoding: 'utf8' });
  return { ok: res.status === 0, out: (res.stdout || '').trim() };
}

function have(tool) {
  return capture(`${tool} --version`).ok;
}

// ---- job definitions -------------------------------------------------------
// Each job mirrors a job in ci.yml. `paths` are the dorny/paths-filter globs
// for --changed. `db` marks jobs needing Postgres. `run` returns a result:
//   true  -> passed
//   false -> failed
//   'skip'-> nothing to do locally (e.g. tool missing)

const JS_PATHS = [
  'apps/server/**', 'tools/generate-wger-platform-exercises.mjs',
  'tools/platform-exercise-cleanup.mjs',
  'packages/contract/**', 'packages/golden-vectors/**',
  'sidecars/**', '.node-version', 'package.json', 'pnpm-workspace.yaml',
  'pnpm-lock.yaml', 'tsconfig.base.json', '.github/workflows/ci.yml',
];

const DEPENDENCY_HYGIENE_PATHS = [
  '.github/dependabot.yml', 'tools/check-dependency-hygiene.mjs',
  'package.json', 'pnpm-workspace.yaml', 'pnpm-lock.yaml',
  'apps/server/package.json',
  'packages/contract/package.json', 'packages/golden-vectors/package.json',
  'pubspec.yaml', 'pubspec.lock', 'apps/mobile/pubspec.yaml',
  '.github/workflows/ci.yml',
];

const JOBS = {
  dependency_hygiene: {
    title: 'Dependency update coverage',
    paths: DEPENDENCY_HYGIENE_PATHS,
    run: () => run('node tools/check-dependency-hygiene.mjs'),
  },

  mobile: {
    title: 'Flutter analyze and test',
    paths: ['apps/mobile/**', 'pubspec.yaml', 'pubspec.lock',
      '.github/workflows/ci.yml'],
    run: () =>
      run('flutter pub get') &&
      run('dart run melos bootstrap') &&
      run('dart run build_runner build', { cwd: MOBILE }) &&
      run('git diff --exit-code -- apps/mobile/lib/data/local/app_database.g.dart') &&
      run('dart run tool/generate_design_tokens.dart', { cwd: MOBILE }) &&
      run('git diff --exit-code -- apps/mobile/lib/theme/design_tokens.g.dart') &&
      run('flutter analyze', { cwd: MOBILE }) &&
      run('flutter test test/performance/performance_budgets_test.dart', { cwd: MOBILE }) &&
      run('flutter test', { cwd: MOBILE }),
  },

  golden: {
    title: 'Golden-vector parity (TS + Dart)',
    paths: [
      'apps/server/src/analytics/**', 'apps/server/src/metric-reading-normalization.ts',
      'apps/server/test/analytics.golden.test.mjs',
      'apps/server/test/metric-reading-normalization.golden.test.mjs',
      'apps/server/test/nutrition-analytics.golden.test.mjs',
      'apps/server/package.json', '.node-version',
      'apps/mobile/lib/domain/analytics/**', 'apps/mobile/lib/domain/metrics/**',
      'apps/mobile/lib/domain/nutrition/**',
      'apps/mobile/lib/domain/training/training_dimensions.dart',
      'apps/mobile/test/domain/exercise_analytics_test.dart',
      'apps/mobile/test/domain/metric_reading_normalization_test.dart',
      'apps/mobile/test/domain/nutrition_aggregation_golden_test.dart',
      'apps/mobile/pubspec.yaml', 'pubspec.yaml', 'pubspec.lock',
      'packages/golden-vectors/**', 'pnpm-workspace.yaml', 'pnpm-lock.yaml',
      'tsconfig.base.json', '.github/workflows/ci.yml',
    ],
    pnpm: true,
    run: () =>
      run('flutter pub get') &&
      run('corepack pnpm --filter @perennia/server test:golden-vectors') &&
      run('flutter test test/domain/exercise_analytics_test.dart test/domain/metric_reading_normalization_test.dart test/domain/nutrition_aggregation_golden_test.dart', { cwd: MOBILE }),
  },

  contract: {
    title: 'Contract drift',
    paths: ['apps/server/**', 'apps/mobile/assets/seeds/platform_exercises.json',
      'apps/mobile/assets/seeds/usda_foods.json',
      'apps/mobile/lib/api/**', 'apps/mobile/pubspec.yaml',
      'packages/contract/**', 'tools/generate-server-platform-exercise-seed.mjs',
      'tools/generate-server-usda-food-seed.mjs',
      '.node-version', 'package.json', 'pnpm-workspace.yaml',
      'pnpm-lock.yaml', 'tsconfig.base.json', '.github/workflows/ci.yml'],
    pnpm: true,
    run: () =>
      run('node tools/generate-server-platform-exercise-seed.mjs --check') &&
      run('node tools/generate-server-usda-food-seed.mjs --check') &&
      run('corepack pnpm --filter @perennia/contract check:drift'),
  },

  js: {
    title: 'JS workspace checks',
    paths: JS_PATHS,
    pnpm: true,
    db: true,
    run: (databaseUrl) =>
      run('corepack pnpm js:typecheck') &&
      run('corepack pnpm js:test', { env: { DATABASE_URL: databaseUrl } }),
  },

  sync: {
    title: 'Sync convergence simulation',
    paths: JS_PATHS,
    pnpm: true,
    db: true,
    run: (databaseUrl) =>
      run('corepack pnpm --filter @perennia/server test:sync-convergence', {
        env: { DATABASE_URL: databaseUrl },
      }),
  },

  workflow_lint: {
    title: 'Workflow lint (best-effort)',
    paths: ['.github/workflows/**'],
    run: () => {
      let ran = false;
      let ok = true;
      if (have('actionlint')) {
        ran = true;
        ok = run('actionlint') && ok;
      } else {
        console.log('  ⚠ actionlint not installed — skipping workflow lint');
      }
      return ran ? ok : 'skip';
    },
  },
};

// ---- path-filter matching (for --changed) ----------------------------------

function matchGlob(file, pattern) {
  if (pattern.endsWith('/**')) {
    const prefix = pattern.slice(0, -3);
    return file === prefix || file.startsWith(prefix + '/');
  }
  return file === pattern;
}

function changedFiles() {
  const base = capture('git merge-base HEAD main');
  if (!base.ok) {
    console.log('  ⚠ could not find merge-base with `main` — running all selected jobs');
    return null;
  }
  const sets = [
    capture(`git diff --name-only ${base.out} HEAD`),
    capture('git diff --name-only HEAD'),
    capture('git ls-files --others --exclude-standard'),
  ];
  const files = new Set();
  for (const s of sets) {
    if (!s.ok) continue;
    for (const f of s.out.split('\n')) if (f.trim()) files.add(f.trim());
  }
  return files;
}

// ---- Postgres lifecycle ----------------------------------------------------

function startPostgres() {
  console.log(`\n▸ Starting ephemeral Postgres (${PG_IMAGE}) on host port ${PG_PORT}…`);
  capture(`docker rm -f ${PG_CONTAINER}`); // clear any stale container
  const up = run(
    `docker run -d --rm --name ${PG_CONTAINER} ` +
    `-e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres ` +
    `-e POSTGRES_DB=${PG_BOOTSTRAP_DB} -p ${PG_PORT}:5432 ${PG_IMAGE}`,
  );
  if (!up) throw new Error('Failed to start Postgres container (is Docker running? is the port free?)');

  // The postgres:*-alpine entrypoint starts a TEMPORARY server to run init
  // scripts, then RESTARTS into the real one. `pg_isready` transiently succeeds
  // against that temporary instance, so a single green check can land right
  // before the restart drops the connection — surfacing as intermittent
  // "Failed query: CREATE SCHEMA" during the first test's migrations. Require
  // several CONSECUTIVE successful real SQL round-trips (spanning the restart
  // window) before declaring the DB ready.
  process.stdout.write('  waiting for Postgres to accept connections');
  const requiredConsecutive = 4;
  let consecutive = 0;
  for (let i = 0; i < 90; i++) {
    // A real query (not just pg_isready) confirms the server is truly serving.
    const ok = capture(
      `docker exec ${PG_CONTAINER} psql -U postgres -d ${PG_BOOTSTRAP_DB} -tAc "select 1"`,
    ).ok;
    if (ok) {
      consecutive += 1;
      if (consecutive >= requiredConsecutive) {
        console.log(' ✓');
        return;
      }
    } else {
      consecutive = 0;
    }
    process.stdout.write('.');
    sleep(500);
  }
  throw new Error('Postgres did not become ready in time');
}

// Hand a job the equivalent of a freshly provisioned service container: an empty
// database of its own. Recreating (rather than truncating) keeps this honest as
// the schema grows — there is no table list to keep in step — and the suites
// already migrate from empty, because that is what hosted CI hands them.
function resetDatabase(job) {
  const db = dbNameFor(job);
  // FORCE (Postgres 13+) evicts connections a crashed earlier run left behind,
  // which would otherwise wedge the drop.
  capture(
    `docker exec ${PG_CONTAINER} psql -U postgres -d ${PG_BOOTSTRAP_DB} ` +
    `-c "DROP DATABASE IF EXISTS ${db} WITH (FORCE)"`,
  );
  const created = capture(
    `docker exec ${PG_CONTAINER} psql -U postgres -d ${PG_BOOTSTRAP_DB} ` +
    `-c "CREATE DATABASE ${db}"`,
  );
  if (!created.ok) {
    throw new Error(`Failed to create a clean database for the ${job} job`);
  }
}

function stopPostgres() {
  capture(`docker rm -f ${PG_CONTAINER}`);
}

// ---- GitHub publish (commit status + sticky PR comment) --------------------
// Commit statuses and issue comments are plain REST calls — NOT billed like
// Actions minutes. So we run the gate locally and publish the verdict to the
// PR ourselves: a ✓/✗ `ci-local` check plus a sticky results comment.

const COMMENT_MARKER = '<!-- ci-local-summary -->';

// Token comes from git's credential helper (same one `git push` uses); never printed.
function githubToken() {
  const res = spawnSync('git', ['credential', 'fill'], {
    input: 'protocol=https\nhost=github.com\n\n',
    encoding: 'utf8',
  });
  if (res.status !== 0) return null;
  const m = (res.stdout || '').match(/^password=(.*)$/m);
  return m && m[1] ? m[1].trim() : null;
}

function ownerRepo() {
  const r = capture('git remote get-url origin');
  if (!r.ok) return null;
  const m = r.out.replace(/\.git$/, '').match(/github\.com[/:]([^/]+)\/([^/]+)$/);
  return m ? `${m[1]}/${m[2]}` : null;
}

async function ghApi(token, method, path, body) {
  const res = await fetch(`https://api.github.com${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'prn-ci-local',
      ...(body ? { 'Content-Type': 'application/json' } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch { json = text; }
  return { ok: res.ok, status: res.status, json };
}

function buildComment(selected, results, state, sha) {
  const icon = { passed: '✅', failed: '❌', skipped: '⏭️' };
  const rows = selected.length
    ? selected.map((n) => `| \`${n}\` | ${icon[results[n]]} ${results[n]} |`).join('\n')
    : '| _(none)_ | no jobs matched the changed paths |';
  return [
    COMMENT_MARKER,
    `## 🧪 Local CI gate — ${state === 'success' ? '✅ passed' : '❌ failed'}`,
    '',
    'Ran via `pnpm ci:local` on a developer machine (GitHub Actions credits exhausted this cycle).',
    '',
    '| Job | Result |',
    '|---|---|',
    rows,
    '',
    `<sub>commit \`${sha.slice(0, 7)}\` · ${new Date().toISOString()} · published locally, not a GitHub Actions run</sub>`,
  ].join('\n');
}

async function publishToPr(selected, results, { token, repo, prOverride, dryRun }) {
  const owner = repo.split('/')[0];
  let pr = null;
  if (prOverride) {
    const r = await ghApi(token, 'GET', `/repos/${repo}/pulls/${prOverride}`);
    if (r.ok) pr = r.json;
    else console.log(`  ⚠ could not load PR #${prOverride} (${r.status})`);
  } else {
    const branch = capture('git rev-parse --abbrev-ref HEAD').out;
    const r = await ghApi(token, 'GET', `/repos/${repo}/pulls?head=${owner}:${branch}&state=open`);
    if (Array.isArray(r.json) && r.json.length) pr = r.json[0];
  }
  const sha = pr ? pr.head.sha : capture('git rev-parse HEAD').out;

  const failedJobs = selected.filter((n) => results[n] === 'failed');
  const passed = selected.filter((n) => results[n] === 'passed').length;
  const skipped = selected.filter((n) => results[n] === 'skipped').length;
  const state = failedJobs.length ? 'failure' : 'success';
  const description = (failedJobs.length
    ? `Failed: ${failedJobs.join(', ')}`
    : selected.length
      ? `${passed} passed, ${skipped} skipped — local gate`
      : 'No jobs matched changed paths — local gate'
  ).slice(0, 140);

  const status = { state, context: 'ci-local', description, target_url: pr ? pr.html_url : undefined };
  const comment = buildComment(selected, results, state, sha);

  if (dryRun) {
    console.log(`\n  [dry-run] would POST /repos/${repo}/statuses/${sha.slice(0, 7)}`);
    console.log(`  [dry-run] status: ${JSON.stringify(status)}`);
    console.log(`  [dry-run] ${pr ? `would upsert comment on PR #${pr.number}` : 'no PR for branch — comment skipped'}`);
    console.log('  [dry-run] comment body:\n' + comment.split('\n').map((l) => '    ' + l).join('\n'));
    return;
  }

  const st = await ghApi(token, 'POST', `/repos/${repo}/statuses/${sha}`, status);
  console.log(st.ok
    ? `  ✓ posted ${state} status (context: ci-local) to ${sha.slice(0, 7)}`
    : `  ⚠ status post failed (${st.status}): ${JSON.stringify(st.json).slice(0, 200)}`);

  if (!pr) {
    console.log('  ℹ no open PR for this branch — skipped the summary comment.');
    return;
  }
  const list = await ghApi(token, 'GET', `/repos/${repo}/issues/${pr.number}/comments?per_page=100`);
  const existing = Array.isArray(list.json)
    ? list.json.find((c) => typeof c.body === 'string' && c.body.includes(COMMENT_MARKER))
    : null;
  const cr = existing
    ? await ghApi(token, 'PATCH', `/repos/${repo}/issues/comments/${existing.id}`, { body: comment })
    : await ghApi(token, 'POST', `/repos/${repo}/issues/${pr.number}/comments`, { body: comment });
  console.log(cr.ok
    ? `  ✓ ${existing ? 'updated' : 'posted'} summary comment on PR #${pr.number}`
    : `  ⚠ comment ${existing ? 'update' : 'post'} failed (${cr.status})`);
}

// ---- main ------------------------------------------------------------------

const argv = process.argv.slice(2);
const flags = new Set();
const requested = [];
let prOverride = null;
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--pr') { prOverride = argv[++i]; continue; }
  if (a.startsWith('--pr=')) { prOverride = a.slice('--pr='.length); continue; }
  if (a.startsWith('--')) { flags.add(a); continue; }
  requested.push(a);
}

if (flags.has('--list')) {
  console.log('Jobs:');
  for (const [name, j] of Object.entries(JOBS)) {
    console.log(`  ${name.padEnd(10)} ${j.title}${j.db ? '  [needs Postgres]' : ''}`);
  }
  process.exit(0);
}

const unknown = requested.filter((n) => !JOBS[n]);
if (unknown.length) {
  console.error(`Unknown job(s): ${unknown.join(', ')}\nKnown: ${Object.keys(JOBS).join(', ')}`);
  process.exit(2);
}

let selected = requested.length ? requested : Object.keys(JOBS);

if (flags.has('--changed')) {
  const changed = changedFiles();
  if (changed) {
    selected = selected.filter((name) =>
      JOBS[name].paths.some((p) => [...changed].some((f) => matchGlob(f, p))));
    console.log(`▸ --changed: ${selected.length ? selected.join(', ') : '(no jobs match the changed paths)'}`);
  }
}

if (flags.has('--skip-db')) {
  selected = selected.filter((name) => !JOBS[name].db);
}

// --no-run: publish a verdict without executing anything. With no jobs this
// records an honest "no jobs affected" success — useful for docs-only PRs.
if (flags.has('--no-run')) {
  selected = [];
}

if (!selected.length && !flags.has('--publish')) {
  console.log('\nNothing to run. ✓');
  process.exit(0);
}

const needsDb = selected.some((name) => JOBS[name].db);
const results = {};
let dbStarted = false;

try {
  if (selected.some((name) => JOBS[name].pnpm)) {
    console.log('\n▸ Installing JS dependencies (pnpm install --frozen-lockfile)…');
    if (!run('corepack pnpm install --frozen-lockfile')) {
      throw new Error('pnpm install failed');
    }
  }
  if (needsDb) {
    startPostgres();
    dbStarted = true;
  }
  for (const name of selected) {
    const job = JOBS[name];
    console.log(`\n${'═'.repeat(70)}\n▶ ${name} — ${job.title}\n${'═'.repeat(70)}`);
    let outcome;
    try {
      if (job.db) resetDatabase(name);
      outcome = job.run(job.db ? dbUrlFor(name) : undefined);
    } catch (err) {
      console.error(`  ✖ ${err.message}`);
      outcome = false;
    }
    results[name] = outcome === 'skip' ? 'skipped' : outcome ? 'passed' : 'failed';
  }
} finally {
  if (dbStarted) {
    console.log('\n▸ Tearing down Postgres…');
    stopPostgres();
  }
}

console.log(`\n${'═'.repeat(70)}\nSummary\n${'═'.repeat(70)}`);
const mark = { passed: '✓', failed: '✖', skipped: '–' };
for (const name of selected) {
  console.log(`  ${mark[results[name]]} ${name.padEnd(10)} ${results[name]}`);
}
if (flags.has('--publish')) {
  console.log('\n▸ Publishing result to GitHub…');
  const token = githubToken();
  const repo = ownerRepo();
  if (!token) console.log('  ⚠ no GitHub token from git credential helper — skipping publish.');
  else if (!repo) console.log('  ⚠ could not determine owner/repo from origin — skipping publish.');
  else await publishToPr(selected, results, { token, repo, prOverride, dryRun: flags.has('--dry-run') });
}

const failed = selected.filter((n) => results[n] === 'failed');
if (failed.length) {
  console.log(`\n✖ CI gate FAILED: ${failed.join(', ')}`);
  process.exit(1);
}
console.log('\n✓ CI gate passed locally.');
