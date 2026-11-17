#!/usr/bin/env node
// Generate realistic test data and load it onto an Android device or emulator.
//
//   pnpm test-data                     # 12 weeks ending today, seed 42, onto the only device
//   pnpm test-data --weeks 26 --seed 7
//   pnpm test-data --end 2026-06-30    # a fixed window, for reproducible screenshots
//   pnpm test-data --no-nutrition      # training and body weight only
//   pnpm test-data --no-push           # just write apps/mobile/build/test-data/perennia.sqlite
//   pnpm test-data --device emulator-5554
//
// The generator (apps/mobile/tool/test_data/) writes a complete app database
// through the app's own repositories, so the file always matches the schema of
// the checkout that built it. Loading it REPLACES the app's database on the
// device. That is deliberate and only possible on a debug build: `run-as`
// works for debuggable apps alone, so this can never touch a store install.
// It is a developer tool, not a restore path; the app's own restore stays
// merge-only.

import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import process from 'node:process';

const ROOT = resolve(new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const MOBILE = join(ROOT, 'apps', 'mobile');
const OUT = join(MOBILE, 'build', 'test-data', 'perennia.sqlite');
const PACKAGE = 'fit.perennia.app';
const DEVICE_TMP = '/data/local/tmp/perennia-test-data.sqlite';

function parseArgs(argv) {
  const options = { weeks: 12, seed: 42, end: '', timezone: 'UTC', nutrition: true, push: true, device: '' };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const value = () => {
      const next = argv[++i];
      if (next === undefined) fail(`${arg} needs a value`);
      return next;
    };
    switch (arg) {
      case '--weeks': options.weeks = Number.parseInt(value(), 10); break;
      case '--seed': options.seed = Number.parseInt(value(), 10); break;
      case '--end': options.end = value(); break;
      case '--timezone': options.timezone = value(); break;
      case '--device': options.device = value(); break;
      case '--no-nutrition': options.nutrition = false; break;
      case '--no-push': options.push = false; break;
      case '-h':
      case '--help':
        console.log(readHeader());
        process.exit(0);
        break;
      default: fail(`Unknown option: ${arg}`);
    }
  }
  if (!Number.isInteger(options.weeks) || options.weeks < 1) fail('--weeks must be a positive integer');
  if (!Number.isInteger(options.seed)) fail('--seed must be an integer');
  if (options.end && !/^\d{4}-\d{2}-\d{2}$/.test(options.end)) fail('--end must be YYYY-MM-DD');
  return options;
}

function readHeader() {
  return 'Usage: pnpm test-data [--weeks N] [--seed N] [--end YYYY-MM-DD] [--timezone TZ]\n' +
    '                      [--no-nutrition] [--no-push] [--device SERIAL]';
}

function fail(message) {
  console.error(`✖ ${message}`);
  process.exit(1);
}

function run(command, args, { cwd = ROOT, capture = false, timeoutMs } = {}) {
  const result = spawnSync(command, args, {
    cwd,
    encoding: 'utf8',
    stdio: capture ? ['ignore', 'pipe', 'pipe'] : 'inherit',
    env: { ...process.env, LANG: process.env.LANG || 'en_US.UTF-8' },
    timeout: timeoutMs,
  });
  if (result.error?.code === 'ETIMEDOUT') {
    fail(`${command} ${args.join(' ')} did not answer within ${timeoutMs / 1000}s. ` +
      'The device may be hung: restart the emulator and try again.');
  }
  if (result.error) fail(`${command}: ${result.error.message}`);
  return result;
}

// An emulator that has stopped responding still lists as "device" and accepts
// connections, then never answers. Without a deadline every adb call would
// hang with it.
const ADB_TIMEOUT_MS = 60_000;

function adbPath() {
  for (const home of [process.env.ANDROID_HOME, process.env.ANDROID_SDK_ROOT]) {
    if (home) {
      const candidate = join(home, 'platform-tools', process.platform === 'win32' ? 'adb.exe' : 'adb');
      if (existsSync(candidate)) return candidate;
    }
  }
  return 'adb';
}

function generate(options) {
  console.log(`▶ Generating ${options.weeks} weeks of test data (seed ${options.seed})…`);
  const defines = [
    `OUT=${OUT}`,
    `WEEKS=${options.weeks}`,
    `SEED=${options.seed}`,
    `TIMEZONE=${options.timezone}`,
    `NUTRITION=${options.nutrition}`,
    ...(options.end ? [`END=${options.end}`] : []),
  ].flatMap((define) => ['--dart-define', define]);
  const result = run('flutter', ['test', 'tool/test_data/generate.dart', ...defines], { cwd: MOBILE, capture: true });
  const output = `${result.stdout}\n${result.stderr}`;
  const summary = output.split('\n').find((line) => line.includes('TEST_DATA_SUMMARY'));
  if (result.status !== 0 || !summary) {
    console.error(output);
    fail('Generation failed.');
  }
  console.log(`✓ ${summary.replace('TEST_DATA_SUMMARY ', '')}`);
}

function push(options) {
  const adb = adbPath();
  const devices = run(adb, ['devices'], { capture: true, timeoutMs: ADB_TIMEOUT_MS }).stdout
    .split('\n').slice(1)
    .map((line) => line.trim().split(/\s+/))
    .filter(([serial, state]) => serial && state === 'device')
    .map(([serial]) => serial);
  const serial = options.device || (devices.length === 1 ? devices[0] : '');
  if (!serial) {
    fail(devices.length === 0
      ? 'No device connected. Start the emulator or plug in a phone, or pass --no-push.'
      : `Several devices connected (${devices.join(', ')}); choose one with --device.`);
  }
  const adbOn = (args, opts) => run(adb, ['-s', serial, ...args], { timeoutMs: ADB_TIMEOUT_MS, ...opts });
  const shell = (command) => adbOn(['shell', command], { capture: true });

  if (!shell(`pm list packages ${PACKAGE}`).stdout.includes(`package:${PACKAGE}`)) {
    fail(`${PACKAGE} is not installed on ${serial}. Build and install a debug APK first:\n` +
      '  cd apps/mobile && flutter build apk --debug && adb install -r build/app/outputs/flutter-apk/app-debug.apk');
  }
  const runAs = shell(`run-as ${PACKAGE} true`);
  if (runAs.status !== 0) {
    fail(`run-as is refused for ${PACKAGE} on ${serial}. Only a debug build can be loaded with ` +
      `test data, and the app must have been opened once.\n  device said: ${(runAs.stdout + runAs.stderr).trim()}`);
  }

  console.log(`▶ Replacing the app database on ${serial}…`);
  shell(`am force-stop ${PACKAGE}`);
  if (adbOn(['push', OUT, DEVICE_TMP], { capture: true }).status !== 0) fail('adb push failed.');
  // Drop any journal left by the previous database, or SQLite would replay it
  // over the new file on open.
  const copy = shell(
    `run-as ${PACKAGE} sh -c 'mkdir -p app_flutter && cp ${DEVICE_TMP} app_flutter/perennia.sqlite && ` +
    `rm -f app_flutter/perennia.sqlite-journal app_flutter/perennia.sqlite-wal app_flutter/perennia.sqlite-shm'`,
  );
  shell(`rm -f ${DEVICE_TMP}`);
  if (copy.status !== 0) fail(`Copy into the app's storage failed:\n${copy.stderr}`);
  shell(`monkey -p ${PACKAGE} -c android.intent.category.LAUNCHER 1`);
  console.log('✓ Loaded. The app has been restarted with the new data.');
}

const options = parseArgs(process.argv.slice(2));
generate(options);
if (options.push) push(options);
